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
	// array in x-fastest order (matching SdfBaked's indexing). Empty on bad args.
	PackedFloat32Array read_sdf_lod0(Object *p_terrain, Vector3i origin, Vector3i size);

protected:
	static void _bind_methods();
};

#endif // DC_REGION_READER_H
