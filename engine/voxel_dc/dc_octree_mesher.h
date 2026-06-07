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
			Vector3i lattice_world_origin = Vector3i());

protected:
	static void _bind_methods();
};

#endif // DC_OCTREE_MESHER_H
