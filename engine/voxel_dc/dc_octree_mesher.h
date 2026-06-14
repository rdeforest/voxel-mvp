#ifndef DC_OCTREE_MESHER_H
#define DC_OCTREE_MESHER_H

// Octree Dual Contouring over a multi-LOD clipmap, in C++ for speed. This is the
// "own meshing layer": DCTerrainManager reads nested baked SDF levels from the
// terrain, hands them here, and we build ONE adaptive octree spanning the camera
// vicinity and mesh it crack-free (minimal-edge enumeration with octree
// point-location). This is the production terrain mesher; covered by
// test/test_dc_octree_mesher.gd and test/test_dc_real_terrain.gd.

#include "core/math/vector4i.h"
#include "core/object/ref_counted.h"
#include "core/templates/hash_set.h"
#include "core/variant/typed_array.h"

class DCOctreeMesher : public RefCounted {
	GDCLASS(DCOctreeMesher, RefCounted)

	// Persistent across calls (reuse the SAME instance): the world-space nodes that
	// collapsed last frame, keyed Vector4i(world_origin.xyz, size). Hysteresis reads
	// this to keep an already-collapsed node collapsed until its error clearly exceeds
	// the threshold — so cells don't oscillate collapsed<->subdivided as the camera
	// moves (the LOD popping). Keyed by WORLD origin so the keys survive the clipmap's
	// periodic recenter snap. Only touched inside mesh_clipmap; one job at a time.
	HashSet<Vector4i> _prev_collapse;
	HashSet<Vector4i> _curr_collapse;

	// Per-triangle owner cell origin (WORLD lattice) of the last mesh_clipmap/mesh_subregion
	// call — lets the incremental path know which cached triangles a re-meshed sub-box
	// replaces. One Vector3 (integer-valued) per emitted triangle.
	PackedVector3Array  _last_tri_owners;
	// Parallel to _last_tri_owners: the owner cell's SIZE (in base-cell lattice units) for
	// each triangle. The B1 splice reads the max owner size in the edit box to align its
	// sub-box to whole cells at the local displayed resolution (the alignment trap fix).
	PackedFloat32Array  _last_tri_owner_sizes;

public:
	// Mesh a clipmap of nested baked SDF levels (finest first) into a Mesh.ARRAY_*
	// array (VERTEX/NORMAL/INDEX), or an empty Array if the region has no surface.
	// Everything is in the octree's lattice space (1 unit = 1 world metre); the
	// caller positions the resulting mesh at the region origin.
	//
	// level k: data = level_data[k] (flat float grid, x-fastest, dim^3); lattice
	// origin = level_origins[k]; cell size = level_cells[k]. Clipmap centre
	// `center`; level-0 half-extent `half0` (level k half-extent = half0 * 2^k).
	// The octree root is the cube [0, 2^depth]^3.
	// error_driven: refine by screen-space error instead of distance bands. A node
	// stops subdividing (coarsens) once its QEF fit error, projected to screen, is
	// below eps_px — so flat regions mesh coarse, detail stays fine. camera is the
	// viewpoint in lattice space; proj = viewport_height / (2*tan(fov/2)) (so screen
	// error = world_error * proj / distance). The data resolution (clipmap level) is
	// still the floor — error-refine only coarsens, never exceeds available data.
	// lattice_world_origin: world coords of lattice (0,0,0); makes the hysteresis keys
	// world-stable across the clipmap's recenter snap. Only used when error_driven.
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
			bool incremental = false,
			int max_leaf = 0);

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
