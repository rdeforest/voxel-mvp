#include "mpm_sim.h"

#include "core/math/math_funcs.h"

// Constitutive models for MpmSim — the Kirchhoff stress per material, and the SAND
// (Drucker-Prager) plastic return-mapping. Split from the transfer/step machinery in
// mpm_sim.cpp; these are the physics of the material, not the MLS-MPM grid transfer.

// Kirchhoff stress τ = P Fᵀ for the active constitutive model. May plastically update `f`
// (the SAND return-mapping moves strain from elastic to plastic).
Mat3 MpmSim::_stress(Mat3 &f) const {
	if (_material == 2) { // Drucker-Prager sand
		return _sand(f);
	}
	if (_material == 1) { // fixed-corotated: τ = 2μ(F−R)Fᵀ + λ J(J−1) I, R = U Vᵀ
		Mat3 u, v;
		double s[3];
		f.svd(u, s, v);
		const Mat3 r = u * v.transposed();
		const double J = s[0] * s[1] * s[2];
		return (f - r).scaled(2.0 * _mu) * f.transposed() + Mat3::identity().scaled(_lambda * J * (J - 1.0));
	}
	// neo-Hookean: τ = μ(FFᵀ − I) + λ ln(J) I
	double J = f.determinant();
	if (J < 1e-4) {
		J = 1e-4; // guard a (near-)inverted particle so ln(J) stays finite
	}
	return (f * f.transposed() - Mat3::identity()).scaled(_mu) + Mat3::identity().scaled(_lambda * Math::log(J));
}

// Build a diagonal Mat3 from three values.
static Mat3 diag3(double a, double b, double c) {
	Mat3 d = Mat3::zero();
	d.m[0][0] = a;
	d.m[1][1] = b;
	d.m[2][2] = c;
	return d;
}

// Drucker-Prager sand (Klár 2016). SVD the elastic F, take Hencky strain ε = ln σ, project
// it onto the cohesionless yield cone (tension → tip; outside the cone → onto its surface),
// rebuild the *elastic* F from the returned strain (the excess becomes plastic flow), and
// return the log-strain Kirchhoff stress τ = U·diag(2μεᵢ + λ tr ε)·Uᵀ.
Mat3 MpmSim::_sand(Mat3 &f) const {
	Mat3 u, v;
	double s[3];
	f.svd(u, s, v);
	double eps[3];
	for (int i = 0; i < 3; i++) {
		eps[i] = Math::log(MAX(Math::abs(s[i]), 1e-4));
	}
	const double tr = eps[0] + eps[1] + eps[2];
	const double eh[3] = { eps[0] - tr / 3.0, eps[1] - tr / 3.0, eps[2] - tr / 3.0 };
	const double eh_norm = Math::sqrt(eh[0] * eh[0] + eh[1] * eh[1] + eh[2] * eh[2]);

	double ne[3]; // returned (elastic) Hencky strain
	if (tr > 0.0 || eh_norm < 1e-12) {
		// Volumetric extension: cohesionless sand can't sustain it → return to the cone tip
		// (all deviatoric + tensile strain plasticises). Pure compression on-axis stays.
		const double v_strain = (tr > 0.0) ? 0.0 : tr / 3.0;
		ne[0] = ne[1] = ne[2] = v_strain;
	} else {
		const double dgamma = eh_norm + (3.0 * _lambda + 2.0 * _mu) / (2.0 * _mu) * tr * _alpha;
		if (dgamma <= 0.0) {
			ne[0] = eps[0]; // inside the cone → elastic, unchanged
			ne[1] = eps[1];
			ne[2] = eps[2];
		} else {
			for (int i = 0; i < 3; i++) {
				ne[i] = eps[i] - dgamma * eh[i] / eh_norm; // project onto the cone surface
			}
		}
	}

	f = u * diag3(Math::exp(ne[0]), Math::exp(ne[1]), Math::exp(ne[2])) * v.transposed();
	const double trn = ne[0] + ne[1] + ne[2];
	const Mat3 tp = diag3(2.0 * _mu * ne[0] + _lambda * trn, 2.0 * _mu * ne[1] + _lambda * trn, 2.0 * _mu * ne[2] + _lambda * trn);
	return u * tp * u.transposed();
}

