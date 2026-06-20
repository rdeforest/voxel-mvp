#ifndef DC_OCTREE_MESHER_H
#define DC_OCTREE_MESHER_H

// Octree Dual Contouring in C++. One crack-free adaptive-octree mesher (minimal-edge
// enumeration with octree point-location) behind two entry points: mesh_world — the live
// terrain render (DcWorldPreview), one octree over a world box sampling the EditStore
// directly — and mesh_clipmap, which meshes nested baked SDF levels (collision, falling
// chunks, and the trusted reference mesher in tests). Covered by test_dc_world_octree.gd,
// test_dc_octree_mesher.gd, test_dc_real_terrain.gd.

#include "edit_store.h"

#include "core/math/vector4i.h"
#include "core/object/ref_counted.h"
#include "core/templates/hash_set.h"
#include "core/variant/typed_array.h"

struct DCOctreePersist; // the retained octree (Octree is .cpp-local), kept across remesh()/grow_world()

class DCOctreeMesher : public RefCounted {
	GDCLASS(DCOctreeMesher, RefCounted)

	// The last full build's octree (tree + per-node QEFs + field snapshot), kept alive so remesh()
	// can re-decide collapse against a new camera without re-sampling. Null until the first build.
	DCOctreePersist *_persist = nullptr;

	// Per-triangle owner cell origin (WORLD lattice) of the last mesh call. One Vector3
	// (integer-valued) per emitted triangle; read by the dcinval LOD diagnostic overlay.
	PackedVector3Array  _last_tri_owners;

	// Parallel to _last_tri_owners: the owner cell's SIZE (in base-cell lattice units) for
	// each triangle — the cell size each triangle was meshed at.
	PackedFloat32Array  _last_tri_owner_sizes;

	// Leaves whose Hermite data was sampled by the last build/grow (the field-derived build cost). After a
	// grow_world this counts ONLY the leading-edge band — proof the retained interior was not resampled.
	int _last_build_samples = 0;

	// Phase timing for the last mesh_world or grow_world call (milliseconds).
	// _last_accel_ms  = time spent in bake_accel (0 when the accel was reused in grow_world).
	// _last_build_ms  = time spent in the build/reconcile + reaccumulate pass (field sampling).
	// _last_collapse_ms = time spent in recollapse_and_mesh (collapse + triangle emit).
	double _last_accel_ms   = 0.0;
	double _last_build_ms   = 0.0;
	double _last_collapse_ms = 0.0;

	// Breakdown of _last_build_ms (mesh_world only): tree construction (serial), leaf sampling
	// (parallel — the dominant field cost), QEF roll-up (serial). Pinpoints the Amdahl ceiling.
	double _last_construct_ms = 0.0;
	double _last_sample_ms    = 0.0;
	double _last_accum_ms     = 0.0;
	double _last_collapse_pass_ms = 0.0;

public:
	~DCOctreeMesher();

	// Re-walk the retained octree (from the last full mesh_clipmap) against a new camera/proj/eps and
	// re-mesh — no rebuild, no field sampling. The Stage 2 movement path: collapse is re-decided per
	// node from the cached QEFs, only the changed cells flip. Empty Array if no build is retained.
	Array remesh(Vector3 camera, double proj, double eps_px);

	// Mesh nested baked SDF levels (finest first) into a Mesh.ARRAY_* array, empty if the region
	// has no surface. Lattice space = 1 unit/metre; the caller positions the mesh at the origin.
	// error_driven coarsens by screen-space error (eps_px); the data resolution is the floor. With
	// level_indices + palette, each vertex carries an ARRAY_COLOR whose alpha picks material-colour
	// (a=0) vs slope-shading (a=1, the default). Input layout, the LOD math, and the colour
	// convention live in docs/roadmap/design/03-dc-qef-geometry.md.
	Array mesh_clipmap(
			const TypedArray<PackedFloat32Array> &level_data,
			int dim,
			const PackedVector3Array &level_origins,
			const PackedFloat32Array &level_cells,
			Vector3 center,
			double half0,
			int depth,
			Vector3 camera = Vector3(),
			double proj = 0.0,
			double eps_px = 0.0,
			bool error_driven = false,
			Vector3i lattice_world_origin = Vector3i(),
			const TypedArray<PackedByteArray> &level_indices = TypedArray<PackedByteArray>(),
			const PackedColorArray &palette = PackedColorArray(),
			bool uniform_core = false,
			double prune_safety = 0.0,
			Vector3i emit_min = Vector3i(),
			Vector3i emit_max = Vector3i(),
			Vector3i build_min = Vector3i(),
			Vector3i build_max = Vector3i());

	// World-fixed octree (doc 16 THE GOAL, scaffold): build + mesh ONE octree over the world-aligned
	// box [world_origin, world_origin + 2^depth) in lattice units (1 unit = base_cell metres), sampling
	// the EditStore field (generator + edits) DIRECTLY per cell — no concentric clipmap, no geomorph.
	// Bottom-up exact (build to floor where there's surface, accumulate fine QEF, collapse by screen
	// error). camera is the viewpoint in this lattice frame; proj = viewport_height / (2*tan(fov/2)).
	// Returns Mesh.ARRAY_* (lattice-local). This IS the live terrain render (DcWorldPreview).
	Array mesh_world(
			Ref<EditStore> store,
			Vector3i world_origin,
			int depth,
			double base_cell,
			Vector3 camera = Vector3(),
			double proj = 0.0,
			double eps_px = 0.0,
			bool error_driven = false,
			const PackedColorArray &palette = PackedColorArray(),
			Vector3i win_min = Vector3i(), // resident window (WORLD lattice); win_min == win_max ⇒ whole root
			Vector3i win_max = Vector3i());// graded data floor (eps_px/proj) is derived internally — one knob

	// Incremental window growth (doc 16 Stage B): re-window the RETAINED world octree (from a prior
	// mesh_world) — graft cells newly in [win_min, win_max), sampling only them; evict cells that left;
	// re-collapse + mesh against camera/proj/eps. Byte-identical to a fresh mesh_world of the new window,
	// but the interior is reused (not resampled). Empty Array if no world octree is retained.
	Array grow_world(Vector3 camera, double proj, double eps_px, Vector3i win_min, Vector3i win_max);

	// Incremental edit (doc 20 E): re-mesh the RETAINED world octree after the EditStore field changed inside
	// [dirty_min, dirty_max) (WORLD lattice), with the window unchanged. Re-samples only the edit box (not the
	// whole window), then re-collapses + meshes against camera/proj/eps. Surface-identical to a fresh
	// mesh_world of the edited field. Empty Array if no world octree is retained (caller falls back to build).
	Array edit_world(Ref<EditStore> store, Vector3 camera, double proj, double eps_px, Vector3i dirty_min, Vector3i dirty_max);

	// Field-sampled leaf count of the last build/grow — after grow_world, just the leading-edge band.
	int get_last_build_sample_count() const { return _last_build_samples; }

	// Total slots in the retained octree's cell array (live + free-list). Bounded across a traverse (B1b).
	int get_octree_cell_count() const;

	// Full prune-accel bakes run so far. grow_world reuses the accel (doesn't bump this) when the
	// resident window is unchanged — e.g. a stationary refine — so a held view refines without re-baking.
	int get_accel_bake_count() const;

	// Phase timing for the last mesh_world / grow_world (milliseconds). Read these after the call
	// to see where the build's time goes: accel bake vs field sampling vs collapse + mesh emit.
	double get_last_accel_ms()    const { return _last_accel_ms;    }
	double get_last_build_ms()    const { return _last_build_ms;    }
	double get_last_collapse_ms() const { return _last_collapse_ms; }

	double get_last_construct_ms() const { return _last_construct_ms; }
	double get_last_sample_ms()    const { return _last_sample_ms;    }
	double get_last_accum_ms()     const { return _last_accum_ms;     }
	double get_last_collapse_pass_ms() const { return _last_collapse_pass_ms; }

	// Parallel worker count for the build's parallel phases (construct / sample / accumulate / collapse /
	// emit / accel-bake). 1 = serial. Output is deterministic and identical regardless of the count.
	void set_thread_count(int n);
	int  get_thread_count() const;

	// Per-triangle owner cell origins (WORLD lattice) from the last mesh call — same order/count
	// as the returned ARRAY_INDEX divided by 3.
	PackedVector3Array get_last_triangle_owners()      const { return _last_tri_owners; }
	// Parallel to get_last_triangle_owners(): one float per triangle = owner cell size (lattice
	// units) — the LOD each triangle was meshed at, used by the dcinval diagnostic.
	PackedFloat32Array get_last_triangle_owner_sizes() const { return _last_tri_owner_sizes; }

protected:
	static void _bind_methods();
};

#endif // DC_OCTREE_MESHER_H
