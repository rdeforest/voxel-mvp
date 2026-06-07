#include "dc_region_reader.h"

#include "modules/voxel/generators/voxel_generator.h"
#include "modules/voxel/storage/voxel_buffer.h"
#include "modules/voxel/storage/voxel_data.h"
#include "modules/voxel/storage/voxel_data_grid.h"
#include "modules/voxel/storage/voxel_format.h"
#include "modules/voxel/terrain/variable_lod/voxel_lod_terrain.h"

using zylann::Box3i;
using zylann::voxel::VoxelBuffer;
using zylann::voxel::VoxelData;
using zylann::voxel::VoxelDataGrid;
using zylann::voxel::VoxelFormat;
using zylann::voxel::VoxelGenerator;
using zylann::voxel::VoxelLodTerrain;

void DCRegionReader::_bind_methods() {
	ClassDB::bind_method(
			D_METHOD("read_sdf_lod0", "terrain", "origin", "size"),
			&DCRegionReader::read_sdf_lod0);
	ClassDB::bind_method(
			D_METHOD("read_sdf_lod", "terrain", "lod", "origin", "size"),
			&DCRegionReader::read_sdf_lod);
	ClassDB::bind_method(
			D_METHOD("read_indices_lod", "terrain", "lod", "origin", "size"),
			&DCRegionReader::read_indices_lod);
}

PackedFloat32Array DCRegionReader::read_sdf_lod0(Object *p_terrain, Vector3i origin, Vector3i size) {
	return read_sdf_lod(p_terrain, 0, origin, size);
}

PackedFloat32Array DCRegionReader::read_sdf_lod(Object *p_terrain, int lod, Vector3i origin, Vector3i size) {
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
	if (lod < 0) {
		ERR_PRINT("DCRegionReader: negative lod");
		return out;
	}

	// Transient grab of the store — used and released within this call.
	std::shared_ptr<VoxelData> data = vlt->get_storage_shared();
	if (data == nullptr) {
		ERR_PRINT("DCRegionReader: terrain has no VoxelData");
		return out;
	}
	if (lod >= int(data->get_lod_count())) {
		ERR_PRINT(String("DCRegionReader: lod {0} >= lod_count {1}").format(
				varray(lod, int(data->get_lod_count()))));
		return out;
	}

	const VoxelFormat format = data->get_format();
	VoxelBuffer buffer(VoxelBuffer::ALLOCATOR_DEFAULT);
	buffer.create(size, &format);

	// Baseline. LOD0: copy() locks internally and fills unloaded cells from the
	// generator, including edits. LOD>0: generate the procedural baseline (copy()
	// is LOD0-only), then overlay edits below.
	VoxelDataGrid grid;
	if (lod == 0) {
		data->copy(origin, buffer, uint32_t(1) << VoxelBuffer::CHANNEL_SDF, false);
	} else {
		Ref<VoxelGenerator> generator = data->get_generator();
		if (generator.is_valid()) {
			VoxelGenerator::VoxelQueryData q{ buffer, origin, uint32_t(lod) };
			generator->generate_block(q);
		}
		// Present data-store blocks at this LOD carry edits as downsampled mips.
		const int step = 1 << lod;
		const Box3i world_box(origin, Vector3i(size.x * step, size.y * step, size.z * step));
		data->get_blocks_grid(grid, world_box, uint32_t(lod));
	}

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

	// Overlay edits (LOD>0). try_get_voxel_f takes LOD-voxel coords (world >> lod);
	// where a block is present its value wins over the procedural baseline.
	if (grid.has_any_block()) {
		const Vector3i base(origin.x >> lod, origin.y >> lod, origin.z >> lod);
		grid.lock_read();
		i = 0;
		for (int z = 0; z < size.z; ++z) {
			for (int y = 0; y < size.y; ++y) {
				for (int x = 0; x < size.x; ++x) {
					float v;
					if (grid.try_get_voxel_f(base + Vector3i(x, y, z), v, VoxelBuffer::CHANNEL_SDF)) {
						w[i] = v;
					}
					++i;
				}
			}
		}
		grid.unlock_read();
	}

	return out;
}

PackedByteArray DCRegionReader::read_indices_lod(Object *p_terrain, int lod, Vector3i origin, Vector3i size) {
	PackedByteArray out;
	VoxelLodTerrain *vlt = Object::cast_to<VoxelLodTerrain>(p_terrain);
	if (vlt == nullptr) {
		ERR_PRINT("DCRegionReader: terrain is not a VoxelLodTerrain");
		return out;
	}
	if (size.x <= 0 || size.y <= 0 || size.z <= 0 || lod < 0) {
		ERR_PRINT("DCRegionReader: bad size/lod");
		return out;
	}

	std::shared_ptr<VoxelData> data = vlt->get_storage_shared();
	if (data == nullptr || lod >= int(data->get_lod_count())) {
		ERR_PRINT("DCRegionReader: no VoxelData or lod out of range");
		return out;
	}

	const VoxelFormat format = data->get_format();
	VoxelBuffer buffer(VoxelBuffer::ALLOCATOR_DEFAULT);
	buffer.create(size, &format);

	// LOD0: bulk-copy the indices channel (fills unloaded cells from defaults = 0).
	// LOD>0: copy() is LOD0-only, so the baseline stays the channel default (0 =
	// natural); edits overlay below.
	if (lod == 0) {
		data->copy(origin, buffer, uint32_t(1) << VoxelBuffer::CHANNEL_INDICES, false);
	}

	const int64_t count = int64_t(size.x) * int64_t(size.y) * int64_t(size.z);
	out.resize(count);
	uint8_t *w = out.ptrw();
	int64_t i = 0;
	for (int z = 0; z < size.z; ++z) {
		for (int y = 0; y < size.y; ++y) {
			for (int x = 0; x < size.x; ++x) {
				w[i++] = uint8_t(buffer.get_voxel(x, y, z, VoxelBuffer::CHANNEL_INDICES));
			}
		}
	}

	// Overlay edited blocks at LOD>0. The grid stores downsampled mips of edits;
	// integer channels mip nearest-neighbour, so a stamped material id survives the
	// mip. VoxelDataGrid has no integer getter, so look the block up by hand (the
	// same block-location try_get_voxel_f does) and read CHANNEL_INDICES directly.
	if (lod > 0) {
		const int step = 1 << lod;
		const Box3i world_box(origin, Vector3i(size.x * step, size.y * step, size.z * step));
		VoxelDataGrid grid;
		data->get_blocks_grid(grid, world_box, uint32_t(lod));
		if (grid.has_any_block()) {
			const unsigned int po2 = grid.get_block_size_po2();
			const int bmask = (1 << po2) - 1;
			const Vector3i base(origin.x >> lod, origin.y >> lod, origin.z >> lod);
			grid.lock_read();
			i = 0;
			for (int z = 0; z < size.z; ++z) {
				for (int y = 0; y < size.y; ++y) {
					for (int x = 0; x < size.x; ++x) {
						const Vector3i p = base + Vector3i(x, y, z);
						VoxelBuffer *block = grid.get_block_no_lock(Vector3i(p.x >> po2, p.y >> po2, p.z >> po2));
						if (block != nullptr) {
							const Vector3i rpos(p.x & bmask, p.y & bmask, p.z & bmask);
							w[i] = uint8_t(block->get_voxel(rpos, VoxelBuffer::CHANNEL_INDICES));
						}
						++i;
					}
				}
			}
			grid.unlock_read();
		}
	}

	return out;
}
