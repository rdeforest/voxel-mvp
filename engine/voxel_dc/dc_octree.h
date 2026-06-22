#ifndef DC_OCTREE_H
#define DC_OCTREE_H

// The core DC algorithm: build an adaptive octree over an SdfSource, accumulate fine QEFs up the
// tree, collapse by screen-error, and mesh crack-free by octree point-location. `Octree` is one big
// struct on purpose — it is the irreducible unit of the algorithm (cf. the "one class per file"
// case). The incremental grow/reconcile/edit paths (doc 16/17/20) live here too.

#include "dc_mesh_common.h"  // to_v3, QUERY_EPS, g_mesh_threads, parallel_for
#include "dc_mmap_arena.h"   // MmapArena — the cell arena, disk-paged (M2)
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
	int parent = -1;       // c2 (doc 20): up-link, so a refine can mark its ancestor path dirty for the
	                       // incremental reaccumulate/collapse (skip the clean subtrees a drain didn't touch).
	bool path_dirty = false; // a descendant changed this grow → reaccumulate/recollapse must descend here
	int vertex = -1;
	bool leaf = true;
	bool absent = false; // window_mode: a leaf OUTSIDE the resident window — no QEF, no vertex, not
	                     // meshed. The window boundary is the resident mesh's open rim (like the clipmap's
	                     // outer edge). Distinct from a splice's build-box-miss leaf, which IS meshed.
	// Hot/cold split: the QEF (the big, ~120 B cold field) lives in the parallel `qefs` arena, NOT here — the
	// full-arena hot passes (reconcile / reset_leaves / collapse) never read it, so keeping it out of the hot
	// Cell shrinks what they stream from disk (296→256→~136 B/cell). Indexed by the same cell index. See `qefs`.

	// Incremental-grow caches (doc 17 #3). Both the collapse residual and the emitted vertex are pure
	// functions of `qef` (and the fixed cell box), so a grow that doesn't change this cell's qef can reuse
	// last frame's solve instead of redoing the SVD — turning the per-grow solve cost from O(window) into
	// O(changed band). `dirty` is the per-frame signal reconcile sets where it changes a cell and
	// reaccumulate propagates to ancestors; it clears the *_valid bits, which otherwise persist across grows.
	// A fresh cell is born with both invalid (solve once), so the full-build path is unaffected.
	float   we_cache  = 0.0f;       // sqrt(qef.residual(solved vertex)) — the collapse screen-error numerator
	F3      vpos_cache;             // solved vertex position (lattice-local) — emitted as a float GPU vertex
	float   verr_cache = 0.0f;      // sqrt(qef.residual(vpos)) — this leaf's geometric error (dcinval diagnostic)
	F3      vnorm_cache;            // solved vertex normal
	Color   vcol_cache;             // solved vertex material colour (only when emit_color)
	bool we_valid  = false;         // we_cache holds this cell's current qef's residual
	bool vtx_valid = false;         // vpos/vnorm/vcol_cache hold this cell's current qef's solve
	bool dirty     = false;         // qef changed THIS reconcile → invalidate caches up to the root
	// c3 tier 1 (doc 20): incremental emit. `vertex` doubles as a STABLE vertex slot across grows; tri_at/tri_n
	// are this leaf's triangle range in the persistent index/owner arrays (tri_at = first triangle, tri_n = count),
	// so a drain tombstones the old range + appends the new one instead of rebuilding the whole mesh.
	int tri_at = 0;                 // first triangle index into the persistent owner/index arrays
	int tri_n  = 0;                 // number of triangles this leaf currently owns (0 = not emitting)
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
	int64_t cell_budget = 0;  // memory budget (cells): build stops descending past this (0 = arena cap only).
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

	// c3 tier 1 (doc 20): persistent incremental emit. verts/indices/etc. survive across grows; a drain
	// tombstones changed leaves' triangles (degenerate them in place) and appends the new ones, then a full
	// emit re-compacts when the tombstone fraction grows. emit_warm = the arrays + per-leaf tri ranges are valid.
	LocalVector<int> vslot_free;  // recycled vertex slots (from leaves that stopped emitting)
	int  vslot_high = 0;          // next fresh vertex slot (high-water mark)
	int  tomb_tris  = 0;          // tombstoned (degenerate) triangles awaiting the next compaction
	bool emit_warm  = false;      // persistent emit arrays + per-leaf tri_at/tri_n are valid (post full emit)
	bool emit_track = false;      // recollapse_dirty records changed subtree roots into emit_dirty (incremental emit on)
	LocalVector<int> emit_dirty;  // subtree roots the incremental emit must re-walk this grow (from recollapse_dirty)
	bool verify_emit_on = false;  // debug: run verify_emit() after each emit to catch dangling-slot triangles
	int  last_bad_tris  = 0;      // verify_emit result: non-degenerate triangles spanning ≫ their owner cell
	Vector3 last_bad_pos;         // a vertex (lattice-local) of the first bad triangle found, for localising it
	String  last_bad_info;        // up to 5 bad tris this emit: owner cell + 3 vertices — read over REST to diagnose
	int64_t verify_total_bad = 0; // cumulative bad triangles across all emits this session (frequency signal)
	int     verify_bad_emits = 0; // cumulative emits that produced ≥1 bad triangle
	bool emit_diff_on = false;    // debug: after an incremental emit, full-emit the same tree + diff (catches DROPS)
	int last_drop_tris = 0;       // triangles the FULL emit has that the incremental dropped (= holes) this emit
	int last_extra_tris = 0;      // triangles the incremental emit has that the full doesn't (= doubles/dangling)
	int64_t emit_diff_total_drop = 0; // cumulative dropped triangles this session
	String last_drop_info;        // up to 5 dropped triangles this emit (centroid) — read over REST to localise
	uint64_t last_build_us    = 0; // phase timing: build() + accumulate_qef() (microseconds)
	uint64_t last_collapse_us = 0; // phase timing: recollapse_and_mesh() (microseconds)
	uint64_t last_construct_us = 0; // sub-phase: build() tree construction (serial)
	uint64_t last_sample_us    = 0; // sub-phase: sample_leaves_parallel() (parallel)
	uint64_t last_accum_us     = 0; // sub-phase: accumulate_sums() (serial)
	uint64_t last_collapse_pass_us = 0; // sub-phase: collapse_pass() serial tree walk (within emit bucket)
	uint64_t last_reset_us = 0;    // recollapse sub-phase: reset_leaves() full O(cells) walk
	uint64_t last_pass1_us = 0;    // recollapse sub-phase: vertex slot scan + parallel place_vertex
	uint64_t last_pass2_us = 0;    // recollapse sub-phase: edge scan + parallel emit + concat
	uint64_t last_reconcile_us = 0; // grow sub-phase: reconcile() the O(tree) graft/evict/collect walk (c4 target)
	uint64_t last_reaccum_us   = 0; // grow sub-phase: reaccumulate() the O(tree-or-changed) QEF re-sum (c4 target)
	MmapArena<Cell> cells; // M2: disk-paged cell arena — hot (visible) cells in RAM, cold (retained) on disk
	MmapArena<Qef>  qefs;  // hot/cold split: per-cell QEF, parallel to `cells` (same index). Grown in lockstep
	                       // (alloc_cell / resize_uninitialized mirror to both) so qefs[i] is the QEF of cells[i].
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
		qefs[idx] = leaf_qef(idx);
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
				qefs[idx] = Qef();
			} else {
				sample_leaf(idx);
			}
			return;
		}
		Qef sum;
		for (int i = 0; i < 8; ++i) {
			int ch = cells[idx].children[i];
			accumulate_qef(ch);
			sum.add(qefs[ch]);
		}
		qefs[idx] = sum;
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
					qefs[i] = Qef();
				} else {
					leaves.push_back(int(i));
				}
			}
		}
		build_samples = int(leaves.size());
		const int n = int(leaves.size());
		const int nthreads = (g_mesh_threads > 1 && n >= 64) ? MIN(g_mesh_threads, n) : 1;
		parallel_for(n, nthreads, [this, &leaves](int k) {
			qefs[leaves[k]] = leaf_qef(leaves[k]);
		});
	}

	// Roll the (already-sampled) leaf QEFs up the tree — same post-order sum as accumulate_qef but with
	// NO leaf sampling (the leaves are filled by sample_leaves_parallel first). Same summands and order,
	// so qefs[0] is bit-identical to accumulate_qef(0).
	void accumulate_sums(int idx) {
		if (cells[idx].children[0] < 0) {
			return; // leaf — qef already set by sample_leaves_parallel
		}
		Qef sum;
		for (int i = 0; i < 8; ++i) {
			int ch = cells[idx].children[i];
			accumulate_sums(ch);
			sum.add(qefs[ch]);
		}
		qefs[idx] = sum;
	}

	// Reset every node's leaf flag to its STRUCTURAL state (leaf iff it has no children) and clear the
	// placed vertex, so collapse_pass + meshing can re-run from scratch on a camera re-walk.
	void reset_leaves() {
		const int n = int(cells.size());
		const int threads = (g_mesh_threads > 1 && n >= 8192) ? MIN(g_mesh_threads, n) : 1;
		parallel_for(n, threads, [this](int i) { // independent per cell → byte-identical to the serial loop
			cells[i].leaf = cells[i].children[0] < 0;
			cells[i].vertex = -1;
			cells[i].tri_n = 0;          // the full emit rebuilds the index array + only re-stamps tri_at/tri_n on
			                             // EMITTING leaves, so a leaf that stops emitting would keep a STALE range
			                             // pointing at another leaf's triangles — a later incremental drain would
			                             // then tombstone the wrong leaf. Reset here so non-emitters carry tri_n=0.
			cells[i].path_dirty = false; // c4: a move does a FULL collapse (camera changed) and won't consume the
			                             // incremental-reaccumulate marks, so clear them here or they leak to the
			                             // next grow and decay reaccumulate back toward O(tree). Free — already O(n).
		});
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

	// Reset a subtree to its STRUCTURAL collapse state (leaf iff no children), so collapse_pass can re-decide
	// it. Used when an incremental re-decide un-collapses a node whose subtree was orphaned (all leaf=false).
	void reset_subtree(int idx) {
		cells[idx].leaf = cells[idx].children[0] < 0;
		if (cells[idx].children[0] >= 0) {
			for (int i = 0; i < 8; ++i) {
				reset_subtree(cells[idx].children[i]);
			}
		}
	}

	// c2 (doc 20): INCREMENTAL collapse — re-decide only the path_dirty subtrees (the cells a drain's
	// reaccumulate re-summed); clean subtrees keep last grow's leaf flags. Post-order, consuming path_dirty.
	// A node's own collapse can flip: expand→collapse is handled by collapse_test's orphan_subtree; the
	// collapse→expand (un-collapse) case must fully re-decide the now-rendered subtree, which was orphaned.
	void recollapse_dirty(int idx) {
		if (!cells[idx].path_dirty) {
			return; // clean subtree — its leaf flags are unchanged from last grow
		}
		cells[idx].path_dirty = false;
		if (cells[idx].children[0] < 0) {
			cells[idx].leaf = true; // structural leaf
			return;
		}
		bool any_child_marked = false;
		for (int i = 0; i < 8; ++i) {
			if (cells[cells[idx].children[i]].path_dirty) {
				any_child_marked = true;
			}
			recollapse_dirty(cells[idx].children[i]);
		}
		if (!any_child_marked) {
			// Tip of the marked tree = the refined cell. Its subtree is freshly built (structural leaf flags),
			// so collapse_pass decides the whole new subtree's LOD — not just this node.
			collapse_pass(idx);
			if (emit_track) {
				emit_dirty.push_back(idx); // c3: its whole subtree's emit changed
			}
			return;
		}
		// Ancestor of a refined cell: only its own collapse can flip (its qef was re-summed). expand→collapse
		// is handled by collapse_test's orphan_subtree; collapse→expand must restore the orphaned subtree.
		bool was_leaf = cells[idx].leaf;
		cells[idx].leaf = false;
		collapse_test(idx);
		if (was_leaf && !cells[idx].leaf) {
			reset_subtree(idx);
			collapse_pass(idx);
		}
		if (emit_track && was_leaf != cells[idx].leaf) {
			emit_dirty.push_back(idx); // c3: this ancestor's collapse flipped → its subtree's emit changed
		}
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
		qefs.push_back(Qef()); // hot/cold split: keep the QEF arena index-synced with cells
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
			qefs[idx] = Qef(); // hot/cold split: QEF lives in the parallel arena (c is the hot Cell at idx)
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
			cells[child].parent = idx;
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
		qefs[idx] = Qef(); // hot/cold split: QEF lives in the parallel arena (c is the hot Cell at idx)
		c.we_valid = false; // born invalid — a reused slot's cached solve belongs to a dead cell
		c.vtx_valid = false;
		c.dirty = false;
		c.path_dirty = false;
		c.parent = -1; // set by the caller's build/grow loop after this returns; root stays -1
		c.tri_n = 0;   // c3: not emitting yet (no cached triangle range)
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
			// Memory budget: stop descending if the next level would exceed it. The arena cap is the hard
			// int-index-safety ceiling; cell_budget (from max_cells) is the softer user bound. Without this a
			// re-root into dense terrain at LOG2=4 builds past the cap and resize_uninitialized hard-aborts.
			const int64_t cap = cells.capacity();
			const int64_t budget = (cell_budget > 0 && cell_budget < cap) ? cell_budget : cap;
			if (int64_t(base) + int64_t(d_count) * 8 > budget) {
				for (int j = 0; j < d_count; ++j) {
					cells[descenders[j]].leaf = true; // budget hit → keep these coarse (valid leaves, no children)
				}
				break;
			}
			cells.resize_uninitialized(base + int64_t(d_count) * 8); // init_cell fills every new slot in parallel below
			qefs.resize_uninitialized(base + int64_t(d_count) * 8);  // hot/cold split: same slots in the QEF arena
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
					cells[child].parent = fi;
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
					sum.add(qefs[cells[idx].children[i]]);
				}
				qefs[idx] = sum;
			});
		}
	}

	// One node's collapse decision — the body of collapse_pass without the recursion. Reads only its own
	// accumulated qef, writes only its own leaf flag + orphans its own (disjoint) subtree.
	void collapse_test(int idx) {
		if (cells[idx].children[0] < 0 || !error_driven || qefs[idx].count == 0 || cells[idx].size > max_leaf_size) {
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
			const Vector3 v = qefs[idx].solve(cmin, cmax);
			we = Math::sqrt(qefs[idx].residual(v));
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
		while (!cells[idx].leaf && cells[idx].children[0] >= 0) {
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
			const Qef &qef = qefs[idx];
			Vector3 cmin = to_v3(cells[idx].origin);
			Vector3 cmax = cmin + Vector3(1, 1, 1) * double(cells[idx].size);
			Vector3 v = qef.solve(cmin, cmax);
			Vector3 n = qef.nsum.length_squared() > 0.0 ? Vector3(qef.nsum).normalized() : Vector3(0, 1, 0);
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

	// --- c3 tier 1: incremental emit (tombstone + append) -----------------------------------------------
	int emit_alloc_slot() {
		if (!vslot_free.is_empty()) {
			int s = vslot_free[vslot_free.size() - 1];
			vslot_free.resize(vslot_free.size() - 1);
			return s;
		}
		return vslot_high++;
	}

	// Degenerate this leaf's triangles in place (3 equal indices = zero-area, not rendered) and count them
	// toward the next compaction. The owner/size/err entries stay stale — a degenerate tri never reaches dcinval.
	void emit_tombstone(int idx) {
		int at = cells[idx].tri_at;
		int nt = cells[idx].tri_n;
		int32_t *ip = indices.ptrw();
		for (int t = at; t < at + nt; ++t) {
			int32_t v = ip[t * 3];
			ip[t * 3 + 1] = v;
			ip[t * 3 + 2] = v;
		}
		tomb_tris += nt;
		cells[idx].tri_n = 0;
	}

	void emit_drop(int idx) { // a cell that stopped emitting: tombstone its tris + recycle its vertex slot
		if (cells[idx].tri_n > 0) {
			emit_tombstone(idx);
		}
		if (cells[idx].vertex >= 0) {
			vslot_free.push_back(cells[idx].vertex);
			cells[idx].vertex = -1;
		}
	}

	void emit_append(int idx, const EmitSink &s) { // append this leaf's fresh triangles to the persistent arrays
		cells[idx].tri_at = int(tri_owners.size());
		cells[idx].tri_n = int(s.owners.size());
		for (uint32_t k = 0; k < s.indices.size(); ++k) {
			indices.push_back(s.indices[k]);
		}
		for (uint32_t k = 0; k < s.owners.size(); ++k) {
			tri_owners.push_back(s.owners[k]);
			tri_owner_sizes.push_back(s.owner_sizes[k]);
			tri_owner_errors.push_back(s.owner_errs[k]);
		}
	}

	// Drop a cell, AND if it was emitting (had a slot), collect its neighbours into `re`. Its freed slot goes on
	// vslot_free and is reused this same emit — so any neighbour whose quad still indexes that slot would dangle
	// to the reused slot's (possibly far-away) vertex. Re-emitting those neighbours retires their stale tris.
	void drop_and_collect(int idx, HashSet<int> &re) {
		if (cells[idx].vertex >= 0) {
			emit_collect_neighbors(idx, re);
		}
		emit_drop(idx);
	}

	// Walk a changed subtree: surviving render leaves go to the re-emit set; cells that stopped emitting drop.
	// Stop at a render leaf (leaf=true, whether collapsed-internal or structural) AND at any childless cell
	// (a structural leaf, or one orphaned by a collapse above — orphans are leaf=false but have no children).
	void emit_walk_dirty(int idx, HashSet<int> &re) {
		if (cells[idx].leaf || cells[idx].children[0] < 0) {
			if (cells[idx].leaf && qefs[idx].count > 0) {
				re.insert(idx);
			} else {
				drop_and_collect(idx, re);
			}
			return;
		}
		drop_and_collect(idx, re); // expanded internal node — not itself a render leaf; clear any stale triangles
		for (int i = 0; i < 8; ++i) {
			emit_walk_dirty(cells[idx].children[i], re);
		}
	}

	// Collect every render leaf overlapping a LATTICE box — an octree descent that only enters overlapping
	// subtrees, so it costs O(leaves in the box), not O(box volume).
	void collect_leaves_in_box(int idx, const Vector3i &bmin, const Vector3i &bmax, HashSet<int> &re) {
		Vector3i co = cells[idx].origin;
		int cs = cells[idx].size;
		if (co.x >= bmax.x || co.x + cs <= bmin.x || co.y >= bmax.y || co.y + cs <= bmin.y ||
				co.z >= bmax.z || co.z + cs <= bmin.z) {
			return; // no overlap
		}
		if (cells[idx].leaf || cells[idx].children[0] < 0) {
			if (cells[idx].leaf && qefs[idx].count > 0) {
				re.insert(idx);
			}
			return;
		}
		for (int i = 0; i < 8; ++i) {
			collect_leaves_in_box(cells[idx].children[i], bmin, bmax, re);
		}
	}

	// Existing leaves adjacent to a changed root reference its (now-moved) vertex slot or share a reassigned
	// edge, so they re-emit too. The seam is the unit shell around the root box — gathered as six face slabs
	// (each spanning the full shell cross-section, so edges/corners are covered) via the octree box query.
	void emit_collect_neighbors(int root, HashSet<int> &re) {
		Vector3i o = cells[root].origin;
		int S = cells[root].size;
		Vector3i lo = o - Vector3i(1, 1, 1);
		Vector3i hi = o + Vector3i(S + 1, S + 1, S + 1);
		collect_leaves_in_box(0, lo, Vector3i(o.x, hi.y, hi.z), re);                 // -x face slab
		collect_leaves_in_box(0, Vector3i(o.x + S, lo.y, lo.z), hi, re);             // +x
		collect_leaves_in_box(0, Vector3i(lo.x, lo.y, lo.z), Vector3i(hi.x, o.y, hi.z), re);   // -y
		collect_leaves_in_box(0, Vector3i(lo.x, o.y + S, lo.z), hi, re);             // +y
		collect_leaves_in_box(0, Vector3i(lo.x, lo.y, lo.z), Vector3i(hi.x, hi.y, o.z), re);   // -z
		collect_leaves_in_box(0, Vector3i(lo.x, lo.y, o.z + S), hi, re);             // +z
		re.erase(root); // the root itself isn't its own neighbour
	}

	void emit_incremental() {
		uint64_t t0 = OS::get_singleton()->get_ticks_usec();
		last_reset_us = 0;
		HashSet<int> re;
		for (uint32_t r = 0; r < emit_dirty.size(); ++r) {
			emit_walk_dirty(emit_dirty[r], re); // tombstone vanished tris, collect surviving leaves
		}
		for (uint32_t r = 0; r < emit_dirty.size(); ++r) {
			emit_collect_neighbors(emit_dirty[r], re); // seam leaves around each changed root
		}
		// Expand the re-emit set by ONE more neighbour ring. A seam leaf in `re` emits quads (try_edge) that
		// reference its OWN ring-cell neighbours; if such a neighbour isn't slotted, try_edge drops the whole
		// quad (line ~825). The pass above only collected the dirty roots' neighbours, not the neighbours of
		// those — so the seam leaves' far-side ring cells were unslotted → connected patches of dropped tris,
		// every drain. Collecting the neighbours of the current `re` set closes that gap (gated by emit_warm
		// only, so still O(changed)). Snapshot first: emit_collect_neighbors mutates `re`.
		LocalVector<int> re_layer;
		for (const int &L : re) {
			re_layer.push_back(L);
		}
		for (uint32_t i = 0; i < re_layer.size(); ++i) {
			emit_collect_neighbors(re_layer[i], re);
		}
		// Assign slots to new leaves first, so the edge emit below reads every neighbour's CURRENT slot.
		for (const int &L : re) {
			if (cells[L].vertex < 0) {
				cells[L].vertex = emit_alloc_slot();
			}
		}
		if (int(verts.size()) < vslot_high) {
			verts.resize(vslot_high);
			normals.resize(vslot_high);
			if (emit_color) {
				colors.resize(vslot_high);
			}
		}
		for (const int &L : re) {
			place_vertex(L);
		}
		uint64_t t1 = OS::get_singleton()->get_ticks_usec();
		last_pass1_us = t1 - t0;
		for (const int &L : re) {
			if (cells[L].tri_n > 0) {
				emit_tombstone(L); // its old triangles (it survived but its edges may have changed)
			}
			EmitSink s;
			emit_leaf_edges(s, L);
			emit_append(L, s);
		}
		last_pass2_us = OS::get_singleton()->get_ticks_usec() - t1;
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
	void recollapse_and_mesh(bool incremental = false) {
		// c3 tier 1: a DRAIN reuses the persistent emit arrays (tombstone + append the changed band) once they
		// are warm and not too fragmented; a full/rebuild emit — or a compaction when tombstones pile up —
		// rebuilds the arrays from scratch (which also re-compacts and re-warms the state).
		bool inc_emit = incremental && emit_warm && (tomb_tris * 3 < int(tri_owners.size()) + 1);
		emit_track = inc_emit;
		if (inc_emit) {
			emit_dirty.clear();
		} else {
			verts.clear();
			normals.clear();
			colors.clear();
			indices.clear();
			tri_owners.clear();
			tri_owner_sizes.clear();
			tri_owner_errors.clear();
		}
		uint64_t tr0 = OS::get_singleton()->get_ticks_usec();
		if (inc_emit) {
			// keep stable vertex slots + last grow's leaf flags — emit_incremental patches only the changes
		} else if (incremental) {
			// compacting full emit on a drain: keep leaf flags (incremental collapse set them), reset slots +
			// tri ranges (this rebuilds the index array, so non-emitters must not keep a stale tri range — see
			// reset_leaves; otherwise a later incremental drain tombstones the wrong leaf's triangles).
			const int n = int(cells.size());
			const int threads = (g_mesh_threads > 1 && n >= 8192) ? MIN(g_mesh_threads, n) : 1;
			parallel_for(n, threads, [this](int i) { cells[i].vertex = -1; cells[i].tri_n = 0; });
		} else {
			reset_leaves();
		}
		uint64_t tc0 = OS::get_singleton()->get_ticks_usec();
		last_reset_us = tc0 - tr0;
		// level_start is set only by the parallel bottom-up full build; the grow/reconcile path leaves it
		// empty (its tree isn't level-laid-out), so that falls back to the serial recursive collapse.
		if (incremental) {
			recollapse_dirty(0); // re-decide only the path_dirty subtrees; clean leaf flags stand
		} else if (!level_start.is_empty()) {
			collapse_parallel();
		} else {
			collapse_pass(0);
		}
		uint64_t tp1 = OS::get_singleton()->get_ticks_usec();
		last_collapse_pass_us = tp1 - tc0;
		if (inc_emit) {
			emit_incremental(); // tombstone + append only the changed leaves + seam neighbours
			emit_track = false;
			if (verify_emit_on) {
				verify_emit();
			}
			return;
		}
		int n = int(cells.size());

		// Pass 1: one vertex per surviving surface leaf. The cell-index-order rank IS the vertex slot (so the
		// indices match the serial emit), but the scattered per-cell read dominates on a drain (place_vertex is
		// cached) — so PARALLELISE it: mark emitters in parallel, prefix-sum the dense marks for slots (serial
		// but cache-tight), then fill slot→cell in parallel. Byte-identical to the serial scan.
		const int cthreads = (g_mesh_threads > 1 && n >= 8192) ? MIN(g_mesh_threads, n) : 1;
		LocalVector<uint8_t> is_vtx;
		is_vtx.resize(n);
		parallel_for(n, cthreads, [this, &is_vtx](int i) {
			is_vtx[i] = (cells[i].leaf && qefs[i].count > 0) ? 1 : 0;
		});
		LocalVector<int> voff;
		voff.resize(n);
		int vcount = 0;
		for (int i = 0; i < n; ++i) {
			voff[i] = vcount;
			vcount += is_vtx[i];
		}
		LocalVector<int> vcells;
		vcells.resize(vcount);
		parallel_for(n, cthreads, [this, &is_vtx, &voff, &vcells](int i) {
			if (is_vtx[i]) {
				cells[i].vertex = voff[i];
				vcells[voff[i]] = i;
			}
		});
		verts.resize(vcount);
		normals.resize(vcount);
		if (emit_color) {
			colors.resize(vcount);
		}
		const int vthreads = (g_mesh_threads > 1 && vcount >= 64) ? MIN(g_mesh_threads, vcount) : 1;
		parallel_for(vcount, vthreads, [this, &vcells](int k) {
			place_vertex(vcells[k]);
		});
		uint64_t tp2 = OS::get_singleton()->get_ticks_usec();
		last_pass1_us = tp2 - tp1;

		// Pass 2: stitch edges. Each surviving leaf emits into its OWN sink in parallel (reads of cells/
		// verts are immutable now), then the sinks concatenate in cell-index order — byte-identical to
		// the old serial single-array emit (same leaf order, same per-leaf edge order).
		// Same parallel compaction for the edge-emit leaf list (cell-index order preserved).
		LocalVector<uint8_t> is_edge;
		is_edge.resize(n);
		parallel_for(n, cthreads, [this, &is_edge](int i) {
			is_edge[i] = (cells[i].leaf && cells[i].vertex >= 0) ? 1 : 0;
		});
		LocalVector<int> eoff;
		eoff.resize(n);
		int ecount = 0;
		for (int i = 0; i < n; ++i) {
			eoff[i] = ecount;
			ecount += is_edge[i];
		}
		LocalVector<int> ecells;
		ecells.resize(ecount);
		parallel_for(n, cthreads, [this, &is_edge, &eoff, &ecells](int i) {
			if (is_edge[i]) {
				ecells[eoff[i]] = i;
			}
		});
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
			cells[ecells[e]].tri_at = int(to);            // c3: record this leaf's triangle range for the
			cells[ecells[e]].tri_n = int(s.owners.size()); // incremental emit's tombstone+append to splice against
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
		// c3: a full emit IS a compaction — dense vslots [0,vcount), no tombstones, every leaf's range recorded.
		vslot_high = vcount;
		vslot_free.clear();
		tomb_tris = 0;
		emit_warm = true;
		last_pass2_us = OS::get_singleton()->get_ticks_usec() - tp2;
		if (verify_emit_on) {
			verify_emit();
		}
	}

	// Two cell boxes touch/overlap on all 3 axes — i.e. they're adjacent (share at least an edge). The (up to 4)
	// cells around a DC minimal-edge are pairwise touching regardless of their sizes, so a legit triangle's three
	// owner cells all touch — even across an arbitrary LOD jump. A dangling/reused slot points to a cell that is
	// NOT touching → that's the real bug, independent of edge length.
	bool cells_touch(int i, int j) const {
		const Vector3i a = cells[i].origin;
		const int as = cells[i].size;
		const Vector3i b = cells[j].origin;
		const int bs = cells[j].size;
		return a.x <= b.x + bs && b.x <= a.x + as && a.y <= b.y + bs && b.y <= a.y + as && a.z <= b.z + bs && b.z <= a.z + as;
	}

	// Debug self-check for the incremental-emit accounting. The geometric "far apart" test false-positives on
	// legit large LOD jumps (DC is crack-free across any size jump), so this uses ADJACENCY instead: build a
	// slot→owning-render-leaf map, then a triangle is bad iff a vertex slot is owned by NO current render leaf
	// (a freed-but-still-indexed slot) OR its owning cell does not touch the triangle's other two cells (a
	// reused slot snapped to an unrelated cell). O(cells + triangles); gated by verify_emit_on (debug only).
	void verify_emit() {
		last_bad_tris = 0;
		last_bad_info = String();
		const int32_t *ip = indices.ptr();
		const Vector3 *vp = verts.ptr();
		const int vn = int(verts.size());
		const int nt = int(indices.size()) / 3;
		if (nt == 0) {
			return;
		}
		LocalVector<int> slot_cell; // vertex slot → owning render-leaf cell index (-1 = no live owner)
		slot_cell.resize(vn);
		for (int i = 0; i < vn; ++i) {
			slot_cell[i] = -1;
		}
		const int ncells = int(cells.size());
		for (int i = 0; i < ncells; ++i) {
			const int v = cells[i].vertex;
			if (cells[i].leaf && v >= 0 && v < vn && qefs[i].count > 0) {
				slot_cell[v] = i;
			}
		}
		auto v3s = [](const Vector3 &v) -> String {
			return "(" + String::num(v.x, 1) + "," + String::num(v.y, 1) + "," + String::num(v.z, 1) + ")";
		};
		int captured = 0;
		for (int t = 0; t < nt; ++t) {
			const int s[3] = { ip[t * 3], ip[t * 3 + 1], ip[t * 3 + 2] };
			if (s[0] == s[1] || s[1] == s[2] || s[0] == s[2]) {
				continue; // degenerate = tombstone, not drawn
			}
			int ci[3] = { -1, -1, -1 };
			bool bad = false;
			for (int k = 0; k < 3; ++k) {
				ci[k] = (s[k] >= 0 && s[k] < vn) ? slot_cell[s[k]] : -1;
				if (ci[k] < 0) {
					bad = true; // slot owned by no current render leaf — freed-but-still-indexed
				}
			}
			if (!bad) {
				for (int k = 0; k < 3 && !bad; ++k) {
					for (int m = k + 1; m < 3 && !bad; ++m) {
						if (!cells_touch(ci[k], ci[m])) {
							bad = true; // a vertex cell that doesn't touch the others — snapped to an unrelated cell
						}
					}
				}
			}
			if (!bad) {
				continue;
			}
			if (last_bad_tris == 0 && s[0] >= 0 && s[0] < vn) {
				last_bad_pos = vp[s[0]];
			}
			++last_bad_tris;
			if (captured < 5) {
				++captured;
				String rec = "tri slots=[" + itos(s[0]) + "," + itos(s[1]) + "," + itos(s[2]) + "]";
				for (int k = 0; k < 3; ++k) {
					rec += String(k == 0 ? " A" : (k == 1 ? " B" : " C")) + "=";
					if (s[k] >= 0 && s[k] < vn) {
						rec += v3s(vp[s[k]]);
					} else {
						rec += "OOB";
					}
					if (ci[k] >= 0) {
						rec += "@cell" + v3s(to_v3(cells[ci[k]].origin)) + "sz" + itos(cells[ci[k]].size);
					} else {
						rec += "@FREED"; // the smoking gun — referenced slot owned by no live leaf
					}
				}
				last_bad_info += rec + "\n";
			}
		}
		if (last_bad_tris > 0) {
			verify_total_bad += last_bad_tris;
			++verify_bad_emits;
		}
	}

	String v3str(const Vector3 &v) const {
		return "(" + String::num(v.x, 1) + "," + String::num(v.y, 1) + "," + String::num(v.z, 1) + ")";
	}

	// Position-based, order-independent triangle key: identifies the SAME triangle across the incremental and
	// full emits even though their vertex slots/order differ. Quantized to 1/16 unit to absorb float noise.
	static uint64_t tri_key(const Vector3 &a, const Vector3 &b, const Vector3 &c) {
		auto pk = [](const Vector3 &v) -> uint64_t {
			uint64_t x = uint64_t(int64_t(Math::round(v.x * 16.0)));
			uint64_t y = uint64_t(int64_t(Math::round(v.y * 16.0)));
			uint64_t z = uint64_t(int64_t(Math::round(v.z * 16.0)));
			return x * 1000003u ^ y * 19349663u ^ z * 83492791u;
		};
		const uint64_t ha = pk(a), hb = pk(b), hc = pk(c);
		return ha + hb + hc + (ha ^ hb ^ hc) * 2654435761u; // commutative → order-independent
	}

	void build_tri_set(HashSet<uint64_t> &set) const {
		const int32_t *ip = indices.ptr();
		const Vector3 *vp = verts.ptr();
		const int vn = int(verts.size());
		const int nt = int(indices.size()) / 3;
		for (int t = 0; t < nt; ++t) {
			const int a = ip[t * 3], b = ip[t * 3 + 1], c = ip[t * 3 + 2];
			if (a == b || b == c || a == c) {
				continue;
			}
			if (a < 0 || a >= vn || b < 0 || b >= vn || c < 0 || c >= vn) {
				continue;
			}
			set.insert(tri_key(vp[a], vp[b], vp[c]));
		}
	}

	// Debug: the definitive drop catcher. The current arrays hold the INCREMENTAL emit; full-emit the SAME tree
	// (recollapse_and_mesh(false) — the correct surface), then report every triangle the full emit has that the
	// incremental lacks (= a DROPPED triangle, i.e. a hole). The full result stays as the displayed mesh, so the
	// bug is masked on screen while this is on, but the drops are reported via REST for localising. Expensive
	// (doubles the emit) — debug only, gated by emit_diff_on.
	void compute_emit_diff() {
		HashSet<uint64_t> inc;
		build_tri_set(inc); // the incremental emit's triangles
		recollapse_and_mesh(false); // full emit of the same tree → arrays now hold the CORRECT surface
		last_drop_tris = 0;
		last_extra_tris = 0;
		last_drop_info = String();
		HashSet<uint64_t> full;
		build_tri_set(full);
		const int32_t *ip = indices.ptr();
		const Vector3 *vp = verts.ptr();
		const int vn = int(verts.size());
		const int nt = int(indices.size()) / 3;
		int captured = 0;
		for (int t = 0; t < nt; ++t) {
			const int a = ip[t * 3], b = ip[t * 3 + 1], c = ip[t * 3 + 2];
			if (a == b || b == c || a == c || a < 0 || a >= vn || b < 0 || b >= vn || c < 0 || c >= vn) {
				continue;
			}
			if (!inc.has(tri_key(vp[a], vp[b], vp[c]))) { // full has it, incremental dropped it
				++last_drop_tris;
				if (captured < 5) {
					++captured;
					const Vector3 ctr = (vp[a] + vp[b] + vp[c]) * (1.0 / 3.0);
					String own = (t < int(tri_owners.size())) ? (v3str(tri_owners.ptr()[t]) + " sz" + String::num(tri_owner_sizes.ptr()[t], 0)) : String("?");
					last_drop_info += "DROPPED owner=" + own + " centre=" + v3str(ctr) + " A=" + v3str(vp[a]) + " B=" + v3str(vp[b]) + " C=" + v3str(vp[c]) + "\n";
				}
			}
		}
		for (const uint64_t &h : inc) {
			if (!full.has(h)) {
				++last_extra_tris;
			}
		}
		if (last_drop_tris > 0) {
			emit_diff_total_drop += last_drop_tris;
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
			cells[child].parent = idx;
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
		qefs[idx] = Qef();
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
				mark_path_dirty(idx); // c4: so incremental reaccumulate descends to this changed (→empty) qef
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
				mark_path_dirty(idx); // c4: so incremental reaccumulate descends to this grafted leaf's new qef
			}
			// else: a present leaf already at the floor — unchanged, reused (not resampled)
		} else if (refine_budget >= 0) {
			// C/P/I (doc 20): defer this refine — collect it onto the frontier keyed by its geometric error `we`
			// (the QEF residual of representing this coarse cell as one vertex — how much detail refining recovers).
			// `we` is camera-independent, so the persistent heap survives camera moves; refine_selected() does the
			// worst-error first, the rest stay coarse (QEF still valid) until a later grow reaches them.
			Vector3 cmin = to_v3(cells[idx].origin);
			Vector3 cmax = cmin + Vector3(1, 1, 1) * double(cells[idx].size);
			double we = Math::sqrt(qefs[idx].residual(qefs[idx].solve(cmin, cmax)));
			refine_cands.push_back(RefineCand{ we, idx });
		} else {
			grow_subtree(idx);   // unbudgeted (a move): subdivide to the (finer) floor — full window coverage
			accumulate_qef(idx);
			mark_path_dirty(idx); // c4: so incremental reaccumulate descends to this newly-refined subtree
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
			int x = base[refine_heap_end].idx;
			grow_subtree(x);                                     // at least one per call → always makes progress
			accumulate_qef(x);                                   // x.qef now current (leaf → accumulated)
			cells[x].we_valid = false;                           // x's cached solve/residual belonged to its old
			cells[x].vtx_valid = false;                          // leaf qef — stale now
			mark_path_dirty(x);                                  // mark x + ancestors: incremental reaccum re-sums
			                                                     // the path, recollapse_dirty re-collapse-tests x

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
	// Mark idx and its ancestors path_dirty (so the incremental reaccumulate/recollapse descend to a refined
	// cell instead of walking the whole tree). Stops at the first already-marked node — O(depth) per refine.
	void mark_path_dirty(int idx) {
		for (int p = idx; p >= 0 && !cells[p].path_dirty; p = cells[p].parent) {
			cells[p].path_dirty = true;
		}
	}

	// Roll up accumulated QEFs from changed children. `incremental` (a reuse/drain grow): prune subtrees that
	// aren't path_dirty — their qef + child sum are unchanged, so skip them. A clean child still contributes
	// its (current) qef to the parent's sum; only the WALK is pruned, so the result equals the full pass.
	// Non-incremental (rebuild): walk everything (reconcile changed cells without marking the path).
	bool reaccumulate(int idx, bool incremental) {
		const bool marked = cells[idx].path_dirty;
		if (incremental && !marked && !cells[idx].dirty) {
			return false; // subtree untouched this grow — its qef and caches are still current
		}
		bool changed;
		if (cells[idx].children[0] < 0) {
			if (cells[idx].absent) {
				qefs[idx] = Qef();
			}
			changed = cells[idx].dirty; // leaf: a re-sampled or newly-evicted leaf (reconcile set dirty)
		} else {
			bool any = false;
			Qef sum;
			for (int i = 0; i < 8; ++i) {
				int ch = cells[idx].children[i];
				any |= reaccumulate(ch, incremental);
				sum.add(qefs[ch]);
			}
			// `marked` means a refined descendant changed below this node. That descendant rolled up its own
			// subtree (accumulate_qef) and returns false from reaccumulate (its qef is already current), so `any`
			// alone misses it — a marked internal node must re-sum to pull the changed child's qef into its own.
			if (any || marked) {
				qefs[idx] = sum; // a child changed → this node's accumulated qef changed
			}
			changed = any || marked || cells[idx].dirty;
		}
		if (changed) {
			cells[idx].we_valid = false;  // qef changed → cached collapse residual is stale
			cells[idx].vtx_valid = false; // qef changed → cached vertex solve is stale
		}
		cells[idx].dirty = false;      // per-frame signal consumed
		if (!incremental) {
			cells[idx].path_dirty = false; // full path: clear here (recollapse won't read marks). Incremental:
		}                                  // leave them for recollapse_dirty to walk + consume.
		return changed;
	}
};

} // namespace dc_mesh
} // namespace voxel_dc

#endif // DC_OCTREE_H
