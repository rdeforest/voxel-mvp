#ifndef EDIT_STORE_LATTICE_H
#define EDIT_STORE_LATTICE_H

// Internal to edit_store*.cpp: GDScript SdfLattice's geometry and field, which the
// predictions build and query. Each operation reproduces its GDScript original operation for
// operation, in the same order and at the same precision (this is a precision=double build, so
// real_t and GDScript float are both double; only the lattice store is float32), because a preview
// must name exactly the cells the write flips and test_edit_store_predict gates that byte for byte.
// Rewriting an expression "equivalently" (a different association, a hoisted product) can change
// the last bit.

#include "core/variant/dictionary.h"

#include "edit_store.h"
#include "octree_geometry.h"
#include "sdf_field.h"

namespace edit_store_lattice {

// Whether the cube (o, s) overlaps the open box (rmin, rmax): the leaves a stamp or write touches.
inline bool overlaps(const Vector3 &o, double s, const Vector3 &rmin, const Vector3 &rmax) {
	return o.x + s > rmin.x && o.y + s > rmin.y && o.z + s > rmin.z &&
			o.x < rmax.x && o.y < rmax.y && o.z < rmax.z;
}

// A leaf no coarser than `cell` is written as it is; a coarser one is subdivided first.
inline bool is_write_leaf(double s, double cell) {
	return s <= cell * 1.0000001;
}

// The corners of child `child` of a leaf with corners `src`: its field, trilerped, at float32.
inline void child_corners(const float *src, int child, float *out) {
	using voxel_dc::CB;
	for (int j = 0; j < 8; ++j) {
		out[j] = float(voxel_dc::trilerp(src, (CB[child][0] + CB[j][0]) * 0.5, (CB[child][1] + CB[j][1]) * 0.5,
				(CB[child][2] + CB[j][2]) * 0.5));
	}
}

// Mirrors of GDScript constants. The byte-identical gate fails if one drifts.
constexpr double CELL_SAMPLE_OFFSET = 0.5; // VoxelConstants.VOXEL_CENTER_OFFSET (VoxelUtils.sample_point)
constexpr double SOLID_THRESHOLD = 0.0;    // VoxelConstants.SDF_SOLID_THRESHOLD
constexpr int OP_UNION = 0;                // STORE_OP_UNION == CsgState.Op.ADD

// The region a lattice rewrites is always its whole cube: write_region rewrites every leaf
// overlapping the array it is handed.
struct Lattice {
	Vector3 origin;
	double cell = 1.0;
	int dim = 0;
	PackedFloat32Array sdf;
	bool writes = false;

	Lattice(const Vector3 &p_origin, double p_cell, int p_dim) :
			origin(p_origin), cell(p_cell), dim(p_dim) {
		sdf.resize(int64_t(dim) * dim * dim);
	}

	Lattice(const PackedFloat32Array &p_sdf, int p_dim, const Vector3 &p_origin, double p_cell) :
			origin(p_origin), cell(p_cell), dim(p_dim), sdf(p_sdf) {}

	bool is_valid() const {
		return dim >= 2 && cell > 0.0 && sdf.size() == int64_t(dim) * dim * dim;
	}

	Vector3 point(int x, int y, int z) const {
		return origin + Vector3(x, y, z) * cell;
	}

	Vector3 region_hi() const {
		return origin + Vector3(1, 1, 1) * (double(dim - 1) * cell);
	}

	// The centre of the rewritten leaf a point's "before" value is read from: the one above it on
	// each axis, as store.sample reads, except on a max face, where the leaf above is not rewritten.
	Vector3 owner_centre(int x, int y, int z) const {
		const int top = dim - 2;
		return origin + (Vector3(MIN(x, top), MIN(y, top), MIN(z, top)) + Vector3(0.5, 0.5, 0.5)) * cell;
	}

	Dictionary to_dictionary() const {
		Dictionary out;
		out["origin"] = origin;
		out["cell"] = cell;
		out["dim"] = dim;
		out["sdf"] = sdf;
		out["writes"] = writes;
		return out;
	}
};

// Every point takes combine(point, the value a rewritten leaf holds there now). `writes` notes a
// point whose stored float32 changes; most writes show one, and prediction() settles the rest.
template <typename Combine>
void fill(const EditStore &store, Lattice &lat, Combine combine) {
	float *w = lat.sdf.ptrw();
	for (int z = 0; z < lat.dim; ++z) {
		for (int y = 0; y < lat.dim; ++y) {
			for (int x = 0; x < lat.dim; ++x) {
				const Vector3 p = lat.point(x, y, z);
				const double before = store.sample_toward(p, lat.owner_centre(x, y, z));
				const float after = float(combine(p, before));
				w[voxel_dc::flat_index(x, y, z, lat.dim)] = after;
				lat.writes = lat.writes || after != float(before);
			}
		}
	}
}

// What SdfLattice.predicted reads. A lattice whose points all match the leaf they were read from
// can still change a corner another rewritten leaf holds (a seam an earlier write left at its
// region's faces, or a finer leaf's detail), so an unchanged-looking one asks the full question.
inline Dictionary prediction(const EditStore &store, Lattice &lat) {
	lat.writes = lat.writes || store.lattice_writes(lat.sdf, lat.dim, lat.origin, lat.cell);
	return lat.to_dictionary();
}

} // namespace edit_store_lattice

#endif // EDIT_STORE_LATTICE_H
