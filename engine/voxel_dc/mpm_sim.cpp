#include "mpm_sim.h"

#include "core/math/math_funcs.h"

// --- Mat3 ---

Mat3 Mat3::identity() {
	Mat3 r = zero();
	r.m[0][0] = r.m[1][1] = r.m[2][2] = 1.0;
	return r;
}

Mat3 Mat3::zero() {
	Mat3 r;
	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			r.m[i][j] = 0.0;
		}
	}
	return r;
}

Mat3 Mat3::outer(const Vector3 &a, const Vector3 &b) {
	Mat3 r;
	const double av[3] = { a.x, a.y, a.z };
	const double bv[3] = { b.x, b.y, b.z };
	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			r.m[i][j] = av[i] * bv[j];
		}
	}
	return r;
}

Mat3 Mat3::operator*(const Mat3 &o) const {
	Mat3 r = zero();
	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			for (int k = 0; k < 3; k++) {
				r.m[i][j] += m[i][k] * o.m[k][j];
			}
		}
	}
	return r;
}

Mat3 Mat3::operator+(const Mat3 &o) const {
	Mat3 r;
	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			r.m[i][j] = m[i][j] + o.m[i][j];
		}
	}
	return r;
}

Mat3 Mat3::operator-(const Mat3 &o) const {
	Mat3 r;
	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			r.m[i][j] = m[i][j] - o.m[i][j];
		}
	}
	return r;
}

Mat3 Mat3::scaled(double s) const {
	Mat3 r;
	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			r.m[i][j] = m[i][j] * s;
		}
	}
	return r;
}

Vector3 Mat3::xform(const Vector3 &v) const {
	return Vector3(
			m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z,
			m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z,
			m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z);
}

Mat3 Mat3::transposed() const {
	Mat3 r;
	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			r.m[i][j] = m[j][i];
		}
	}
	return r;
}

double Mat3::determinant() const {
	return m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
			m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
			m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
}

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

int MpmSim::add_particle(Vector3 pos, double mass, double volume) {
	_x.push_back(pos);
	_v.push_back(Vector3());
	_F.push_back(Mat3::identity());
	_C.push_back(Mat3::zero());
	_mass.push_back(mass);
	_vol.push_back(volume);
	return int(_x.size()) - 1;
}

void MpmSim::step(double dt) {
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
		// Advance the deformation gradient with last step's affine velocity, then take the
		// neo-Hookean Kirchhoff stress τ = μ(FFᵀ − I) + λ ln(J) I.
		_F[p] = (Mat3::identity() + _C[p].scaled(dt)) * _F[p];
		double J = _F[p].determinant();
		if (J < 1e-4) {
			J = 1e-4; // guard a (near-)inverted particle so ln(J) stays finite
		}
		const Mat3 FFt = _F[p] * _F[p].transposed();
		const Mat3 tau = (FFt - Mat3::identity()).scaled(_mu) + Mat3::identity().scaled(_lambda * Math::log(J));
		const Mat3 affine = tau.scaled(-dt * _vol[p] * dinv) + _C[p].scaled(_mass[p]);

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

// Momentum→velocity, gravity, floor + domain-wall boundaries (contact resolved on the grid).
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
				if (_origin.y + iy * _dx <= _floor_y && v.y < 0.0) {
					v.y = 0.0;
					v.x *= (1.0 - _friction);
					v.z *= (1.0 - _friction);
				}
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
		_v[p] = nv;
		_C[p] = nc;
		_x[p] += nv * dt;
	}
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

void MpmSim::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "origin", "dim", "dx", "gravity", "E", "nu", "floor_y"), &MpmSim::configure);
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
