#include "voxel_mesher_dc.h"

#include "dc_qef.h"
#include "octree_geometry.h"

#include "core/math/color.h"
#include "core/templates/local_vector.h"
#include "modules/voxel/storage/voxel_buffer.h"

using voxel_dc::CB;       // cube corners by xyz bits (shared with the octree mesher/store)
using voxel_dc::EDGES;    // 12 edges as corner-index pairs
using voxel_dc::Qef;
using zylann::voxel::VoxelBuffer;

namespace {

// godot_voxel hands us a block buffer with this much neighbour margin. We need
// enough that a boundary cell's QEF vertex is computed identically in both
// adjacent blocks (else the two place slightly different vertices -> seam):
// the +boundary cell reads corner+1 for crossings AND corner+2 for the central-
// difference gradient there, so MAX_PADDING must be 3; symmetrically MIN=2.
const int MIN_PADDING = 2;
const int MAX_PADDING = 3;

// Per-block (grid) edge ring — DISTINCT from voxel_dc::RING (the octree mesher's
// centred quadrant offsets); this is the corner-origin form for fixed-grid meshing.
const int RING[4][2] = { { -1, -1 }, { 0, -1 }, { 0, 0 }, { -1, 0 } };

// Debug palette: per-vertex colour by LOD index, painted by the terrain shader
// when its debug_lod uniform is on (console: `set debug_lod 1`).
Color lod_color(int lod) {
	static const Color palette[6] = {
		Color(0.30, 0.90, 0.30), // 0 green
		Color(0.30, 0.80, 0.95), // 1 cyan
		Color(0.95, 0.90, 0.30), // 2 yellow
		Color(0.95, 0.55, 0.20), // 3 orange
		Color(0.90, 0.30, 0.30), // 4 red
		Color(0.85, 0.45, 0.95), // 5 magenta
	};
	return palette[CLAMP(lod, 0, 5)];
}

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
	PackedColorArray colors;
	PackedInt32Array indices;
	const Color this_lod_color = lod_color(int(input.lod_index));

	for (int lz = 0; lz <= bs; ++lz) {
		for (int ly = 0; ly <= bs; ++ly) {
			for (int lx = 0; lx <= bs; ++lx) {
				const int bx = lx + MIN_PADDING, by = ly + MIN_PADDING, bz = lz + MIN_PADDING;
				Qef qef;
				Vector3 nsum;
				for (int e = 0; e < 12; ++e) {
					const int *ca = CB[EDGES[e][0]];
					const int *cb = CB[EDGES[e][1]];
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
				colors.push_back(this_lod_color);
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
					int A[3] = { g[0] + MIN_PADDING, g[1] + MIN_PADDING, g[2] + MIN_PADDING };
					int B[3] = { A[0], A[1], A[2] };
					B[axis] += 1;
					const float fa = sd(A[0], A[1], A[2]);
					const float fb = sd(B[0], B[1], B[2]);
					if ((fa < 0.0f) == (fb < 0.0f) || fa == fb) {
						continue;
					}
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
					// Front faces air. RING is CCW in the perp plane, so reverse the winding
					// when the +axis corner is the air side (fb > fa). Split along the shorter
					// diagonal so a non-planar quad doesn't fold a triangle inward. Both use
					// the crossing sign and vertex positions only -- never the gradient, which
					// at voxel resolution can flip a quad's facing and cull it into a hole.
					const bool reverse = fb > fa;
					const bool short02 = verts[ring_v[0]].distance_squared_to(verts[ring_v[2]]) <= verts[ring_v[1]].distance_squared_to(verts[ring_v[3]]);
					const int *r = ring_v;
					if (short02) {
						if (reverse) {
							indices.push_back(r[0]); indices.push_back(r[2]); indices.push_back(r[1]);
							indices.push_back(r[0]); indices.push_back(r[3]); indices.push_back(r[2]);
						} else {
							indices.push_back(r[0]); indices.push_back(r[1]); indices.push_back(r[2]);
							indices.push_back(r[0]); indices.push_back(r[2]); indices.push_back(r[3]);
						}
					} else {
						if (reverse) {
							indices.push_back(r[1]); indices.push_back(r[3]); indices.push_back(r[2]);
							indices.push_back(r[1]); indices.push_back(r[0]); indices.push_back(r[3]);
						} else {
							indices.push_back(r[1]); indices.push_back(r[2]); indices.push_back(r[3]);
							indices.push_back(r[1]); indices.push_back(r[3]); indices.push_back(r[0]);
						}
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
	surface.arrays[Mesh::ARRAY_COLOR] = colors;
	surface.arrays[Mesh::ARRAY_INDEX] = indices;
	output.surfaces.push_back(surface);
	output.primitive_type = Mesh::PRIMITIVE_TRIANGLES;
}
