#include "dc_octree_mesher.h"

#include "dc_qef.h"

#include "core/math/math_funcs.h"
#include "core/templates/local_vector.h"
#include "scene/resources/mesh.h"

using voxel_dc::Qef;

namespace {

// Cube corners by xyz bits (matches DualContour._corner_offset) and the 12 edges.
const int CORNER[8][3] = {
	{ 0, 0, 0 }, { 1, 0, 0 }, { 0, 1, 0 }, { 1, 1, 0 },
	{ 0, 0, 1 }, { 1, 0, 1 }, { 0, 1, 1 }, { 1, 1, 1 },
};
const int EDGES[12][2] = {
	{ 0, 1 }, { 2, 3 }, { 4, 5 }, { 6, 7 },
	{ 0, 2 }, { 1, 3 }, { 4, 6 }, { 5, 7 },
	{ 0, 4 }, { 1, 5 }, { 2, 6 }, { 3, 7 },
};
// Four cells around an edge, in (perp-u, perp-v) quadrant offsets.
const int RING[4][2] = { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } };
const double QUERY_EPS = 0.25; // perpendicular offset to land just across an edge

inline Vector3 to_v3(const Vector3i &v) {
	return Vector3(real_t(v.x), real_t(v.y), real_t(v.z));
}

// One baked SDF grid (a clipmap level): trilinear value + central-difference
// gradient, mirroring SdfBaked. Reads are clamped at the grid edge.
struct Level {
	const float *data = nullptr;
	Vector3 origin;
	double cell = 1.0;
	int dim = 0;

	double grid(int x, int y, int z) const {
		x = CLAMP(x, 0, dim - 1);
		y = CLAMP(y, 0, dim - 1);
		z = CLAMP(z, 0, dim - 1);
		return double(data[x + dim * (y + dim * z)]);
	}

	double at(const Vector3 &world) const {
		double lx = (world.x - origin.x) / cell;
		double ly = (world.y - origin.y) / cell;
		double lz = (world.z - origin.z) / cell;
		int x0 = int(Math::floor(lx)), y0 = int(Math::floor(ly)), z0 = int(Math::floor(lz));
		double fx = lx - x0, fy = ly - y0, fz = lz - z0;
		double c00 = Math::lerp(grid(x0, y0, z0), grid(x0 + 1, y0, z0), fx);
		double c10 = Math::lerp(grid(x0, y0 + 1, z0), grid(x0 + 1, y0 + 1, z0), fx);
		double c01 = Math::lerp(grid(x0, y0, z0 + 1), grid(x0 + 1, y0, z0 + 1), fx);
		double c11 = Math::lerp(grid(x0, y0 + 1, z0 + 1), grid(x0 + 1, y0 + 1, z0 + 1), fx);
		return Math::lerp(Math::lerp(c00, c10, fy), Math::lerp(c01, c11, fy), fz);
	}
};

// The clipmap: pick the finest level whose box contains the point (single-valued
// in position -> crack-free), sample it. target_cell_size drives subdivision.
struct Clipmap {
	LocalVector<Level> levels;
	Vector3 center;
	double half0 = 1.0;

	int level_index(const Vector3 &p) const {
		double d = MAX(Math::abs(p.x - center.x), MAX(Math::abs(p.y - center.y), Math::abs(p.z - center.z)));
		int n = int(levels.size());
		for (int k = 0; k < n; ++k) {
			if (d <= half0 * double(1 << k)) {
				return k;
			}
		}
		return n - 1;
	}

	double value(const Vector3 &p) const {
		return levels[level_index(p)].at(p);
	}

	Vector3 gradient(const Vector3 &p) const {
		const Level &L = levels[level_index(p)];
		double h = L.cell;
		Vector3 g(
				L.at(p + Vector3(h, 0, 0)) - L.at(p - Vector3(h, 0, 0)),
				L.at(p + Vector3(0, h, 0)) - L.at(p - Vector3(0, h, 0)),
				L.at(p + Vector3(0, 0, h)) - L.at(p - Vector3(0, 0, h)));
		return g.length_squared() > 0.0 ? g.normalized() : Vector3(0, 1, 0);
	}

	double target_cell_size(const Vector3 &p) const {
		return double(1 << level_index(p));
	}
};

struct Cell {
	Vector3i origin;
	int size = 0;
	int children[8];
	int vertex = -1;
	bool leaf = true;
};

// Builds + meshes one octree over a clipmap. Mirrors OctreeDC: subdivide to the
// clipmap's per-position target size, one QEF vertex per surface leaf, then
// minimal-edge meshing with point-location (the smallest cell owns each edge; a
// coarser neighbour returned twice collapses the quad to a triangle -> seamless).
struct Octree {
	Clipmap clip;
	int root_size = 0;
	int max_depth = 0;
	LocalVector<Cell> cells;
	PackedVector3Array verts;
	PackedVector3Array normals;
	PackedInt32Array indices;

	int build(const Vector3i &origin, int size, int depth) {
		int idx = int(cells.size());
		Cell c;
		c.origin = origin;
		c.size = size;
		c.leaf = true;
		for (int i = 0; i < 8; ++i) {
			c.children[i] = -1;
		}
		cells.push_back(c);
		if (depth >= max_depth || size <= 1) {
			return idx;
		}
		Vector3 center = to_v3(origin) + Vector3(1, 1, 1) * (size * 0.5);
		if (double(size) <= clip.target_cell_size(center)) {
			return idx;
		}
		int half = size >> 1;
		cells[idx].leaf = false; // index-access only; cells may reallocate during recursion
		for (int i = 0; i < 8; ++i) {
			Vector3i co = origin + Vector3i(CORNER[i][0], CORNER[i][1], CORNER[i][2]) * half;
			int child = build(co, half, depth + 1);
			cells[idx].children[i] = child;
		}
		return idx;
	}

	int find_leaf(const Vector3 &p) const {
		if (p.x < 0.0 || p.y < 0.0 || p.z < 0.0) {
			return -1;
		}
		if (p.x >= root_size || p.y >= root_size || p.z >= root_size) {
			return -1;
		}
		int idx = 0;
		while (!cells[idx].leaf) {
			const Cell &c = cells[idx];
			Vector3 center = to_v3(c.origin) + Vector3(1, 1, 1) * (c.size * 0.5);
			int i = (p.x >= center.x ? 1 : 0) | (p.y >= center.y ? 2 : 0) | (p.z >= center.z ? 4 : 0);
			idx = c.children[i];
		}
		return idx;
	}

	void build_vertex(int idx) {
		Vector3i o = cells[idx].origin;
		int s = cells[idx].size;
		Qef qef;
		Vector3 nsum;
		for (int e = 0; e < 12; ++e) {
			const int *pa = CORNER[EDGES[e][0]];
			const int *pb = CORNER[EDGES[e][1]];
			Vector3i ca = o + Vector3i(pa[0], pa[1], pa[2]) * s;
			Vector3i cb = o + Vector3i(pb[0], pb[1], pb[2]) * s;
			double fa = clip.value(to_v3(ca));
			double fb = clip.value(to_v3(cb));
			if ((fa < 0.0) == (fb < 0.0) || fa == fb) {
				continue;
			}
			double t = fa / (fa - fb);
			Vector3 p = to_v3(ca).lerp(to_v3(cb), t);
			Vector3 n = clip.gradient(p);
			qef.add_plane(p, n);
			nsum += n;
		}
		if (qef.count == 0) {
			return;
		}
		Vector3 cmin = to_v3(o);
		Vector3 cmax = cmin + Vector3(1, 1, 1) * double(s);
		cells[idx].vertex = int(verts.size());
		verts.push_back(qef.solve(cmin, cmax));
		normals.push_back(nsum.length_squared() > 0.0 ? nsum.normalized() : Vector3(0, 1, 0));
	}

	static bool origin_less(const Vector3i &a, const Vector3i &b) {
		if (a.x != b.x) {
			return a.x < b.x;
		}
		if (a.y != b.y) {
			return a.y < b.y;
		}
		return a.z < b.z;
	}

	// This leaf owns the edge iff it is a smallest cell around it and, among equal
	// smallest cells, the lexicographically least origin (so exactly one emits).
	bool owns_edge(int leaf_idx, const int ring_cells[4]) const {
		int min_size = cells[leaf_idx].size;
		for (int k = 0; k < 4; ++k) {
			int ci = ring_cells[k];
			if (ci >= 0 && cells[ci].size < min_size) {
				min_size = cells[ci].size;
			}
		}
		if (cells[leaf_idx].size != min_size) {
			return false;
		}
		for (int k = 0; k < 4; ++k) {
			int ci = ring_cells[k];
			if (ci >= 0 && cells[ci].size == min_size && origin_less(cells[ci].origin, cells[leaf_idx].origin)) {
				return false;
			}
		}
		return true;
	}

	void emit_poly(const int ring[], int rc, const Vector3 &outward) {
		Vector3 p0 = verts[ring[0]], p1 = verts[ring[1]], p2 = verts[ring[2]];
		// Godot CW-from-front: reverse when the right-hand normal points outward.
		bool flip = (p1 - p0).cross(p2 - p0).dot(outward) >= 0.0;
		if (rc == 3) {
			if (flip) {
				indices.push_back(ring[0]); indices.push_back(ring[2]); indices.push_back(ring[1]);
			} else {
				indices.push_back(ring[0]); indices.push_back(ring[1]); indices.push_back(ring[2]);
			}
		} else {
			if (flip) {
				indices.push_back(ring[0]); indices.push_back(ring[2]); indices.push_back(ring[1]);
				indices.push_back(ring[0]); indices.push_back(ring[3]); indices.push_back(ring[2]);
			} else {
				indices.push_back(ring[0]); indices.push_back(ring[1]); indices.push_back(ring[2]);
				indices.push_back(ring[0]); indices.push_back(ring[2]); indices.push_back(ring[3]);
			}
		}
	}

	void try_edge(int leaf_idx, int axis, int u, int w, int su, int sw) {
		Vector3i lo = cells[leaf_idx].origin;
		int s = cells[leaf_idx].size;
		lo[u] += su * s;
		lo[w] += sw * s;
		Vector3i hi = lo;
		hi[axis] += s;
		double fa = clip.value(to_v3(lo));
		double fb = clip.value(to_v3(hi));
		if ((fa < 0.0) == (fb < 0.0) || fa == fb) {
			return;
		}
		Vector3 mid = (to_v3(lo) + to_v3(hi)) * 0.5;
		Vector3 udir, wdir;
		udir[u] = 1.0;
		wdir[w] = 1.0;
		int ring_cells[4];
		for (int k = 0; k < 4; ++k) {
			Vector3 q = mid + udir * (RING[k][0] * QUERY_EPS) + wdir * (RING[k][1] * QUERY_EPS);
			ring_cells[k] = find_leaf(q);
		}
		if (!owns_edge(leaf_idx, ring_cells)) {
			return;
		}
		int ring[4];
		int rc = 0;
		for (int k = 0; k < 4; ++k) {
			int ci = ring_cells[k];
			if (ci < 0 || cells[ci].vertex < 0) {
				return;
			}
			int v = cells[ci].vertex;
			if (rc == 0 || ring[rc - 1] != v) {
				ring[rc++] = v;
			}
		}
		if (rc > 1 && ring[0] == ring[rc - 1]) {
			--rc;
		}
		if (rc < 3) {
			return;
		}
		double t = fa / (fa - fb);
		Vector3 outward = clip.gradient(to_v3(lo).lerp(to_v3(hi), t));
		emit_poly(ring, rc, outward);
	}

	void emit_leaf_edges(int leaf_idx) {
		for (int axis = 0; axis < 3; ++axis) {
			int u = (axis + 1) % 3;
			int w = (axis + 2) % 3;
			for (int su = 0; su < 2; ++su) {
				for (int sw = 0; sw < 2; ++sw) {
					try_edge(leaf_idx, axis, u, w, su, sw);
				}
			}
		}
	}

	void run() {
		build(Vector3i(0, 0, 0), root_size, 0);
		// Pass 1: a QEF vertex for every surface leaf. Pass 2: stitch edges.
		int n = int(cells.size());
		for (int i = 0; i < n; ++i) {
			if (cells[i].leaf) {
				build_vertex(i);
			}
		}
		for (int i = 0; i < n; ++i) {
			if (cells[i].leaf && cells[i].vertex >= 0) {
				emit_leaf_edges(i);
			}
		}
	}
};

} // namespace

Array DCOctreeMesher::mesh_clipmap(
		const TypedArray<PackedFloat32Array> &level_data,
		int dim,
		const PackedVector3Array &level_origins,
		const PackedFloat32Array &level_cells,
		Vector3 center,
		double half0,
		int depth) {
	Array out;
	const int n = level_data.size();
	if (n == 0 || dim < 2 || level_origins.size() != n || level_cells.size() != n || depth < 1) {
		ERR_PRINT("DCOctreeMesher: bad arguments");
		return out;
	}

	// Hold the level arrays for the call so their data pointers stay valid.
	LocalVector<PackedFloat32Array> held;
	held.resize(n);
	const int64_t per_level = int64_t(dim) * dim * dim;

	Octree oct;
	oct.root_size = 1 << depth;
	oct.max_depth = depth;
	oct.clip.center = center;
	oct.clip.half0 = half0;
	oct.clip.levels.resize(n);
	for (int k = 0; k < n; ++k) {
		held[k] = level_data[k];
		if (held[k].size() != per_level) {
			ERR_PRINT("DCOctreeMesher: level data size mismatch");
			return out;
		}
		Level lv;
		lv.data = held[k].ptr();
		lv.origin = level_origins[k];
		lv.cell = level_cells[k];
		lv.dim = dim;
		oct.clip.levels[k] = lv;
	}

	oct.run();

	if (oct.verts.is_empty()) {
		return out;
	}
	out.resize(Mesh::ARRAY_MAX);
	out[Mesh::ARRAY_VERTEX] = oct.verts;
	out[Mesh::ARRAY_NORMAL] = oct.normals;
	out[Mesh::ARRAY_INDEX] = oct.indices;
	return out;
}

void DCOctreeMesher::_bind_methods() {
	ClassDB::bind_method(
			D_METHOD("mesh_clipmap", "level_data", "dim", "level_origins", "level_cells", "center", "half0", "depth"),
			&DCOctreeMesher::mesh_clipmap);
}
