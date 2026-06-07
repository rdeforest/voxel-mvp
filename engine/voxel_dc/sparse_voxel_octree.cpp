#include "sparse_voxel_octree.h"

#include "octree_geometry.h"

using namespace voxel_dc;

int SparseVoxelOctree::_new_node(const Vector3 &o, double s) {
	Node n;
	n.origin = o;
	n.size = s;
	nodes.push_back(n);
	return int(nodes.size()) - 1;
}

void SparseVoxelOctree::setup(Vector3 origin, double size) {
	nodes.clear();
	_new_node(origin, size);
}

void SparseVoxelOctree::imprint(const voxel_dc::Field &f, double min_leaf, int material) {
	if (nodes.is_empty()) {
		return; // call setup() first
	}
	const Vector3 ro = nodes[0].origin;
	const double rs = nodes[0].size;
	nodes.clear();
	_new_node(ro, rs);
	_imprint_node(0, f, min_leaf, material);
}

void SparseVoxelOctree::imprint_sphere(Vector3 center, double radius, double min_leaf, int material) {
	imprint(voxel_dc::SphereField(center, radius), min_leaf, material);
}

void SparseVoxelOctree::imprint_box(Vector3 center, Vector3 size, double min_leaf, int material) {
	imprint(voxel_dc::BoxField(center, size), min_leaf, material);
}

// Surface beyond the node's circumradius -> one uniform-sign leaf (bulk, O(1)); at the
// data floor -> a fine leaf with corner samples; otherwise subdivide and recurse.
void SparseVoxelOctree::_imprint_node(int idx, const voxel_dc::Field &f, double min_leaf, int material) {
	const Vector3 o = nodes[idx].origin;
	const double s = nodes[idx].size;
	const Vector3 center = o + Vector3(1, 1, 1) * (s * 0.5);
	const double fc = f.sample(center);
	if (Math::abs(fc) > s * 0.8660254) {
		Node &n = nodes[idx];
		n.has_corners = true;
		n.material = fc < 0.0 ? uint8_t(material) : 0;
		for (int i = 0; i < 8; ++i) {
			n.corners[i] = float(fc);
		}
		return;
	}
	if (s <= min_leaf * 1.0000001) {
		float cs[8];
		for (int i = 0; i < 8; ++i) {
			cs[i] = float(f.sample(corner(o, s, i)));
		}
		Node &n = nodes[idx];
		n.has_corners = true;
		n.material = uint8_t(material);
		for (int i = 0; i < 8; ++i) {
			n.corners[i] = cs[i];
		}
		return;
	}
	const double half = s * 0.5;
	int ch[8];
	for (int i = 0; i < 8; ++i) {
		ch[i] = _new_node(o + Vector3(CB[i][0], CB[i][1], CB[i][2]) * half, half);
	}
	for (int i = 0; i < 8; ++i) {
		nodes[idx].children[i] = ch[i]; // index-access: nodes may have reallocated above
	}
	for (int i = 0; i < 8; ++i) {
		_imprint_node(ch[i], f, min_leaf, material);
	}
}

void SparseVoxelOctree::stamp(const voxel_dc::Field &f, double min_leaf, int material, int op) {
	if (!nodes.is_empty()) {
		_stamp_node(0, f, min_leaf, material, op);
	}
}

void SparseVoxelOctree::stamp_sphere(Vector3 center, double radius, double min_leaf, int material, int op) {
	stamp(voxel_dc::SphereField(center, radius), min_leaf, material, op);
}

void SparseVoxelOctree::stamp_box(Vector3 center, Vector3 size, double min_leaf, int material, int op) {
	stamp(voxel_dc::BoxField(center, size), min_leaf, material, op);
}

// In-place combine. Existing leaves keep their exact corners (just combined with the
// brush); a coarse leaf is subdivided (inheriting the parent field) only where the
// brush's surface needs finer detail — so untouched surface is byte-for-byte intact.
void SparseVoxelOctree::_stamp_node(int idx, const voxel_dc::Field &f, double min_leaf, int material, int op) {
	if (!nodes[idx].is_leaf()) {
		for (int i = 0; i < 8; ++i) {
			_stamp_node(nodes[idx].children[i], f, min_leaf, material, op);
		}
		return;
	}
	if (!nodes[idx].has_corners) {
		return; // unwritten — the brush only edits existing matter (prototype)
	}
	const Vector3 o = nodes[idx].origin;
	const double s = nodes[idx].size;
	const double sc = f.sample(o + Vector3(1, 1, 1) * (s * 0.5));
	if (s > min_leaf * 1.0000001 && Math::abs(sc) <= s * 0.8660254) {
		_subdivide_inherit(idx);
		for (int i = 0; i < 8; ++i) {
			_stamp_node(nodes[idx].children[i], f, min_leaf, material, op);
		}
		return;
	}
	Node &n = nodes[idx];
	const bool binds = op == 0 && sc < trilerp(n.corners, 0.5, 0.5, 0.5);
	for (int i = 0; i < 8; ++i) {
		const double sd = f.sample(corner(o, s, i));
		n.corners[i] = op == 0 ? MIN(n.corners[i], float(sd)) : MAX(n.corners[i], float(-sd));
	}
	if (binds) {
		n.material = uint8_t(material);
	}
}

// Subdivide a leaf into 8 children reproducing its field (corners trilerp'd from this
// leaf), so refining for a brush doesn't move the existing surface.
void SparseVoxelOctree::_subdivide_inherit(int idx) {
	const Vector3 o = nodes[idx].origin;
	const double s = nodes[idx].size;
	float src[8];
	for (int i = 0; i < 8; ++i) {
		src[i] = nodes[idx].corners[i];
	}
	const uint8_t mat = nodes[idx].material;
	const double half = s * 0.5;
	int ch[8];
	for (int i = 0; i < 8; ++i) {
		const int ci = _new_node(o + Vector3(CB[i][0], CB[i][1], CB[i][2]) * half, half);
		Node &c = nodes[ci];
		c.has_corners = true;
		c.material = mat;
		for (int j = 0; j < 8; ++j) {
			const double fx = (CB[i][0] + CB[j][0]) * 0.5;
			const double fy = (CB[i][1] + CB[j][1]) * 0.5;
			const double fz = (CB[i][2] + CB[j][2]) * 0.5;
			c.corners[j] = float(trilerp(src, fx, fy, fz));
		}
		ch[i] = ci;
	}
	Node &n = nodes[idx];
	for (int i = 0; i < 8; ++i) {
		n.children[i] = ch[i];
	}
	n.has_corners = false;
}

int SparseVoxelOctree::_child_index(int idx, const Vector3 &p) const {
	const Node &n = nodes[idx];
	const Vector3 mid = n.origin + Vector3(1, 1, 1) * (n.size * 0.5);
	return (p.x >= mid.x ? 1 : 0) | (p.y >= mid.y ? 2 : 0) | (p.z >= mid.z ? 4 : 0);
}

int SparseVoxelOctree::_leaf_at(const Vector3 &p) const {
	if (nodes.is_empty()) {
		return -1;
	}
	int idx = 0;
	while (!nodes[idx].is_leaf()) {
		idx = nodes[idx].children[_child_index(idx, p)];
	}
	return idx;
}

double SparseVoxelOctree::sample(Vector3 p) const {
	const int idx = _leaf_at(p);
	if (idx < 0 || !nodes[idx].has_corners) {
		return OCTREE_EMPTY;
	}
	const Node &n = nodes[idx];
	const Vector3 f = (p - n.origin) / n.size;
	return trilerp(n.corners, f.x, f.y, f.z);
}

int SparseVoxelOctree::material_at(Vector3 p) const {
	const int idx = _leaf_at(p);
	return idx < 0 ? 0 : int(nodes[idx].material);
}

int SparseVoxelOctree::leaf_count() const {
	int n = 0;
	for (uint32_t i = 0; i < nodes.size(); ++i) {
		if (nodes[i].is_leaf() && nodes[i].has_corners) {
			++n;
		}
	}
	return n;
}

void SparseVoxelOctree::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "origin", "size"), &SparseVoxelOctree::setup);
	ClassDB::bind_method(D_METHOD("imprint_sphere", "center", "radius", "min_leaf", "material"), &SparseVoxelOctree::imprint_sphere);
	ClassDB::bind_method(D_METHOD("imprint_box", "center", "size", "min_leaf", "material"), &SparseVoxelOctree::imprint_box);
	ClassDB::bind_method(D_METHOD("stamp_sphere", "center", "radius", "min_leaf", "material", "op"), &SparseVoxelOctree::stamp_sphere);
	ClassDB::bind_method(D_METHOD("stamp_box", "center", "size", "min_leaf", "material", "op"), &SparseVoxelOctree::stamp_box);
	ClassDB::bind_method(D_METHOD("sample", "p"), &SparseVoxelOctree::sample);
	ClassDB::bind_method(D_METHOD("material_at", "p"), &SparseVoxelOctree::material_at);
	ClassDB::bind_method(D_METHOD("leaf_count"), &SparseVoxelOctree::leaf_count);
	ClassDB::bind_method(D_METHOD("mesh"), &SparseVoxelOctree::mesh);
}
