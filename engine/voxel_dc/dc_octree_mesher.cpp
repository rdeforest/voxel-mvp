#include "dc_octree_mesher.h"

#include "dc_qef.h"

#include "core/math/math_funcs.h"
#include "core/templates/local_vector.h"
#include "scene/resources/mesh.h"

using voxel_dc::Qef;

namespace {

// Cube corners by xyz bits, and the 12 edges.
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
// gradient. Reads are clamped at the grid edge.
struct Level {
	const float *data = nullptr;
	const uint8_t *idx = nullptr; // optional CHANNEL_INDICES bytes, same layout as data
	Vector3 origin;
	double cell = 1.0;
	int dim = 0;

	double grid(int x, int y, int z) const {
		x = CLAMP(x, 0, dim - 1);
		y = CLAMP(y, 0, dim - 1);
		z = CLAMP(z, 0, dim - 1);
		return double(data[x + dim * (y + dim * z)]);
	}

	// Nearest material id at a world point (ids are discrete — no interpolation).
	int index_nearest(const Vector3 &world) const {
		if (idx == nullptr) {
			return 0;
		}
		int x = int(Math::round((world.x - origin.x) / cell));
		int y = int(Math::round((world.y - origin.y) / cell));
		int z = int(Math::round((world.z - origin.z) / cell));
		x = CLAMP(x, 0, dim - 1);
		y = CLAMP(y, 0, dim - 1);
		z = CLAMP(z, 0, dim - 1);
		return int(idx[x + dim * (y + dim * z)]);
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

	// Geomorphed sample: blend level k into level k+1 across the OUTER HALF of level k's
	// band, so the field is CONTINUOUS across every LOD boundary (at the boundary the
	// blend equals level k+1, which is exactly what the next band uses at its inner edge).
	// A hard level switch steps the surface where the coarse mip drops detail the fine
	// level has, and the crack-free stitch bridges that step with near-vertical slivers;
	// blending removes the step. Still single-valued in position -> still crack-free.
	double value(const Vector3 &p) const {
		int k = level_index(p);
		double v = levels[k].at(p);
		if (k + 1 < int(levels.size())) {
			double d = MAX(Math::abs(p.x - center.x), MAX(Math::abs(p.y - center.y), Math::abs(p.z - center.z)));
			double boundary = half0 * double(1 << k);
			double inner = boundary * 0.5; // band is (boundary/2, boundary]
			if (d > inner) {
				double t = CLAMP((d - inner) / (boundary - inner), 0.0, 1.0);
				v = Math::lerp(v, levels[k + 1].at(p), t);
			}
		}
		return v;
	}

	Vector3 gradient(const Vector3 &p) const {
		double h = double(1 << level_index(p)); // local cell size
		Vector3 g(
				value(p + Vector3(h, 0, 0)) - value(p - Vector3(h, 0, 0)),
				value(p + Vector3(0, h, 0)) - value(p - Vector3(0, h, 0)),
				value(p + Vector3(0, 0, h)) - value(p - Vector3(0, 0, h)));
		return g.length_squared() > 0.0 ? g.normalized() : Vector3(0, 1, 0);
	}

	double target_cell_size(const Vector3 &p) const {
		return double(1 << level_index(p));
	}

	int index_at(const Vector3 &p) const {
		return levels[level_index(p)].index_nearest(p);
	}
};

struct Cell {
	Vector3i origin;
	int size = 0;
	int children[8];
	int vertex = -1;
	bool leaf = true;
	Qef qef; // accumulated up the tree (own crossings for a leaf; children's sum otherwise)
};

// Builds + meshes one octree over a clipmap: subdivide to the clipmap's
// per-position target size (the data-resolution floor), then — when error_driven —
// COLLAPSE bottom-up wherever one vertex represents the surface within eps_px on
// screen, so flat regions coarsen and curved ones stay fine. One QEF vertex per
// surviving leaf, then minimal-edge meshing with point-location (the smallest cell
// owns each edge; a coarser neighbour returned twice collapses the quad to a
// triangle -> seamless across the size jumps the collapse introduces).
struct Octree {
	Clipmap clip;
	int root_size = 0;
	int max_depth = 0;
	Vector3 camera;          // viewpoint in lattice space (error-driven refine)
	double proj = 0.0;       // viewport_height / (2*tan(fov/2))
	double eps_px = 0.0;     // screen-space error threshold (px)
	bool error_driven = false;
	int max_leaf_size = 0;   // min-grid floor: never collapse above this (a flat world keeps >=2 cells/axis, so it meshes instead of collapsing to one empty cell)
	Vector3i world_origin;   // world coords of lattice (0,0,0): makes the hysteresis keys world-stable
	HashSet<Vector4i> *prev_collapse = nullptr; // last frame's collapsed world-nodes (read)
	HashSet<Vector4i> *curr_collapse = nullptr; // this frame's collapsed world-nodes (write)
	static constexpr double HYST = 2.5;          // stay-collapsed slack: subdivide only past eps*HYST
	bool emit_color = false;       // sample material ids and emit per-vertex colours
	PackedColorArray palette;      // material id -> albedo (index 0 = natural)
	LocalVector<Cell> cells;
	PackedVector3Array verts;
	PackedVector3Array normals;
	PackedColorArray colors;       // per-vertex material colour (rgb); a=0 material, a=1 natural
	PackedInt32Array indices;

	// A leaf's QEF, built from the 12 cube edges that cross the isosurface (the cell's
	// own Hermite data at its own size).
	Qef leaf_qef(int idx) const {
		Qef qef;
		Vector3i o = cells[idx].origin;
		int s = cells[idx].size;
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
			qef.add_plane(p, clip.gradient(p));
		}
		return qef;
	}

	// Recursively orphan a node's whole subtree (mark every descendant non-leaf), so a
	// collapsed node is the sole leaf over its region regardless of how its descendants
	// had decided. Leaves have children[i] == -1, so this stops there.
	void orphan_subtree(int idx) {
		for (int i = 0; i < 8; ++i) {
			int ch = cells[idx].children[i];
			if (ch < 0) {
				continue;
			}
			orphan_subtree(ch);
			cells[ch].leaf = false;
		}
	}

	// Bottom-up pass: give every cell its accumulated QEF (a leaf's own crossings; an
	// internal node = sum of its children's, so the node carries ALL the fine Hermite
	// data within it — no coarse-corner undersampling). When error_driven, collapse a
	// node into a single leaf if one vertex fits that accumulated data within the screen
	// threshold (and the node isn't above the min-grid floor). The threshold is
	// HYSTERETIC: a node that was collapsed last frame stays collapsed until its error
	// clearly exceeds eps (×HYST), so cells don't oscillate as the camera moves. The
	// accumulated QEF's residual already refuses to collapse over real detail, so no
	// "all children are leaves" gate is needed — collapsing just orphans the subtree;
	// point-location meshing stitches the resulting size jumps crack-free.
	void accumulate(int idx) {
		if (cells[idx].leaf) {
			cells[idx].qef = leaf_qef(idx);
			return;
		}
		Qef sum;
		for (int i = 0; i < 8; ++i) {
			int ch = cells[idx].children[i];
			accumulate(ch);
			sum.add(cells[ch].qef);
		}
		cells[idx].qef = sum;
		if (!error_driven || sum.count == 0 || cells[idx].size > max_leaf_size) {
			return;
		}
		Vector3 cmin = to_v3(cells[idx].origin);
		Vector3 cmax = cmin + Vector3(1, 1, 1) * double(cells[idx].size);
		Vector3 v = sum.solve(cmin, cmax);
		double we = Math::sqrt(sum.residual(v) / double(sum.count));
		Vector3 center = cmin + Vector3(1, 1, 1) * (cells[idx].size * 0.5);
		double dist = MAX((center - camera).length(), 1e-3);
		double screen_err = we * proj / dist;
		Vector4i key(cells[idx].origin.x + world_origin.x, cells[idx].origin.y + world_origin.y,
				cells[idx].origin.z + world_origin.z, cells[idx].size);
		bool was_collapsed = prev_collapse != nullptr && prev_collapse->has(key);
		double threshold = was_collapsed ? eps_px * HYST : eps_px;
		if (screen_err > threshold) {
			return; // too complex here for one vertex (with hysteresis slack if it was collapsed)
		}
		cells[idx].leaf = true; // collapse: this node is the leaf; its subtree is orphaned
		orphan_subtree(idx);
		if (curr_collapse != nullptr) {
			curr_collapse->insert(key);
		}
	}

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
			return idx; // at the data resolution floor — can't refine further
		}
		// Always build down to the data floor; error-driven coarsening happens bottom-up
		// in accumulate() (build fine, then collapse where the fine data fits one vertex),
		// which measures the real surface instead of undersampling at coarse corners.
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

	// Place this leaf's vertex from its accumulated QEF. For a collapsed leaf the QEF
	// holds all the fine crossings within it, so the vertex and normal reflect the real
	// surface, not a coarse re-sample.
	void place_vertex(int idx) {
		const Qef &qef = cells[idx].qef;
		Vector3 cmin = to_v3(cells[idx].origin);
		Vector3 cmax = cmin + Vector3(1, 1, 1) * double(cells[idx].size);
		Vector3 v = qef.solve(cmin, cmax);
		Vector3 n = qef.nsum.length_squared() > 0.0 ? qef.nsum.normalized() : Vector3(0, 1, 0);
		cells[idx].vertex = int(verts.size());
		verts.push_back(v);
		normals.push_back(n);
		if (emit_color) {
			// Sample the solid voxel just behind the surface: the normal points
			// outward, so step inward to land in the cell that carries the id.
			int id = clip.index_at(v - n * 0.5);
			if (id > 0 && id < int(palette.size())) {
				const Color &c = palette[id];
				colors.push_back(Color(c.r, c.g, c.b, 0.0)); // a=0 -> explicit material colour
			} else {
				colors.push_back(Color(0, 0, 0, 1.0)); // a=1 -> natural (slope-shaded; also the
													   // default for meshes with no colour array)
			}
		}
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

	// Emit one triangle wound so its front face points `outward` (Godot is CW-from-front,
	// so reverse when the right-hand normal already points outward).
	void emit_tri(int i0, int i1, int i2, const Vector3 &outward) {
		Vector3 n = (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0]);
		if (n.dot(outward) >= 0.0) {
			indices.push_back(i0); indices.push_back(i2); indices.push_back(i1);
		} else {
			indices.push_back(i0); indices.push_back(i1); indices.push_back(i2);
		}
	}

	// Decide winding PER TRIANGLE, not once for the whole quad: a quad spanning a LOD
	// size jump is non-planar, so a single flip decision leaves one of its two triangles
	// back-facing — a culled, see-through gap. Orienting each triangle to `outward`
	// independently keeps the surface consistently wound across the seam.
	void emit_poly(const int ring[], int rc, const Vector3 &outward) {
		emit_tri(ring[0], ring[1], ring[2], outward);
		if (rc == 4) {
			emit_tri(ring[0], ring[2], ring[3], outward);
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
		// Keep a flat world at >=2 cells/axis so it meshes (a fully-collapsed flat region
		// is one empty cell — no quad). half the root => the 8 root children may collapse,
		// nothing coarser.
		max_leaf_size = MAX(1, root_size >> 1);
		accumulate(0); // QEF up the tree + error-driven collapse
		// Pass 1: a vertex per surviving surface leaf. Pass 2: stitch edges.
		int n = int(cells.size());
		for (int i = 0; i < n; ++i) {
			if (cells[i].leaf && cells[i].qef.count > 0) {
				place_vertex(i);
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
		int depth,
		Vector3 camera,
		double proj,
		double eps_px,
		bool error_driven,
		Vector3i lattice_world_origin,
		const TypedArray<PackedByteArray> &level_indices,
		const PackedColorArray &palette) {
	Array out;
	const int n = level_data.size();
	if (n == 0 || dim < 2 || level_origins.size() != n || level_cells.size() != n || depth < 1) {
		ERR_PRINT("DCOctreeMesher: bad arguments");
		return out;
	}

	// Hold the level arrays for the call so their data pointers stay valid.
	LocalVector<PackedFloat32Array> held;
	held.resize(n);
	LocalVector<PackedByteArray> held_idx;
	held_idx.resize(n);
	const int64_t per_level = int64_t(dim) * dim * dim;
	const bool with_indices = level_indices.size() == n && palette.size() > 0;

	Octree oct;
	oct.emit_color = with_indices;
	oct.palette = palette;
	oct.root_size = 1 << depth;
	oct.max_depth = depth;
	oct.camera = camera;
	oct.proj = proj;
	oct.eps_px = eps_px;
	oct.error_driven = error_driven;
	oct.world_origin = lattice_world_origin;
	oct.prev_collapse = &_prev_collapse;
	oct.curr_collapse = &_curr_collapse;
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
		if (with_indices) {
			held_idx[k] = level_indices[k];
			if (held_idx[k].size() == per_level) {
				lv.idx = held_idx[k].ptr();
			}
		}
		oct.clip.levels[k] = lv;
	}

	oct.run();

	// This frame's collapse decisions become next frame's history (and bound the set to
	// the current window — untouched nodes drop out).
	if (error_driven) {
		SWAP(_prev_collapse, _curr_collapse);
		_curr_collapse.clear();
	}

	if (oct.verts.is_empty()) {
		return out;
	}
	out.resize(Mesh::ARRAY_MAX);
	out[Mesh::ARRAY_VERTEX] = oct.verts;
	out[Mesh::ARRAY_NORMAL] = oct.normals;
	if (!oct.colors.is_empty()) {
		out[Mesh::ARRAY_COLOR] = oct.colors;
	}
	out[Mesh::ARRAY_INDEX] = oct.indices;
	return out;
}

void DCOctreeMesher::_bind_methods() {
	ClassDB::bind_method(
			D_METHOD("mesh_clipmap", "level_data", "dim", "level_origins", "level_cells", "center", "half0", "depth",
					"camera", "proj", "eps_px", "error_driven", "lattice_world_origin", "level_indices", "palette"),
			&DCOctreeMesher::mesh_clipmap,
			DEFVAL(Vector3()), DEFVAL(0.0), DEFVAL(0.0), DEFVAL(false), DEFVAL(Vector3i()),
			DEFVAL(TypedArray<PackedByteArray>()), DEFVAL(PackedColorArray()));
}
