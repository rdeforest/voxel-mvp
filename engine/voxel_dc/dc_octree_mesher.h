#ifndef DC_OCTREE_MESHER_H
#define DC_OCTREE_MESHER_H

// Octree Dual Contouring over a multi-LOD clipmap, in C++ for speed. This is the
// "own meshing layer": DCTerrainManager reads nested baked SDF levels from the
// terrain, hands them here, and we build ONE adaptive octree spanning the camera
// vicinity and mesh it crack-free (minimal-edge enumeration with octree
// point-location). This is the production terrain mesher; covered by
// test/test_dc_octree_mesher.gd and test/test_dc_real_terrain.gd.

#include "edit_store.h"

#include "core/math/vector4i.h"
#include "core/object/ref_counted.h"
#include "core/templates/hash_set.h"
#include "core/variant/typed_array.h"

struct DCOctreePersist; // pimpl: the retained octree (Octree is .cpp-local) — see remesh()

class DCOctreeMesher : public RefCounted {
	GDCLASS(DCOctreeMesher, RefCounted)

	// The last full build's octree (tree + per-node QEFs + field snapshot), kept alive so remesh()
	// can re-decide collapse against a new camera without re-sampling. Null until the first build.
	DCOctreePersist *_persist = nullptr;

	// Per-triangle owner cell origin (WORLD lattice) of the last mesh_clipmap/mesh_subregion
	// call — lets the incremental path know which cached triangles a re-meshed sub-box
	// replaces. One Vector3 (integer-valued) per emitted triangle.
	PackedVector3Array  _last_tri_owners;
	// Parallel to _last_tri_owners: the owner cell's SIZE (in base-cell lattice units) for
	// each triangle. The B1 splice reads the max owner size in the edit box to align its
	// sub-box to whole cells at the local displayed resolution (the alignment trap fix).
	PackedFloat32Array  _last_tri_owner_sizes;

	// Leaves whose Hermite data was sampled by the last build/grow (the field-derived build cost). After a
	// grow_world this counts ONLY the leading-edge band — proof the retained interior was not resampled.
	int _last_build_samples = 0;

public:
	~DCOctreeMesher();

	// Re-walk the retained octree (from the last full mesh_clipmap) against a new camera/proj/eps and
	// re-mesh — no rebuild, no field sampling. The Stage 2 movement path: collapse is re-decided per
	// node from the cached QEFs, only the changed cells flip. Empty Array if no build is retained.
	Array remesh(Vector3 camera, double proj, double eps_px);

	// Mesh a clipmap of nested baked SDF levels (finest first) into a Mesh.ARRAY_*
	// array (VERTEX/NORMAL/INDEX), or an empty Array if the region has no surface.
	// Everything is in the octree's lattice space (1 unit = 1 world metre); the
	// caller positions the resulting mesh at the region origin.
	//
	// level k: data = level_data[k] (flat float grid, x-fastest, dim^3); lattice
	// origin = level_origins[k]; cell size = level_cells[k]. Clipmap centre
	// `center`; level-0 half-extent `half0` (level k half-extent = half0 * 2^k).
	// The octree root is the cube [0, 2^depth]^3.
	// error_driven: coarsen by SCREEN-SPACE ERROR — a node stops subdividing once its
	// accumulated QEF fit error, projected to pixels (we * proj / dist), drops to eps_px,
	// so a feature coarsens as it recedes and a narrow FOV (telescope) refines distant
	// terrain. camera is the viewpoint in root-local lattice space; proj = viewport_height
	// / (2*tan(fov/2)). The data resolution (clipmap level) is still the floor — error-LOD
	// only coarsens, never exceeds available data.
	// lattice_world_origin: world coords of lattice (0,0,0); converts a cell's local
	// origin to its world position for the emit/build boxes.
	// level_indices: optional per-level CHANNEL_INDICES bytes (same layout/order as
	// level_data); palette: material id -> albedo Color (index 0 = natural). When
	// both are supplied, each output vertex gets an ARRAY_COLOR: rgb = palette[id]
	// of the solid cell behind the vertex, with a = 0 for an explicit material and
	// a = 1 for natural terrain. The shader reads alpha to choose the material colour
	// vs slope-shading; a=1 is also the default for meshes with no colour array, so
	// godot_voxel's own per-block meshes stay slope-shaded. Empty arrays = no colours
	// emitted (back-compat with the tests' calls).
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

	// Incremental edit patch: mesh a small UNIFORM (1 m) cube [sub_origin, sub_origin+sub_size]
	// from a fresh SDF grid, emitting ONLY the triangles owned by cells whose origin lies in
	// the world box [core_min, core_max). The cube must be a couple cells larger than the core
	// on every side (apron) so boundary quads stitch and land on UNCHANGED vertices — then the
	// patch splices into the cached full mesh crack-free (the uniform 1 m fine core guarantees
	// the same per-cell vertices the full build produced). Returns Mesh.ARRAY_* (lattice-local
	// to sub_origin); pair with get_last_triangle_owners() for the per-triangle owner box test.
	Array mesh_subregion(
			const PackedFloat32Array &data,
			int dim,
			Vector3 data_origin,
			double cell,
			Vector3i sub_origin,
			int sub_size,
			Vector3i core_min,
			Vector3i core_max,
			const PackedByteArray &indices = PackedByteArray(),
			const PackedColorArray &palette = PackedColorArray());

	// World-fixed octree (doc 16 THE GOAL, scaffold): build + mesh ONE octree over the world-aligned
	// box [world_origin, world_origin + 2^depth) in lattice units (1 unit = base_cell metres), sampling
	// the EditStore field (generator + edits) DIRECTLY per cell — no concentric clipmap, no geomorph.
	// Bottom-up exact (build to floor where there's surface, accumulate fine QEF, collapse by screen
	// error). camera is the viewpoint in this lattice frame; proj = viewport_height / (2*tan(fov/2)).
	// Returns Mesh.ARRAY_* (lattice-local). The world-fixed substrate the live clipmap render migrates to.
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

	// Field-sampled leaf count of the last build/grow — after grow_world, just the leading-edge band.
	int get_last_build_sample_count() const { return _last_build_samples; }

	// Total slots in the retained octree's cell array (live + free-list). Bounded across a traverse (B1b).
	int get_octree_cell_count() const;

	// Per-triangle owner cell origins (WORLD lattice) from the last mesh call — same order/count
	// as the returned ARRAY_INDEX divided by 3.
	PackedVector3Array get_last_triangle_owners()      const { return _last_tri_owners; }
	// Parallel to get_last_triangle_owners(): one float per triangle = owner cell size (lattice
	// units). Used by the B1 splice to find the max displayed cell size in the edit box so it can
	// align its sub-box to whole cells at the local LOD.
	PackedFloat32Array get_last_triangle_owner_sizes() const { return _last_tri_owner_sizes; }

protected:
	static void _bind_methods();
};

#endif // DC_OCTREE_MESHER_H
