#include "voxel_mesher_dc.h"

#include "modules/voxel/storage/voxel_buffer.h"

using zylann::voxel::VoxelBuffer;

namespace {

// Push a quad (a,b,c,d ring) with flat normal n, wound so it faces outward.
// Godot treats clockwise-from-front as the front face: the right-hand normal of
// (a,b,c) is (b-a)x(c-a); when it points OUTWARD the ring is CCW from outside
// (a back face), so reverse. Mirrors the GDScript DC prototype's winding rule.
void add_quad(PackedVector3Array &verts, PackedVector3Array &normals, PackedInt32Array &indices,
		const Vector3 &a, const Vector3 &b, const Vector3 &c, const Vector3 &d, const Vector3 &n) {
	const int base = verts.size();
	verts.push_back(a);
	verts.push_back(b);
	verts.push_back(c);
	verts.push_back(d);
	for (int i = 0; i < 4; ++i) {
		normals.push_back(n);
	}
	const bool rh_outward = (b - a).cross(c - a).dot(n) >= 0.0f;
	if (rh_outward) {
		indices.push_back(base + 0); indices.push_back(base + 2); indices.push_back(base + 1);
		indices.push_back(base + 0); indices.push_back(base + 3); indices.push_back(base + 2);
	} else {
		indices.push_back(base + 0); indices.push_back(base + 1); indices.push_back(base + 2);
		indices.push_back(base + 0); indices.push_back(base + 2); indices.push_back(base + 3);
	}
}

} // namespace

VoxelMesherDC::VoxelMesherDC() {
	set_padding(0, 0);
}

int VoxelMesherDC::get_used_channels_mask() const {
	return (1 << VoxelBuffer::CHANNEL_SDF);
}

void VoxelMesherDC::build(Output &output, const Input &input) {
	const VoxelBuffer &voxels = input.voxels;
	const Vector3i size = voxels.get_size();

	// Plumbing proof: does this block straddle the surface (mixed SDF sign)?
	bool has_neg = false;
	bool has_pos = false;
	for (int z = 0; z < size.z && !(has_neg && has_pos); ++z) {
		for (int y = 0; y < size.y && !(has_neg && has_pos); ++y) {
			for (int x = 0; x < size.x; ++x) {
				const float sd = voxels.get_voxel_f(x, y, z, VoxelBuffer::CHANNEL_SDF);
				if (sd < 0.0f) {
					has_neg = true;
				} else {
					has_pos = true;
				}
				if (has_neg && has_pos) {
					break;
				}
			}
		}
	}
	if (!(has_neg && has_pos)) {
		return; // fully inside or fully outside -> no surface here
	}

	// Emit a cube spanning the block, in local voxel space [0, size].
	const Vector3 s = Vector3(size);
	const Vector3 p000(0, 0, 0), p100(s.x, 0, 0), p010(0, s.y, 0), p110(s.x, s.y, 0);
	const Vector3 p001(0, 0, s.z), p101(s.x, 0, s.z), p011(0, s.y, s.z), p111(s.x, s.y, s.z);

	PackedVector3Array verts;
	PackedVector3Array normals;
	PackedInt32Array indices;
	add_quad(verts, normals, indices, p000, p010, p011, p001, Vector3(-1, 0, 0));
	add_quad(verts, normals, indices, p100, p101, p111, p110, Vector3(1, 0, 0));
	add_quad(verts, normals, indices, p000, p001, p101, p100, Vector3(0, -1, 0));
	add_quad(verts, normals, indices, p010, p110, p111, p011, Vector3(0, 1, 0));
	add_quad(verts, normals, indices, p000, p100, p110, p010, Vector3(0, 0, -1));
	add_quad(verts, normals, indices, p001, p011, p111, p101, Vector3(0, 0, 1));

	Output::Surface surface;
	surface.arrays.resize(Mesh::ARRAY_MAX);
	surface.arrays[Mesh::ARRAY_VERTEX] = verts;
	surface.arrays[Mesh::ARRAY_NORMAL] = normals;
	surface.arrays[Mesh::ARRAY_INDEX] = indices;
	output.surfaces.push_back(surface);
	output.primitive_type = Mesh::PRIMITIVE_TRIANGLES;
}
