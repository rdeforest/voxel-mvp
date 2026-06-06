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
	LocalVector<uint8_t> _broken;

	Vector3 _gravity = Vector3(0.0, -9.8, 0.0);
	int _substeps = 4;
	int _iterations = 8;
	double _damping = 0.99;

public:
	void configure(Vector3 gravity, int substeps, int iterations, double damping);
	int add_node(Vector3 p, double mass);
	int add_member(int a, int b, double compliance, double tension, double compression);
	void step(double dt);

	int node_count() const { return int(_pos.size()); }
	int member_count() const { return int(_ma.size()); }
	int live_member_count() const;
	Vector3 get_position(int i) const { return _pos[i]; }
	bool is_pinned(int i) const { return _inv_mass[i] == 0.0; }
	double member_force(int k) const { return _force[k]; }
	bool member_broken(int k) const { return _broken[k] != 0; }

	// { verts: PackedVector3Array (line pairs), colors: PackedColorArray } for live
	// members, coloured green→red by force/limit. One call per draw.
	Dictionary get_stress_geometry() const;

protected:
	static void _bind_methods();
};

#endif // PBD_SIM_H
