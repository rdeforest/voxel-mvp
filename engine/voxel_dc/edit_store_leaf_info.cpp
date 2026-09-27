#include "edit_store.h"

#include "octree_geometry.h"

using namespace voxel_dc;

Dictionary EditStore::leaf_info(Vector3 p) const {
	Dictionary out;
	if (nodes.is_empty() || !_inside_root(p)) {
		return out;
	}
	const int leaf = _leaf_at(p);
	const Node &n = nodes[leaf];
	PackedFloat64Array corners;
	corners.resize(8);
	for (int i = 0; i < 8; ++i) {
		corners.set(i, n.is_edited() ? double(n.corners[i]) : _gen.sample(corner(n.origin, n.size, i)));
	}
	out["origin"] = n.origin;
	out["size"] = n.size;
	out["field"] = int(n.field);
	out["corners"] = corners;
	if (n.is_edited()) {
		out["material"] = int(n.material);
	}
	if (n.field == INHERITED_FIELD) {
		out["source_origin"] = nodes[n.source].origin;
		out["source_size"] = nodes[n.source].size;
	}
	return out;
}
