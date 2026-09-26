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
#include "core/math/aabb.h"
#include "core/math/transform_3d.h"
#include "core/object/ref_counted.h"
#include "core/templates/local_vector.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"
#include "core/variant/typed_array.h"

#include "sdf_field.h"
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
	// the rest sparse. `indices` may be empty: leaves keep the material they hold (0 for
	// one this write materialises from the generator).
	void write_region(const PackedFloat32Array &sdf, const PackedByteArray &indices, int dim, Vector3 origin, double cell);
	// write_region, returning what it did to cells: { solid, air } the cells whose sample point it
	// flipped (every cell whose sample point sits in a rewritten leaf, in z-y-x order, like
	// lattice_flips), `air_materials` the material each `air` cell held before (parallel to it), and
	// `changed` whether any of those cells' sample value moved at all. See edit_store_write_flips.cpp.
	Dictionary write_region_flips(const PackedFloat32Array &sdf, const PackedByteArray &indices, int dim,
			Vector3 origin, double cell);

	// The field an edit WOULD write, without writing: the lattice every SdfLattice builder hands
	// write_region (SdfLattice.sphere_stamp, VoxelImprint.lattice, StoreWrite.lattice, and the work
	// sets BellSculptAction / FlattenAction generate), bit for bit — test_edit_store_predict gates it
	// against the GDScript originals kept in test/support/lattice_oracle.gd. Each returns
	// { origin, cell, dim, sdf, made, writes } (what SdfLattice.predicted reads; `made` is filled by the
	// brush predictions, sphere stamp and imprint, and empty for the rest); an empty Dictionary is a
	// refusal (bad arguments) or, for bell / flatten, a reshape that writes no point. `shape` is a
	// CsgSdf.Shape with `dims` = box [x, y, z], cylinder [radius, height], sphere [radius]; `peak`
	// is the SDF the bell adds at its centre column (negative raises the surface).
	// See edit_store_predict.cpp / edit_store_predict_work.cpp.
	Dictionary predict_sphere_stamp(Vector3 center, double radius, int op, double min_leaf) const;
	Dictionary predict_imprint(int shape, const PackedFloat64Array &dims, Transform3D xform, int op, double cell) const;
	Dictionary predict_work(const TypedArray<Vector3i> &points, const PackedFloat64Array &sdfs) const;
	Dictionary predict_bell(Vector3 center, double radius, double peak) const;
	Dictionary predict_flatten(Vector3 plane_point, Vector3 normal, double radius) const;
	// Whether the store holds solid at a point of predict_imprint's lattice (same shape / dims /
	// xform / cell) that lies within `reach` of the brush, or at `below` from such a point. Gated
	// against ConstructionAction's GDScript original (the oracle) by test_construction_attach_predict.
	bool imprint_near_solid(int shape, const PackedFloat64Array &dims, Transform3D xform, double cell,
			double reach, Vector3 below) const;

	// Questions asked of a predicted lattice (the write_region arguments: dim^3 values, x fastest)
	// against the store as it is now. lattice_flips = SdfLattice.flips: { solid, air }, the cells
	// whose sample point the write turns solid / air (empty Dictionary if the cell size does not
	// tile the unit grid). lattice_turns_in = SdfLattice.solidifies_in / empties_in: whether the
	// write turns any point of `box` solid (to_solid) or air that the store holds otherwise now.
	// lattice_writes: whether write_region would change any stored corner — every corner of every
	// leaf it rewrites, compared at float32 against what that leaf holds now (the generator's value
	// for an unedited leaf); material is not considered. lattice_materials = SdfLattice.materials:
	// the per-leaf material write_region takes, painting the leaves with a corner in `made`.
	Dictionary lattice_flips(const PackedFloat32Array &sdf, int dim, Vector3 origin, double cell) const;
	bool lattice_turns_in(const PackedFloat32Array &sdf, int dim, Vector3 origin, double cell, AABB box, bool to_solid) const;
	bool lattice_writes(const PackedFloat32Array &sdf, int dim, Vector3 origin, double cell) const;
	PackedByteArray lattice_materials(const PackedFloat32Array &sdf, const PackedByteArray &made, int dim,
			Vector3 origin, double cell, int material, bool air_keeps) const;

	double sample(Vector3 p) const;  // stored edit if any, else the generator
	// sample() read from the leaf on `toward`'s side of every leaf boundary `p` lies on (sample()
	// takes the upper side), so a point on a region's max face can be read from inside the region.
	double sample_toward(Vector3 p, Vector3 toward) const;
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
	// Dense per-cell material ids over a cubic region (generator = 0 where unedited), the
	// material companion to fill_region — the render samples both for a clipmap level. No
	// scrolling buffer: material is read once per full re-mesh, not per moving frame.
	PackedByteArray fill_indices_region(Vector3i origin, int dim, double cell) const;
	int material_at(Vector3 p) const;
	int leaf_count() const;          // stored (edited) leaves — the storage measure

	static double terrain_surface(double x, double z, double base, double amp, double period, int octaves, int seed);

	PackedByteArray serialize() const;     // the sparse edited tree + root + generator params
	bool deserialize(const PackedByteArray &bytes);

protected:
	static void _bind_methods();

private:
	// Where a node's field comes from. Subdividing an edited leaf must leave its field exactly as it
	// was (a trilerp re-rounded to float32 at the children's corners moves samples a write never
	// touched), so its children read the subdivided leaf's own corners over its own cube: they are
	// INHERITED leaves of that FIELD_SOURCE (`Node::source`). An inherited leaf also holds that field
	// at its corners, rounded to float32 (what a write or stamp compares or combines with).
	// Serialized as the byte that was `has_corners` (0 / 1), so older blobs read unchanged; `source`
	// is not serialized but relinked on load (_link_sources) from the FIELD_SOURCE ancestors.
	enum FieldState : uint8_t {
		NO_FIELD,        // internal, or an unedited leaf (-> generator)
		OWN_FIELD,       // an edited leaf: its corners over its cube
		INHERITED_FIELD, // an edited leaf: its FIELD_SOURCE's field
		FIELD_SOURCE,    // internal: a subdivided edited leaf, its corners the field its inheritors read
	};

	struct Node {
		Vector3 origin;
		double size = 0.0;
		int children[8];
		float corners[8];
		FieldState field = NO_FIELD;
		uint8_t material = 0;
		int source = -1; // an edited leaf: the node whose field it reads (itself, or its FIELD_SOURCE)
		Node() {
			for (int i = 0; i < 8; ++i) {
				children[i] = -1;
				corners[i] = 0.0f;
			}
		}
		bool is_leaf() const { return children[0] < 0; }
		bool is_edited() const { return field == OWN_FIELD || field == INHERITED_FIELD; }
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

	struct RegionWrite; // a write_region call as lattice_writes walks it (edit_store_dry_run.cpp)

	int _new_node(const Vector3 &o, double s);
	void _stamp(const voxel_dc::Field &brush, const Vector3 &rmin, const Vector3 &rmax, int op, int material, double min_leaf);
	void _stamp_region(int idx, const voxel_dc::Field &brush, const Vector3 &rmin, const Vector3 &rmax, int op, int material, double min_leaf);
	void _write_region(int idx, const voxel_dc::ArrayField &sdf, const PackedByteArray &indices,
			int adim, const Vector3 &aorigin, double cell, const Vector3 &rmin, const Vector3 &rmax);
	void _subdivide(int idx); // edited leaf -> inherit its field; unedited -> fresh (still generator)
	bool _write_changes(int idx, RegionWrite &write) const;
	bool _leaf_write_changes(const Vector3 &o, double s, int field, RegionWrite &write) const;
	bool _corner_changes(const Vector3 &c, int slot, const float *held, RegionWrite &write) const;
	int _leaf_at(const Vector3 &p) const;
	int _leaf_toward(const Vector3 &p, const Vector3 &toward) const;
	int _leaf_field(int leaf) const;
	static bool _read_node(StreamPeerBuffer &b, int index, Node &n);
	bool _link_sources(int idx, int source);
	double _field_value(int field, const Vector3 &p) const;
	float _held_corner(int field, const Vector3 &o, double s, int i) const;
	bool _inside_root(const Vector3 &p) const;
};

#endif // EDIT_STORE_H
