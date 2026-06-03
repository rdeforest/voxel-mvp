#ifndef VOXEL_MESHER_DC_H
#define VOXEL_MESHER_DC_H

// Our Dual Contouring mesher as a Godot module, subclassing godot_voxel's
// VoxelMesher. F0 stage: a plumbing proof — build() emits a cube per surface-
// straddling block (no DC yet), to validate the module compiles, links against
// godot_voxel, registers, and is driven by VoxelLodTerrain. F1 replaces build()
// with real Dual Contouring.

#include "modules/voxel/meshers/voxel_mesher.h"

using zylann::voxel::VoxelMesher;

class VoxelMesherDC : public VoxelMesher {
	GDCLASS(VoxelMesherDC, VoxelMesher)

public:
	VoxelMesherDC();

	void build(Output &output, const Input &input) override;
	int get_used_channels_mask() const override;
	bool supports_lod() const override { return true; }

protected:
	static void _bind_methods() {}
};

#endif // VOXEL_MESHER_DC_H
