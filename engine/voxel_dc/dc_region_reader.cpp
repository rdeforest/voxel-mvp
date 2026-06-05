#include "dc_region_reader.h"

#include "modules/voxel/storage/voxel_buffer.h"
#include "modules/voxel/storage/voxel_data.h"
#include "modules/voxel/storage/voxel_format.h"
#include "modules/voxel/terrain/variable_lod/voxel_lod_terrain.h"

using zylann::voxel::VoxelBuffer;
using zylann::voxel::VoxelData;
using zylann::voxel::VoxelFormat;
using zylann::voxel::VoxelLodTerrain;

void DCRegionReader::_bind_methods() {
	ClassDB::bind_method(
			D_METHOD("read_sdf_lod0", "terrain", "origin", "size"),
			&DCRegionReader::read_sdf_lod0);
}

PackedFloat32Array DCRegionReader::read_sdf_lod0(Object *p_terrain, Vector3i origin, Vector3i size) {
	PackedFloat32Array out;
	VoxelLodTerrain *vlt = Object::cast_to<VoxelLodTerrain>(p_terrain);
	if (vlt == nullptr) {
		ERR_PRINT(String("DCRegionReader: terrain is not a VoxelLodTerrain; class=") +
				(p_terrain != nullptr ? p_terrain->get_class() : String("<null>")));
		return out;
	}
	if (size.x <= 0 || size.y <= 0 || size.z <= 0) {
		ERR_PRINT("DCRegionReader: non-positive size");
		return out;
	}

	// Transient grab of the store — used and released within this call.
	std::shared_ptr<VoxelData> data = vlt->get_storage_shared();
	if (data == nullptr) {
		ERR_PRINT("DCRegionReader: terrain has no VoxelData");
		return out;
	}

	const VoxelFormat format = data->get_format();
	VoxelBuffer buffer(VoxelBuffer::ALLOCATOR_DEFAULT);
	buffer.create(size, &format);
	// copy() locks internally and fills unloaded cells from the generator.
	data->copy(origin, buffer, uint32_t(1) << VoxelBuffer::CHANNEL_SDF, false);

	const int64_t count = int64_t(size.x) * int64_t(size.y) * int64_t(size.z);
	out.resize(count);
	float *w = out.ptrw();
	int64_t i = 0;
	for (int z = 0; z < size.z; ++z) {
		for (int y = 0; y < size.y; ++y) {
			for (int x = 0; x < size.x; ++x) {
				w[i++] = float(buffer.get_voxel_f(x, y, z, VoxelBuffer::CHANNEL_SDF));
			}
		}
	}
	return out;
}
