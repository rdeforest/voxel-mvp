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

// Mirrors of GDScript constants. The byte-identical gate fails if one drifts.
constexpr double CELL_SAMPLE_OFFSET = 0.5; // VoxelConstants.VOXEL_CENTER_OFFSET (VoxelUtils.sample_point)
constexpr double SOLID_THRESHOLD = 0.0;    // VoxelConstants.SDF_SOLID_THRESHOLD
constexpr int OP_UNION = 0;                // STORE_OP_UNION == CsgState.Op.ADD
constexpr double SDF_BAND = 5.0;           // VoxelConstants.SDF_AIR == -SDF_SOLID

// SdfLattice.materials's paint rule, shared by every brush write (the lattice builder's `made` and
// EditStore's stamps) so the same brush paints the same leaves whichever path writes it. A point is
// `made` when the write leaves it solid and the brush is solid there. The GDScript rule also counted
// a point the write turned from air to solid; under a brush combine (union = min(before, brush),
// subtract = max(before, -brush)) that point is always one the brush is solid at, and a subtract
// never makes one, so the clause adds nothing and is left out.
inline bool brush_made_solid(float after, double brush) {
	return after < SOLID_THRESHOLD && brush < SOLID_THRESHOLD;
}

// A rewritten leaf takes `material` iff the write made one of its corners solid (`material` < 0
// never repaints: a carve); otherwise it keeps what it was made of (`held()`, the material_at its
// centre before the write) while it keeps a solid corner or `air_keeps`, else 0.
template <typename Held>
int brush_leaf_material(bool made, bool solid, int material, bool air_keeps, Held held) {
	if (made && material >= 0) {
		return material;
	}
	return solid || air_keeps ? held() : 0;
}

// The region a lattice rewrites is always its whole cube: write_region rewrites every leaf
// overlapping the array it is handed.
struct Lattice {
	Vector3 origin;
	double cell = 1.0;
	int dim = 0;
	PackedFloat32Array sdf;
	PackedByteArray made; // brush lattices only (fill_brush): per point, 1 = the write made it solid
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
		out["made"] = made;
		out["writes"] = writes;
		return out;
	}
};

// Whether the write rewrites the leaves over coordinate `v` on `axis` (EditStore's strict-overlap
// test, which is separable per axis).
inline bool rewrites_1d(const Lattice &lat, double v, int axis) {
	const double leaf = Math::floor(v / lat.cell) * lat.cell;
	return leaf < lat.region_hi()[axis] && leaf + lat.cell > lat.origin[axis];
}

// Along one axis, every cell whose sample point sits in a rewritten leaf.
inline LocalVector<int> rewritten_cells(const Lattice &lat, int axis) {
	LocalVector<int> out;
	const int64_t first = int64_t(Math::floor(lat.origin[axis])) - 1;
	const int64_t end = int64_t(Math::ceil(lat.region_hi()[axis])) + 1;
	for (int64_t c = first; c < end; ++c) {
		if (rewrites_1d(lat, double(c) + CELL_SAMPLE_OFFSET, axis)) {
			out.push_back(int(c));
		}
	}
	return out;
}

// visit(cell) for every cell whose sample point sits in a rewritten leaf — the only cells the
// write can change — in SdfLattice.cells's z-y-x order, which the flip lists keep. Stops at the
// first visit that returns false.
template <typename Visit>
bool for_each_rewritten_cell(const Lattice &lat, Visit visit) {
	const LocalVector<int> xs = rewritten_cells(lat, 0);
	const LocalVector<int> ys = rewritten_cells(lat, 1);
	const LocalVector<int> zs = rewritten_cells(lat, 2);
	for (const int z : zs) {
		for (const int y : ys) {
			for (const int x : xs) {
				if (!visit(Vector3i(x, y, z))) {
					return false;
				}
			}
		}
	}
	return true;
}

inline Vector3 cell_sample_point(const Vector3i &c) {
	return Vector3(c) + Vector3(1, 1, 1) * CELL_SAMPLE_OFFSET;
}

enum Flip {
	FLIP_NONE,
	FLIP_TO_SOLID,
	FLIP_TO_AIR,
};

// CellFlips._add: how a cell's sample value crossing SOLID_THRESHOLD, from `was` to `now`, flips it.
inline Flip flip(double was, double now) {
	if (was >= SOLID_THRESHOLD && now < SOLID_THRESHOLD) {
		return FLIP_TO_SOLID;
	}
	if (was < SOLID_THRESHOLD && now >= SOLID_THRESHOLD) {
		return FLIP_TO_AIR;
	}
	return FLIP_NONE;
}

// Every point takes combine(its flat index, point, the value a rewritten leaf holds there now).
// `writes` notes a point whose stored float32 changes; most writes show one, and prediction()
// settles the rest.
template <typename Combine>
void fill(const EditStore &store, Lattice &lat, Combine combine) {
	float *w = lat.sdf.ptrw();
	for (int z = 0; z < lat.dim; ++z) {
		for (int y = 0; y < lat.dim; ++y) {
			for (int x = 0; x < lat.dim; ++x) {
				const int i = voxel_dc::flat_index(x, y, z, lat.dim);
				const Vector3 p = lat.point(x, y, z);
				const double before = store.sample_toward(p, lat.owner_centre(x, y, z));
				const float after = float(combine(i, p, before));
				w[i] = after;
				lat.writes = lat.writes || after != float(before);
			}
		}
	}
}

// A brush combined into the field: union = min(before, brush(p)), subtract = max(before, -brush(p)),
// brush(p) < SOLID_THRESHOLD being the brush's inside. `made` (brush_made_solid) is taken here
// because the brush value and the owner leaf's "before" are both in hand.
template <typename Brush>
void fill_brush(const EditStore &store, Lattice &lat, int op, Brush brush) {
	lat.made.resize(lat.sdf.size());
	uint8_t *made = lat.made.ptrw();
	fill(store, lat, [&](int i, const Vector3 &p, double before) {
		const double b = brush(p);
		const double after = op == OP_UNION ? MIN(before, b) : MAX(before, -b);
		made[i] = brush_made_solid(float(after), b);
		return after;
	});
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
