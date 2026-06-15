#include "dc_octree_mesher.h"

#include "dc_qef.h"
#include "octree_geometry.h"
#include "sdf_field.h"

#include "core/math/math_funcs.h"
#include "core/templates/local_vector.h"
#include "scene/resources/mesh.h"

// CB (cube corners by xyz bits), EDGES (12 corner-pairs), RING (4 cells around an edge),
// and Qef all come from voxel_dc — shared with the SparseVoxelOctree storage/mesher so
// the corner order can't drift between them.
using namespace voxel_dc;

namespace {

const double QUERY_EPS = 0.25; // perpendicular offset to land just across an edge

inline Vector3 to_v3(const Vector3i &v) {
	return Vector3(real_t(v.x), real_t(v.y), real_t(v.z));
}

// One baked SDF grid (a clipmap level): trilinear value (shared voxel_dc sampler) plus
// the material-index channel. Reads are clamped at the grid edge.
struct Level {
	const float *data = nullptr;
	const uint8_t *idx = nullptr; // optional CHANNEL_INDICES bytes, same layout as data
	Vector3 origin;
	double cell = 1.0;
	int dim = 0;

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
		return voxel_dc::sample_trilinear(data, dim, origin, cell, world);
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
	//
	// EXCEPT the finest level (k==0) is kept PURE: its blend factor depends on
	// distance-from-camera, so blending coarse LOD1 data into the fine band makes a
	// close object's field — and thus its mesh — change as the camera orbits it (the
	// "< 10 m structure shifts with view angle" bug). The whole build region lives in
	// level 0, so it must read pure fine data, identical from every angle. Geomorph
	// still smooths the coarser, farther transitions (k>=1) where the camera-distance
	// dependence isn't noticeable. (The proper fix — one fine field + error-collapse,
	// no discrete LOD levels near the player — retires geomorph entirely; substrate
	// Phase A. This keeps the finest band stable until then.)
	double value(const Vector3 &p) const {
		int k = level_index(p);
		double v = levels[k].at(p);
		if (k > 0 && k + 1 < int(levels.size())) {
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

	// Material of the solid a surface vertex BOUNDS. A vertex bounds the body on the side its
	// normal points away from, so we look STRAIGHT INWARD (toward -n): if the nearest cell is
	// Natural(0) (the one-cell per-leaf boundary shell), scan the neighbours aligned with -n
	// (offset·n̂ < -0.9, i.e. within ~25° of straight inward) and take the closest nonzero id
	// (ties -> lowest, deterministic).
	//
	// Near-straight-inward, NOT a hemisphere, on purpose. A part's own face/edge/corner vertex
	// has its normal pointing out of the part, so the cell straight behind it (axis for a face,
	// the matching diagonal for an edge/corner) is the part interior -> it reads the part. But a
	// terrain-surface vertex BESIDE a part points up out of the ground; the part is a sideways or
	// down-AND-sideways neighbour — those offsets are not aligned with -n, so they're excluded and
	// the ground stays natural instead of bleeding the part's material outward. (A plain inward
	// hemisphere still bled: a down-sideways diagonal is "inward" yet reaches the part beside it.)
	// Scan at the level's own cell size so it stays single-level -> crack-free.
	int index_prefer_explicit(const Vector3 &p, const Vector3 &n) const {
		const Level &lv = levels[level_index(p)];
		int id = lv.index_nearest(p);
		if (id > 0) {
			return id;
		}
		const double c = lv.cell;
		int best = 0;
		double best_d2 = 1e30;
		for (int dz = -1; dz <= 1; ++dz) {
			for (int dy = -1; dy <= 1; ++dy) {
				for (int dx = -1; dx <= 1; ++dx) {
					if (dx == 0 && dy == 0 && dz == 0) {
						continue;
					}
					Vector3 off(dx, dy, dz);
					if (off.normalized().dot(n) >= -0.9) {
						continue; // not aligned with -n (straight inward); sideways neighbours excluded
					}
					int nid = lv.index_nearest(p + off * c);
					if (nid <= 0) {
						continue;
					}
					double d2 = double(dx * dx + dy * dy + dz * dz);
					if (d2 < best_d2 || (d2 == best_d2 && nid < best)) {
						best_d2 = d2;
						best = nid;
					}
				}
			}
		}
		return best;
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
	double residual_tol = 0.0; // world-residual collapse tolerance (base-cell units) — necessity LOD
	bool error_driven = false;
	int max_leaf_size = 0;   // min-grid floor: never collapse above this (a flat world keeps >=2 cells/axis, so it meshes instead of collapsing to one empty cell)
	Vector3i world_origin;   // world coords of lattice (0,0,0): converts a cell's local origin to its world position for the emit/build boxes
	bool emit_color = false;       // sample material ids and emit per-vertex colours
	PackedColorArray palette;      // material id -> albedo (index 0 = natural)
	bool uniform_core = false;     // keep the finest level (level 0) at 1m — never collapse it,
	                               // so the fine field has clean cell boundaries an edit patch
	                               // can splice against (incremental meshing). Outer levels still
	                               // collapse by screen error.
	double prune_safety = 0.0;     // >0 enables the surface-sparse build: stop subdividing a cell
	                               // proven surface-free by a locally-estimated Lipschitz bound, so
	                               // the tree is O(surface) not O(volume). The factor pads the
	                               // gradient estimate against nonlinearity (≈1.5 safe). 0 = the
	                               // old dense build-to-floor everywhere.
	bool emit_filter = false;      // emit only triangles owned by cells inside [emit_min, emit_max)
	Vector3i emit_min;             // (WORLD lattice) — the incremental patch's core box
	Vector3i emit_max;
	bool build_box = false;        // restrict the build to cells overlapping [build_min, build_max)
	Vector3i build_min;            // (WORLD lattice) — a splice builds only the edit box + apron, on the
	Vector3i build_max;            // FULL build's frame, so its cells share that lattice → crack-free
	LocalVector<Cell> cells;
	PackedVector3Array verts;
	PackedVector3Array normals;
	PackedColorArray colors;       // per-vertex material colour (rgb); a=0 material, a=1 natural
	PackedInt32Array indices;
	PackedVector3Array tri_owners;      // WORLD owner-cell origin per emitted triangle
	PackedFloat32Array tri_owner_sizes; // parallel: owner cell SIZE (lattice units)

	// World-lattice origin of a cell (cells store origin relative to the octree root).
	Vector3i cell_world_origin(int idx) const {
		return cells[idx].origin + world_origin;
	}

	bool owner_in_emit_box(int idx) const {
		Vector3i o = cell_world_origin(idx);
		return o.x >= emit_min.x && o.x < emit_max.x && o.y >= emit_min.y && o.y < emit_max.y && o.z >= emit_min.z && o.z < emit_max.z;
	}

	// Does a cell (lattice origin + size) overlap the build box (WORLD lattice)? A splice descends
	// only overlapping cells, so the tree is a thin spine to the edit box plus the box at full res.
	bool cell_overlaps_build_box(const Vector3i &origin, int size) const {
		Vector3i o = origin + world_origin;
		return o.x + size > build_min.x && o.x < build_max.x && o.y + size > build_min.y && o.y < build_max.y && o.z + size > build_min.z && o.z < build_max.z;
	}

	// A leaf's QEF, built from the 12 cube edges that cross the isosurface (the cell's
	// own Hermite data at its own size).
	Qef leaf_qef(int idx) const {
		Qef qef;
		Vector3i o = cells[idx].origin;
		int s = cells[idx].size;
		for (int e = 0; e < 12; ++e) {
			const int *pa = CB[EDGES[e][0]];
			const int *pb = CB[EDGES[e][1]];
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
	// node into a single leaf if one vertex fits that accumulated data within the
	// world-residual tolerance (and the node isn't above the min-grid floor). The
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
		// Never collapse the finest level: a uniform 1m fine core gives edit patches clean
		// cell boundaries to splice against (incremental meshing). Outer levels still coarsen.
		if (uniform_core) {
			Vector3 c = cmin + Vector3(1, 1, 1) * (cells[idx].size * 0.5);
			if (clip.level_index(c) == 0) {
				return;
			}
		}
		Vector3 v = sum.solve(cmin, cmax);
		// Collapse error = the L2 residual of the accumulated QEF at the merged vertex,
		// NOT divided by plane count. The old /count averaged a thin feature's few
		// high-residual planes into the many ZERO-residual planes of the flat surface
		// around it, so a big cell collapsed over a spire and the surface flapped /
		// vanished. Undivided, flat planes contribute exactly 0 (they don't dilute), so
		// the residual reflects the feature's own error: ~0 on flat/cliff/gently-curved
		// regions, spiking where one vertex can't represent a feature -> the feature
		// vetoes its own collapse.
		//
		// Necessity-driven LOD: collapse when that residual is within a fixed WORLD-space
		// tolerance (base-cell units) — NOT scaled by camera distance. The mesh is then
		// f(field), not f(field, camera): moving or turning the camera changes the LOD
		// nowhere, so a distant (telescoped) view is already as detailed as the surface
		// demands. Detail is bought only where the field needs it.
		double we = Math::sqrt(sum.residual(v));
		if (we > residual_tol) {
			return; // surface here needs more than one vertex
		}
		cells[idx].leaf = true; // collapse: this node is the leaf; its subtree is orphaned
		orphan_subtree(idx);
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
		if (build_box && !cell_overlaps_build_box(origin, size)) {
			return idx; // outside the splice's edit box+apron — leaf, don't descend (no data sampled)
		}
		Vector3 center = to_v3(origin) + Vector3(1, 1, 1) * (size * 0.5);
		// Surface-sparse prune: if the cell is provably surface-free, stop here instead of
		// subdividing its whole subtree down to the floor (the dense build's 10M-cell cost).
		// |field(center)| greater than the field's worst-case change to any corner means no
		// zero-crossing inside. The change is bounded by half the cell-scale gradient summed
		// over axes (L1, conservative vs the diagonal), padded by prune_safety for the field's
		// nonlinearity. Self-calibrating: steep regions have a big gradient and prune less, so
		// no global slope constant to mis-tune. A pruned cell carries no surface, so no
		// crossing edge touches it and the stitch loses nothing.
		if (prune_safety > 0.0 && size > 1) {
			double fc = clip.value(center);
			double h = size * 0.5;
			double gx = Math::abs(clip.value(center + Vector3(h, 0, 0)) - clip.value(center - Vector3(h, 0, 0)));
			double gy = Math::abs(clip.value(center + Vector3(0, h, 0)) - clip.value(center - Vector3(0, h, 0)));
			double gz = Math::abs(clip.value(center + Vector3(0, 0, h)) - clip.value(center - Vector3(0, 0, h)));
			double spread = 0.5 * (gx + gy + gz) * prune_safety;
			if (Math::abs(fc) > spread) {
				return idx; // confidently surface-free — uniform leaf, don't subdivide
			}
		}
		if (double(size) <= clip.target_cell_size(center)) {
			return idx; // at the data resolution floor — can't refine further
		}
		// Always build down to the data floor; error-driven coarsening happens bottom-up
		// in accumulate() (build fine, then collapse where the fine data fits one vertex),
		// which measures the real surface instead of undersampling at coarse corners.
		int half = size >> 1;
		cells[idx].leaf = false; // index-access only; cells may reallocate during recursion
		for (int i = 0; i < 8; ++i) {
			Vector3i co = origin + Vector3i(CB[i][0], CB[i][1], CB[i][2]) * half;
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
			// outward, so step inward to land in the cell that carries the id. Prefer an
			// inward explicit material so a placed part's faces read the part, while a terrain
			// vertex beside the part stays natural (the body it bounds is inward, not sideways).
			int id = clip.index_prefer_explicit(v - n * 0.5, n);
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
	// so reverse when the right-hand normal already points outward). `owner` (world lattice)
	// is the cell that owns this edge — tagged per triangle for the incremental splice.
	// `owner_size` is the owner cell's size in lattice units, for the B1 alignment fix.
	void emit_tri(int i0, int i1, int i2, const Vector3 &outward, const Vector3 &owner, float owner_size) {
		Vector3 n = (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0]);
		if (n.dot(outward) >= 0.0) {
			indices.push_back(i0); indices.push_back(i2); indices.push_back(i1);
		} else {
			indices.push_back(i0); indices.push_back(i1); indices.push_back(i2);
		}
		tri_owners.push_back(owner);
		tri_owner_sizes.push_back(owner_size);
	}

	// Decide winding PER TRIANGLE, not once for the whole quad: a quad spanning a LOD
	// size jump is non-planar, so a single flip decision leaves one of its two triangles
	// back-facing — a culled, see-through gap. Orienting each triangle to `outward`
	// independently keeps the surface consistently wound across the seam.
	void emit_poly(const int ring[], int rc, const Vector3 &outward, const Vector3 &owner, float owner_size) {
		emit_tri(ring[0], ring[1], ring[2], outward, owner, owner_size);
		if (rc == 4) {
			emit_tri(ring[0], ring[2], ring[3], outward, owner, owner_size);
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
		if (emit_filter && !owner_in_emit_box(leaf_idx)) {
			return; // incremental patch: only the core box's own triangles
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
		// Winding reference = the surface normal (gradient), which is the most accurate direction and
		// is needed where the surface grazes the edge (then the axial facing alone is ambiguous). BUT
		// the gradient is a finite difference stepped by the cell size, so where two surfaces sit
		// closer than a cell — a part resting on sloped ground, leaving a thin air wedge — it samples
		// ACROSS the gap into the far solid and, on our non-true-distance SDF, flips, back-facing the
		// wedge. The edge's own endpoints give the facing along `axis` unambiguously (solid→air =
		// sign(fb - fa); fa, fb are opposite-signed, checked above). So trust the gradient, but if its
		// axial component CONTRADICTS that sign it jumped a thin feature — veto it to the axial facing.
		double t = fa / (fa - fb);
		Vector3 outward = clip.gradient(to_v3(lo).lerp(to_v3(hi), t));
		double axis_face = (fb > fa) ? 1.0 : -1.0;
		if (outward[axis] * axis_face < 0.0) {
			outward = Vector3();
			outward[axis] = axis_face;
		}
		emit_poly(ring, rc, outward, to_v3(cell_world_origin(leaf_idx)), float(cells[leaf_idx].size));
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
		double residual_tol,
		bool error_driven,
		Vector3i lattice_world_origin,
		const TypedArray<PackedByteArray> &level_indices,
		const PackedColorArray &palette,
		bool uniform_core,
		double prune_safety,
		Vector3i emit_min,
		Vector3i emit_max,
		Vector3i build_min,
		Vector3i build_max) {
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
	oct.uniform_core = uniform_core;   // keep the 1m fine core uniform so edit patches splice cleanly
	oct.prune_safety = prune_safety;   // >0: surface-sparse build (skip provably-empty regions)
	oct.root_size = 1 << depth;
	oct.max_depth = depth;
	oct.residual_tol = residual_tol;
	oct.error_driven = error_driven;
	oct.world_origin = lattice_world_origin;
	// Emit-box filter: when emit_min != emit_max (caller set them), restrict output to
	// triangles owned by cells inside [emit_min, emit_max). Same mechanism as mesh_subregion.
	if (emit_min != emit_max) {
		oct.emit_filter = true;
		oct.emit_min = emit_min;
		oct.emit_max = emit_max;
	}
	// Build-box restriction: a splice builds on the FULL frame (root_origin/_ROOT_DEPTH) but descends
	// only cells overlapping [build_min, build_max) (the edit box + apron), so its cells land on the
	// full build's lattice and neighbours — no offset sub-octree, no seam divergence.
	if (build_min != build_max) {
		oct.build_box = true;
		oct.build_min = build_min;
		oct.build_max = build_max;
	}
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

	_last_tri_owners      = oct.tri_owners;
	_last_tri_owner_sizes = oct.tri_owner_sizes;
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

Array DCOctreeMesher::mesh_subregion(
		const PackedFloat32Array &data,
		int dim,
		Vector3 data_origin,
		double cell,
		Vector3i sub_origin,
		int sub_size,
		Vector3i core_min,
		Vector3i core_max,
		const PackedByteArray &indices,
		const PackedColorArray &palette) {
	Array out;
	_last_tri_owners      = PackedVector3Array();
	_last_tri_owner_sizes = PackedFloat32Array();
	if (dim < 2 || sub_size < 1 || data.size() != int64_t(dim) * dim * dim) {
		ERR_PRINT("DCOctreeMesher::mesh_subregion: bad arguments");
		return out;
	}
	const bool with_indices = indices.size() == data.size() && palette.size() > 0;

	// One uniform level at the data resolution; no error-driven collapse, so the cube is
	// meshed at 1m throughout — identical per-cell vertices to the full build's fine core.
	Octree oct;
	oct.emit_color = with_indices;
	oct.palette = palette;
	oct.root_size = sub_size;
	oct.max_depth = 0;
	for (int s = sub_size; s > 1; s >>= 1) {
		oct.max_depth++;
	}
	oct.error_driven = false;
	oct.world_origin = sub_origin;          // cells.origin is local to sub_origin -> owners are world
	oct.emit_filter = true;
	oct.emit_min = core_min;
	oct.emit_max = core_max;
	oct.clip.center = Vector3();
	oct.clip.half0 = double(sub_size) * 4.0; // one level, so level_index is always 0 anyway
	oct.clip.levels.resize(1);
	Level lv;
	lv.data = data.ptr();
	lv.origin = data_origin;
	lv.cell = cell;
	lv.dim = dim;
	if (with_indices) {
		lv.idx = indices.ptr();
	}
	oct.clip.levels[0] = lv;

	oct.run();

	_last_tri_owners      = oct.tri_owners;
	_last_tri_owner_sizes = oct.tri_owner_sizes;
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
					"residual_tol", "error_driven", "lattice_world_origin", "level_indices", "palette",
					"uniform_core", "prune_safety", "emit_min", "emit_max", "build_min", "build_max"),
			&DCOctreeMesher::mesh_clipmap,
			DEFVAL(0.0), DEFVAL(false), DEFVAL(Vector3i()),
			DEFVAL(TypedArray<PackedByteArray>()), DEFVAL(PackedColorArray()), DEFVAL(false), DEFVAL(0.0),
			DEFVAL(Vector3i()), DEFVAL(Vector3i()), DEFVAL(Vector3i()), DEFVAL(Vector3i()));
	ClassDB::bind_method(
			D_METHOD("mesh_subregion", "data", "dim", "data_origin", "cell", "sub_origin", "sub_size",
					"core_min", "core_max", "indices", "palette"),
			&DCOctreeMesher::mesh_subregion,
			DEFVAL(PackedByteArray()), DEFVAL(PackedColorArray()));
	ClassDB::bind_method(D_METHOD("get_last_triangle_owners"),      &DCOctreeMesher::get_last_triangle_owners);
	ClassDB::bind_method(D_METHOD("get_last_triangle_owner_sizes"), &DCOctreeMesher::get_last_triangle_owner_sizes);
}
