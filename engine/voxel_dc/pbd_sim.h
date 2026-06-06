#ifndef PBD_SIM_H
#define PBD_SIM_H

// Position-Based Dynamics (XPBD) structural solver in C++. Holds the particle
// network (positions + breakable distance-constraint "members") and steps it.
// A C++ port of scripts/structural/pbd/{pbd_network,pbd_solver}.gd — the GDScript
// builder (PbdNetworkBuilder) populates one of these via add_node/add_member, then
// calls step() each physics tick. Members break on AXIAL FORCE (from the XPBD
// multiplier), not strain. get_stress_geometry() returns line verts + stress
// colours for the renderer in one call (no per-member GDScript round-trips).

#include "core/object/ref_counted.h"
#include "core/templates/local_vector.h"
#include "core/math/vector3.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"

class PbdSim : public RefCounted {
	GDCLASS(PbdSim, RefCounted)

	// Double precision throughout: this is a precision=double build (Vector3 is
	// double), and at near-rigid stiffness float32 rounding buckles symmetric
	// structures over time.
	LocalVector<Vector3> _pos;
	LocalVector<Vector3> _vel;
	LocalVector<Vector3> _prev;
	LocalVector<double> _inv_mass;

	LocalVector<int32_t> _ma;
	LocalVector<int32_t> _mb;
	LocalVector<double> _rest;
	LocalVector<double> _compliance;
	LocalVector<double> _tension;     // max tensile force
	LocalVector<double> _compression; // max compressive force
	LocalVector<double> _lambda;      // XPBD multiplier, reset per substep
	LocalVector<double> _force;       // peak signed axial force this step (+tension)
	LocalVector<double> _damage;      // fatigue accumulator [0,1]; breaks at 1
	LocalVector<uint8_t> _broken;

	// Fatigue: an overloaded member doesn't snap instantly — damage accrues ∝ overload
	// and it fails after a delay that shrinks with load (creep), healing if relieved.
	// _fatigue_inv_tau = 1 / (seconds-to-break at 2× the limit).
	double _fatigue_inv_tau = 0.8;

	// Sleeping. A settled node stops integrating + its both-asleep members are
	// skipped, so a quiescent structure costs nothing. A node may sleep only when
	// it is BOTH slow AND not carrying near-limit load — otherwise a rigid,
	// overstressed member (which barely moves) would sleep and never break.
	LocalVector<uint8_t> _sleeping;
	LocalVector<int32_t> _still;      // consecutive low-motion steps
	int _awake_count = 0;             // awake dynamic nodes; step() is a no-op at 0
	double _sleep_speed = 0.02;       // m/s below which a node counts as still
	int _sleep_after = 24;            // still steps before sleeping (~0.4s @ 60Hz)
	double _wake_strain = 0.02;       // constraint error (m) that wakes a strained neighbour
	double _sleep_force_frac = 0.5;   // a node stays awake while a member exceeds this × limit

	// Per-step scratch (capacity reused across steps; not part of the model).
	LocalVector<int32_t> _active;     // member indices with ≥1 awake endpoint
	LocalVector<uint8_t> _wake_req;   // per-node wake request, applied at end of step
	LocalVector<uint8_t> _hot;        // per-node: incident member near its limit this step

	Vector3 _gravity = Vector3(0.0, -9.8, 0.0);
	int _substeps = 4;
	int _iterations = 8;
	double _damping = 0.99;
	bool _broke_last_step = false;

	bool _awake_dyn(int i) const { return _inv_mass[i] > 0.0 && _sleeping[i] == 0; }

public:
	void configure(Vector3 gravity, int substeps, int iterations, double damping);
	void set_sleep_params(double speed, int after, double wake_strain, double force_frac);
	void set_fatigue(double seconds_to_break_at_double_load);
	int add_node(Vector3 p, double mass);
	int add_member(int a, int b, double compliance, double tension, double compression);
	void step(double dt);

	int node_count() const { return int(_pos.size()); }
	int member_count() const { return int(_ma.size()); }
	int live_member_count() const;
	Vector3 get_position(int i) const { return _pos[i]; }
	bool is_pinned(int i) const { return _inv_mass[i] == 0.0; }
	int member_a(int k) const { return _ma[k]; }
	int member_b(int k) const { return _mb[k]; }
	double member_force(int k) const { return _force[k]; }
	double member_tension(int k) const { return _tension[k]; }
	double member_compression(int k) const { return _compression[k]; }
	double member_damage(int k) const { return _damage[k]; }
	bool member_broken(int k) const { return _broken[k] != 0; }
	bool broke_last_step() const { return _broke_last_step; }

	int awake_count() const { return _awake_count; }
	bool is_sleeping(int i) const { return _sleeping[i] != 0; }
	void wake_all();

	// Connected components (over live members) that contain NO pinned anchor —
	// structure that has come loose and is falling. Array of PackedInt32Array (node
	// indices per component). Empty while everything is still anchored.
	Array get_detached_components() const;

	// { verts: PackedVector3Array (line pairs), colors: PackedColorArray } for live
	// members, coloured green→red by force/limit. One call per draw.
	Dictionary get_stress_geometry() const;

protected:
	static void _bind_methods();
};

#endif // PBD_SIM_H
