#include "edit_store.h"

#include "core/math/aabb.h"
#include "core/math/vector2.h"

#include "edit_store_lattice.h"

// The brush predictions (SdfLattice.sphere_stamp, VoxelImprint.lattice), the material a brush
// lattice paints, and the two questions asked of any predicted lattice (the cells it flips, and
// whether it turns a box solid or air).
// Bit-exactness rules: edit_store_lattice.h.

using namespace edit_store_lattice;

namespace {

constexpr double IMPRINT_MARGIN = 2.0; // VoxelImprint.MARGIN

enum CsgShapeKind { // CsgSdf.Shape
	CSG_BOX,
	CSG_CYLINDER,
	CSG_SPHERE,
};

// The leaf with lattice corner `i0`, trilerped at fractions `f` across it.
double trilerp(const Lattice &lat, const float *sdf, const Vector3i &i0, const Vector3 &f) {
	const int sy = lat.dim;
	const int sz = lat.dim * lat.dim;
	const int i = voxel_dc::flat_index(i0.x, i0.y, i0.z, lat.dim);
	const double c00 = Math::lerp(double(sdf[i]), double(sdf[i + 1]), f.x);
	const double c10 = Math::lerp(double(sdf[i + sy]), double(sdf[i + sy + 1]), f.x);
	const double c01 = Math::lerp(double(sdf[i + sz]), double(sdf[i + sz + 1]), f.x);
	const double c11 = Math::lerp(double(sdf[i + sy + sz]), double(sdf[i + sy + sz + 1]), f.x);
	return Math::lerp(Math::lerp(c00, c10, f.y), Math::lerp(c01, c11, f.y), f.z);
}

// A rewritten leaf the box overlaps along one axis: its lattice index and the fractions across it
// to test — the overlap's two ends and any cell sample point between them.
struct Piece {
	int k = 0;
	LocalVector<double> fracs;
};

LocalVector<Piece> pieces_1d(const Lattice &lat, const AABB &box, int axis) {
	const double lo = box.position[axis];
	const double hi = lo + box.size[axis];
	const double o = lat.origin[axis];
	const int64_t first = MAX(int64_t(Math::floor((lo - o) / lat.cell)), int64_t(0));
	const int64_t end = MIN(int64_t(Math::ceil((hi - o) / lat.cell)), int64_t(lat.dim - 1));
	LocalVector<Piece> out;
	for (int64_t k = first; k < end; ++k) {
		const double leaf_lo = o + double(k) * lat.cell;
		if (!rewrites_1d(lat, leaf_lo + lat.cell * 0.5, axis)) {
			continue;
		}
		const double a = MAX(lo, leaf_lo);
		const double b = MIN(hi, leaf_lo + lat.cell);
		Piece piece;
		piece.k = int(k);
		piece.fracs.push_back((a - leaf_lo) / lat.cell);
		piece.fracs.push_back((b - leaf_lo) / lat.cell);
		const int64_t c_end = int64_t(Math::ceil(b - CELL_SAMPLE_OFFSET)) + 1;
		for (int64_t c = int64_t(Math::floor(a - CELL_SAMPLE_OFFSET)); c < c_end; ++c) {
			const double sp = double(c) + CELL_SAMPLE_OFFSET;
			if (sp > a && sp < b) {
				piece.fracs.push_back((sp - leaf_lo) / lat.cell);
			}
		}
		out.push_back(piece);
	}
	return out;
}

// CsgBoxShape / CsgCylinderShape / CsgSphereShape .local_aabb().
AABB csg_local_aabb(int shape, const double *dims) {
	switch (shape) {
		case CSG_BOX: {
			const Vector3 size(dims[0], dims[1], dims[2]);
			return AABB(-size * 0.5, size);
		}
		case CSG_CYLINDER: {
			const double radius = dims[0];
			const double height = dims[1];
			return AABB(Vector3(-radius, -height * 0.5, -radius), Vector3(radius * 2.0, height, radius * 2.0));
		}
		default:
			return AABB(-(Vector3(1, 1, 1) * dims[0]), Vector3(1, 1, 1) * dims[0] * 2.0);
	}
}

// CsgSdf.box / cylinder / sphere.
double csg_sdf(int shape, const double *dims, const Vector3 &p) {
	switch (shape) {
		case CSG_BOX: {
			const Vector3 q = p.abs() - Vector3(dims[0], dims[1], dims[2]) * 0.5;
			const double outside = q.max(Vector3()).length();
			const double inside = MIN(MAX(q.x, MAX(q.y, q.z)), 0.0);
			return outside + inside;
		}
		case CSG_CYLINDER: {
			const double radial = Vector2(p.x, p.z).length() - dims[0];
			const double axial = Math::abs(p.y) - dims[1] * 0.5;
			const double outside = Vector2(MAX(radial, 0.0), MAX(axial, 0.0)).length();
			const double inside = MIN(MAX(radial, axial), 0.0);
			return outside + inside;
		}
		default:
			return p.length() - dims[0];
	}
}

int csg_dim_count(int shape) {
	switch (shape) {
		case CSG_BOX:
			return 3;
		case CSG_CYLINDER:
			return 2;
		case CSG_SPHERE:
			return 1;
		default:
			return -1;
	}
}

// Where the imprint's lattice sits (VoxelImprint.world_box inlined): points `cell` apart covering
// the brush's world box, one point of slack beyond it on every side.
struct LatticePlace {
	Vector3 origin;
	int dim = 0;
};

LatticePlace imprint_place(int shape, const double *dims, const Transform3D &xform, double cell) {
	const AABB box = xform.xform(csg_local_aabb(shape, dims)).grow(IMPRINT_MARGIN);
	const Vector3i lo = Vector3i((box.position / cell).floor()) - Vector3i(1, 1, 1);
	const Vector3i hi = Vector3i(((box.position + box.size) / cell).ceil()) + Vector3i(1, 1, 1);
	const Vector3i span = hi - lo;
	return { Vector3(lo) * cell, MAX(span.x, MAX(span.y, span.z)) + 1 };
}

// The shape / dims / cell arguments predict_imprint and imprint_near_solid share.
bool imprint_args_valid(int shape, const PackedFloat64Array &dims, double cell) {
	ERR_FAIL_COND_V_MSG(csg_dim_count(shape) < 0, false, "Unknown CsgSdf.Shape.");
	ERR_FAIL_COND_V_MSG(dims.size() != csg_dim_count(shape), false, "Wrong dims count for the shape.");
	ERR_FAIL_COND_V_MSG(!(cell > 0.0), false, "cell must be positive.");
	return true;
}

} // namespace

// SdfLattice.sphere_stamp.
Dictionary EditStore::predict_sphere_stamp(Vector3 center, double radius, int op, double min_leaf) const {
	ERR_FAIL_COND_V_MSG(!(min_leaf > 0.0), Dictionary(), "min_leaf must be positive.");
	const Vector3 pad = Vector3(1, 1, 1) * (radius + min_leaf);
	const Vector3 first = ((center - pad) / min_leaf).floor();
	const Vector3 span = ((center + pad) / min_leaf).ceil() - first;
	Lattice lat(first * min_leaf, min_leaf, int(MAX(span.x, MAX(span.y, span.z))) + 1);
	fill_brush(*this, lat, op, [&](const Vector3 &p) { return p.distance_to(center) - radius; });
	return prediction(*this, lat);
}

// VoxelImprint.lattice.
Dictionary EditStore::predict_imprint(int shape, const PackedFloat64Array &dims, Transform3D xform, int op, double cell) const {
	if (!imprint_args_valid(shape, dims, cell)) {
		return Dictionary();
	}
	const double *d = dims.ptr();
	const Transform3D inverse = xform.affine_inverse();
	const LatticePlace place = imprint_place(shape, d, xform, cell);
	Lattice lat(place.origin, cell, place.dim);
	fill_brush(*this, lat, op, [&](const Vector3 &p) {
		return CLAMP(csg_sdf(shape, d, inverse.xform(p)), -SDF_BAND, SDF_BAND);
	});
	return prediction(*this, lat);
}

// ConstructionAction's attach test, over the points of the lattice predict_imprint builds (its
// field is not needed, so it is not built). The answer is a bool, so the scan order (z-y-x, as the
// original) only decides how early it stops.
bool EditStore::imprint_near_solid(int shape, const PackedFloat64Array &dims, Transform3D xform, double cell,
		double reach, Vector3 below) const {
	if (!imprint_args_valid(shape, dims, cell)) {
		return false;
	}
	const double *d = dims.ptr();
	const Transform3D inverse = xform.affine_inverse();
	const LatticePlace place = imprint_place(shape, d, xform, cell);
	for (int z = 0; z < place.dim; ++z) {
		for (int y = 0; y < place.dim; ++y) {
			for (int x = 0; x < place.dim; ++x) {
				const Vector3 p = place.origin + Vector3(x, y, z) * cell;
				if (csg_sdf(shape, d, inverse.xform(p)) > reach) {
					continue;
				}
				if (sample(p) < SOLID_THRESHOLD || sample(p + below) < SOLID_THRESHOLD) {
					return true;
				}
			}
		}
	}
	return false;
}

// SdfLattice.materials: brush_leaf_material over each leaf, `made` coming from fill_brush.
PackedByteArray EditStore::lattice_materials(const PackedFloat32Array &sdf, const PackedByteArray &made, int dim,
		Vector3 origin, double cell, int material, bool air_keeps) const {
	const Lattice lat(sdf, dim, origin, cell);
	ERR_FAIL_COND_V_MSG(!lat.is_valid(), PackedByteArray(), "Not a lattice: sdf must hold dim^3 values, dim >= 2, cell > 0.");
	ERR_FAIL_COND_V_MSG(made.size() != sdf.size(), PackedByteArray(), "made must hold dim^3 values (a brush prediction's).");
	const float *values = sdf.ptr();
	const uint8_t *m = made.ptr();
	const Vector3 half = Vector3(1, 1, 1) * (cell * 0.5);
	PackedByteArray out;
	out.resize(sdf.size());
	uint8_t *w = out.ptrw();
	memset(w, 0, out.size());
	for (int z = 0; z < dim - 1; ++z) {
		for (int y = 0; y < dim - 1; ++y) {
			for (int x = 0; x < dim - 1; ++x) {
				bool painted = false;
				bool solid = false;
				for (int k = 0; k < 8; ++k) {
					const int j = voxel_dc::flat_index(x + voxel_dc::CB[k][0], y + voxel_dc::CB[k][1], z + voxel_dc::CB[k][2], dim);
					painted = painted || m[j] == 1;
					solid = solid || values[j] < SOLID_THRESHOLD;
				}
				const Vector3 centre = lat.point(x, y, z) + half;
				w[voxel_dc::flat_index(x, y, z, dim)] = uint8_t(brush_leaf_material(painted, solid, material, air_keeps,
						[&] { return material_at(centre); }));
			}
		}
	}
	return out;
}

// SdfLattice.value_at at every rewritten cell's sample point, then CellFlips._add, in z-y-x order.
// Refused (an empty Dictionary) when a rewritten cell's sample point falls outside the lattice
// (a cell size that does not tile the unit grid), rather than returning missing cells.
Dictionary EditStore::lattice_flips(const PackedFloat32Array &sdf, int dim, Vector3 origin, double cell) const {
	const Lattice lat(sdf, dim, origin, cell);
	ERR_FAIL_COND_V_MSG(!lat.is_valid(), Dictionary(), "Not a lattice: sdf must hold dim^3 values, dim >= 2, cell > 0.");
	const float *values = sdf.ptr();
	TypedArray<Vector3i> solid;
	TypedArray<Vector3i> air;
	const bool tiled = for_each_rewritten_cell(lat, [&](const Vector3i &c) {
		const Vector3 p = cell_sample_point(c);
		const Vector3 l = (p - origin) / cell;
		const Vector3i i0(int64_t(Math::floor(l.x)), int64_t(Math::floor(l.y)), int64_t(Math::floor(l.z)));
		if (MIN(i0.x, MIN(i0.y, i0.z)) < 0 || MAX(i0.x, MAX(i0.y, i0.z)) > dim - 2) {
			return false;
		}
		const Flip f = flip(sample(p), trilerp(lat, values, i0, l - Vector3(i0)));
		if (f == FLIP_TO_SOLID) {
			solid.push_back(c);
		} else if (f == FLIP_TO_AIR) {
			air.push_back(c);
		}
		return true;
	});
	ERR_FAIL_COND_V_MSG(!tiled, Dictionary(),
			"A rewritten cell's sample point lies outside the lattice: the cell size does not tile the unit grid.");
	Dictionary out;
	out["solid"] = solid;
	out["air"] = air;
	return out;
}

// SdfLattice.solidifies_in / empties_in: over each rewritten leaf the written field is one
// trilerp, so its extremes over the leaf's piece of `box` are at the piece's corners; those corners
// plus every cell sample point inside the piece are tested against the store's current value.
bool EditStore::lattice_turns_in(const PackedFloat32Array &sdf, int dim, Vector3 origin, double cell, AABB box, bool to_solid) const {
	const Lattice lat(sdf, dim, origin, cell);
	ERR_FAIL_COND_V_MSG(!lat.is_valid(), false, "Not a lattice: sdf must hold dim^3 values, dim >= 2, cell > 0.");
	const LocalVector<Piece> px = pieces_1d(lat, box, 0);
	const LocalVector<Piece> py = pieces_1d(lat, box, 1);
	const LocalVector<Piece> pz = pieces_1d(lat, box, 2);
	const float *values = sdf.ptr();
	for (const Piece &z : pz) {
		for (const Piece &y : py) {
			for (const Piece &x : px) {
				const Vector3i i0(x.k, y.k, z.k);
				for (const double fz : z.fracs) {
					for (const double fy : y.fracs) {
						for (const double fx : x.fracs) {
							const Vector3 f(fx, fy, fz);
							if ((trilerp(lat, values, i0, f) < SOLID_THRESHOLD) != to_solid) {
								continue;
							}
							if ((sample(origin + (Vector3(i0) + f) * cell) < SOLID_THRESHOLD) != to_solid) {
								return true;
							}
						}
					}
				}
			}
		}
	}
	return false;
}
