#ifndef DC_REGION_READER_H
#define DC_REGION_READER_H

// Fast bulk read of a terrain SDF region, for the F2 "own meshing layer" (path b).
// Uses VoxelData::copy() — one locked C++ bulk copy — instead of GDScript
// per-voxel get_voxel_f calls, which are far too slow for camera-sized regions.
//
// The voxel store is accessed TRANSIENTLY (fetched, used, released within the
// call). The spike found that HOLDING a shared_ptr<VoxelData> in a long-lived
// object crashes the running engine; a transient grab is safe.

#include "core/math/vector3i.h"
#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

class DCRegionReader : public RefCounted {
	GDCLASS(DCRegionReader, RefCounted)

public:
	// Read CHANNEL_SDF over the box [origin, origin + size) at LOD0 into a flat
	// array in x-fastest order. Empty on bad args.
	PackedFloat32Array read_sdf_lod0(Object *p_terrain, Vector3i origin, Vector3i size);

	// Read CHANNEL_SDF at an arbitrary LOD. `origin` is in LOD0/world voxels (pass
	// a multiple of 1<<lod); `size` is the sample count per axis; each sample spans
	// 1<<lod world units (the clipmap level's cell size). Edit-inclusive: the
	// procedural generator fills the baseline, then any present data-store blocks
	// at that LOD (where edits live as downsampled mips) overlay it. lod==0 routes
	// to the LOD0 copy() path. Flat array, x-fastest. Empty on bad args.
	PackedFloat32Array read_sdf_lod(Object *p_terrain, int lod, Vector3i origin, Vector3i size);

protected:
	static void _bind_methods();
};

#endif // DC_REGION_READER_H
