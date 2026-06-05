#include "register_types.h"

#include "core/object/class_db.h"

#include "dc_octree_mesher.h"
#include "dc_region_reader.h"
#include "voxel_mesher_dc.h"

// Module name is `voxel_dc`; Godot generates calls to these by that name. It
// sorts after `voxel`, so VoxelMesher is registered before we subclass it.
void initialize_voxel_dc_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	ClassDB::register_class<VoxelMesherDC>();
	ClassDB::register_class<DCRegionReader>();
	ClassDB::register_class<DCOctreeMesher>();
}

void uninitialize_voxel_dc_module(ModuleInitializationLevel p_level) {
}
