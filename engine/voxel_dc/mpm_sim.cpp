#include "mpm_sim.h"

#include "core/math/math_funcs.h"

// --- MpmSim ---

void MpmSim::configure(Vector3 origin, int dim, double dx, Vector3 gravity, double E, double nu, double floor_y) {
	_origin = origin;
	_dim = dim;
	_dx = dx;
	_inv_dx = 1.0 / dx;
	_gravity = gravity;
	_mu = E / (2.0 * (1.0 + nu));
	_lambda = E * nu / ((1.0 + nu) * (1.0 - 2.0 * nu));
	_floor_y = floor_y;
	_gv.resize(_grid_count());
	_gm.resize(_grid_count());
}

// Drucker-Prager friction coefficient from a friction angle (≈ the resulting repose angle).
void MpmSim::set_sand_friction(double friction_angle_degrees) {
	const double phi = Math::deg_to_rad(friction_angle_degrees);
	const double sin_phi = Math::sin(phi);
	_alpha = Math::sqrt(2.0 / 3.0) * 2.0 * sin_phi / (3.0 - sin_phi);
}

int MpmSim::add_particle(Vector3 pos, double mass, double volume) {
	_x.push_back(pos);
	_v.push_back(Vector3());
	_F.push_back(Mat3::identity());
	_C.push_back(Mat3::zero());
	_mass.push_back(mass);
	_vol.push_back(volume);
	_sleeping.push_back(0); // new particles start awake (adding one is a disturbance)
	_still.push_back(0);
	_affine.push_back(Mat3::zero());
	_awake_count++;
	return int(_x.size()) - 1;
}

void MpmSim::set_sleep_params(double speed, int after, double wake_speed) {
	_sleep_speed = speed;
	_sleep_after = after;
	_wake_speed = wake_speed;
}

void MpmSim::wake_all() {
	for (uint32_t i = 0; i < _sleeping.size(); i++) {
		if (_sleeping[i]) {
			_sleeping[i] = 0;
			_still[i] = 0;
			_awake_count++;
		}
	}
}

void MpmSim::wake_region(Vector3 center, double radius) {
	const double r2 = radius * radius;
	for (uint32_t i = 0; i < _sleeping.size(); i++) {
		if (_sleeping[i] && _x[i].distance_squared_to(center) < r2) {
			_sleeping[i] = 0;
			_still[i] = 0;
			_awake_count++;
		}
	}
}

void MpmSim::step(double dt) {
	if (_sleep_enabled && _awake_count == 0) {
		return; // fully quiescent — costs nothing (doc 12 "sparse sleeping")
	}
	const int gc = _grid_count();
	for (int i = 0; i < gc; i++) {
		_gv[i] = Vector3();
		_gm[i] = 0.0;
	}
	_p2g(dt);
	_grid_update(dt);
	_g2p(dt);
}

void MpmSim::_stencil(const Vector3 &pos, int base[3], Vector3 &fx, double w[3][3]) const {
	const Vector3 gx = (pos - _origin) * _inv_dx;
	base[0] = int(Math::floor(gx.x - 0.5));
	base[1] = int(Math::floor(gx.y - 0.5));
	base[2] = int(Math::floor(gx.z - 0.5));
	fx = gx - Vector3(base[0], base[1], base[2]);
	const double f[3] = { fx.x, fx.y, fx.z };
	for (int a = 0; a < 3; a++) {
		w[a][0] = 0.5 * (1.5 - f[a]) * (1.5 - f[a]);
		w[a][1] = 0.75 - (f[a] - 1.0) * (f[a] - 1.0);
		w[a][2] = 0.5 * (f[a] - 0.5) * (f[a] - 0.5);
	}
}

// Scatter particle mass + momentum (incl. the internal-stress affine term) to the grid.
void MpmSim::_p2g(double dt) {
	const double dinv = 4.0 * _inv_dx * _inv_dx; // quadratic-kernel D⁻¹
	const int np = int(_x.size());
	for (int p = 0; p < np; p++) {
		// Asleep particles reuse their cached affine (F frozen, C = 0) — no SVD, but they
		// still scatter so support is preserved. Awake particles advance F + recompute stress.
		Mat3 affine;
		if (_sleeping[p]) {
			affine = _affine[p];
		} else {
			_F[p] = (Mat3::identity() + _C[p].scaled(dt)) * _F[p];
			affine = _stress(_F[p]).scaled(-dt * _vol[p] * dinv) + _C[p].scaled(_mass[p]);
		}

		int base[3];
		Vector3 fx;
		double w[3][3];
		_stencil(_x[p], base, fx, w);
		for (int i = 0; i < 3; i++) {
			for (int j = 0; j < 3; j++) {
				for (int k = 0; k < 3; k++) {
					const int ix = base[0] + i, iy = base[1] + j, iz = base[2] + k;
					if (ix < 0 || iy < 0 || iz < 0 || ix >= _dim || iy >= _dim || iz >= _dim) {
						continue;
					}
					const Vector3 dpos = (Vector3(i, j, k) - fx) * _dx; // particle→node (world)
					const double weight = w[0][i] * w[1][j] * w[2][k];
					const int n = ix + iy * _dim + iz * _dim * _dim;
					_gv[n] += (_v[p] * _mass[p] + affine.xform(dpos)) * weight;
					_gm[n] += weight * _mass[p];
				}
			}
		}
	}
}

// Outward normal of the collider at p: normalized SDF gradient (central differences).
Vector3 MpmSim::_collider_normal(const Vector3 &p) const {
	const double h = 0.5 * _dx;
	const Vector3 g(
			_collider->sample(p + Vector3(h, 0, 0)) - _collider->sample(p - Vector3(h, 0, 0)),
			_collider->sample(p + Vector3(0, h, 0)) - _collider->sample(p - Vector3(0, h, 0)),
			_collider->sample(p + Vector3(0, 0, h)) - _collider->sample(p - Vector3(0, 0, h)));
	const double len = g.length();
	return len > 1e-9 ? g / len : Vector3(0, 1, 0);
}

// Resolve contact for one grid node: if it's inside the collider and moving inward, remove
// the inward-normal velocity and apply friction to what's left. SDF terrain when set, else
// a flat floor plane (the bare-core fallback).
void MpmSim::_apply_collider(const Vector3 &world, Vector3 &v) const {
	if (_collider.is_valid()) {
		if (_collider->sample(world) < 0.0) { // node inside solid terrain
			const Vector3 nrm = _collider_normal(world);
			const double vn = v.dot(nrm);
			if (vn < 0.0) {
				v -= nrm * vn; // strip the component driving into the surface
				v *= (1.0 - _friction);
			}
		}
		return;
	}
	if (world.y <= _floor_y && v.y < 0.0) {
		v.y = 0.0;
		v.x *= (1.0 - _friction);
		v.z *= (1.0 - _friction);
	}
}

// Momentum→velocity, gravity, collider + domain-wall boundaries (contact resolved on the grid).
void MpmSim::_grid_update(double dt) {
	for (int iz = 0; iz < _dim; iz++) {
		for (int iy = 0; iy < _dim; iy++) {
			for (int ix = 0; ix < _dim; ix++) {
				const int n = ix + iy * _dim + iz * _dim * _dim;
				if (_gm[n] <= 0.0) {
					continue;
				}
				Vector3 v = _gv[n] / _gm[n];
				v += _gravity * dt;
				_apply_collider(Vector3(_origin.x + ix * _dx, _origin.y + iy * _dx, _origin.z + iz * _dx), v);
				// Keep material inside the grid: kill velocity heading out of the domain.
				if ((ix < 2 && v.x < 0.0) || (ix >= _dim - 2 && v.x > 0.0)) {
					v.x = 0.0;
				}
				if ((iy < 2 && v.y < 0.0) || (iy >= _dim - 2 && v.y > 0.0)) {
					v.y = 0.0;
				}
				if ((iz < 2 && v.z < 0.0) || (iz >= _dim - 2 && v.z > 0.0)) {
					v.z = 0.0;
				}
				_gv[n] = v;
			}
		}
	}
}

// Gather velocity + rebuild the APIC affine matrix, then advect.
void MpmSim::_g2p(double dt) {
	const double dinv = 4.0 * _inv_dx * _inv_dx;
	const int np = int(_x.size());
	for (int p = 0; p < np; p++) {
		int base[3];
		Vector3 fx;
		double w[3][3];
		_stencil(_x[p], base, fx, w);
		Vector3 nv;
		Mat3 nc = Mat3::zero();
		for (int i = 0; i < 3; i++) {
			for (int j = 0; j < 3; j++) {
				for (int k = 0; k < 3; k++) {
					const int ix = base[0] + i, iy = base[1] + j, iz = base[2] + k;
					if (ix < 0 || iy < 0 || iz < 0 || ix >= _dim || iy >= _dim || iz >= _dim) {
						continue;
					}
					const Vector3 dpos = (Vector3(i, j, k) - fx) * _dx;
					const double weight = w[0][i] * w[1][j] * w[2][k];
					const Vector3 g_v = _gv[ix + iy * _dim + iz * _dim * _dim];
					nv += g_v * weight;
					nc = nc + Mat3::outer(g_v, dpos).scaled(dinv * weight); // APIC affine
				}
			}
		}

		if (_sleep_enabled && _sleeping[p]) {
			// Asleep: don't advect. Wake if the grid is now pushing it (a disturbance arrived).
			if (nv.length() > _wake_speed) {
				_sleeping[p] = 0;
				_still[p] = 0;
				_awake_count++;
			}
			continue;
		}

		_v[p] = nv;
		_C[p] = nc;
		_x[p] += nv * dt;
		_maybe_sleep(p, nv.length(), dt, dinv);
	}
}

void MpmSim::_maybe_sleep(int p, double nv_len, double dt, double dinv) {
	if (!_sleep_enabled) {
		return;
	}
	if (nv_len >= _sleep_speed) {
		_still[p] = 0;
		return;
	}
	if (++_still[p] < _sleep_after) {
		return;
	}
	// Sleep: freeze in place and cache the (C = 0) P2G affine so support holds without
	// re-running the SVD while asleep.
	_v[p] = Vector3();
	_C[p] = Mat3::zero();
	_affine[p] = _stress(_F[p]).scaled(-dt * _vol[p] * dinv);
	_sleeping[p] = 1;
	_awake_count--;
}

Vector3 MpmSim::average_position() const {
	Vector3 sum;
	const int np = int(_x.size());
	for (int i = 0; i < np; i++) {
		sum += _x[i];
	}
	return np > 0 ? sum / double(np) : sum;
}

double MpmSim::lowest_y() const {
	double lo = INFINITY;
	for (uint32_t i = 0; i < _x.size(); i++) {
		lo = MIN(lo, _x[i].y);
	}
	return lo;
}

double MpmSim::kinetic_energy() const {
	double e = 0.0;
	for (uint32_t i = 0; i < _x.size(); i++) {
		e += 0.5 * _mass[i] * _v[i].length_squared();
	}
	return e;
}

bool MpmSim::is_finite() const {
	for (uint32_t i = 0; i < _x.size(); i++) {
		if (!_x[i].is_finite() || !_v[i].is_finite()) {
			return false;
		}
	}
	return true;
}

Dictionary MpmSim::debug_svd(Basis m) const {
	Mat3 f;
	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			f.m[i][j] = m.rows[i][j];
		}
	}
	Mat3 u, v;
	double s[3];
	f.svd(u, s, v);
	Mat3 sig = Mat3::zero();
	sig.m[0][0] = s[0];
	sig.m[1][1] = s[1];
	sig.m[2][2] = s[2];
	const Mat3 recon = u * sig * v.transposed();
	double err = 0.0;
	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			const double d = recon.m[i][j] - f.m[i][j];
			err += d * d;
		}
	}
	Dictionary out;
	out["error"] = Math::sqrt(err);
	out["det_u"] = u.determinant();
	out["det_v"] = v.determinant();
	out["s0"] = s[0];
	out["s1"] = s[1];
	out["s2"] = s[2];
	return out;
}

void MpmSim::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "origin", "dim", "dx", "gravity", "E", "nu", "floor_y"), &MpmSim::configure);
	ClassDB::bind_method(D_METHOD("set_material", "m"), &MpmSim::set_material);
	ClassDB::bind_method(D_METHOD("set_contact_friction", "f"), &MpmSim::set_contact_friction);
	ClassDB::bind_method(D_METHOD("set_sand_friction", "friction_angle_degrees"), &MpmSim::set_sand_friction);
	ClassDB::bind_method(D_METHOD("set_sdf_collider", "store"), &MpmSim::set_sdf_collider);
	ClassDB::bind_method(D_METHOD("set_sleeping", "on"), &MpmSim::set_sleeping);
	ClassDB::bind_method(D_METHOD("set_sleep_params", "speed", "after", "wake_speed"), &MpmSim::set_sleep_params);
	ClassDB::bind_method(D_METHOD("awake_count"), &MpmSim::awake_count);
	ClassDB::bind_method(D_METHOD("is_asleep"), &MpmSim::is_asleep);
	ClassDB::bind_method(D_METHOD("wake_all"), &MpmSim::wake_all);
	ClassDB::bind_method(D_METHOD("wake_region", "center", "radius"), &MpmSim::wake_region);
	ClassDB::bind_method(D_METHOD("debug_svd", "m"), &MpmSim::debug_svd);
	ClassDB::bind_method(D_METHOD("rasterize_to_store", "store", "cell", "radius", "material_index"), &MpmSim::rasterize_to_store);
	ClassDB::bind_method(D_METHOD("add_particle", "pos", "mass", "volume"), &MpmSim::add_particle);
	ClassDB::bind_method(D_METHOD("step", "dt"), &MpmSim::step);
	ClassDB::bind_method(D_METHOD("particle_count"), &MpmSim::particle_count);
	ClassDB::bind_method(D_METHOD("get_position", "i"), &MpmSim::get_position);
	ClassDB::bind_method(D_METHOD("get_velocity", "i"), &MpmSim::get_velocity);
	ClassDB::bind_method(D_METHOD("average_position"), &MpmSim::average_position);
	ClassDB::bind_method(D_METHOD("lowest_y"), &MpmSim::lowest_y);
	ClassDB::bind_method(D_METHOD("kinetic_energy"), &MpmSim::kinetic_energy);
	ClassDB::bind_method(D_METHOD("is_finite"), &MpmSim::is_finite);
}
