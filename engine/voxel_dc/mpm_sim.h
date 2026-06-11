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

#include "core/object/ref_counted.h"
#include "core/templates/local_vector.h"
#include "core/math/vector3.h"

// Minimal 3×3 double matrix for the solver kernel — Basis is rotation-oriented and lacks
// the +/scalar/outer-product ops a continuum step needs, so a purpose-built type is clearer.
struct Mat3 {
	double m[3][3];

	static Mat3 identity();
	static Mat3 zero();
	static Mat3 outer(const Vector3 &a, const Vector3 &b); // a ⊗ b (a bᵀ)

	Mat3 operator*(const Mat3 &o) const;
	Mat3 operator+(const Mat3 &o) const;
	Mat3 operator-(const Mat3 &o) const;
	Mat3 scaled(double s) const;
	Vector3 xform(const Vector3 &v) const; // m · v
	Mat3 transposed() const;
	double determinant() const;
};

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

	// Floor collider at world y = _floor_y: grid nodes at/below it lose downward velocity
	// and have tangential velocity scaled by (1 − _friction). The first SDF-collider proof;
	// the EditStore-SDF collider replaces this in a later increment.
	double _floor_y = 0.0;
	double _friction = 0.5;

	int _grid_count() const { return _dim * _dim * _dim; }

public:
	// E = Young's modulus, nu = Poisson's ratio → Lamé μ, λ.
	void configure(Vector3 origin, int dim, double dx, Vector3 gravity, double E, double nu, double floor_y);
	int add_particle(Vector3 pos, double mass, double volume);
	void step(double dt);

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
