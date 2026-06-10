#ifndef EDIT_STORE_H
#define EDIT_STORE_H

// The persistent data layer (Phase B core — see docs/roadmap/design/11-octree-edit-store.md).
// A SPARSE octree that stores ONLY the player's edits (SDF + material) and defers to the
// procedural TerrainField generator everywhere it has no data:
//
//   sample(p) = has_edit(p) ? stored(p) : generator(p)
//
// Storing nothing for unedited world is the point — the generator is stateless and
// regenerated on demand, so the store stays sparse and bounded by edit VOLUME, not world
// volume. Edits land copy-on-write: the first brush to touch a region materialises the
// generator there (down to the brush's leaf size), folds the brush in, and stores the
// result; later edits combine with the stored value. Replaces godot_voxel's VoxelData +
// stream. C++ so render/collision can sample it on a worker thread.

#include "core/io/stream_peer.h"
#include "core/object/ref_counted.h"
#include "core/templates/local_vector.h"
#include "core/variant/array.h"

#include "terrain_field.h"

class EditStore : public RefCounted {
	GDCLASS(EditStore, RefCounted)

public:
	// World root the edits live in (must bound them) + the generator params edits defer to.
	void setup(Vector3 origin, double size, double base, double amp, double period, int octaves, int seed);

	// Copy-on-write brush stamps: materialise the generator under the brush, fold the brush
	// in (op 0 = UNION add, 1 = SUBTRACT carve), store the result down to `min_leaf`.
	void stamp_sphere(Vector3 center, double radius, int op, int material, double min_leaf);
	void stamp_box(Vector3 center, Vector3 size, int op, int material, double min_leaf);

	// Write a region's final SDF (+ per-cell material) from a dense cubic array — e.g.
	// re-read from godot_voxel after an edit — into the store, REPLACING whatever was
	// there (the array is the authoritative result, not a brush to combine). The dual-
	// write shadow path. Copy-on-write: materialises the region down to `cell`, leaving
	// the rest sparse. `indices` may be empty (material 0).
	void write_region(const PackedFloat32Array &sdf, const PackedByteArray &indices, int dim, Vector3 origin, double cell);

	double sample(Vector3 p) const;  // stored edit if any, else the generator
	bool has_edit(Vector3 p) const;  // true where the player has edited (stored), false = generator
	Ref<EditStore> duplicate() const; // immutable snapshot for a worker thread (the store is sparse, so cheap)

	// Sample a dense cubic region of the field (generator + edits), REUSING a previous
	// buffer where it overlaps — the scrolling-buffer incremental fill (e.g. for a moving
	// collision region). A cell that maps into `prev` and isn't in the dirty box is copied;
	// the rest are sampled fresh. Pass empty `prev` for a full sample. `dirty` (origin/size
	// in world cells; size 0 = none) forces re-sampling of an edited box. `origin` is in
	// world units; the field makes no heightfield assumption, so this works for any field.
	PackedFloat32Array fill_region(Vector3i origin, int dim, double cell,
			const PackedFloat32Array &prev, Vector3i prev_origin, Vector3i dirty_origin, Vector3i dirty_size) const;
	int material_at(Vector3 p) const;
	int leaf_count() const;          // stored (edited) leaves — the storage measure

	PackedByteArray serialize() const;     // the sparse edited tree + root + generator params
	void deserialize(const PackedByteArray &bytes);

protected:
	static void _bind_methods();

private:
	struct Node {
		Vector3 origin;
		double size = 0.0;
		int children[8];
		float corners[8];
		bool has_corners = false; // a stored (edited) leaf; false = internal or unedited (-> generator)
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
	Vector3 _root_origin;
	double _root_size = 0.0;
	double _base = 0.0;
	double _amp = 0.0;
	double _period = 1.0;
	int _octaves = 0;
	int _seed = 0;
	voxel_dc::TerrainField _gen;

	int _new_node(const Vector3 &o, double s);
	void _stamp(const voxel_dc::Field &brush, const Vector3 &rmin, const Vector3 &rmax, int op, int material, double min_leaf);
	void _stamp_region(int idx, const voxel_dc::Field &brush, const Vector3 &rmin, const Vector3 &rmax, int op, int material, double min_leaf);
	void _write_region(int idx, const voxel_dc::ArrayField &sdf, const PackedByteArray &indices,
			int adim, const Vector3 &aorigin, double cell, const Vector3 &rmin, const Vector3 &rmax);
	void _subdivide(int idx); // edited leaf -> inherit its field; unedited -> fresh (still generator)
	int _leaf_at(const Vector3 &p) const;
	int _child_index(int idx, const Vector3 &p) const;
	bool _inside_root(const Vector3 &p) const;
};

#endif // EDIT_STORE_H
