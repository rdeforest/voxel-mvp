#include "voxel_mesher_dc.h"

#include "core/templates/local_vector.h"
#include "modules/voxel/storage/voxel_buffer.h"

using zylann::voxel::VoxelBuffer;

namespace {

// godot_voxel hands us a block buffer with this much neighbour margin. We need
// enough that a boundary cell's QEF vertex is computed identically in both
// adjacent blocks (else the two place slightly different vertices -> seam):
// the +boundary cell reads corner+1 for crossings AND corner+2 for the central-
// difference gradient there, so MAX_PADDING must be 3; symmetrically MIN=2.
const int MIN_PADDING = 2;
const int MAX_PADDING = 3;

// Cube corners by xyz bits: 0=(0,0,0) .. 7=(1,1,1). 12 edges as corner pairs.
const int CORNER[8][3] = {
	{ 0, 0, 0 }, { 1, 0, 0 }, { 0, 1, 0 }, { 1, 1, 0 },
	{ 0, 0, 1 }, { 1, 0, 1 }, { 0, 1, 1 }, { 1, 1, 1 },
};
const int EDGES[12][2] = {
	{ 0, 1 }, { 2, 3 }, { 4, 5 }, { 6, 7 },
	{ 0, 2 }, { 1, 3 }, { 4, 6 }, { 5, 7 },
	{ 0, 4 }, { 1, 5 }, { 2, 6 }, { 3, 7 },
};
// Ring of the four cells around an edge, in (perp-u, perp-v) offsets.
const int RING[4][2] = { { -1, -1 }, { 0, -1 }, { 0, 0 }, { -1, 0 } };

// Quadratic Error Function solver (ported from the GDScript prototype): the
// cell vertex minimizes sum of squared distances to the crossing tangent
// planes. Solved via Jacobi eigen-decomposition of A^T A with small eigenvalues
// clamped (pseudo-inverse), biased toward the crossings' mass point, then
// clamped into the cell.
struct Qef {
	double a00 = 0, a01 = 0, a02 = 0, a11 = 0, a12 = 0, a22 = 0;
	Vector3 atb;
	Vector3 mass;
	int count = 0;

	void add_plane(const Vector3 &p, const Vector3 &n_in) {
		Vector3 n = n_in.normalized();
		double d = n.dot(p);
		a00 += n.x * n.x; a01 += n.x * n.y; a02 += n.x * n.z;
		a11 += n.y * n.y; a12 += n.y * n.z; a22 += n.z * n.z;
		atb += n * d;
		mass += p;
		++count;
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
		return (centroid + offset).clamp(cmin, cmax);
	}
};

} // namespace

VoxelMesherDC::VoxelMesherDC() {
	set_padding(MIN_PADDING, MAX_PADDING);
}

int VoxelMesherDC::get_used_channels_mask() const {
	return (1 << VoxelBuffer::CHANNEL_SDF);
}

void VoxelMesherDC::build(Output &output, const Input &input) {
	const VoxelBuffer &voxels = input.voxels;
	const Vector3i bufsize = voxels.get_size();
	const int sx = bufsize.x, sy = bufsize.y, sz = bufsize.z;

	// Block cells per axis (buffer minus padding). Need at least one cell.
	const int bs = MIN(sx, MIN(sy, sz)) - (MIN_PADDING + MAX_PADDING);
	if (bs < 1) {
		return;
	}
	const int scale = 1 << input.lod_index;

	// SDF read, clamped into the buffer (gradients sample neighbours).
	auto sd = [&](int x, int y, int z) -> float {
		x = CLAMP(x, 0, sx - 1);
		y = CLAMP(y, 0, sy - 1);
		z = CLAMP(z, 0, sz - 1);
		return float(voxels.get_voxel_f(x, y, z, VoxelBuffer::CHANNEL_SDF));
	};
	auto grad = [&](int x, int y, int z) -> Vector3 {
		return Vector3(sd(x + 1, y, z) - sd(x - 1, y, z),
				sd(x, y + 1, z) - sd(x, y - 1, z),
				sd(x, y, z + 1) - sd(x, y, z - 1));
	};

	// One QEF vertex per surface cell, over local cells [0, bs] (the extra +1
	// layer is the next block's boundary cell, read from padding so the two
	// blocks place an identical vertex there -> seamless).
	const int dim = bs + 1;
	LocalVector<int> cell_vert;
	cell_vert.resize(dim * dim * dim);
	for (uint32_t i = 0; i < cell_vert.size(); ++i) {
		cell_vert[i] = -1;
	}
	auto cidx = [&](int lx, int ly, int lz) -> int { return lx + dim * (ly + dim * lz); };

	PackedVector3Array verts;
	PackedVector3Array normals;
	PackedInt32Array indices;

	for (int lz = 0; lz <= bs; ++lz) {
		for (int ly = 0; ly <= bs; ++ly) {
			for (int lx = 0; lx <= bs; ++lx) {
				const int bx = lx + MIN_PADDING, by = ly + MIN_PADDING, bz = lz + MIN_PADDING;
				Qef qef;
				Vector3 nsum;
				for (int e = 0; e < 12; ++e) {
					const int *ca = CORNER[EDGES[e][0]];
					const int *cb = CORNER[EDGES[e][1]];
					const int ax = bx + ca[0], ay = by + ca[1], az = bz + ca[2];
					const int bx2 = bx + cb[0], by2 = by + cb[1], bz2 = bz + cb[2];
					const float fa = sd(ax, ay, az);
					const float fb = sd(bx2, by2, bz2);
					if ((fa < 0.0f) == (fb < 0.0f) || fa == fb) {
						continue;
					}
					const float t = fa / (fa - fb);
					const Vector3 pa(ax, ay, az), pb(bx2, by2, bz2);
					const Vector3 p = pa.lerp(pb, t);
					Vector3 n = grad(ax, ay, az).lerp(grad(bx2, by2, bz2), t);
					if (n.length_squared() == 0.0) {
						n = Vector3(0, 1, 0);
					}
					n.normalize();
					qef.add_plane(p, n);
					nsum += n;
				}
				if (qef.count == 0) {
					continue;
				}
				const Vector3 cmin(bx, by, bz);
				const Vector3 vbuf = qef.solve(cmin, cmin + Vector3(1, 1, 1));
				cell_vert[cidx(lx, ly, lz)] = verts.size();
				verts.push_back((vbuf - Vector3(MIN_PADDING, MIN_PADDING, MIN_PADDING)) * scale);
				normals.push_back(nsum.normalized());
			}
		}
	}

	if (verts.is_empty()) {
		return;
	}

	// Quads across sign-changing grid edges. Ownership keeps each shared edge
	// emitted by exactly one block: along the edge axis a in [0, bs); in the two
	// perpendicular axes the index runs [1, bs] (this block owns its + faces,
	// the - faces belong to the neighbour).
	for (int axis = 0; axis < 3; ++axis) {
		const int u = (axis + 1) % 3;
		const int w = (axis + 2) % 3;
		for (int a = 0; a < bs; ++a) {
			for (int gu = 1; gu <= bs; ++gu) {
				for (int gw = 1; gw <= bs; ++gw) {
					int g[3];
					g[axis] = a; g[u] = gu; g[w] = gw;
					// Edge endpoints (buffer corners) along `axis`.
					int A[3] = { g[0] + MIN_PADDING, g[1] + MIN_PADDING, g[2] + MIN_PADDING };
					int B[3] = { A[0], A[1], A[2] };
					B[axis] += 1;
					const float fa = sd(A[0], A[1], A[2]);
					const float fb = sd(B[0], B[1], B[2]);
					if ((fa < 0.0f) == (fb < 0.0f) || fa == fb) {
						continue;
					}
					// Four surrounding cells (perp ring), all at axis index a.
					int ring_v[4];
					bool ok = true;
					for (int k = 0; k < 4; ++k) {
						int c[3];
						c[axis] = a;
						c[u] = gu + RING[k][0];
						c[w] = gw + RING[k][1];
						const int vi = cell_vert[cidx(c[0], c[1], c[2])];
						if (vi < 0) { ok = false; break; }
						ring_v[k] = vi;
					}
					if (!ok) {
						continue;
					}
					const float t = fa / (fa - fb);
					Vector3 outward = grad(A[0], A[1], A[2]).lerp(grad(B[0], B[1], B[2]), t);
					// Godot front faces are clockwise-from-front: when the right-
					// hand normal of [0,1,2] points outward the ring reads CCW
					// (a back face), so reverse it.
					const Vector3 p0 = verts[ring_v[0]], p1 = verts[ring_v[1]], p2 = verts[ring_v[2]];
					const bool rh_outward = (p1 - p0).cross(p2 - p0).dot(outward) >= 0.0;
					if (rh_outward) {
						indices.push_back(ring_v[0]); indices.push_back(ring_v[2]); indices.push_back(ring_v[1]);
						indices.push_back(ring_v[0]); indices.push_back(ring_v[3]); indices.push_back(ring_v[2]);
					} else {
						indices.push_back(ring_v[0]); indices.push_back(ring_v[1]); indices.push_back(ring_v[2]);
						indices.push_back(ring_v[0]); indices.push_back(ring_v[2]); indices.push_back(ring_v[3]);
					}
				}
			}
		}
	}

	if (indices.is_empty()) {
		return;
	}

	Output::Surface surface;
	surface.arrays.resize(Mesh::ARRAY_MAX);
	surface.arrays[Mesh::ARRAY_VERTEX] = verts;
	surface.arrays[Mesh::ARRAY_NORMAL] = normals;
	surface.arrays[Mesh::ARRAY_INDEX] = indices;
	output.surfaces.push_back(surface);
	output.primitive_type = Mesh::PRIMITIVE_TRIANGLES;
}
