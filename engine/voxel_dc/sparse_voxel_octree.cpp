#include "sparse_voxel_octree.h"

namespace {

// Cube corners by xyz bits (matches the GDScript CORNERS / the mesher's table).
const int CB[8][3] = {
	{ 0, 0, 0 }, { 1, 0, 0 }, { 0, 1, 0 }, { 1, 1, 0 },
	{ 0, 0, 1 }, { 1, 0, 1 }, { 0, 1, 1 }, { 1, 1, 1 },
};

inline Vector3 corner(const Vector3 &o, double s, int i) {
	return o + Vector3(CB[i][0], CB[i][1], CB[i][2]) * s;
}

inline double trilerp(const float *c, double fx, double fy, double fz) {
	double c00 = Math::lerp(double(c[0]), double(c[1]), fx);
	double c10 = Math::lerp(double(c[2]), double(c[3]), fx);
	double c01 = Math::lerp(double(c[4]), double(c[5]), fx);
	double c11 = Math::lerp(double(c[6]), double(c[7]), fx);
	return Math::lerp(Math::lerp(c00, c10, fy), Math::lerp(c01, c11, fy), fz);
}

const double EMPTY = 1e30; // sample() of an unwritten region

} // namespace

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
		return EMPTY;
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
	ClassDB::bind_method(D_METHOD("sample", "p"), &SparseVoxelOctree::sample);
	ClassDB::bind_method(D_METHOD("material_at", "p"), &SparseVoxelOctree::material_at);
	ClassDB::bind_method(D_METHOD("leaf_count"), &SparseVoxelOctree::leaf_count);
}
