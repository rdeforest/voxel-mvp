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

Mat3 Mat3::inverse() const {
	const double d = determinant();
	Mat3 r = zero();
	if (Math::abs(d) < 1e-12) {
		return r; // singular
	}
	const double id = 1.0 / d;
	r.m[0][0] = (m[1][1] * m[2][2] - m[1][2] * m[2][1]) * id;
	r.m[0][1] = (m[0][2] * m[2][1] - m[0][1] * m[2][2]) * id;
	r.m[0][2] = (m[0][1] * m[1][2] - m[0][2] * m[1][1]) * id;
	r.m[1][0] = (m[1][2] * m[2][0] - m[1][0] * m[2][2]) * id;
	r.m[1][1] = (m[0][0] * m[2][2] - m[0][2] * m[2][0]) * id;
	r.m[1][2] = (m[0][2] * m[1][0] - m[0][0] * m[1][2]) * id;
	r.m[2][0] = (m[1][0] * m[2][1] - m[1][1] * m[2][0]) * id;
	r.m[2][1] = (m[0][1] * m[2][0] - m[0][0] * m[2][1]) * id;
	r.m[2][2] = (m[0][0] * m[1][1] - m[0][1] * m[1][0]) * id;
	return r;
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

static Vector3 column(const Mat3 &a, int i) {
	return Vector3(a.m[0][i], a.m[1][i], a.m[2][i]);
}

static void set_column(Mat3 &a, int i, const Vector3 &c) {
	a.m[0][i] = c.x;
	a.m[1][i] = c.y;
	a.m[2][i] = c.z;
}

// Crossing with the coordinate axis `a` is least aligned with keeps |a × axis| ≥ sqrt(2/3),
// so the result is well-conditioned for any unit `a`.
static Vector3 any_orthogonal(const Vector3 &a) {
	const Vector3 m = a.abs();
	const Vector3::Axis least = m.x <= m.y && m.x <= m.z ? Vector3::AXIS_X : (m.y <= m.z ? Vector3::AXIS_Y : Vector3::AXIS_Z);
	Vector3 axis;
	axis[least] = 1.0;
	return a.cross(axis).normalized();
}

// U = F V Σ⁻¹ column by column (F·v_i = σ_i u_i). σ is sorted, so the columns with a
// (near-)zero σ are a suffix; F gives them no direction, and any orthonormal completion still
// reconstructs F, so they complete U to a right-handed basis.
static void fill_u(const Mat3 &fv, const double ss[3], Mat3 &u) {
	int rank = 0;
	while (rank < 3 && ss[rank] > 1e-12) {
		set_column(u, rank, column(fv, rank) / ss[rank]);
		rank++;
	}
	if (rank == 0) {
		set_column(u, 0, Vector3(1, 0, 0));
	}
	if (rank <= 1) {
		set_column(u, 1, any_orthogonal(column(u, 0)));
	}
	if (rank <= 2) {
		set_column(u, 2, column(u, 0).cross(column(u, 1)).normalized());
	}
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

	fill_u((*this) * v, ss, u);

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

