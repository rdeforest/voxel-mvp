#include "mpm_sim.h"

#include "core/math/math_funcs.h"

// PB-MPM constitutive code (Lewin 2024): the per-particle constraint projection
// (SolveConstraints, run each iteration) and the post-iteration integration (F update + safety
// clamp). Elastic this increment; PB-MPM sand (Drucker-Prager on the integrated F + logJp) is
// the next. The grid transfers and mechanics live in mpm_sim.cpp.

static double sgn(double x) {
	return x < 0.0 ? -1.0 : 1.0;
}

// Elastic constraint target for a candidate F*: blend the rotation (shape preservation, α→1)
// with the closest volume-preserving matrix (α→0), per elasticity_ratio.
Mat3 MpmSim::_constraint_target(const Mat3 &fstar) const {
	Mat3 u, v;
	double s[3];
	fstar.svd(u, s, v);
	const double df = fstar.determinant();
	const double cdf = CLAMP(Math::abs(df), 0.1, 1000.0);
	const Mat3 Q = fstar.scaled(1.0 / (sgn(df) * Math::sqrt(cdf)));
	const Mat3 R = u * v.transposed();
	const double a = _elasticity_ratio;
	return R.scaled(a) + Q.scaled(1.0 - a);
}

// Nudge each awake particle's deformation displacement D toward the target that would bring its
// candidate deformation gradient F* = (I+D)F to the constraint shape. Jacobi-style (all particles
// independent) — the iteration loop in step() reconciles them through the grid.
void MpmSim::_solve_constraints() {
	const int np = int(_x.size());
	for (int p = 0; p < np; p++) {
		if (_sleep_enabled && _sleeping[p]) {
			continue;
		}
		const Mat3 fstar = (Mat3::identity() + _D[p]) * _F[p];
		const Mat3 tgt = _constraint_target(fstar);
		const Mat3 diff = (tgt * _F[p].inverse() - Mat3::identity()) - _D[p];
		_D[p] = _D[p] + diff.scaled(_elastic_relaxation);
	}
}

// Evolve F ← (I+D)F (with an SVD safety clamp on the singular values to stop force blow-ups),
// advect x by the displacement, seed gravity into the displacement for the next step, and push
// out of the collider at the particle level (the grid did most of the contact work).
void MpmSim::_integrate(double dt) {
	const Vector3 g_disp = _gravity * (dt * dt);
	const int np = int(_x.size());
	for (int p = 0; p < np; p++) {
		if (_sleep_enabled && _sleeping[p]) {
			continue;
		}
		_F[p] = (Mat3::identity() + _D[p]) * _F[p];
		Mat3 u, v;
		double s[3];
		_F[p].svd(u, s, v);
		for (int a = 0; a < 3; a++) {
			s[a] = CLAMP(s[a], 0.2, 10000.0);
		}
		Mat3 sig = Mat3::zero();
		sig.m[0][0] = s[0];
		sig.m[1][1] = s[1];
		sig.m[2][2] = s[2];
		_F[p] = u * sig * v.transposed();

		_x[p] += _d[p];
		_d[p] += g_disp;

		if (_collider.is_valid()) {
			const double sd = _collider->sample(_x[p]);
			if (sd < 0.0) {
				_x[p] -= _collider_normal(_x[p]) * sd;
			}
		} else if (_x[p].y < _floor_y) {
			_x[p].y = _floor_y;
		}
	}
}
