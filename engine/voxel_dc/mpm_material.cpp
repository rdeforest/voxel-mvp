#include "mpm_sim.h"

#include "core/math/math_funcs.h"

// PB-MPM constitutive code (Lewin 2024): the per-particle constraint projection
// (SolveConstraints, run each iteration) and the post-iteration integration (F update +
// plasticity). Elastic + Drucker-Prager sand. The grid transfers/mechanics live in mpm_sim.cpp.

static double sgn(double x) {
	return x < 0.0 ? -1.0 : 1.0;
}

static Mat3 diag3(double a, double b, double c) {
	Mat3 m = Mat3::zero();
	m.m[0][0] = a;
	m.m[1][1] = b;
	m.m[2][2] = c;
	return m;
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

// Sand constraint target: like elastic but the shape target is the (volume-clamped) candidate
// itself rather than a pure rotation, and the volume target only resists compression (cdf ≤ 1).
static Mat3 sand_target(const Mat3 &fstar, double logjp, double ratio) {
	Mat3 u, v;
	double s[3];
	fstar.svd(u, s, v);
	if (logjp == 0.0) {
		for (int i = 0; i < 3; i++) {
			s[i] = CLAMP(s[i], 1.0, 1000.0);
		}
	}
	const double df = fstar.determinant();
	const double cdf = CLAMP(Math::abs(df), 0.1, 1.0);
	const Mat3 Q = fstar.scaled(1.0 / (sgn(df) * Math::sqrt(cdf)));
	const Mat3 shape = u * diag3(s[0], s[1], s[2]) * v.transposed();
	return shape.scaled(ratio) + Q.scaled(1.0 - ratio);
}

void MpmSim::_solve_constraints() {
	const int np = int(_x.size());
	for (int p = 0; p < np; p++) {
		if (_sleep_enabled && _sleeping[p]) {
			continue;
		}
		const Mat3 fstar = (Mat3::identity() + _D[p]) * _F[p];
		const Mat3 tgt = (_material == 2) ? sand_target(fstar, _logJp[p], _elasticity_ratio) : _constraint_target(fstar);
		const Mat3 diff = (tgt * _F[p].inverse() - Mat3::identity()) - _D[p];
		_D[p] = _D[p] + diff.scaled(_elastic_relaxation);
		if (_material == 2 && _viscosity > 0.0) {
			// Remove the deviatoric (shear) part of D — granular viscous damping.
			const Mat3 deviatoric = (_D[p] + _D[p].transposed()).scaled(-1.0);
			_D[p] = _D[p] + deviatoric.scaled(_viscosity * 0.5);
		}
	}
}

// Drucker-Prager return-mapping (Klár 2016) on the singular values, with logJp hardening.
// Projects the Hencky strain onto the cohesionless yield cone; expansion forgets all strain.
void MpmSim::_drucker_prager(double s[3], double &logjp) const {
	const double sin_phi = Math::sin(Math::deg_to_rad(_friction_angle));
	const double alpha = Math::sqrt(2.0 / 3.0) * 2.0 * sin_phi / (3.0 - sin_phi);
	const double beta = 0.5;
	double e[3];
	double tr = logjp;
	for (int i = 0; i < 3; i++) {
		e[i] = Math::log(MAX(Math::abs(s[i]), 1e-6));
		tr += e[i];
	}
	double ehat[3];
	double frob = 0.0;
	for (int i = 0; i < 3; i++) {
		ehat[i] = e[i] - tr / 3.0;
		frob += ehat[i] * ehat[i];
	}
	frob = Math::sqrt(frob);
	if (tr >= 0.0) {
		s[0] = s[1] = s[2] = 1.0; // expansion: forget all deformation
		logjp = beta * tr;
		return;
	}
	logjp = 0.0;
	const double dgamma = frob + (_elasticity_ratio + 1.0) * tr * alpha;
	if (dgamma > 0.0 && frob > 1e-9) {
		for (int i = 0; i < 3; i++) {
			s[i] = Math::exp(e[i] - dgamma / frob * ehat[i]);
		}
	}
}

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
			s[a] = CLAMP(s[a], 0.2, 10000.0); // safety: stop force blow-ups from a degenerate F
		}
		if (_material == 2) {
			_drucker_prager(s, _logJp[p]);
		}
		_F[p] = u * diag3(s[0], s[1], s[2]) * v.transposed();

		_x[p] += _d[p];
		_d[p] = _d[p] * (1.0 - _damping) + g_disp; // damp the carried velocity so it settles

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
