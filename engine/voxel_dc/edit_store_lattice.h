#ifndef EDIT_STORE_LATTICE_H
#define EDIT_STORE_LATTICE_H

// Internal to edit_store_predict*.cpp: GDScript SdfLattice's geometry and field, which the
// predictions build and query. Each operation reproduces its GDScript original operation for
// operation, in the same order and at the same precision (this is a precision=double build, so
// real_t and GDScript float are both double; only the lattice store is float32), because a preview
// must name exactly the cells the write flips and test_edit_store_predict gates that byte for byte.
// Rewriting an expression "equivalently" (a different association, a hoisted product) can change
// the last bit.

#include "core/variant/dictionary.h"

#include "edit_store.h"
#include "sdf_field.h"

namespace edit_store_lattice {

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

	// What SdfLattice.predicted reads.
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

// Every point takes combine(point, the store's current value there).
template <typename Combine>
void fill(const EditStore &store, Lattice &lat, Combine combine) {
	float *w = lat.sdf.ptrw();
	for (int z = 0; z < lat.dim; ++z) {
		for (int y = 0; y < lat.dim; ++y) {
			for (int x = 0; x < lat.dim; ++x) {
				const Vector3 p = lat.point(x, y, z);
				const double before = store.sample(p);
				const double after = combine(p, before);
				w[voxel_dc::flat_index(x, y, z, lat.dim)] = float(after);
				lat.writes = lat.writes || after != before;
			}
		}
	}
}

} // namespace edit_store_lattice

#endif // EDIT_STORE_LATTICE_H
