// SparseVoxelOctree's Dual-Contouring mesher (split from the storage .cpp for length;
// same class, methods just live here). One vertex per surface leaf, crack-free
// point-location stitch across leaf-size jumps, per-triangle winding to the leaf gradient.

#include "sparse_voxel_octree.h"

#include "octree_geometry.h"

#include "scene/resources/mesh.h"

using namespace voxel_dc;

int SparseVoxelOctree::_find_leaf(const Vector3 &p) const {
	if (nodes.is_empty()) {
		return -1;
	}
	const Node &r = nodes[0];
	if (p.x < r.origin.x || p.y < r.origin.y || p.z < r.origin.z) {
		return -1;
	}
	if (p.x >= r.origin.x + r.size || p.y >= r.origin.y + r.size || p.z >= r.origin.z + r.size) {
		return -1;
	}
	int idx = 0;
	while (!nodes[idx].is_leaf()) {
		idx = nodes[idx].children[_child_index(idx, p)];
	}
	return idx;
}

bool SparseVoxelOctree::_leaf_vertex(int idx, Vector3 &out_v) const {
	const Node &n = nodes[idx];
	Vector3 sum;
	int cnt = 0;
	for (int e = 0; e < 12; ++e) {
		const float fa = n.corners[EDGES[e][0]];
		const float fb = n.corners[EDGES[e][1]];
		if ((fa < 0.0f) == (fb < 0.0f)) {
			continue;
		}
		const double t = fa / (fa - fb);
		sum += corner(n.origin, n.size, EDGES[e][0]).lerp(corner(n.origin, n.size, EDGES[e][1]), t);
		++cnt;
	}
	if (cnt == 0) {
		return false;
	}
	out_v = sum / double(cnt);
	return true;
}

Vector3 SparseVoxelOctree::_leaf_normal(int idx) const {
	const float *c = nodes[idx].corners;
	Vector3 g(
			(c[1] - c[0]) + (c[3] - c[2]) + (c[5] - c[4]) + (c[7] - c[6]),
			(c[2] - c[0]) + (c[3] - c[1]) + (c[6] - c[4]) + (c[7] - c[5]),
			(c[4] - c[0]) + (c[5] - c[1]) + (c[6] - c[2]) + (c[7] - c[3]));
	return g.length_squared() > 0.0 ? g.normalized() : Vector3(0, 1, 0);
}

bool SparseVoxelOctree::_owns_edge(int idx, const int ring[4]) const {
	double min_size = nodes[idx].size;
	for (int k = 0; k < 4; ++k) {
		if (ring[k] >= 0 && nodes[ring[k]].size < min_size) {
			min_size = nodes[ring[k]].size;
		}
	}
	if (nodes[idx].size != min_size) {
		return false;
	}
	for (int k = 0; k < 4; ++k) {
		const int ci = ring[k];
		if (ci >= 0 && nodes[ci].size == min_size && origin_less(nodes[ci].origin, nodes[idx].origin)) {
			return false;
		}
	}
	return true;
}

void SparseVoxelOctree::_emit_poly(const int ring[], int rc, const Vector3 &outward,
		const PackedVector3Array &verts, PackedInt32Array &out) const {
	const int tris[2][3] = { { ring[0], ring[1], ring[2] }, { ring[0], ring[2], ring[3] } };
	const int ntri = rc == 4 ? 2 : 1;
	for (int ti = 0; ti < ntri; ++ti) {
		const int i0 = tris[ti][0], i1 = tris[ti][1], i2 = tris[ti][2];
		const Vector3 n = (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0]);
		if (n.dot(outward) >= 0.0) {
			out.push_back(i0); out.push_back(i2); out.push_back(i1);
		} else {
			out.push_back(i0); out.push_back(i1); out.push_back(i2);
		}
	}
}

void SparseVoxelOctree::_try_edge(int idx, int axis, int u, int w, int su, int sw,
		const PackedVector3Array &verts, PackedInt32Array &out) const {
	const double s = nodes[idx].size;
	const Vector3 lo = nodes[idx].origin + axis_vec(u, su * s) + axis_vec(w, sw * s);
	const Vector3 hi = lo + axis_vec(axis, s);
	const double fa = sample(lo);
	const double fb = sample(hi);
	if (fa >= OCTREE_EMPTY || fb >= OCTREE_EMPTY || (fa < 0.0) == (fb < 0.0)) {
		return;
	}
	const Vector3 mid = (lo + hi) * 0.5;
	const double eps = s * 0.25;
	int ring_cells[4];
	for (int k = 0; k < 4; ++k) {
		ring_cells[k] = _find_leaf(mid + axis_vec(u, RING[k][0] * eps) + axis_vec(w, RING[k][1] * eps));
	}
	if (!_owns_edge(idx, ring_cells)) {
		return;
	}
	int ring[4];
	int rc = 0;
	for (int k = 0; k < 4; ++k) {
		const int ci = ring_cells[k];
		if (ci < 0 || nodes[ci].vertex < 0) {
			return;
		}
		if (rc == 0 || ring[rc - 1] != nodes[ci].vertex) {
			ring[rc++] = nodes[ci].vertex;
		}
	}
	if (rc > 1 && ring[0] == ring[rc - 1]) {
		--rc;
	}
	if (rc >= 3) {
		_emit_poly(ring, rc, _leaf_normal(idx), verts, out);
	}
}

void SparseVoxelOctree::_stitch_leaf(int idx, const PackedVector3Array &verts, PackedInt32Array &out) const {
	for (int axis = 0; axis < 3; ++axis) {
		const int u = (axis + 1) % 3;
		const int w = (axis + 2) % 3;
		for (int su = 0; su < 2; ++su) {
			for (int sw = 0; sw < 2; ++sw) {
				_try_edge(idx, axis, u, w, su, sw, verts, out);
			}
		}
	}
}

Array SparseVoxelOctree::mesh() {
	PackedVector3Array verts;
	PackedVector3Array normals;
	PackedInt32Array idx;
	for (uint32_t i = 0; i < nodes.size(); ++i) {
		nodes[i].vertex = -1;
		Vector3 v;
		if (nodes[i].is_leaf() && nodes[i].has_corners && _leaf_vertex(i, v)) {
			nodes[i].vertex = int(verts.size());
			verts.push_back(v);
			normals.push_back(_leaf_normal(i));
		}
	}
	for (uint32_t i = 0; i < nodes.size(); ++i) {
		if (nodes[i].is_leaf() && nodes[i].vertex >= 0) {
			_stitch_leaf(i, verts, idx);
		}
	}
	Array out;
	out.resize(Mesh::ARRAY_MAX);
	out[Mesh::ARRAY_VERTEX] = verts;
	out[Mesh::ARRAY_NORMAL] = normals;
	out[Mesh::ARRAY_INDEX] = idx;
	return out;
}
