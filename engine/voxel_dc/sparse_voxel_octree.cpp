#include "sparse_voxel_octree.h"

#include "scene/resources/mesh.h"

namespace {

// Cube corners by xyz bits (matches the GDScript CORNERS / the mesher's table).
const int CB[8][3] = {
	{ 0, 0, 0 }, { 1, 0, 0 }, { 0, 1, 0 }, { 1, 1, 0 },
	{ 0, 0, 1 }, { 1, 0, 1 }, { 0, 1, 1 }, { 1, 1, 1 },
};
const int EDGES[12][2] = {
	{ 0, 1 }, { 2, 3 }, { 4, 5 }, { 6, 7 },
	{ 0, 2 }, { 1, 3 }, { 4, 6 }, { 5, 7 },
	{ 0, 4 }, { 1, 5 }, { 2, 6 }, { 3, 7 },
};
const int RING[4][2] = { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } };

inline Vector3 axis_vec(int i, double a) {
	return i == 0 ? Vector3(a, 0, 0) : (i == 1 ? Vector3(0, a, 0) : Vector3(0, 0, a));
}
inline bool origin_less(const Vector3 &a, const Vector3 &b) {
	if (a.x != b.x) {
		return a.x < b.x;
	}
	if (a.y != b.y) {
		return a.y < b.y;
	}
	return a.z < b.z;
}

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

// --- meshing (Dual Contouring directly over the octree) ---

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
	if (fa >= EMPTY || fb >= EMPTY || (fa < 0.0) == (fb < 0.0)) {
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
