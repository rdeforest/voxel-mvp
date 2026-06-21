#ifndef DC_QEF_H
#define DC_QEF_H

// Quadratic Error Function solver for one Dual Contouring cell: the vertex
// minimizes the sum of squared distances to the crossing tangent planes. Solved
// via cyclic Jacobi eigen-decomposition of A^T A with small eigenvalues clamped
// (pseudo-inverse), biased toward the crossings' mass point, then clamped into the
// cell. Used by DCOctreeMesher (octree clipmap).

#include "core/math/math_funcs.h"
#include "core/math/vector3.h"
#include "core/typedefs.h"

namespace voxel_dc {

// Compact float vector for the QEF's small-magnitude fields + the solve-result caches (vertex positions /
// normals / errors, which are consumed as float on the GPU anyway). Halves their storage vs the
// precision=double Vector3 (3x double). NOT for the precision-critical accumulators atb/mass/btb — those stay
// double, since the crossing points are in lattice coords (magnitudes to ~2048+), so btb=Σd² reaches ~1e8 and
// the residual (the LOD signal) is a difference of large numbers that float would lose to cancellation.
struct F3 {
	float x = 0, y = 0, z = 0;
	F3() {}
	F3(const Vector3 &v) : x(float(v.x)), y(float(v.y)), z(float(v.z)) {}
	operator Vector3() const { return Vector3(x, y, z); }
	void operator+=(const Vector3 &v) { x += float(v.x); y += float(v.y); z += float(v.z); }
	void operator+=(const F3 &o) { x += o.x; y += o.y; z += o.z; }
	double length_squared() const { return double(x) * x + double(y) * y + double(z) * z; }
};

struct Qef {
	double a00 = 0, a01 = 0, a02 = 0, a11 = 0, a12 = 0, a22 = 0; // ATA: keep double — the eigen-solve amplifies any
	                                                             // perturbation, and float made the vertex path-dependent
	Vector3 atb;   // Σ n·d — d at lattice scale → keep double (feeds the residual's differencing)
	Vector3 mass;  // Σ p — lattice-coord centroid for the solve bias → keep double
	F3 nsum;       // Σ plane normals (the vertex normal, not its position) — small magnitude → float
	double btb = 0; // Σ d² — reaches ~1e8 → keep double (residual = ... + btb cancels against the rest)
	int count = 0;

	void add_plane(const Vector3 &p, const Vector3 &n_in) {
		Vector3 n = n_in.normalized();
		double d = n.dot(p);
		a00 += n.x * n.x; a01 += n.x * n.y; a02 += n.x * n.z;
		a11 += n.y * n.y; a12 += n.y * n.z; a22 += n.z * n.z;
		atb += n * d;
		mass += p;
		nsum += n;
		btb += d * d;
		++count;
	}

	// Merge another cell's QEF (additive Hermite data) — the basis of bottom-up
	// octree simplification: a parent's QEF is the sum of its children's, so its
	// residual reflects the TRUE fine surface within it (no coarse-corner undersampling).
	void add(const Qef &o) {
		a00 += o.a00; a01 += o.a01; a02 += o.a02; a11 += o.a11; a12 += o.a12; a22 += o.a22;
		atb += o.atb; mass += o.mass; nsum += o.nsum; btb += o.btb; count += o.count;
	}

	// Sum of squared distances from v to the crossing planes: ||A v - b||^2 =
	// v·(A^T A)v - 2 v·(A^T b) + b·b. ~0 when one vertex fits the surface in the cell
	// (flat or a clean edge/corner); large when the surface is too complex for one
	// vertex — the geometric-error signal for adaptive LOD.
	double residual(const Vector3 &v) const {
		return MAX(0.0, v.dot(ata_mul(v)) - 2.0 * v.dot(atb) + btb);
	}

	Vector3 ata_mul(const Vector3 &v) const {
		return Vector3(
				a00 * v.x + a01 * v.y + a02 * v.z,
				a01 * v.x + a11 * v.y + a12 * v.z,
				a02 * v.x + a12 * v.y + a22 * v.z);
	}

	// Cyclic Jacobi eigen-decomposition of the symmetric A^T A.
	void eigen(Vector3 &values, Vector3 vecs[3]) const {
		double a[3][3] = { { a00, a01, a02 }, { a01, a11, a12 }, { a02, a12, a22 } };
		double v[3][3] = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } };
		for (int sweep = 0; sweep < 12; ++sweep) {
			int p = 0, q = 1;
			double best = Math::abs(a[0][1]);
			if (Math::abs(a[0][2]) > best) { best = Math::abs(a[0][2]); p = 0; q = 2; }
			if (Math::abs(a[1][2]) > best) { best = Math::abs(a[1][2]); p = 1; q = 2; }
			if (best < 1e-14) {
				break;
			}
			double app = a[p][p], aqq = a[q][q], apq = a[p][q];
			double phi = 0.5 * Math::atan2(2.0 * apq, app - aqq);
			double c = Math::cos(phi), s = Math::sin(phi);
			int r = 3 - p - q;
			a[p][p] = c * c * app + 2.0 * s * c * apq + s * s * aqq;
			a[q][q] = s * s * app - 2.0 * s * c * apq + c * c * aqq;
			a[p][q] = 0.0; a[q][p] = 0.0;
			double arp = a[r][p], arq = a[r][q];
			a[p][r] = c * arp + s * arq; a[r][p] = a[p][r];
			a[q][r] = -s * arp + c * arq; a[r][q] = a[q][r];
			for (int row = 0; row < 3; ++row) {
				double vp = v[row][p], vq = v[row][q];
				v[row][p] = c * vp + s * vq;
				v[row][q] = -s * vp + c * vq;
			}
		}
		values = Vector3(a[0][0], a[1][1], a[2][2]);
		vecs[0] = Vector3(v[0][0], v[1][0], v[2][0]);
		vecs[1] = Vector3(v[0][1], v[1][1], v[2][1]);
		vecs[2] = Vector3(v[0][2], v[1][2], v[2][2]);
	}

	Vector3 solve(const Vector3 &cmin, const Vector3 &cmax) const {
		if (count == 0) {
			return (cmin + cmax) * 0.5;
		}
		Vector3 centroid = mass / double(count);
		Vector3 rhs = atb - ata_mul(centroid);
		Vector3 values;
		Vector3 vecs[3];
		eigen(values, vecs);
		double vmax = MAX(Math::abs(values.x), MAX(Math::abs(values.y), Math::abs(values.z)));
		Vector3 offset;
		if (vmax > 0.0) {
			double floor_val = vmax * 1e-3;
			for (int i = 0; i < 3; ++i) {
				double lam = values[i];
				if (Math::abs(lam) <= floor_val) {
					continue;
				}
				offset += vecs[i] * (vecs[i].dot(rhs) / lam);
			}
		}
		// If the solution lands outside the cell it's an unreliable extrapolation
		// (ill-conditioned feature solve); fall back to the mass point, which lies
		// on the crossings (inside the cell, on the surface).
		Vector3 v = centroid + offset;
		if (v.x < cmin.x || v.y < cmin.y || v.z < cmin.z ||
				v.x > cmax.x || v.y > cmax.y || v.z > cmax.z) {
			return centroid.clamp(cmin, cmax);
		}
		return v;
	}
};

} // namespace voxel_dc

#endif // DC_QEF_H
