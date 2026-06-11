#include "register_types.h"

#include "core/object/class_db.h"

#include "dc_octree_mesher.h"
#include "edit_store.h"
#include "pbd_sim.h"
#include "sparse_voxel_octree.h"

// Module name is `voxel_dc`; Godot generates calls to these by that name.
void initialize_voxel_dc_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	ClassDB::register_class<DCOctreeMesher>();
	ClassDB::register_class<PbdSim>();
	ClassDB::register_class<SparseVoxelOctree>();
	ClassDB::register_class<EditStore>();
}

void uninitialize_voxel_dc_module(ModuleInitializationLevel p_level) {
}
