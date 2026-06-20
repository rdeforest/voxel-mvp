#include "dc_octree_mesher.h"

#include "dc_clipmap_source.h"
#include "dc_edit_store_source.h"
#include "dc_mesh_common.h"
#include "dc_octree.h"
#include "dc_sdf_source.h"
#include "edit_store.h"

#include "core/os/os.h"
#include "scene/resources/mesh.h"

// The mesher's internal structs — Octree, Clipmap, EditStoreSource, Level, plus the g_mesh_threads
// worker count and parallel_for — live in the voxel_dc::dc_mesh internal namespace, split across the
// per-concern headers (dc_mesh_common.h, dc_sdf_source.h, dc_clipmap_source.h, dc_edit_store_source.h,
// dc_octree.h) included above. Qef and the CB/EDGES/RING corner tables come from voxel_dc itself
// (dc_qef.h / octree_geometry.h, pulled in transitively), shared so the corner order can't drift.
using namespace voxel_dc;
using namespace voxel_dc::dc_mesh;

// The retained octree (Stage 2): a full build keeps its tree + per-node QEFs + the field snapshot
// alive so remesh() can re-decide collapse against a new camera without re-sampling. Octree is
// .cpp-local, so this is a pimpl the header forward-declares.
struct DCOctreePersist {
	Octree oct;
	Clipmap clip;                              // clipmap path: the field source oct.src points at
	LocalVector<PackedFloat32Array> held;      // keeps level SDF data alive (Level.data points in)
	LocalVector<PackedByteArray> held_idx;     // ...and the per-level material indices
	// World-fixed path (mesh_world): the EditStore field source oct.src points at, plus a Ref keeping the
	// store alive — so remesh() can re-collapse the retained world octree against a new camera (no resample).
	Ref<EditStore> world_store;
	EditStoreSource world_src{ nullptr, Vector3(), 1.0 };
};

// Pack an octree's meshed surface into a Mesh.ARRAY_* array (empty if no surface).
static Array pack_output(const Octree &oct) {
	Array out;
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

DCOctreeMesher::~DCOctreeMesher() {
	if (_persist != nullptr) {
		memdelete(_persist);
	}
}

// Re-walk the retained octree against a new camera/proj/eps and re-mesh — no build, no field
// sampling (Stage 2 movement path). Requires a prior full mesh_clipmap to have retained a tree.
Array DCOctreeMesher::remesh(Vector3 camera, double proj, double eps_px) {
	if (_persist == nullptr) {
		return Array(); // nothing retained yet — a benign no-op (caller falls back to mesh_clipmap)
	}
	Octree &oct = _persist->oct;
	oct.camera = camera;
	oct.proj = proj;
	oct.eps_px = eps_px;
	oct.recollapse_and_mesh();
	_last_tri_owners = oct.tri_owners;
	_last_tri_owner_sizes = oct.tri_owner_sizes;
	_last_tri_owner_errors = oct.tri_owner_errors;
	return pack_output(oct);
}

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

	// Retain ONLY a full build (no emit/build box) so remesh() can re-walk it; a splice is restricted
	// to a sub-box, so it builds into a transient octree and leaves the retained full build intact.
	const bool retain = (emit_min == emit_max) && (build_min == build_max);
	Octree transient_oct;
	Clipmap transient_clip;
	LocalVector<PackedFloat32Array> transient_held;
	LocalVector<PackedByteArray> transient_held_idx;
	Octree *octp = &transient_oct;
	Clipmap *clipp = &transient_clip;
	LocalVector<PackedFloat32Array> *heldp = &transient_held;
	LocalVector<PackedByteArray> *held_idxp = &transient_held_idx;
	if (retain) {
		if (_persist != nullptr) {
			memdelete(_persist);
		}
		_persist = memnew(DCOctreePersist);
		octp = &_persist->oct;
		clipp = &_persist->clip;
		heldp = &_persist->held;
		held_idxp = &_persist->held_idx;
	}

	// Hold the level arrays for the call so their data pointers stay valid.
	LocalVector<PackedFloat32Array> &held = *heldp;
	held.resize(n);
	LocalVector<PackedByteArray> &held_idx = *held_idxp;
	held_idx.resize(n);
	const int64_t per_level = int64_t(dim) * dim * dim;
	const bool with_indices = level_indices.size() == n && palette.size() > 0;

	Octree &oct = *octp;
	Clipmap &clip = *clipp;
	oct.src = &clip;
	oct.emit_color = with_indices;
	oct.palette = palette;
	oct.uniform_core = uniform_core;   // keep the 1m fine core uniform so edit patches splice cleanly
	oct.prune_safety = prune_safety;   // >0: surface-sparse build (skip provably-empty regions)
	oct.root_size = 1 << depth;
	oct.max_depth = depth;
	oct.camera = camera;
	oct.proj = proj;
	oct.eps_px = eps_px;
	oct.error_driven = error_driven;
	oct.world_origin = lattice_world_origin;
	// Emit-box filter: when emit_min != emit_max (caller set them), restrict output to
	// triangles owned by cells inside [emit_min, emit_max).
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
	clip.center = center;
	clip.half0 = half0;
	clip.levels.resize(n);
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
		clip.levels[k] = lv;
	}

	if (prune_safety > 0.0) {
		clip.build_mips(); // min/max pyramids for the exact surface-sparse prune
	}
	oct.run();

	_last_tri_owners      = oct.tri_owners;
	_last_tri_owner_sizes = oct.tri_owner_sizes;
	_last_tri_owner_errors = oct.tri_owner_errors;
	return pack_output(oct);
}

// World-fixed octree (doc 16 THE GOAL, scaffold): build + mesh ONE octree rooted at the WORLD-aligned
// box [world_origin, world_origin + 2^depth) (lattice units; 1 unit = base_cell metres), sampling the
// EditStore field DIRECTLY — no concentric clipmap, no geomorph. Bottom-up exact: build to the floor
// where there is surface, accumulate fine QEF up the tree, collapse by screen-error (we*proj/dist vs
// eps_px) from real fine data. camera is the viewpoint in this lattice frame (world/base_cell -
// world_origin). Returns Mesh.ARRAY_* (lattice-local; caller scales by base_cell + positions at
// world_origin). This is the seam the persistent/incremental world octree grows from; the live render
// still runs mesh_clipmap until this path is trusted.
Array DCOctreeMesher::mesh_world(
		Ref<EditStore> store,
		Vector3i world_origin,
		int depth,
		double base_cell,
		Vector3 camera,
		double proj,
		double eps_px,
		bool error_driven,
		const PackedColorArray &palette,
		Vector3i win_min,
		Vector3i win_max) {
	Array out;
	if (store.is_null() || depth < 1 || base_cell <= 0.0) {
		ERR_PRINT("DCOctreeMesher::mesh_world: bad arguments");
		return out;
	}
	// Retain the world octree (like a full mesh_clipmap) so remesh() can re-collapse it against a new
	// camera with no field resampling — the persistent-octree foundation for incremental movement. The
	// EditStoreSource + a Ref to the store live in the persist so oct.src stays valid across remesh().
	if (_persist != nullptr) {
		memdelete(_persist);
	}
	_persist = memnew(DCOctreePersist);
	_persist->world_store = store;
	_persist->world_src = EditStoreSource(store.ptr(), Vector3(world_origin), base_cell);
	Octree &oct = _persist->oct;
	oct.src = &_persist->world_src;
	oct.emit_color = palette.size() > 0;
	oct.palette = palette;
	oct.root_size = 1 << depth;
	oct.max_depth = depth;
	oct.camera = camera;
	oct.proj = proj;
	oct.eps_px = eps_px;
	oct.error_driven = error_driven;
	oct.world_origin = world_origin;
	oct.uniform_core = false; // the whole world octree collapses by screen-error; no fine bubble to pin
	oct.prune_safety = 0.0;   // off unless a window is set (below) — a windowless build stays dense to floor
	// Resident WINDOW (doc 16 Stage B): when win_min != win_max, build only the cells overlapping the
	// window box (WORLD lattice) and mark the rest absent — the large root can span the roam region while
	// the build cost stays bounded to the window. Default (win_min == win_max) = build the whole root.
	// P2 (doc 17): graded data floor DERIVED from the single eps_px knob — build only as fine as a cell
	// renders. A size-s cell at distance d projects to ~s·proj/d px, = eps_px at s = eps_px·d/proj, so
	// floor_k = eps_px/proj. No separate dial: the budget controller drives eps_px (start coarse, tighten to
	// the frame/WORK budget) and the floor follows. (proj==0 → no camera → uniform fine.)
	double floor_k = (proj > 0.0 && eps_px > 0.0) ? eps_px / proj : 0.0;
	_persist->world_src.cam = camera;
	_persist->world_src.floor_k = floor_k;
	if (win_min != win_max) {
		oct.build_box = true;
		oct.window_mode = true;
		oct.build_min = win_min;
		oct.build_max = win_max;
		// Bake the surface-sparse accel (P1+P2) over the window and turn the prune on. Uniform (floor_k==0)
		// → one res-1 level covering the window; graded → concentric levels (fine near camera, coarse far),
		// so a large window stays affordable.
		uint64_t ta0 = OS::get_singleton()->get_ticks_usec();
		_persist->world_src.bake_accel(win_min - world_origin, win_max - world_origin, camera, floor_k);
		_last_accel_ms = double(OS::get_singleton()->get_ticks_usec() - ta0) / 1000.0;
		oct.prune_safety = 1.0;
	} else {
		_last_accel_ms = 0.0;
	}
	oct.run();

	_last_build_ms    = double(oct.last_build_us)    / 1000.0;
	_last_collapse_ms = double(oct.last_collapse_us) / 1000.0;
	_last_construct_ms = double(oct.last_construct_us) / 1000.0;
	_last_sample_ms    = double(oct.last_sample_us)    / 1000.0;
	_last_accum_ms     = double(oct.last_accum_us)     / 1000.0;
	_last_collapse_pass_ms = double(oct.last_collapse_pass_us) / 1000.0;
	_last_tri_owners      = oct.tri_owners;
	_last_tri_owner_sizes = oct.tri_owner_sizes;
	_last_tri_owner_errors = oct.tri_owner_errors;
	_last_build_samples   = oct.build_samples;
	return pack_output(oct);
}

// Incremental window growth (doc 16 Stage B): re-window the RETAINED world octree (from a prior
// mesh_world) to [win_min, win_max) (WORLD lattice) — graft the cells that newly entered, sampling ONLY
// them; evict the cells that left — then re-collapse + mesh against camera/proj/eps. The interior cells
// (in both windows) keep their tree, QEFs, and vertices: a move re-samples just the leading-edge band,
// not the whole vicinity. By construction the result is byte-identical to a from-scratch mesh_world of
// the new window. Benign no-op (empty Array) if nothing is retained — caller falls back to mesh_world.
Array DCOctreeMesher::grow_world(Vector3 camera, double proj, double eps_px, Vector3i win_min, Vector3i win_max, int refine_budget, Vector3i emit_min, Vector3i emit_max) {
	if (_persist == nullptr) {
		return Array();
	}
	Octree &oct = _persist->oct;
	oct.build_box = true;
	oct.window_mode = true;
	oct.build_min = win_min;   // M (doc 20): RESIDENCY box — sampled + kept (can be larger than the view).
	oct.build_max = win_max;
	// M (doc 20): emit only the VISIBLE window [emit_min, emit_max) — the retained cells outside it stay
	// resident (no re-sample on backtrack) and pre-baked (ready when walked into), but aren't drawn. Default
	// (emit_min == emit_max) draws the whole residency box (pre-M behaviour). The emit boundary stitches to
	// the resident-but-hidden cells, so it's a clean LOD seam, not an open rim.
	oct.emit_filter = (emit_min != emit_max);
	oct.emit_min = emit_min;
	oct.emit_max = emit_max;
	// P1/P2: re-bake the accel over the NEW window so the leading-edge band is covered (an uncovered box
	// would prune the band away). Keep the build's floor_k; recentre the accel on the new camera. The
	// retained interior isn't rebuilt — its prune decisions stand (geometrically identical, empty either
	// way). NOTE: grow does not re-grade interior cells whose floor changed with the camera — that's the
	// incremental band-diff (a later increment); a graded dcworld full-rebuilds on larger moves meanwhile.
	_last_accel_ms = 0.0; // default: accel reused (no bake cost this grow)
	if (_persist->world_src.has_accel) {
		double floor_k = (proj > 0.0 && eps_px > 0.0) ? eps_px / proj : 0.0; // same single-knob derivation
		_persist->world_src.cam = camera;
		_persist->world_src.floor_k = floor_k;
		// Re-bake the prune accel only when the resident window actually moved. A stationary refine (the
		// budget controller lowering eps with the camera still) keeps the same window, so the accel from
		// the last bake still covers every queried box — reuse it (this is what lets a held view keep
		// refining cheaply, with no fixed per-grow bake cost). A move re-bakes to cover the new leading
		// edge; reusing a stale window would leave that band uncovered, and an uncovered box prunes away.
		Vector3i win_lo = win_min - oct.world_origin;
		Vector3i win_hi = win_max - oct.world_origin;
		if (win_lo != _persist->world_src.accel_win_lo || win_hi != _persist->world_src.accel_win_hi) {
			uint64_t ta0 = OS::get_singleton()->get_ticks_usec();
			_persist->world_src.bake_accel(win_lo, win_hi, camera, floor_k);
			_last_accel_ms = double(OS::get_singleton()->get_ticks_usec() - ta0) / 1000.0;
		}
		oct.prune_safety = 1.0;
	}
	oct.build_samples = 0;
	// C/P (doc 20): a stationary refine passes a finite budget so each frame refines at most that many cells
	// (the rest stay coarse, refine_pending true → caller drains over frames). A move passes -1 (unbudgeted)
	// so the window is always fully covered. Window grafts/evictions aren't budgeted — only floor refinement.
	oct.refine_budget = refine_budget;
	oct.refine_pending = false;
	oct.refine_cands.clear();
	// Set the view BEFORE reconcile: P scores each refine candidate by its on-screen size (needs camera/proj).
	oct.camera = camera;
	oct.proj = proj;
	oct.eps_px = eps_px;
	oct.level_start.clear(); // reconcile rebuilds the tree incrementally, not level-laid-out → serial collapse
	uint64_t tb0 = OS::get_singleton()->get_ticks_usec();
	oct.reconcile(0);    // graft leading edge (samples only new cells) + evict trailing edge; collect refines
	if (refine_budget >= 0) {
		oct.refine_selected(refine_budget); // C/P: refine worst-on-screen first for up to refine_budget us; defer the rest
	}
	oct.reaccumulate(0); // roll up ancestor QEFs from cached children — no field sampling
	_last_build_ms = double(OS::get_singleton()->get_ticks_usec() - tb0) / 1000.0;
	uint64_t tc0 = OS::get_singleton()->get_ticks_usec();
	oct.recollapse_and_mesh();
	_last_collapse_ms = double(OS::get_singleton()->get_ticks_usec() - tc0) / 1000.0;
	_last_tri_owners      = oct.tri_owners;
	_last_tri_owner_sizes = oct.tri_owner_sizes;
	_last_tri_owner_errors = oct.tri_owner_errors;
	_last_build_samples   = oct.build_samples;
	return pack_output(oct);
}

// Incremental EDIT (doc 20 E): the retained window is unchanged but the EditStore field changed inside
// [dirty_min, dirty_max) (WORLD lattice). Re-bake the accel over the resident window (its min/max mips are
// stale over the edit — a newly added surface would otherwise be pruned away), reconcile ONLY the edited box
// (force-resample its present leaves, refine where surface appeared, coarsen where it vanished), roll up, and
// recollapse+mesh. The surface equals a fresh mesh_world of the edited field, but only the edit box is
// re-sampled — not the whole window (the move-path's no-resample property, extended to field changes). Empty
// Array if no world octree is retained (caller falls back to mesh_world). camera/proj/eps are the current
// view (unchanged by a pure edit; passed so a re-bake/collapse uses the live operating point).
Array DCOctreeMesher::edit_world(Ref<EditStore> store, Vector3 camera, double proj, double eps_px, Vector3i dirty_min, Vector3i dirty_max) {
	if (_persist == nullptr || store.is_null()) {
		return Array();
	}
	// Re-point the retained source at the CURRENT store snapshot (it includes the edit). The cached QEFs
	// outside the edit box still agree with it (the field there is unchanged); reconcile_edit re-samples
	// the box against this store. A later grow_world also reads this snapshot — the retained source follows.
	_persist->world_store = store;
	_persist->world_src.store = store.ptr();
	Octree &oct = _persist->oct;
	_last_accel_ms = 0.0;
	if (_persist->world_src.has_accel) {
		double floor_k = (proj > 0.0 && eps_px > 0.0) ? eps_px / proj : 0.0;
		_persist->world_src.cam = camera;
		_persist->world_src.floor_k = floor_k;
		uint64_t ta0 = OS::get_singleton()->get_ticks_usec();
		// Re-bake over the SAME window the last build/grow covered (octree-local, stored on the source).
		_persist->world_src.bake_accel(_persist->world_src.accel_win_lo, _persist->world_src.accel_win_hi, camera, floor_k);
		_last_accel_ms = double(OS::get_singleton()->get_ticks_usec() - ta0) / 1000.0;
	}
	oct.field_dirty = true;
	// Pad by one cell: a DC cell's QEF samples its 12 edges' CORNERS, so a cell whose body sits just outside
	// the changed-field box still has a corner ON the box face that moved — its QEF changed and it must be
	// re-sampled too. One lattice unit covers a corner-on-boundary touch for a cell of any size; over-
	// inclusion is safe (re-sampling an unchanged cell yields the same value). Caller passes the field box.
	oct.field_dirty_min = dirty_min - Vector3i(1, 1, 1);
	oct.field_dirty_max = dirty_max + Vector3i(1, 1, 1);
	oct.build_samples = 0;
	oct.level_start.clear(); // reconcile path: the tree isn't level-laid-out → serial collapse
	uint64_t tb0 = OS::get_singleton()->get_ticks_usec();
	oct.reconcile_edit(0); // walk only the edited box — samples only its band
	oct.reaccumulate(0);   // roll up ancestor QEFs from cached children — no field sampling
	_last_build_ms = double(OS::get_singleton()->get_ticks_usec() - tb0) / 1000.0;
	oct.field_dirty = false;
	oct.camera = camera;
	oct.proj = proj;
	oct.eps_px = eps_px;
	uint64_t tc0 = OS::get_singleton()->get_ticks_usec();
	oct.recollapse_and_mesh();
	_last_collapse_ms = double(OS::get_singleton()->get_ticks_usec() - tc0) / 1000.0;
	_last_tri_owners      = oct.tri_owners;
	_last_tri_owner_sizes = oct.tri_owner_sizes;
	_last_tri_owner_errors = oct.tri_owner_errors;
	_last_build_samples   = oct.build_samples;
	return pack_output(oct);
}

// Total slots in the retained octree's cell array (live + free). With B1b's free-list this plateaus
// across a long traverse (evicted slots reused), instead of growing every move — the bound the test gates.
int DCOctreeMesher::get_octree_cell_count() const {
	return _persist != nullptr ? int(_persist->oct.cells.size()) : 0;
}

bool DCOctreeMesher::get_refine_pending() const {
	return _persist != nullptr && _persist->oct.refine_pending;
}

int DCOctreeMesher::get_accel_bake_count() const {
	return _persist != nullptr ? _persist->world_src.bake_count : 0;
}

void DCOctreeMesher::set_thread_count(int n) {
	g_mesh_threads = CLAMP(n, 1, 256);
}

int DCOctreeMesher::get_thread_count() const {
	return g_mesh_threads;
}

void DCOctreeMesher::_bind_methods() {
	ClassDB::bind_method(
			D_METHOD("mesh_clipmap", "level_data", "dim", "level_origins", "level_cells", "center", "half0", "depth",
					"camera", "proj", "eps_px", "error_driven", "lattice_world_origin", "level_indices", "palette",
					"uniform_core", "prune_safety", "emit_min", "emit_max", "build_min", "build_max"),
			&DCOctreeMesher::mesh_clipmap,
			DEFVAL(Vector3()), DEFVAL(0.0), DEFVAL(0.0), DEFVAL(false), DEFVAL(Vector3i()),
			DEFVAL(TypedArray<PackedByteArray>()), DEFVAL(PackedColorArray()), DEFVAL(false), DEFVAL(0.0),
			DEFVAL(Vector3i()), DEFVAL(Vector3i()), DEFVAL(Vector3i()), DEFVAL(Vector3i()));
	ClassDB::bind_method(
			D_METHOD("mesh_world", "store", "world_origin", "depth", "base_cell",
					"camera", "proj", "eps_px", "error_driven", "palette", "win_min", "win_max"),
			&DCOctreeMesher::mesh_world,
			DEFVAL(Vector3()), DEFVAL(0.0), DEFVAL(0.0), DEFVAL(false), DEFVAL(PackedColorArray()),
			DEFVAL(Vector3i()), DEFVAL(Vector3i()));
	ClassDB::bind_method(
			D_METHOD("grow_world", "camera", "proj", "eps_px", "win_min", "win_max", "refine_budget", "emit_min", "emit_max"),
			&DCOctreeMesher::grow_world, DEFVAL(-1), DEFVAL(Vector3i()), DEFVAL(Vector3i()));
	ClassDB::bind_method(D_METHOD("get_refine_pending"), &DCOctreeMesher::get_refine_pending);
	ClassDB::bind_method(
			D_METHOD("edit_world", "store", "camera", "proj", "eps_px", "dirty_min", "dirty_max"),
			&DCOctreeMesher::edit_world);
	ClassDB::bind_method(D_METHOD("remesh", "camera", "proj", "eps_px"), &DCOctreeMesher::remesh);
	ClassDB::bind_method(D_METHOD("get_last_build_sample_count"), &DCOctreeMesher::get_last_build_sample_count);
	ClassDB::bind_method(D_METHOD("get_octree_cell_count"),      &DCOctreeMesher::get_octree_cell_count);
	ClassDB::bind_method(D_METHOD("get_accel_bake_count"),       &DCOctreeMesher::get_accel_bake_count);
	ClassDB::bind_method(D_METHOD("get_last_triangle_owners"),      &DCOctreeMesher::get_last_triangle_owners);
	ClassDB::bind_method(D_METHOD("get_last_triangle_owner_sizes"), &DCOctreeMesher::get_last_triangle_owner_sizes);
	ClassDB::bind_method(D_METHOD("get_last_triangle_owner_errors"), &DCOctreeMesher::get_last_triangle_owner_errors);
	ClassDB::bind_method(D_METHOD("get_last_accel_ms"),    &DCOctreeMesher::get_last_accel_ms);
	ClassDB::bind_method(D_METHOD("get_last_build_ms"),    &DCOctreeMesher::get_last_build_ms);
	ClassDB::bind_method(D_METHOD("get_last_collapse_ms"), &DCOctreeMesher::get_last_collapse_ms);
	ClassDB::bind_method(D_METHOD("get_last_construct_ms"), &DCOctreeMesher::get_last_construct_ms);
	ClassDB::bind_method(D_METHOD("get_last_sample_ms"),    &DCOctreeMesher::get_last_sample_ms);
	ClassDB::bind_method(D_METHOD("get_last_accum_ms"),     &DCOctreeMesher::get_last_accum_ms);
	ClassDB::bind_method(D_METHOD("get_last_collapse_pass_ms"), &DCOctreeMesher::get_last_collapse_pass_ms);
	ClassDB::bind_method(D_METHOD("set_thread_count", "n"), &DCOctreeMesher::set_thread_count);
	ClassDB::bind_method(D_METHOD("get_thread_count"),      &DCOctreeMesher::get_thread_count);
}
