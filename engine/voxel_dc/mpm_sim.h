#ifndef MPM_SIM_H
#define MPM_SIM_H

// PB-MPM (Position Based Material Point Method) structural-physics solver — the continuum
// substrate that docs/roadmap/design/12-mpm-structural-substrate.md adopts to replace PBD.
// Following Lewin 2024 (EA SEED): a semi-implicit compliant-constraint MPM that is
// UNCONDITIONALLY STABLE at any timestep, over the MLS-MPM grid transfer (Hu 2018, APIC).
// Everything works in DISPLACEMENT (= velocity·dt): particles carry position, displacement d,
// a deformation-displacement matrix D (the APIC affine of displacement), and a deformation
// gradient F. One timestep iterates [SolveConstraints → P2G → GridUpdate → G2P] iterationCount
// times, then integrates (F ← (I+D)F with plasticity; x += d; d gets gravity for the next
// step). SolveConstraints replaces explicit stress with a per-particle constraint projection
// (elastic: toward the polar/volume-preserving target; sand: + Drucker-Prager). The 3×3 polar
// SVD, the SDF collider, sparse sleeping, and the EditStore thaw/freeze coupling carry over
// from the explicit spike. Not yet wired into the world — headless-tested.

#include "mat3.h"
#include "edit_store.h"

#include "core/object/ref_counted.h"
#include "core/templates/local_vector.h"
#include "core/math/vector3.h"
#include "core/math/basis.h"
#include "core/variant/dictionary.h"

class MpmSim : public RefCounted {
	GDCLASS(MpmSim, RefCounted)

	// Particles (one entry per index).
	LocalVector<Vector3> _x;    // position (world)
	LocalVector<Vector3> _d;    // displacement this step (= velocity·dt; carries gravity over)
	LocalVector<Mat3>    _D;    // deformation displacement (APIC affine of displacement)
	LocalVector<Mat3>    _F;    // deformation gradient
	LocalVector<double>  _mass;
	LocalVector<double>  _vol;  // initial volume V₀
	LocalVector<double>  _logJp;// sand: log of plastic volume (Drucker-Prager hardening)
	LocalVector<int32_t> _pmat; // material index — the cell each particle was thawed from; carried
	                            // back on freeze so a mixed chunk re-deposits per-cell, not as one material

	// Background grid. One node per lattice point; index = i + j·dim + k·dim². The grid carries
	// displacement-momentum during P2G, then mass-weighted displacement after GridUpdate.
	LocalVector<Vector3> _grid_disp;
	LocalVector<double>  _grid_mass;

	Vector3 _origin  = Vector3(0, 0, 0);
	int     _dim     = 32;              // nodes per axis
	double  _dx      = 1.0;
	double  _inv_dx  = 1.0;

	Vector3 _gravity = Vector3(0.0, -9.8, 0.0);

	// PB-MPM constraint parameters (Lewin 2024). iterations = the Jacobi-style outer loop
	// (more = stiffer/converged). elasticity_ratio α blends the constraint target between the
	// rotation (shape preservation, α→1) and the volume-preserving shape (α→0). relaxation is
	// how far D moves toward the target each iteration.
	int    _material           = 0;    // 0/1 = elastic, 2 = sand
	int    _iterations         = 5;
	double _elasticity_ratio   = 1.0;  // rotation (shape-preserving) target — stable default
	double _elastic_relaxation = 0.5;  // under-relaxed; high relax + many iters can over-drive
	double _friction_angle     = 35.0; // sand (degrees)
	double _viscosity          = 0.0;  // deviatoric damping (sand uses a little)
	double _damping            = 0.0;  // global velocity damping per step — dissipates energy so
	                                   // material actually comes to rest (PB-MPM otherwise conserves
	                                   // it: a frictionless body slides/bounces forever).

	// When set, the world-fixed grid re-centres on the particle centroid each step so the
	// material never reaches the domain walls (the grid is scratch — rebuilt every step — so
	// shifting the origin is free). The active region follows the material, like the DC
	// collision regions follow bodies. Off by default (the tests pin a fixed grid).
	bool _recenter = false;

	// Static collider. With a `_collider` EditStore set, contact is resolved against its SDF
	// (the real terrain) — a grid node whose displaced position lands inside solid is pushed
	// back out along the SDF normal (the grid-resolved contact PBD lacked). Without one, a flat
	// floor at world y = _floor_y is the fallback (keeps the bare-core tests collider-free).
	Ref<EditStore> _collider;
	double _floor_y  = 0.0;
	double _friction = 0.0; // tangential damping on contact (kept low; see the explicit spike notes)

	// Sparse sleeping (doc 12). A particle whose displacement stays below _sleep_speed·dt for
	// _sleep_after steps stops being solved/advected: its P2G contribution is cached (D frozen,
	// d = 0), and it re-wakes when the grid displacement at its location exceeds _wake_speed·dt.
	// A fully-asleep sim's step() is a no-op. Off by default so the bare-physics tests are clean.
	bool                 _sleep_enabled = false;
	LocalVector<uint8_t> _sleeping;
	LocalVector<int32_t> _still;
	int                  _awake_count   = 0;
	double               _sleep_speed   = 0.05;
	int                  _sleep_after   = 80;
	double               _wake_speed    = 0.2;

	int _grid_count() const { return _dim * _dim * _dim; }

	// PB-MPM timestep phases.
	void _solve_constraints();              // per-particle constraint projection → D
	void _p2g();                            // scatter mass + displacement-momentum
	void _grid_update();                    // mass-weight + collider (displacement form)
	void _g2p();                            // gather displacement + rebuild D, sleep transition
	void _integrate(double dt);             // F ← (I+D)F (+plasticity); x += d; gravity; wake/push

	void _apply_collider(const Vector3 &node_world, Vector3 &disp) const;
	Vector3 _collider_normal(const Vector3 &p) const; // outward = normalized SDF gradient
	void _stencil(const Vector3 &pos, int base[3], Vector3 &fx, double w[3][3]) const;
	Mat3 _constraint_target(const Mat3 &f) const;    // elastic α·R + (1−α)·vol-preserving
	void _drucker_prager(double s[3], double &logjp) const; // sand plasticity on the singular values

public:
	void configure(Vector3 origin, int dim, double dx, Vector3 gravity, double floor_y);
	void set_material(int m) { _material = m; }
	void set_iterations(int n) { _iterations = n; }
	void set_elastic(double ratio, double relaxation) { _elasticity_ratio = ratio; _elastic_relaxation = relaxation; }
	void set_contact_friction(double f) { _friction = f; }
	void set_sand_friction(double friction_angle_degrees) { _friction_angle = friction_angle_degrees; }
	void set_viscosity(double v) { _viscosity = v; }
	void set_damping(double d) { _damping = d; } // global velocity damping so material settles
	void set_recenter(bool on) { _recenter = on; } // grid follows the material centroid
	void set_sdf_collider(const Ref<EditStore> &store) { _collider = store; }
	void set_sleeping(bool on) { _sleep_enabled = on; }
	void set_sleep_params(double speed, int after, double wake_speed);
	int add_particle(Vector3 pos, double mass, double volume, int material = 0);
	void clear(); // drop all particles (after a freeze-back); keeps the grid config
	void step(double dt);

	// Largest particle displacement magnitude last step — a settle gauge for the freeze trigger.
	double max_displacement() const;

	int awake_count() const { return _awake_count; }
	bool is_asleep() const { return _sleep_enabled && _awake_count == 0; }
	void wake_all();
	void wake_region(Vector3 center, double radius);

	// Test hook: SVD a matrix and report {error, det_u, det_v, s0, s1, s2}. Pins the SVD.
	Dictionary debug_svd(Basis m) const;

	// Thaw/freeze coupling (mpm_couple.cpp).
	Dictionary rasterize_to_store(Ref<EditStore> store, double cell, double radius, int material_index);
	int thaw_from_store(Ref<EditStore> store, Vector3 origin, int dim, double cell, int ppa, double mass, double volume);

	int particle_count() const { return int(_x.size()); }
	Vector3 get_position(int i) const { return _x[i]; }
	Vector3 get_displacement(int i) const { return _d[i]; }
	Vector3 average_position() const;
	double lowest_y() const;
	double kinetic_energy() const;
	bool is_finite() const; // false if any particle went NaN/Inf (blew up)

protected:
	static void _bind_methods();
};

#endif // MPM_SIM_H
