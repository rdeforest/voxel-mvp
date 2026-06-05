#ifndef VOXEL_MESHER_DC_H
#define VOXEL_MESHER_DC_H

// Our per-block Dual Contouring mesher, subclassing godot_voxel's VoxelMesher and
// set as the terrain's mesher in world.tscn. build() does real DC: one QEF vertex
// per surface cell + quad emission (QEF in dc_qef.h). godot_voxel builds terrain
// COLLISION from these blocks, so this stays active even when the path-b octree
// render layer (DCTerrainManager + DCOctreeMesher) draws instead and hides this
// mesh via render_layers_mask. Per-block DC cracks at LOD boundaries (the F2
// problem) — which is why the octree layer exists for rendering.

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
