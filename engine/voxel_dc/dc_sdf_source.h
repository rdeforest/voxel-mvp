#ifndef DC_SDF_SOURCE_H
#define DC_SDF_SOURCE_H

// The octree's field source abstraction. The octree doesn't care WHERE the SDF comes from — two
// implementations: the camera-centered Clipmap (dc_clipmap_source.h) and the world-fixed
// EditStoreSource (dc_edit_store_source.h).

#include "core/math/vector3.h"

namespace voxel_dc {
namespace dc_mesh {

// The octree's field source: everything the build + mesh need to know about the field, abstracted
// so the octree doesn't care WHERE the SDF comes from. Two implementations: the camera-centered
// `Clipmap` (concentric baked grids — the godot_voxel-era render path) and `EditStoreSource` (samples
// the world-fixed EditStore field directly — the world-fixed-octree substrate, doc 16 THE GOAL).
struct SdfSource {
	virtual ~SdfSource() {}
	virtual double value(const Vector3 &p) const = 0;
	virtual Vector3 gradient(const Vector3 &p) const = 0;
	virtual double target_cell_size(const Vector3 &p) const = 0;        // the data-resolution floor at p
	virtual bool surface_free(const Vector3 &cmin, const Vector3 &cmax) const = 0; // no zero-crossing in box
	virtual int index_prefer_explicit(const Vector3 &p, const Vector3 &n) const = 0; // material id behind a vertex
	virtual bool is_finest_level(const Vector3 &p) const = 0;           // for uniform_core (pin the fine bubble)
};

} // namespace dc_mesh
} // namespace voxel_dc

#endif // DC_SDF_SOURCE_H
