#include "pbd_sim.h"

#include "core/math/color.h"
#include "core/math/math_funcs.h"
#include "core/templates/hash_map.h"
#include "core/typedefs.h"
#include "core/variant/variant.h"

static int uf_find(LocalVector<int> &parent, int x) {
	while (parent[x] != x) {
		parent[x] = parent[parent[x]];
		x = parent[x];
	}
	return x;
}

void PbdSim::configure(Vector3 gravity, int substeps, int iterations, double damping) {
	_gravity = gravity;
	_substeps = MAX(1, substeps);
	_iterations = MAX(1, iterations);
	_damping = damping;
}

void PbdSim::set_sleep_params(double speed, int after, double wake_strain, double force_frac) {
	_sleep_speed = MAX(0.0, speed);
	_sleep_after = MAX(1, after);
	_wake_strain = MAX(0.0, wake_strain);
	_sleep_force_frac = CLAMP(force_frac, 0.0, 1.0);
}

void PbdSim::wake_all() {
	for (uint32_t i = 0; i < _sleeping.size(); ++i) {
		if (_inv_mass[i] > 0.0 && _sleeping[i]) {
			_sleeping[i] = 0;
			_still[i] = 0;
			++_awake_count;
		}
	}
}

int PbdSim::add_node(Vector3 p, double mass) {
	int i = int(_pos.size());
	_pos.push_back(p);
	_vel.push_back(Vector3());
	_prev.push_back(p);
	_inv_mass.push_back(mass <= 0.0 ? 0.0 : 1.0 / mass);
	_sleeping.push_back(0);
	_still.push_back(0);
	if (mass > 0.0) {
		++_awake_count;
	}
	return i;
}

int PbdSim::add_member(int a, int b, double compliance, double tension, double compression) {
	int k = int(_ma.size());
	_ma.push_back(a);
	_mb.push_back(b);
	_rest.push_back(_pos[a].distance_to(_pos[b]));
	_compliance.push_back(compliance);
	_tension.push_back(tension);
	_compression.push_back(compression);
	_lambda.push_back(0.0f);
	_force.push_back(0.0f);
	_broken.push_back(0);
	return k;
}

int PbdSim::live_member_count() const {
	int n = 0;
	for (uint32_t k = 0; k < _broken.size(); ++k) {
		if (_broken[k] == 0) {
			++n;
		}
	}
	return n;
}

void PbdSim::step(double dt) {
	const int mc = int(_ma.size());
	const int nc = int(_pos.size());
	if (_awake_count == 0) {
		return; // fully settled: nothing dynamic is awake
	}
	const double h = dt / double(_substeps);
	const double inv_h2 = 1.0 / (h * h);

	_wake_req.resize(nc);
	_hot.resize(nc);
	for (int i = 0; i < nc; ++i) {
		_wake_req[i] = 0;
		_hot[i] = 0;
	}

	// Active members carry the work: anything with an awake dynamic endpoint. A
	// both-asleep (or fully-pinned) member is skipped — that's the saving. Reset
	// peak force only on active members so asleep members keep their last (still
	// accurate) holding force for the stress viz.
	_active.clear();
	for (int k = 0; k < mc; ++k) {
		if (_broken[k]) {
			continue;
		}
		if (_awake_dyn(_ma[k]) || _awake_dyn(_mb[k])) {
			_active.push_back(k);
			_force[k] = 0.0;
		}
	}

	for (int s = 0; s < _substeps; ++s) {
		for (int i = 0; i < nc; ++i) {
			if (!_awake_dyn(i)) {
				continue;
			}
			_prev[i] = _pos[i];
			_vel[i] += _gravity * h;
			_pos[i] += _vel[i] * h;
		}
		for (uint32_t ai = 0; ai < _active.size(); ++ai) {
			_lambda[_active[ai]] = 0.0;
		}
		for (int it = 0; it < _iterations; ++it) {
			for (uint32_t ai = 0; ai < _active.size(); ++ai) {
				const int k = _active[ai];
				const int a = _ma[k];
				const int b = _mb[k];
				// Asleep / pinned endpoints act as infinite mass (rigid anchors).
				const double wa = _awake_dyn(a) ? _inv_mass[a] : 0.0;
				const double wb = _awake_dyn(b) ? _inv_mass[b] : 0.0;
				const double w = wa + wb;
				if (w == 0.0) {
					continue;
				}
				const Vector3 d = _pos[b] - _pos[a];
				const double dist = d.length();
				if (dist == 0.0) {
					continue;
				}
				const Vector3 n = d / dist;
				const double c = dist - _rest[k];
				const double a_tilde = _compliance[k] * inv_h2;
				const double dlambda = (-c - a_tilde * _lambda[k]) / (w + a_tilde);
				_lambda[k] += dlambda;
				const Vector3 corr = n * dlambda;
				_pos[a] -= corr * wa;
				_pos[b] += corr * wb;
				// An awake node straining a shared member wakes its sleeping neighbour.
				if (Math::abs(c) > _wake_strain) {
					if (_inv_mass[a] > 0.0 && _sleeping[a]) {
						_wake_req[a] = 1;
					}
					if (_inv_mass[b] > 0.0 && _sleeping[b]) {
						_wake_req[b] = 1;
					}
				}
			}
		}
		for (int i = 0; i < nc; ++i) {
			if (!_awake_dyn(i)) {
				continue;
			}
			_vel[i] = (_pos[i] - _prev[i]) / h * _damping;
		}
		// The XPBD multiplier is the constraint force: f = -lambda / h^2 (+tension).
		for (uint32_t ai = 0; ai < _active.size(); ++ai) {
			const int k = _active[ai];
			const double f = -_lambda[k] * inv_h2;
			if (Math::abs(f) > Math::abs(_force[k])) {
				_force[k] = f;
			}
		}
	}

	// Breakage (active members only — asleep ones are sub-limit by construction).
	// A break wakes its endpoints so load redistributes / freed mass falls. Mark
	// near-limit endpoints "hot" so an overstressed-but-rigid node stays awake.
	_broke_last_step = false;
	for (uint32_t ai = 0; ai < _active.size(); ++ai) {
		const int k = _active[ai];
		const int a = _ma[k];
		const int b = _mb[k];
		const double f = _force[k];
		if (f > _tension[k] || f < -_compression[k]) {
			_broken[k] = 1;
			_broke_last_step = true;
			if (_inv_mass[a] > 0.0) {
				_wake_req[a] = 1;
			}
			if (_inv_mass[b] > 0.0) {
				_wake_req[b] = 1;
			}
			continue;
		}
		const double limit = f >= 0.0 ? _tension[k] : _compression[k];
		if (limit > 0.0 && Math::abs(f) >= _sleep_force_frac * limit) {
			_hot[a] = 1;
			_hot[b] = 1;
		}
	}

	for (int i = 0; i < nc; ++i) {
		if (_wake_req[i] && _sleeping[i]) {
			_sleeping[i] = 0;
			_still[i] = 0;
			++_awake_count;
		}
	}

	// Sleep the slow, unstressed awake nodes.
	for (int i = 0; i < nc; ++i) {
		if (!_awake_dyn(i)) {
			continue;
		}
		if (_hot[i]) {
			_still[i] = 0;
			continue;
		}
		if (_vel[i].length() < _sleep_speed) {
			if (++_still[i] >= _sleep_after) {
				_sleeping[i] = 1;
				_vel[i] = Vector3();
				--_awake_count;
			}
		} else {
			_still[i] = 0;
		}
	}
}

Array PbdSim::get_detached_components() const {
	Array out;
	const int n = int(_pos.size());
	if (n == 0) {
		return out;
	}
	LocalVector<int> parent;
	parent.resize(n);
	for (int i = 0; i < n; ++i) {
		parent[i] = i;
	}
	for (int k = 0; k < int(_ma.size()); ++k) {
		if (_broken[k]) {
			continue;
		}
		int ra = uf_find(parent, _ma[k]);
		int rb = uf_find(parent, _mb[k]);
		if (ra != rb) {
			parent[ra] = rb;
		}
	}
	HashMap<int, bool> anchored; // component root -> contains a pinned node
	for (int i = 0; i < n; ++i) {
		int r = uf_find(parent, i);
		bool *e = anchored.getptr(r);
		if (e == nullptr) {
			anchored.insert(r, _inv_mass[i] == 0.0);
		} else if (_inv_mass[i] == 0.0) {
			*e = true;
		}
	}
	HashMap<int, PackedInt32Array> comps;
	for (int i = 0; i < n; ++i) {
		int r = uf_find(parent, i);
		if (anchored[r]) {
			continue;
		}
		PackedInt32Array *c = comps.getptr(r);
		if (c == nullptr) {
			comps.insert(r, PackedInt32Array());
			c = comps.getptr(r);
		}
		c->push_back(i);
	}
	for (const KeyValue<int, PackedInt32Array> &kv : comps) {
		out.push_back(kv.value);
	}
	return out;
}

Dictionary PbdSim::get_stress_geometry() const {
	PackedVector3Array verts;
	PackedColorArray colors;
	for (int k = 0; k < int(_ma.size()); ++k) {
		if (_broken[k]) {
			continue;
		}
		const double f = _force[k];
		const double limit = f >= 0.0 ? _tension[k] : _compression[k];
		const double r = CLAMP(Math::abs(f) / MAX(limit, 0.001), 0.0, 1.0);
		const Color col(float(r), float(1.0 - r), 0.0f);
		verts.push_back(_pos[_ma[k]]);
		colors.push_back(col);
		verts.push_back(_pos[_mb[k]]);
		colors.push_back(col);
	}
	Dictionary out;
	out["verts"] = verts;
	out["colors"] = colors;
	return out;
}

void PbdSim::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "gravity", "substeps", "iterations", "damping"), &PbdSim::configure);
	ClassDB::bind_method(D_METHOD("set_sleep_params", "speed", "after", "wake_strain", "force_frac"), &PbdSim::set_sleep_params);
	ClassDB::bind_method(D_METHOD("add_node", "position", "mass"), &PbdSim::add_node);
	ClassDB::bind_method(D_METHOD("add_member", "a", "b", "compliance", "tension", "compression"), &PbdSim::add_member);
	ClassDB::bind_method(D_METHOD("step", "dt"), &PbdSim::step);
	ClassDB::bind_method(D_METHOD("node_count"), &PbdSim::node_count);
	ClassDB::bind_method(D_METHOD("member_count"), &PbdSim::member_count);
	ClassDB::bind_method(D_METHOD("live_member_count"), &PbdSim::live_member_count);
	ClassDB::bind_method(D_METHOD("get_position", "i"), &PbdSim::get_position);
	ClassDB::bind_method(D_METHOD("is_pinned", "i"), &PbdSim::is_pinned);
	ClassDB::bind_method(D_METHOD("member_force", "k"), &PbdSim::member_force);
	ClassDB::bind_method(D_METHOD("member_broken", "k"), &PbdSim::member_broken);
	ClassDB::bind_method(D_METHOD("broke_last_step"), &PbdSim::broke_last_step);
	ClassDB::bind_method(D_METHOD("awake_count"), &PbdSim::awake_count);
	ClassDB::bind_method(D_METHOD("is_sleeping", "i"), &PbdSim::is_sleeping);
	ClassDB::bind_method(D_METHOD("wake_all"), &PbdSim::wake_all);
	ClassDB::bind_method(D_METHOD("get_detached_components"), &PbdSim::get_detached_components);
	ClassDB::bind_method(D_METHOD("get_stress_geometry"), &PbdSim::get_stress_geometry);
}
