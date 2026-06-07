#ifndef SPARSE_VOXEL_OCTREE_H
#define SPARSE_VOXEL_OCTREE_H

// The data substrate (Phase B), C++ port of the proven GDScript prototype
// (scripts/dc/voxel_octree.gd). A SPARSE, ADAPTIVE octree storing an edited SDF field
// (+ material) at whatever resolution each region needs — down to sub-metre, which
// godot_voxel's fixed 1m grid can't. Surface-dominated: a node subdivides only where a
// brush's surface passes, so storage scales with surface AREA, not volume. C++ so the
// mesher can read it on a worker thread. Flat node pool (cache-friendly, snapshot-able).

#include "core/math/vector3.h"
#include "core/object/ref_counted.h"
#include "core/templates/local_vector.h"

#include "sdf_field.h"

class SparseVoxelOctree : public RefCounted {
	GDCLASS(SparseVoxelOctree, RefCounted)

public:
	void setup(Vector3 origin, double size); // create the root cube
	void imprint_sphere(Vector3 center, double radius, double min_leaf, int material);
	void imprint_box(Vector3 center, Vector3 size, double min_leaf, int material);

	double sample(Vector3 p) const; // SDF; large positive (EMPTY) where unwritten
	int material_at(Vector3 p) const;
	int leaf_count() const; // written leaves — the storage measure

	void imprint(const voxel_dc::Field &f, double min_leaf, int material); // C++ entry

protected:
	static void _bind_methods();

private:
	struct Node {
		Vector3 origin;
		double size = 0.0;
		int children[8];
		float corners[8];
		bool has_corners = false; // a written leaf (fine or uniform); false = internal or unwritten
		uint8_t material = 0;
		Node() {
			for (int i = 0; i < 8; ++i) {
				children[i] = -1;
				corners[i] = 0.0f;
			}
		}
		bool is_leaf() const { return children[0] < 0; }
	};

	LocalVector<Node> nodes; // nodes[0] = root

	int _new_node(const Vector3 &o, double s);
	void _imprint_node(int idx, const voxel_dc::Field &f, double min_leaf, int material);
	int _leaf_at(const Vector3 &p) const;
	int _child_index(int idx, const Vector3 &p) const;
};

#endif // SPARSE_VOXEL_OCTREE_H
