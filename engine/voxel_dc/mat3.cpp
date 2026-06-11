#include "mat3.h"

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

// Eigendecomposition of a symmetric 3×3 by cyclic Jacobi: S = V · diag(eval) · Vᵀ, columns
// of V the eigenvectors. Applying each Givens rotation as a full 3×3 product is trivially
// cheap at this size and avoids hand-derived (bug-prone) in-place update formulas.
static void symmetric_eigen(const Mat3 &s_in, Mat3 &v, double eval[3]) {
	Mat3 a = s_in;
	v = Mat3::identity();
	static const int P[3] = { 0, 0, 1 };
	static const int Q[3] = { 1, 2, 2 };
	for (int sweep = 0; sweep < 16; sweep++) {
		double off = Math::abs(a.m[0][1]) + Math::abs(a.m[0][2]) + Math::abs(a.m[1][2]);
		if (off < 1e-300) {
			break;
		}
		for (int t = 0; t < 3; t++) {
			const int p = P[t], q = Q[t];
			const double apq = a.m[p][q];
			if (Math::abs(apq) < 1e-300) {
				continue;
			}
			// Angle that zeros a_pq under A ← JᵀAJ: tan(2φ) = 2·a_pq / (a_qq − a_pp).
			const double phi = 0.5 * Math::atan2(2.0 * apq, a.m[q][q] - a.m[p][p]);
			const double c = Math::cos(phi), sn = Math::sin(phi);
			Mat3 j = Mat3::identity();
			j.m[p][p] = c;
			j.m[q][q] = c;
			j.m[p][q] = sn;
			j.m[q][p] = -sn;
			a = j.transposed() * a * j; // A ← Jᵀ A J
			v = v * j; // accumulate eigenvectors
		}
	}
	eval[0] = a.m[0][0];
	eval[1] = a.m[1][1];
	eval[2] = a.m[2][2];
}

void Mat3::svd(Mat3 &u, double sigma[3], Mat3 &v) const {
	double eval[3];
	symmetric_eigen(transposed() * (*this), v, eval); // V, σ² from FᵀF
	double sig[3] = { Math::sqrt(MAX(eval[0], 0.0)), Math::sqrt(MAX(eval[1], 0.0)), Math::sqrt(MAX(eval[2], 0.0)) };

	// Sort columns of V (and σ) by descending magnitude so the reflection lands on the
	// smallest singular value (the fixed-corotated / Drucker-Prager convention).
	int order[3] = { 0, 1, 2 };
	for (int i = 0; i < 3; i++) {
		for (int j = i + 1; j < 3; j++) {
			if (sig[order[j]] > sig[order[i]]) {
				const int tmp = order[i];
				order[i] = order[j];
				order[j] = tmp;
			}
		}
	}
	Mat3 vs;
	double ss[3];
	for (int i = 0; i < 3; i++) {
		ss[i] = sig[order[i]];
		for (int r = 0; r < 3; r++) {
			vs.m[r][i] = v.m[r][order[i]];
		}
	}
	v = vs;

	// U = F V Σ⁻¹ column by column (F·v_i = σ_i u_i). A (near-)zero σ leaves an undefined
	// column — fill it with the cross product of the other two to keep U orthonormal.
	const Mat3 fv = (*this) * v;
	for (int i = 0; i < 3; i++) {
		if (ss[i] > 1e-12) {
			for (int r = 0; r < 3; r++) {
				u.m[r][i] = fv.m[r][i] / ss[i];
			}
		} else {
			const int a = (i + 1) % 3, b = (i + 2) % 3;
			const Vector3 ca(u.m[0][a], u.m[1][a], u.m[2][a]);
			const Vector3 cb(u.m[0][b], u.m[1][b], u.m[2][b]);
			const Vector3 cr = ca.cross(cb).normalized();
			u.m[0][i] = cr.x;
			u.m[1][i] = cr.y;
			u.m[2][i] = cr.z;
		}
	}

	// Make U and V proper rotations; absorb any reflection into the smallest singular value.
	if (v.determinant() < 0.0) {
		v.m[0][2] = -v.m[0][2];
		v.m[1][2] = -v.m[1][2];
		v.m[2][2] = -v.m[2][2];
		ss[2] = -ss[2];
	}
	if (u.determinant() < 0.0) {
		u.m[0][2] = -u.m[0][2];
		u.m[1][2] = -u.m[1][2];
		u.m[2][2] = -u.m[2][2];
		ss[2] = -ss[2];
	}
	sigma[0] = ss[0];
	sigma[1] = ss[1];
	sigma[2] = ss[2];
}

