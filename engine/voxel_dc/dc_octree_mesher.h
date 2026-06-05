#ifndef DC_OCTREE_MESHER_H
#define DC_OCTREE_MESHER_H

// Octree Dual Contouring over a multi-LOD clipmap, in C++ for speed. This is the
// path-b "own meshing layer": DCTerrainManager reads nested baked SDF levels from
// the terrain, hands them here, and we build ONE adaptive octree spanning the
// camera vicinity and mesh it crack-free (minimal-edge enumeration with octree
// point-location). A C++ port of scripts/dc/{sdf_baked,sdf_clipmap,octree_dc}.gd:
// the GDScript versions stay as the prototype / preview / test mesher.

#include "core/object/ref_counted.h"
#include "core/variant/typed_array.h"

class DCOctreeMesher : public RefCounted {
	GDCLASS(DCOctreeMesher, RefCounted)

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
	Array mesh_clipmap(
			const TypedArray<PackedFloat32Array> &level_data,
			int dim,
			const PackedVector3Array &level_origins,
			const PackedFloat32Array &level_cells,
			Vector3 center,
			double half0,
			int depth);

protected:
	static void _bind_methods();
};

#endif // DC_OCTREE_MESHER_H
