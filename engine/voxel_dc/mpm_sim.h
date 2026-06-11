#ifndef MPM_SIM_H
#define MPM_SIM_H

// MLS-MPM (Moving Least Squares Material Point Method) structural-physics spike — the
// continuum solver that docs/roadmap/design/12-mpm-structural-substrate.md argues should
// replace PBD. This is the SPIKE core (increment 1): particles carry mass / velocity /
// deformation gradient F / APIC affine matrix C; one explicit MLS-MPM step transfers
// particle→grid (P2G), updates grid velocity under gravity + a floor collider, and
// transfers grid→particle (G2P) with the APIC affine reconstruction (the near-lossless
// transfer — doc 12 "error budget"). Elasticity is neo-Hookean (Kirchhoff stress
// τ = μ(FFᵀ − I) + λ ln J · I) so it needs no 3×3 SVD; fixed-corotated + Drucker-Prager
// (which do) land in a later increment. Not wired into the world — headless-tested only,
// per the spike's go/no-go. APIC: Jiang 2015; MLS-MPM: Hu 2018.

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
	LocalVector<Vector3> _v;    // velocity
	LocalVector<Mat3> _F;       // deformation gradient
	LocalVector<Mat3> _C;       // APIC affine velocity matrix
	LocalVector<double> _mass;
	LocalVector<double> _vol;   // initial volume V₀

	// Background grid (dense for the spike; sparse/sleeping is a later increment). One
	// node per lattice point; index = i + j·dim + k·dim². Node world pos = origin + idx·dx.
	LocalVector<Vector3> _gv;   // grid velocity (momentum during P2G, velocity after)
	LocalVector<double> _gm;    // grid mass

	Vector3 _origin = Vector3(0, 0, 0);
	int _dim = 32;              // nodes per axis
	double _dx = 1.0;
	double _inv_dx = 1.0;

	Vector3 _gravity = Vector3(0.0, -9.8, 0.0);
	double _mu = 0.0;          // Lamé μ (shear)
	double _lambda = 0.0;      // Lamé λ

	// Sparse sleeping (doc 12 "design the boundary away"). A particle still for _sleep_after
	// steps stops being stepped: its P2G contribution is CACHED (no SVD, support preserved
	// losslessly — F/stress kept), G2P skips it (it doesn't move), and it re-wakes when the
	// grid velocity at its location exceeds _wake_speed. A fully-asleep sim's step() is a
	// no-op ("a quiescent structure costs nothing"). Off by default so the bare-physics tests
	// are unaffected.
	bool _sleep_enabled = false;
	LocalVector<uint8_t> _sleeping;
	LocalVector<int32_t> _still;
	LocalVector<Mat3> _affine; // cached P2G affine while asleep (F frozen, C = 0)
	int _awake_count = 0;
	double _sleep_speed = 0.05;
	int _sleep_after = 80;
	double _wake_speed = 0.2;

	// Constitutive model. NEO_HOOKEAN needs no SVD (the increment-1 default); COROTATED uses
	// the polar rotation R = UVᵀ so a stiff body holds its shape; SAND is Drucker-Prager
	// elastoplasticity (Klár 2016) — granular flow that piles at an angle of repose.
	int _material = 0;         // 0 = neo-Hookean, 1 = fixed-corotated, 2 = sand
	double _alpha = 0.0;       // Drucker-Prager friction coefficient (from the friction angle)

	// Kirchhoff stress τ for the active model; may plastically update `f` (sand return-map).
	Mat3 _stress(Mat3 &f) const;
	Mat3 _sand(Mat3 &f) const; // Drucker-Prager return-mapping + log-strain (Hencky) stress

	// Static collider. With a `_collider` EditStore set, contact is resolved against its SDF
	// (the real terrain) — grid nodes inside solid lose their inward-normal velocity (normal
	// = SDF gradient), which is the grid-resolved contact PBD lacked. Without one, a flat
	// floor at world y = _floor_y is the fallback (keeps the bare-core tests collider-free).
	Ref<EditStore> _collider;
	double _floor_y = 0.0;
	// Contact friction as a per-contact tangential damping. Kept LOW because it compounds
	// every step a node stays in contact — a high value grips a resting pile's base and
	// stops it spreading (a granular pile's repose should come from the material's own
	// Drucker-Prager friction, not the floor). Coulomb-correct friction is a later refinement.
	double _friction = 0.0;

	int _grid_count() const { return _dim * _dim * _dim; }

	// Apply the static collider to a grid node's velocity (SDF terrain if set, else floor).
	void _apply_collider(const Vector3 &world, Vector3 &v) const;
	Vector3 _collider_normal(const Vector3 &p) const; // outward = normalized SDF gradient

	// One MLS-MPM step, split into its three phases (share the quadratic-B-spline stencil).
	void _p2g(double dt);
	void _grid_update(double dt);
	void _g2p(double dt);
	// Quadratic-B-spline stencil for a particle at `pos`: the base node (lower corner of the
	// 3³ neighbourhood), the fractional offset `fx`, and the per-axis weights w[axis][0..2].
	void _stencil(const Vector3 &pos, int base[3], Vector3 &fx, double w[3][3]) const;

public:
	// E = Young's modulus, nu = Poisson's ratio → Lamé μ, λ.
	void configure(Vector3 origin, int dim, double dx, Vector3 gravity, double E, double nu, double floor_y);
	void set_material(int m) { _material = m; }
	void set_contact_friction(double f) { _friction = f; } // floor/SDF tangential damping
	void set_sand_friction(double friction_angle_degrees); // sets _alpha for the SAND model
	void set_sdf_collider(const Ref<EditStore> &store) { _collider = store; }
	void set_sleeping(bool on) { _sleep_enabled = on; }
	void set_sleep_params(double speed, int after, double wake_speed);
	int add_particle(Vector3 pos, double mass, double volume);
	void step(double dt);

	int awake_count() const { return _awake_count; }
	bool is_asleep() const { return _sleep_enabled && _awake_count == 0; }
	void wake_all();
	void wake_region(Vector3 center, double radius);

	// Test hook: SVD a matrix and report {error (reconstruction Frobenius), det_u, det_v,
	// s0, s1, s2}. Lets the GDScript suite pin the SVD — the riskiest numerical code here.
	Dictionary debug_svd(Basis m) const;

	int particle_count() const { return int(_x.size()); }
	Vector3 get_position(int i) const { return _x[i]; }
	Vector3 get_velocity(int i) const { return _v[i]; }
	Vector3 average_position() const;
	double lowest_y() const;
	double kinetic_energy() const;
	bool is_finite() const; // false if any particle went NaN/Inf (blew up)

protected:
	static void _bind_methods();
};

#endif // MPM_SIM_H
