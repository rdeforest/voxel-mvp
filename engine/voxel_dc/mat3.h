#ifndef MAT3_H
#define MAT3_H

// A minimal 3×3 double matrix for the MPM continuum kernel (mpm_sim). Basis is
// rotation-oriented and lacks the +/scalar/outer-product/SVD ops a continuum step needs,
// so a purpose-built type is clearer. Row-major: m[row][col].

#include "core/math/vector3.h"

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

	// Signed SVD: this = U · diag(sigma) · Vᵀ, with U and V proper rotations (det = +1) and
	// sigma sorted by descending magnitude (the last may be negative, absorbing a reflection
	// — the convention fixed-corotated/Drucker-Prager want so they can handle inversion).
	void svd(Mat3 &u, double sigma[3], Mat3 &v) const;
};

#endif // MAT3_H
