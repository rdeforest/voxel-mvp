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
#include "core/variant/array.h"

#include "sdf_field.h"

class EditStore;

class SparseVoxelOctree : public RefCounted {
	GDCLASS(SparseVoxelOctree, RefCounted)

public:
	void setup(Vector3 origin, double size); // create the root cube
	void imprint_sphere(Vector3 center, double radius, double min_leaf, int material);
	void imprint_box(Vector3 center, Vector3 size, double min_leaf, int material);
	// Build from a dense SDF grid (e.g. DCRegionReader terrain): root spans the grid,
	// refines to `min_leaf` at the surface. The bridge from procedural terrain.
	void imprint_array(const PackedFloat32Array &data, int dim, Vector3 origin, double cell, double min_leaf);

	// Imprint the procedural terrain field (TerrainField) into the existing root cube,
	// refining to `min_leaf` at the surface. The store-over-generator baseline: a fine
	// analytic field at every point, no godot_voxel mips. Params mirror the .tres graph.
	void imprint_terrain(double base, double amp, double period, int octaves, int seed, double min_leaf);
	// The terrain surface height at (x, z) — the analytic oracle, for validating the
	// C++ field against the live VoxelGeneratorGraph without octree reconstruction error.
	static double terrain_surface(double x, double z, double base, double amp, double period, int octaves, int seed);

	// Combine a brush into the EXISTING field in place: op 0 = UNION (add solid),
	// 1 = SUBTRACT (carve). Existing leaves keep their corners (just combined); coarse
	// leaves subdivide (inheriting the parent field) only where the brush adds detail.
	void stamp_sphere(Vector3 center, double radius, double min_leaf, int material, int op);
	void stamp_box(Vector3 center, Vector3 size, double min_leaf, int material, int op);
	void stamp(const voxel_dc::Field &f, double min_leaf, int material, int op);

	double sample(Vector3 p) const; // SDF; large positive (EMPTY) where unwritten
	int material_at(Vector3 p) const;
	int leaf_count() const; // written leaves — the storage measure

	// Dual Contouring straight off the octree: Mesh.ARRAY_* (VERTEX/NORMAL/INDEX),
	// watertight (point-location stitch across leaf-size jumps).
	Array mesh();

	void imprint(const voxel_dc::Field &f, double min_leaf, int material); // C++ entry

	// Distance-graded imprint: leaf size near `focus` is `near_leaf`, doubling every
	// `band` of distance — so one octree spans the whole view, fine where you look,
	// coarse far away (what makes a world-spanning octree affordable). Crack-free across
	// the size jumps by construction (the mesher's point-location stitch).
	void imprint_sphere_graded(Vector3 center, double radius, Vector3 focus,
			double near_leaf, double band, int material);
	// Distance-graded terrain imprint: fine (near_leaf) near `focus`, doubling every
	// `band` of distance — one octree spanning the whole view over the procedural field.
	// The live store-over-generator render path.
	void imprint_terrain_graded(Vector3 focus, double near_leaf, double band,
			double base, double amp, double period, int octaves, int seed);
	// Edit-aware graded terrain imprint: TerrainField base, with `overlay` (a dense SDF
	// grid re-read from the edited store, e.g. DCRegionReader) overlaid inside its box, so
	// edits there show while the rest defers to the generator. Empty overlay = plain terrain.
	void imprint_terrain_overlay_graded(Vector3 focus, double near_leaf, double band,
			double base, double amp, double period, int octaves, int seed,
			const PackedFloat32Array &overlay, int overlay_dim, Vector3 overlay_origin, double overlay_cell);

	// Incremental LOD: refine the EXISTING octree toward a new focus — subdivide surface
	// leaves now too coarse for their distance to `focus` (the player moved closer),
	// imprinting the new children from the terrain field. Only ADDS detail (never
	// coarsens), so it's cheap on movement (touches the leading margin, not the whole
	// tree) and always a correct, watertight representation of the field. Re-imprint from
	// scratch to reset the detail accumulated in the player's wake.
	void refine_terrain_graded(Vector3 focus, double near_leaf, double band,
			double base, double amp, double period, int octaves, int seed);

	// Imprint the field (generator + edits) of an EditStore, graded around focus — the
	// render octree's source once edits live in the store instead of being re-read from
	// godot_voxel. Pass a snapshot (EditStore.duplicate()) when imprinting off-thread.
	// Limitation: a small edit ISOLATED in empty space (e.g. a block built mid-air) can be
	// missed — the graded octree's homogeneity prune undersamples a feature that doesn't
	// reach a coarse node's corners/centre. Surface edits (digs/builds on the ground) are
	// caught because the surface is already subdivided. Fixing the isolated case means
	// force-subdividing where the store has edits — a later refinement.
	void imprint_store_graded(const Ref<EditStore> &store, Vector3 focus, double near_leaf, double band);

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
		int vertex = -1; // mesh-vertex index (mesh() pass)
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
	void _imprint_graded(int idx, const voxel_dc::Field &f, const Vector3 &focus,
			double near_leaf, double band, int material);
	void _refine_graded(int idx, const voxel_dc::Field &f, const Vector3 &focus,
			double near_leaf, double band);
	void _stamp_node(int idx, const voxel_dc::Field &f, double min_leaf, int material, int op);
	void _subdivide_inherit(int idx);
	int _leaf_at(const Vector3 &p) const;       // assumes p in root
	int _find_leaf(const Vector3 &p) const;      // bounds-checked; -1 outside root
	int _child_index(int idx, const Vector3 &p) const;

	// --- meshing ---
	bool _leaf_vertex(int idx, Vector3 &out_v) const;
	Vector3 _leaf_normal(int idx) const;
	void _stitch_leaf(int idx, const PackedVector3Array &verts, PackedInt32Array &out) const;
	void _try_edge(int idx, int axis, int u, int w, int su, int sw,
			const PackedVector3Array &verts, PackedInt32Array &out) const;
	bool _owns_edge(int idx, const int ring[4]) const;
	void _emit_poly(const int ring[], int rc, const Vector3 &outward,
			const PackedVector3Array &verts, PackedInt32Array &out) const;
};

#endif // SPARSE_VOXEL_OCTREE_H
