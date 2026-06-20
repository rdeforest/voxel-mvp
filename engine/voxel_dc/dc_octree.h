#ifndef DC_OCTREE_H
#define DC_OCTREE_H

// The core DC algorithm: build an adaptive octree over an SdfSource, accumulate fine QEFs up the
// tree, collapse by screen-error, and mesh crack-free by octree point-location. `Octree` is one big
// struct on purpose — it is the irreducible unit of the algorithm (cf. the "one class per file"
// case). The incremental grow/reconcile/edit paths (doc 16/17/20) live here too.

#include "dc_mesh_common.h"  // to_v3, QUERY_EPS, g_mesh_threads, parallel_for
#include "dc_qef.h"          // voxel_dc::Qef
#include "dc_sdf_source.h"   // SdfSource
#include "octree_geometry.h" // voxel_dc::CB / EDGES / RING

#include "core/os/os.h"
#include "core/templates/local_vector.h"
#include "core/variant/variant.h" // PackedVector3Array / PackedColorArray / PackedInt32Array / Color

#include <algorithm>
#include <cstring>

namespace voxel_dc {
namespace dc_mesh {

struct Cell {
	Vector3i origin;
	int size = 0;
	int children[8];
	int vertex = -1;
	bool leaf = true;
	bool absent = false; // window_mode: a leaf OUTSIDE the resident window — no QEF, no vertex, not
	                     // meshed. The window boundary is the resident mesh's open rim (like the clipmap's
	                     // outer edge). Distinct from a splice's build-box-miss leaf, which IS meshed.
	Qef qef; // accumulated up the tree (own crossings for a leaf; children's sum otherwise)

	// Incremental-grow caches (doc 17 #3). Both the collapse residual and the emitted vertex are pure
	// functions of `qef` (and the fixed cell box), so a grow that doesn't change this cell's qef can reuse
	// last frame's solve instead of redoing the SVD — turning the per-grow solve cost from O(window) into
	// O(changed band). `dirty` is the per-frame signal reconcile sets where it changes a cell and
	// reaccumulate propagates to ancestors; it clears the *_valid bits, which otherwise persist across grows.
	// A fresh cell is born with both invalid (solve once), so the full-build path is unaffected.
	double  we_cache  = 0.0;        // sqrt(qef.residual(solved vertex)) — the collapse screen-error numerator
	Vector3 vpos_cache;             // solved vertex position (lattice-local)
	double  verr_cache = 0.0;       // sqrt(qef.residual(vpos)) — this leaf's geometric error (dcinval diagnostic)
	Vector3 vnorm_cache;            // solved vertex normal
	Color   vcol_cache;             // solved vertex material colour (only when emit_color)
	bool we_valid  = false;         // we_cache holds this cell's current qef's residual
	bool vtx_valid = false;         // vpos/vnorm/vcol_cache hold this cell's current qef's solve
	bool dirty     = false;         // qef changed THIS reconcile → invalidate caches up to the root
};

// Builds + meshes one octree over a clipmap: subdivide to the clipmap's
// per-position target size (the data-resolution floor), then — when error_driven —
// COLLAPSE bottom-up wherever one vertex represents the surface within eps_px on
// screen, so flat regions coarsen and curved ones stay fine. One QEF vertex per
// surviving leaf, then minimal-edge meshing with point-location (the smallest cell
// owns each edge; a coarser neighbour returned twice collapses the quad to a
// triangle -> seamless across the size jumps the collapse introduces).
struct Octree {
	const SdfSource *src = nullptr;  // field source (Clipmap or EditStoreSource); set by the caller, must outlive run()
	int root_size = 0;
	int max_depth = 0;
	Vector3 camera;          // viewpoint in root-local lattice space (screen-error LOD)
	double proj = 0.0;       // viewport_height / (2*tan(fov/2)) — px per world unit at unit distance
	double eps_px = 0.0;     // screen-space error threshold (px): collapse when we*proj/dist <= eps_px
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
	bool window_mode = false;      // mesh_world only: a build-box-miss leaf is ABSENT (not sampled, not
	                               // meshed) — the box is the resident WINDOW, its edge the mesh rim. A
	                               // splice leaves window_mode off: its out-of-box cells ARE meshed so the
	                               // patch rim can stitch to them (the full build supplies their triangles).
	bool field_dirty = false;      // edit_world (doc 20 E): the FIELD changed inside [field_dirty_min, max)
	Vector3i field_dirty_min;      // (WORLD lattice) — reconcile_edit force-resamples present leaves here
	Vector3i field_dirty_max;      // (the field changed, not just the floor) and refines/coarsens on surface
	                               // appearing/vanishing; cells outside the box are untouched (no resample).
	LocalVector<int> level_start;  // parallel bottom-up: cell-index where each BFS level begins (for level walks)
	int build_samples = 0;         // leaves whose Hermite data was sampled this build (accumulate_qef) —
	                               // the field-derived build cost. A grow re-samples only the new band, so
	                               // this proves the retained interior was NOT resampled (the B1 win).
	int  refine_budget = -1;       // C/P (doc 20): wall-clock µs cap for refine_selected; -1 = unbudgeted (a move).
	bool refine_pending = false;   // a budgeted reconcile deferred some refinement → caller drains over frames.
	struct RefineCand { double err; int idx; }; // P: a floor-refine candidate keyed by its error `we` (camera-indep)
	LocalVector<RefineCand> refine_cands;        // c1 (doc 20): PERSISTENT frontier heap — drained across grows, rebuilt on change
	int  refine_heap_end = 0;                    // live heap size in refine_cands[0, refine_heap_end); pops shrink it
	uint64_t last_build_us    = 0; // phase timing: build() + accumulate_qef() (microseconds)
	uint64_t last_collapse_us = 0; // phase timing: recollapse_and_mesh() (microseconds)
	uint64_t last_construct_us = 0; // sub-phase: build() tree construction (serial)
	uint64_t last_sample_us    = 0; // sub-phase: sample_leaves_parallel() (parallel)
	uint64_t last_accum_us     = 0; // sub-phase: accumulate_sums() (serial)
	uint64_t last_collapse_pass_us = 0; // sub-phase: collapse_pass() serial tree walk (within emit bucket)
	LocalVector<Cell> cells;
	LocalVector<int> free_list;    // (B1b) indices of cells killed by eviction, reused by the next grow so
	                               // `cells` stays bounded across a long traverse instead of leaking.
	PackedVector3Array verts;
	PackedVector3Array normals;
	PackedColorArray colors;       // per-vertex material colour (rgb); a=0 material, a=1 natural
	PackedInt32Array indices;
	PackedVector3Array tri_owners;      // WORLD owner-cell origin per emitted triangle
	PackedFloat32Array tri_owner_sizes; // parallel: owner cell SIZE (lattice units)
	PackedFloat32Array tri_owner_errors; // parallel: owner leaf's geometric error `we` (lattice units, dcinval)

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

	// Does a cell overlap the edited field box (WORLD lattice)? reconcile_edit walks only these cells.
	bool cell_overlaps_field_dirty(const Vector3i &origin, int size) const {
		Vector3i o = origin + world_origin;
		return o.x + size > field_dirty_min.x && o.x < field_dirty_max.x && o.y + size > field_dirty_min.y && o.y < field_dirty_max.y && o.z + size > field_dirty_min.z && o.z < field_dirty_max.z;
	}

	// Should this cell stop subdividing and become a leaf? True at the data floor, when
	// the cell is provably surface-free (prune), or when size is already atomic. This is
	// the shared predicate build() and reconcile() both check — one definition, no drift.
	bool want_leaf(int size, const Vector3i &origin) const {
		Vector3 center = to_v3(origin) + Vector3(1, 1, 1) * (size * 0.5);
		return size <= 1
			|| double(size) <= src->target_cell_size(center)
			|| (prune_safety > 0.0 && src->surface_free(
					to_v3(origin), to_v3(origin) + Vector3(1, 1, 1) * double(size)));
	}

	// Assign this leaf's Hermite data from its own edges and charge the build counter.
	// Call sites that are transitioning an absent leaf to present must set absent=false
	// themselves (the extra step stays inline so this helper stays narrowly scoped).
	void sample_leaf(int idx) {
		cells[idx].qef = leaf_qef(idx);
		cells[idx].dirty = true; // qef changed → ancestors re-sum, this leaf's solve caches invalidate (grow path)
		++build_samples;
	}

	// Free all 8 children of idx (recursively) and reset their slots for reuse.
	// No-op when idx is already a structural leaf (children[0] < 0).
	void discard_children(int idx) {
		if (cells[idx].children[0] < 0) {
			return;
		}
		for (int i = 0; i < 8; ++i) {
			kill_subtree(cells[idx].children[i]);
			cells[idx].children[i] = -1;
		}
	}

	// A leaf's QEF, built from the 12 cube edges that cross the isosurface (the cell's
	// own Hermite data at its own size).
	Qef leaf_qef(int idx) const {
		return leaf_qef_at(cells[idx].origin, cells[idx].size);
	}

	Qef leaf_qef_at(const Vector3i &o, int s) const {
		Qef qef;
		for (int e = 0; e < 12; ++e) {
			const int *pa = CB[EDGES[e][0]];
			const int *pb = CB[EDGES[e][1]];
			Vector3i ca = o + Vector3i(pa[0], pa[1], pa[2]) * s;
			Vector3i cb = o + Vector3i(pb[0], pb[1], pb[2]) * s;
			double fa = src->value(to_v3(ca));
			double fb = src->value(to_v3(cb));
			if ((fa < 0.0) == (fb < 0.0) || fa == fb) {
				continue;
			}
			double t = fa / (fa - fb);
			Vector3 p = to_v3(ca).lerp(to_v3(cb), t);
			qef.add_plane(p, src->gradient(p));
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
	// FIELD-derived pass (expensive, run ONCE per build): give every node its accumulated QEF — a
	// structural leaf's own crossings (leaf_qef samples the field), an internal node = the sum of its
	// children's, so the node carries ALL the fine Hermite data within it (no coarse-corner
	// undersampling). NO collapse here; that is camera-derived and re-runnable (collapse_pass). Uses
	// the STRUCTURAL leaf (no children), not the leaf flag, so it is correct even after a prior
	// collapse_pass dirtied the flags (Stage 2: the retained octree re-collapses without re-sampling).
	void accumulate_qef(int idx) {
		if (cells[idx].children[0] < 0) {
			// An absent leaf (outside the window) contributes an empty QEF (count 0) — a bit-exact no-op
			// in its ancestors' sums, so a windowed/incremental build's QEFs equal a full build's.
			if (cells[idx].absent) {
				cells[idx].qef = Qef();
			} else {
				sample_leaf(idx);
			}
			return;
		}
		Qef sum;
		for (int i = 0; i < 8; ++i) {
			int ch = cells[idx].children[i];
			accumulate_qef(ch);
			sum.add(cells[ch].qef);
		}
		cells[idx].qef = sum;
	}

	// Parallel split of accumulate_qef's leaf sampling — the build's dominant cost. build() leaves the
	// tree structure with every leaf's QEF unset; sampling each present leaf (leaf_qef → 12 field reads)
	// is independent (const reads, writes only its own cell.qef), so it parallelises across g_mesh_threads.
	// Absent leaves get an empty QEF (a bit-exact no-op in ancestor sums). Pair with accumulate_sums(),
	// which then rolls the leaves up internal nodes with NO field work — together bit-identical to
	// accumulate_qef(0), so the result is unchanged whatever the thread count.
	void sample_leaves_parallel() {
		LocalVector<int> leaves;
		for (uint32_t i = 0; i < cells.size(); ++i) {
			if (cells[i].children[0] < 0) { // structural leaf
				if (cells[i].absent) {
					cells[i].qef = Qef();
				} else {
					leaves.push_back(int(i));
				}
			}
		}
		build_samples = int(leaves.size());
		const int n = int(leaves.size());
		const int nthreads = (g_mesh_threads > 1 && n >= 64) ? MIN(g_mesh_threads, n) : 1;
		parallel_for(n, nthreads, [this, &leaves](int k) {
			cells[leaves[k]].qef = leaf_qef(leaves[k]);
		});
	}

	// Roll the (already-sampled) leaf QEFs up the tree — same post-order sum as accumulate_qef but with
	// NO leaf sampling (the leaves are filled by sample_leaves_parallel first). Same summands and order,
	// so cells[0].qef is bit-identical to accumulate_qef(0).
	void accumulate_sums(int idx) {
		if (cells[idx].children[0] < 0) {
			return; // leaf — qef already set by sample_leaves_parallel
		}
		Qef sum;
		for (int i = 0; i < 8; ++i) {
			int ch = cells[idx].children[i];
			accumulate_sums(ch);
			sum.add(cells[ch].qef);
		}
		cells[idx].qef = sum;
	}

	// Reset every node's leaf flag to its STRUCTURAL state (leaf iff it has no children) and clear the
	// placed vertex, so collapse_pass + meshing can re-run from scratch on a camera re-walk.
	void reset_leaves() {
		for (uint32_t i = 0; i < cells.size(); ++i) {
			cells[i].leaf = cells[i].children[0] < 0;
			cells[i].vertex = -1;
		}
	}

	// CAMERA-derived pass (cheap, re-runnable, NO field sampling): collapse a node into one leaf when a
	// single vertex represents its accumulated QEF within eps_px on screen. Bottom-up; a parent collapse
	// orphans its subtree, so the coarsest collapsing ancestor wins.
	//
	// Collapse error = the L2 residual of the accumulated QEF at the merged vertex, NOT divided by plane
	// count: the undivided residual is ~0 on flat/cliff/gently-curved regions (flat planes contribute
	// exactly 0) and spikes where one vertex can't represent a feature, so a thin feature vetoes its own
	// collapse. Screen-space-error LOD projects that world residual to pixels (we * proj / dist): keep
	// refined while it exceeds eps_px (~2px), collapse otherwise — a feature coarsens as it recedes and a
	// narrow FOV (telescope) raises proj to refine distant terrain.
	void collapse_pass(int idx) {
		if (cells[idx].children[0] < 0) {
			return; // structural leaf — nothing to collapse
		}
		for (int i = 0; i < 8; ++i) {
			collapse_pass(cells[idx].children[i]);
		}
		collapse_test(idx); // post-order: decide this node after its subtree (same as collapse_parallel)
	}

	// Tree depth of a cell of the given lattice size (root_size → 0; size 1 → max_depth). Used by the
	// incremental grow to resume build() at the right depth when expanding an existing leaf into a subtree.
	int cell_depth(int size) const {
		int d = 0;
		for (int s = root_size; s > size; s >>= 1) {
			++d;
		}
		return d;
	}

	// Allocate a cell slot — reusing one freed by eviction (B1b) before growing `cells`, so a long
	// traverse churns slots in place instead of leaking. The returned slot is reset by build().
	int alloc_cell() {
		if (!free_list.is_empty()) {
			int i = free_list[free_list.size() - 1];
			free_list.resize(free_list.size() - 1);
			return i;
		}
		int i = int(cells.size());
		cells.push_back(Cell());
		return i;
	}

	int build(const Vector3i &origin, int size, int depth) {
		int idx = alloc_cell();
		{
			Cell &c = cells[idx]; // reset fully — a reused slot may carry stale state
			c.origin = origin;
			c.size = size;
			c.leaf = true;
			c.absent = false;
			c.vertex = -1;
			c.qef = Qef();
			c.we_valid = false; // born invalid — a reused slot's cached solve belongs to a dead cell
			c.vtx_valid = false;
			c.dirty = false;
			for (int i = 0; i < 8; ++i) {
				c.children[i] = -1;
			}
		}
		if (depth >= max_depth || size <= 1) {
			return idx;
		}
		if (build_box && !cell_overlaps_build_box(origin, size)) {
			if (window_mode) {
				cells[idx].absent = true; // outside the resident window — placeholder leaf, never meshed
			}
			return idx; // outside the box — leaf, don't descend (no data sampled)
		}
		// Surface-sparse prune + data-floor check — the same predicate reconcile() evaluates
		// per retained cell; want_leaf() is the single definition for both paths.
		if (want_leaf(size, origin)) {
			return idx;
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

	// Reset a cell slot to a fresh present leaf at (origin, size).
	void init_cell(int idx, const Vector3i &origin, int size) {
		Cell &c = cells[idx];
		c.origin = origin;
		c.size = size;
		c.leaf = true;
		c.absent = false;
		c.vertex = -1;
		c.qef = Qef();
		c.we_valid = false; // born invalid — a reused slot's cached solve belongs to a dead cell
		c.vtx_valid = false;
		c.dirty = false;
		for (int i = 0; i < 8; ++i) {
			c.children[i] = -1;
		}
	}

	// PARALLEL bottom-up construct: the SAME tree the recursive build() makes (want_leaf decides leaf-or-
	// descend, NO field sampling), but level-synchronous — each level's frontier is decided and its
	// children batch-allocated in parallel. Records level_start[] (cell range per BFS level) so accumulate
	// and collapse can walk by level too. Cell layout is frontier-ordered (a different order than build()'s
	// DFS) but the SAME SET of cells → identical surface, only vertex NUMBERING differs.
	void build_bottomup_parallel() {
		level_start.clear();
		int root = alloc_cell();
		init_cell(root, Vector3i(0, 0, 0), root_size);
		level_start.push_back(0);
		LocalVector<int> frontier;
		frontier.push_back(root);
		int depth = 0;
		while (!frontier.is_empty()) {
			const int fn = int(frontier.size());
			const int dthreads = (g_mesh_threads > 1 && fn >= 256) ? MIN(g_mesh_threads, fn) : 1;
			LocalVector<uint8_t> descend;
			descend.resize(fn);
			const int dep = depth;
			parallel_for(fn, dthreads, [this, &frontier, &descend, dep](int k) {
				const int idx = frontier[k];
				const Vector3i o = cells[idx].origin;
				const int s = cells[idx].size;
				if (build_box && !cell_overlaps_build_box(o, s)) {
					if (window_mode) {
						cells[idx].absent = true;
					}
					descend[k] = 0;
				} else {
					descend[k] = (dep >= max_depth || want_leaf(s, o)) ? 0 : 1;
				}
			});
			LocalVector<int> descenders;
			for (int k = 0; k < fn; ++k) {
				if (descend[k]) {
					cells[frontier[k]].leaf = false;
					descenders.push_back(frontier[k]);
				}
			}
			const int d_count = int(descenders.size());
			if (d_count == 0) {
				break;
			}
			const int base = int(cells.size());
			cells.resize_uninitialized(base + int64_t(d_count) * 8); // init_cell fills every new slot in parallel below
			level_start.push_back(base);
			const int athreads = (g_mesh_threads > 1 && d_count >= 32) ? MIN(g_mesh_threads, d_count) : 1;
			parallel_for(d_count, athreads, [this, &descenders, base](int j) {
				const int fi = descenders[j];
				const int half = cells[fi].size >> 1;
				const Vector3i o = cells[fi].origin;
				for (int c = 0; c < 8; ++c) {
					const int child = base + j * 8 + c;
					init_cell(child, o + Vector3i(CB[c][0], CB[c][1], CB[c][2]) * half, half);
					cells[fi].children[c] = child;
				}
			});
			LocalVector<int> next;
			next.resize(int64_t(d_count) * 8);
			for (int j = 0; j < d_count; ++j) {
				for (int c = 0; c < 8; ++c) {
					next[j * 8 + c] = base + j * 8 + c;
				}
			}
			frontier = next;
			++depth;
		}
	}

	// Roll leaf QEFs up the tree IN PARALLEL: deepest level first, each internal node sums its 8 children
	// (children sit in a deeper, already-finished level → no read/write race; distinct parents own distinct
	// children → no write race). Same per-node summand order (0..7) as accumulate_sums → bit-identical.
	void accumulate_parallel() {
		const int L = int(level_start.size());
		for (int lvl = L - 1; lvl >= 0; --lvl) {
			const int lo = level_start[lvl];
			const int hi = (lvl + 1 < L) ? level_start[lvl + 1] : int(cells.size());
			const int n = hi - lo;
			const int threads = (g_mesh_threads > 1 && n >= 256) ? MIN(g_mesh_threads, n) : 1;
			parallel_for(n, threads, [this, lo](int t) {
				const int idx = lo + t;
				if (cells[idx].children[0] < 0) {
					return; // leaf — qef set by sample_leaves_parallel (or empty if absent)
				}
				Qef sum;
				for (int i = 0; i < 8; ++i) {
					sum.add(cells[cells[idx].children[i]].qef);
				}
				cells[idx].qef = sum;
			});
		}
	}

	// One node's collapse decision — the body of collapse_pass without the recursion. Reads only its own
	// accumulated qef, writes only its own leaf flag + orphans its own (disjoint) subtree.
	void collapse_test(int idx) {
		if (cells[idx].children[0] < 0 || !error_driven || cells[idx].qef.count == 0 || cells[idx].size > max_leaf_size) {
			return;
		}
		const Vector3 cmin = to_v3(cells[idx].origin);
		const Vector3 cmax = cmin + Vector3(1, 1, 1) * double(cells[idx].size);
		const Vector3 ctr = cmin + Vector3(1, 1, 1) * (cells[idx].size * 0.5);
		// Never collapse the finest level when uniform_core: a 1m fine core gives edit patches clean
		// cell boundaries to splice against (incremental meshing). Outer levels still coarsen.
		if (uniform_core && src->is_finest_level(ctr)) {
			return;
		}
		// The residual `we` is a pure function of this cell's qef, so a grow reuses last frame's value
		// unless reaccumulate invalidated it (qef changed) — the screen-error test below still re-runs
		// every frame (camera/eps move), but the costly SVD solve is skipped for unchanged cells.
		double we;
		if (cells[idx].we_valid) {
			we = cells[idx].we_cache;
		} else {
			const Vector3 v = cells[idx].qef.solve(cmin, cmax);
			we = Math::sqrt(cells[idx].qef.residual(v));
			cells[idx].we_cache = we;
			cells[idx].we_valid = true;
		}
		const double dist = MAX((ctr - camera).length(), 1e-3);
		if (we * proj / dist > eps_px) {
			return;
		}
		cells[idx].leaf = true;
		orphan_subtree(idx);
	}

	// Screen-error collapse IN PARALLEL: shallowest-meaningful order is irrelevant — each node's decision
	// reads only its own accumulated qef, so process deepest→shallowest level-by-level (matching the serial
	// post-order: a node is tested after its subtree). Same per-node test as collapse_pass → bit-identical
	// leaf flags; same crack-free point-location meshing over the result.
	void collapse_parallel() {
		const int L = int(level_start.size());
		for (int lvl = L - 1; lvl >= 0; --lvl) {
			const int lo = level_start[lvl];
			const int hi = (lvl + 1 < L) ? level_start[lvl + 1] : int(cells.size());
			const int n = hi - lo;
			const int threads = (g_mesh_threads > 1 && n >= 256) ? MIN(g_mesh_threads, n) : 1;
			parallel_for(n, threads, [this, lo](int t) {
				collapse_test(lo + t);
			});
		}
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
	// surface, not a coarse re-sample. The slot (cells[idx].vertex) is pre-assigned in
	// cell-index order by recollapse_and_mesh, so this writes disjoint slots and parallelises.
	void place_vertex(int idx) {
		// The solve + material sample are a pure function of this cell's qef, so a grow reuses last frame's
		// result for a leaf reaccumulate didn't invalidate — only the (cheap) slot write runs every frame.
		// emit_color is fixed for a retained tree's lifetime (grow_world inherits it), so the cached colour
		// is always sampled under the same flag it's read back with.
		if (!cells[idx].vtx_valid) {
			const Qef &qef = cells[idx].qef;
			Vector3 cmin = to_v3(cells[idx].origin);
			Vector3 cmax = cmin + Vector3(1, 1, 1) * double(cells[idx].size);
			Vector3 v = qef.solve(cmin, cmax);
			Vector3 n = qef.nsum.length_squared() > 0.0 ? qef.nsum.normalized() : Vector3(0, 1, 0);
			cells[idx].vpos_cache = v;
			cells[idx].verr_cache = Math::sqrt(qef.residual(v)); // same `we` collapse_test uses — dcinval reads it per emitted leaf
			cells[idx].vnorm_cache = n;
			if (emit_color) {
				// Sample the solid voxel just behind the surface: the normal points
				// outward, so step inward to land in the cell that carries the id. Prefer an
				// inward explicit material so a placed part's faces read the part, while a terrain
				// vertex beside the part stays natural (the body it bounds is inward, not sideways).
				int id = src->index_prefer_explicit(v - n * 0.5, n);
				if (id > 0 && id < int(palette.size())) {
					const Color &c = palette[id];
					cells[idx].vcol_cache = Color(c.r, c.g, c.b, 0.0); // a=0 -> explicit material colour
				} else {
					cells[idx].vcol_cache = Color(0, 0, 0, 1.0); // a=1 -> natural (slope-shaded; also the
																 // default for meshes with no colour array)
				}
			}
			cells[idx].vtx_valid = true;
		}
		int slot = cells[idx].vertex;
		verts.set(slot, cells[idx].vpos_cache);
		normals.set(slot, cells[idx].vnorm_cache);
		if (emit_color) {
			colors.set(slot, cells[idx].vcol_cache);
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

	// Per-leaf triangle output for the parallel emit pass: each surviving leaf fills its own sink
	// (reads of cells/verts are immutable during emit), then recollapse_and_mesh concatenates the
	// sinks in cell-index order — identical to the old serial single-array emit.
	struct EmitSink {
		LocalVector<int32_t> indices;
		LocalVector<Vector3> owners;
		LocalVector<float> owner_sizes;
		LocalVector<float> owner_errs;   // parallel: owner leaf's geometric error (dcinval)
	};

	// Emit one triangle wound so its front face points `outward` (Godot is CW-from-front,
	// so reverse when the right-hand normal already points outward). `owner` (world lattice)
	// is the cell that owns this edge — tagged per triangle for the incremental splice.
	// `owner_size` is the owner cell's size in lattice units, for the B1 alignment fix.
	void emit_tri(EmitSink &sink, int i0, int i1, int i2, const Vector3 &outward, const Vector3 &owner, float owner_size, float owner_err) {
		Vector3 n = (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0]);
		if (n.dot(outward) >= 0.0) {
			sink.indices.push_back(i0); sink.indices.push_back(i2); sink.indices.push_back(i1);
		} else {
			sink.indices.push_back(i0); sink.indices.push_back(i1); sink.indices.push_back(i2);
		}
		sink.owners.push_back(owner);
		sink.owner_sizes.push_back(owner_size);
		sink.owner_errs.push_back(owner_err);
	}

	// Decide winding PER TRIANGLE, not once for the whole quad: a quad spanning a LOD
	// size jump is non-planar, so a single flip decision leaves one of its two triangles
	// back-facing — a culled, see-through gap. Orienting each triangle to `outward`
	// independently keeps the surface consistently wound across the seam.
	void emit_poly(EmitSink &sink, const int ring[], int rc, const Vector3 &outward, const Vector3 &owner, float owner_size, float owner_err) {
		emit_tri(sink, ring[0], ring[1], ring[2], outward, owner, owner_size, owner_err);
		if (rc == 4) {
			emit_tri(sink, ring[0], ring[2], ring[3], outward, owner, owner_size, owner_err);
		}
	}

	void try_edge(EmitSink &sink, int leaf_idx, int axis, int u, int w, int su, int sw) {
		Vector3i lo = cells[leaf_idx].origin;
		int s = cells[leaf_idx].size;
		lo[u] += su * s;
		lo[w] += sw * s;
		Vector3i hi = lo;
		hi[axis] += s;
		double fa = src->value(to_v3(lo));
		double fb = src->value(to_v3(hi));
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
		Vector3 outward = src->gradient(to_v3(lo).lerp(to_v3(hi), t));
		double axis_face = (fb > fa) ? 1.0 : -1.0;
		if (outward[axis] * axis_face < 0.0) {
			outward = Vector3();
			outward[axis] = axis_face;
		}
		emit_poly(sink, ring, rc, outward, to_v3(cell_world_origin(leaf_idx)), float(cells[leaf_idx].size), float(cells[leaf_idx].verr_cache));
	}

	void emit_leaf_edges(EmitSink &sink, int leaf_idx) {
		for (int axis = 0; axis < 3; ++axis) {
			int u = (axis + 1) % 3;
			int w = (axis + 2) % 3;
			for (int su = 0; su < 2; ++su) {
				for (int sw = 0; sw < 2; ++sw) {
					try_edge(sink, leaf_idx, axis, u, w, su, sw);
				}
			}
		}
	}

	void run() {
		build_samples = 0;
		// Keep a flat world at >=2 cells/axis so it meshes (a fully-collapsed flat region is one empty
		// cell — no quad). half the root => the 8 root children may collapse, nothing coarser.
		max_leaf_size = MAX(1, root_size >> 1);
		uint64_t t0 = OS::get_singleton()->get_ticks_usec();
		// Build the tree, sample its leaf QEFs, and roll them up — all level-synchronous parallel (the
		// construct + accumulate; the sample is already parallel). build_bottomup_parallel records
		// level_start[] so recollapse_and_mesh's collapse can walk by level in parallel too.
		build_bottomup_parallel();
		uint64_t tA = OS::get_singleton()->get_ticks_usec();
		sample_leaves_parallel();
		uint64_t tB = OS::get_singleton()->get_ticks_usec();
		accumulate_parallel();
		uint64_t tC = OS::get_singleton()->get_ticks_usec();
		last_construct_us = tA - t0;
		last_sample_us    = tB - tA;
		last_accum_us     = tC - tB;
		last_build_us = tC - t0;
		uint64_t t1 = OS::get_singleton()->get_ticks_usec();
		recollapse_and_mesh();
		last_collapse_us = OS::get_singleton()->get_ticks_usec() - t1;
	}

	// Re-decide collapse against the current camera/proj/eps over the already-built tree + QEFs, then
	// re-mesh. No build (no re-sampling of leaf QEFs) — this is the Stage 2 movement re-walk (and the
	// tail of a fresh build). It DOES sample the field, though: place_vertex reads the material behind
	// each vertex, and try_edge reads value/gradient to stitch and wind — so both passes parallelise.
	// Clears prior output so it is idempotent.
	void recollapse_and_mesh() {
		verts.clear();
		normals.clear();
		colors.clear();
		indices.clear();
		tri_owners.clear();
		tri_owner_sizes.clear();
		tri_owner_errors.clear();
		reset_leaves();
		uint64_t tc0 = OS::get_singleton()->get_ticks_usec();
		// level_start is set only by the parallel bottom-up full build; the grow/reconcile path leaves it
		// empty (its tree isn't level-laid-out), so that falls back to the serial recursive collapse.
		if (!level_start.is_empty()) {
			collapse_parallel();
		} else {
			collapse_pass(0);
		}
		last_collapse_pass_us = OS::get_singleton()->get_ticks_usec() - tc0;
		int n = int(cells.size());

		// Pass 1: one vertex per surviving surface leaf. Assign slots SERIALLY in cell-index order (so the
		// vertex numbering, and the indices that reference it, match the old serial emit), then fill the
		// QEF solve + material sample in PARALLEL into the disjoint pre-assigned slots.
		LocalVector<int> vcells;
		for (int i = 0; i < n; ++i) {
			if (cells[i].leaf && cells[i].qef.count > 0) {
				cells[i].vertex = int(vcells.size());
				vcells.push_back(i);
			}
		}
		int vcount = int(vcells.size());
		verts.resize(vcount);
		normals.resize(vcount);
		if (emit_color) {
			colors.resize(vcount);
		}
		const int vthreads = (g_mesh_threads > 1 && vcount >= 64) ? MIN(g_mesh_threads, vcount) : 1;
		parallel_for(vcount, vthreads, [this, &vcells](int k) {
			place_vertex(vcells[k]);
		});

		// Pass 2: stitch edges. Each surviving leaf emits into its OWN sink in parallel (reads of cells/
		// verts are immutable now), then the sinks concatenate in cell-index order — byte-identical to
		// the old serial single-array emit (same leaf order, same per-leaf edge order).
		LocalVector<int> ecells;
		for (int i = 0; i < n; ++i) {
			if (cells[i].leaf && cells[i].vertex >= 0) {
				ecells.push_back(i);
			}
		}
		int ecount = int(ecells.size());
		LocalVector<EmitSink> sinks;
		sinks.resize(ecount);
		const int ethreads = (g_mesh_threads > 1 && ecount >= 64) ? MIN(g_mesh_threads, ecount) : 1;
		parallel_for(ecount, ethreads, [this, &ecells, &sinks](int e) {
			emit_leaf_edges(sinks[e], ecells[e]);
		});

		int64_t total_idx = 0, total_tri = 0;
		for (int e = 0; e < ecount; ++e) {
			total_idx += sinks[e].indices.size();
			total_tri += sinks[e].owners.size();
		}
		indices.resize(total_idx);
		tri_owners.resize(total_tri);
		tri_owner_sizes.resize(total_tri);
		tri_owner_errors.resize(total_tri);
		int32_t *ip = indices.ptrw();
		Vector3 *op = tri_owners.ptrw();
		float *sp = tri_owner_sizes.ptrw();
		float *ep = tri_owner_errors.ptrw();
		int64_t io = 0, to = 0;
		for (int e = 0; e < ecount; ++e) {
			const EmitSink &s = sinks[e];
			if (s.indices.size() > 0) {
				memcpy(ip + io, s.indices.ptr(), s.indices.size() * sizeof(int32_t));
				io += s.indices.size();
			}
			if (s.owners.size() > 0) {
				memcpy(op + to, s.owners.ptr(), s.owners.size() * sizeof(Vector3));
				memcpy(sp + to, s.owner_sizes.ptr(), s.owner_sizes.size() * sizeof(float));
				memcpy(ep + to, s.owner_errs.ptr(), s.owner_errs.size() * sizeof(float));
				to += s.owners.size();
			}
		}
	}

	// --- Incremental window growth (doc 16 Stage B) -------------------------------------------------
	// Expand an existing absent leaf into a full subtree at its place in the tree, building children with
	// the current window box (so in-window descendants reach the floor, out-of-window ones are absent) —
	// identical structure to what a from-scratch windowed build() would produce for this node.
	void grow_subtree(int idx) {
		Vector3i origin = cells[idx].origin;
		int size = cells[idx].size;
		int half = size >> 1;
		int d = cell_depth(size) + 1;
		cells[idx].leaf = false;
		cells[idx].absent = false;
		for (int i = 0; i < 8; ++i) {
			Vector3i co = origin + Vector3i(CB[i][0], CB[i][1], CB[i][2]) * half;
			int child = build(co, half, d); // build() may reallocate cells — re-index after each call
			cells[idx].children[i] = child;
		}
	}

	// Clear an orphaned subtree and return every slot to the free-list (B1b) for the next grow to reuse.
	// A freed slot is left inert — empty QEF (count 0) + detached + leaf — so even before reuse the
	// flat-array mesh loops skip it (a vertex is placed only for a leaf with qef.count > 0).
	void kill_subtree(int idx) {
		for (int i = 0; i < 8; ++i) {
			int ch = cells[idx].children[i];
			if (ch >= 0) {
				kill_subtree(ch);
			}
			cells[idx].children[i] = -1;
		}
		cells[idx].qef = Qef();
		cells[idx].vertex = -1;
		cells[idx].leaf = true;
		cells[idx].absent = true;
		free_list.push_back(idx);
	}

	// Make this cell into a present leaf at its own size: discard any subtree (coarsen) and sample its own
	// Hermite data. The from-scratch equivalent of a build() that stops here (floor or pruned).
	void make_leaf(int idx) {
		discard_children(idx);
		cells[idx].leaf = true;
		cells[idx].absent = false;
		sample_leaf(idx);
	}

	// Reconcile the retained tree to the CURRENT window + camera floor (build_min/max + target_cell_size),
	// touching only what changed: graft cells that entered the window, evict cells that left, REFINE cells
	// the camera approached (floor now finer), and COARSEN cells it receded from (floor now coarser). The
	// result is structurally identical to a from-scratch build at this camera/window — same leaf/internal/
	// absent decision per cell as build() — so the mesh equals a fresh build, but unchanged cells are reused
	// (not resampled): a move re-meshes only the changed band, not the whole vicinity (doc 17 P2.5 / 13 B3).
	void reconcile(int idx) {
		int sz = cells[idx].size;
		if (!cell_overlaps_build_box(cells[idx].origin, sz)) {
			// Left the window → absent leaf (the placeholder a fresh build leaves here). Already-absent
			// cells are a no-op; only a NEWLY evicted cell changed its qef (→ empty), so only it dirties.
			if (!cells[idx].absent) {
				discard_children(idx);
				cells[idx].leaf = true;
				cells[idx].absent = true;
				cells[idx].dirty = true;
			}
			return;
		}
		// In window. A refined subtree is RETAINED, never coarsened on recede (doc 20 M): the data is still
		// accurate, so we keep it and let collapse_pass draw the right LOD by screen-error every grow — a
		// receded structure re-sharpens instantly on return with no field re-sample. So "has children" is
		// tested before want_leaf: only eviction (outside the residency box, above) ever frees data. This
		// is why a grow that receded no longer equals a fresh build — the retained tree renders ≥ detail.
		if (cells[idx].children[0] >= 0) {
			for (int i = 0; i < 8; ++i) {
				reconcile(cells[idx].children[i]); // retained subtree — recurse for grafts/refines within
			}
		} else if (want_leaf(sz, cells[idx].origin)) {
			// build()'s own leaf test: at the data floor, or provably surface-free (pruned).
			if (cells[idx].absent) {
				cells[idx].absent = false; // entered the window at the floor
				sample_leaf(idx);
			}
			// else: a present leaf already at the floor — unchanged, reused (not resampled)
		} else if (refine_budget >= 0) {
			// C/P/I (doc 20): defer this refine — collect it onto the frontier keyed by its geometric error `we`
			// (the QEF residual of representing this coarse cell as one vertex — how much detail refining recovers).
			// `we` is camera-independent, so the persistent heap survives camera moves; refine_selected() does the
			// worst-error first, the rest stay coarse (QEF still valid) until a later grow reaches them.
			Vector3 cmin = to_v3(cells[idx].origin);
			Vector3 cmax = cmin + Vector3(1, 1, 1) * double(cells[idx].size);
			double we = Math::sqrt(cells[idx].qef.residual(cells[idx].qef.solve(cmin, cmax)));
			refine_cands.push_back(RefineCand{ we, idx });
		} else {
			grow_subtree(idx);   // unbudgeted (a move): subdivide to the (finer) floor — full window coverage
			accumulate_qef(idx);
		}
	}

	// P (doc 20): refine the candidates that look WORST on screen first (largest projected size), spending up
	// to `budget_us` microseconds of wall-clock — "do as much as you can in X ms" — then defer the rest
	// (refine_pending → the caller drains over frames). A wall-clock cap self-tunes where a fixed count can't:
	// the same budget refines fewer chunky cells and more flat ones, tracking real per-cell cost across
	// hardware and scene. Order-only vs an unbudgeted grow: a fully-drained view is identical to refining
	// every candidate, but the chunky/near cells sharpen first — the bloom resolves where the player looks.
	// The deferred candidates' QEFs are untouched, so they're valid as coarse leaves until a later grow.
	//
	// Selection is a PERSISTENT HEAP (c1, doc 20). The frontier `refine_cands` survives across grows: a grow
	// that only DRAINS (camera + eps unchanged) reuses it — pop_heap leaves [0, refine_heap_end) a valid heap,
	// so we just keep popping where we left off, with NO reconcile re-walk and NO re-heapify (O(changed), not
	// O(tree)). A grow that CHANGED the window/eps rebuilds it (reconcile re-collects → make_heap). The key is
	// `we` (geometric error, camera-independent — see doc 20 I), so the heap order survives camera moves.
	// reuse=false: heapify the freshly-collected candidates. reuse=true: continue draining the retained heap.
	void refine_selected(int budget_us, bool reuse) {
		auto worse = [](const RefineCand &a, const RefineCand &b) { return a.err < b.err; }; // max-heap on err
		RefineCand *base = refine_cands.ptr();
		if (!reuse) {
			refine_heap_end = int(refine_cands.size());
			if (refine_heap_end > 0) {
				std::make_heap(base, base + refine_heap_end, worse);
			}
		}
		if (refine_heap_end <= 0) {
			refine_pending = false;
			return;
		}
		uint64_t t0 = OS::get_singleton()->get_ticks_usec();
		while (refine_heap_end > 0) {
			std::pop_heap(base, base + refine_heap_end, worse);  // worst candidate → slot refine_heap_end-1
			--refine_heap_end;
			grow_subtree(base[refine_heap_end].idx);             // at least one per call → always makes progress
			accumulate_qef(base[refine_heap_end].idx);
			if (int64_t(OS::get_singleton()->get_ticks_usec() - t0) >= int64_t(budget_us)) {
				break;
			}
		}
		refine_pending = (refine_heap_end > 0);                  // candidates remain → drain them on a later grow
	}

	// Reconcile the retained tree to an EDITED field box (doc 20 E) — the window and camera floor are
	// UNCHANGED; only the field values inside [field_dirty_min, max) changed. Walks ONLY cells overlapping
	// that box (everything else is field- and floor-identical, so it's a no-op — don't even recurse). Inside
	// the box it differs from reconcile() in one case: a present leaf already at the floor must be RE-SAMPLED
	// (its field changed), where a move would reuse it. Surface appearing → refine to floor; vanishing →
	// coarsen. The accel is re-baked over the window before this so want_leaf's prune reflects the edit.
	// recollapse_and_mesh then re-decides the whole tree's collapse (cheap via 3a's caches), so the result
	// equals a fresh build of the edited field — the seam to unedited neighbours stitches crack-free by the
	// same point-location meshing as any LOD jump (no separate-patch boundary problem; we mutate in place).
	void reconcile_edit(int idx) {
		int sz = cells[idx].size;
		if (!cell_overlaps_field_dirty(cells[idx].origin, sz)) {
			return; // outside the edit → field + floor unchanged → reuse as-is
		}
		if (build_box && !cell_overlaps_build_box(cells[idx].origin, sz)) {
			return; // edit poked past the resident window → leave the rim absent (caller clamps; defensive)
		}
		if (want_leaf(sz, cells[idx].origin)) {
			if (cells[idx].children[0] >= 0) {
				make_leaf(idx);            // edit removed surface here → coarsen the subtree to one leaf
			} else {
				cells[idx].absent = false; // (within the window, so never an eviction)
				sample_leaf(idx);          // present/entered leaf in the edit box → re-sample the new field
			}
		} else if (cells[idx].children[0] >= 0) {
			for (int i = 0; i < 8; ++i) {
				reconcile_edit(cells[idx].children[i]);
			}
		} else {
			grow_subtree(idx);   // edit added surface → subdivide to the floor (samples only this band)
			accumulate_qef(idx);
		}
	}

	// Roll accumulated QEFs back up the tree from the (cached) leaf QEFs — NO field sampling. A retained
	// leaf keeps its cached QEF; an absent leaf contributes empty; an internal node = the in-order sum of
	// its children. Bit-identical to a full accumulate_qef() because the summands and order are identical.
	//
	// Returns whether this subtree's accumulated qef changed this grow (reconcile flagged the changed leaves
	// via `dirty`). A node re-sums only when a child changed — otherwise the in-order sum is bit-identical to
	// last frame's already-stored qef, so the assign is skipped. Where the qef DID change, the cached collapse
	// residual + vertex solve are invalidated so recollapse/emit redo just those; unchanged cells reuse them.
	bool reaccumulate(int idx) {
		bool changed;
		if (cells[idx].children[0] < 0) {
			if (cells[idx].absent) {
				cells[idx].qef = Qef();
			}
			changed = cells[idx].dirty; // leaf: a re-sampled or newly-evicted leaf (reconcile set dirty)
		} else {
			bool any = false;
			Qef sum;
			for (int i = 0; i < 8; ++i) {
				int ch = cells[idx].children[i];
				any |= reaccumulate(ch);
				sum.add(cells[ch].qef);
			}
			if (any) {
				cells[idx].qef = sum; // a child changed → this node's accumulated qef changed
			}
			changed = any || cells[idx].dirty;
		}
		if (changed) {
			cells[idx].we_valid = false;  // qef changed → cached collapse residual is stale
			cells[idx].vtx_valid = false; // qef changed → cached vertex solve is stale
		}
		cells[idx].dirty = false; // per-frame signal consumed
		return changed;
	}
};

} // namespace dc_mesh
} // namespace voxel_dc

#endif // DC_OCTREE_H
