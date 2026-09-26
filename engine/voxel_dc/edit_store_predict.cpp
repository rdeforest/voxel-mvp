#include "edit_store.h"

#include "core/math/aabb.h"
#include "core/math/vector2.h"

#include "sdf_field.h"

// The preview predictions. Each function reproduces a GDScript builder operation for operation, in
// the same order and at the same precision (this is a precision=double build, so real_t and GDScript
// float are both double; only the lattice store is float32), because a preview must name exactly
// the cells the write flips and test_edit_store_predict gates that byte for byte. Rewriting an
// expression "equivalently" (a different association, a hoisted product) can change the last bit.

namespace {

// Mirrors of GDScript constants the builders read. The byte-identical gate fails if either drifts.
constexpr double CELL_SAMPLE_OFFSET = 0.5; // VoxelConstants.VOXEL_CENTER_OFFSET (VoxelUtils.sample_point)
constexpr double IMPRINT_MARGIN = 2.0;     // VoxelImprint.MARGIN
constexpr double SDF_BAND = 5.0;           // VoxelConstants.SDF_AIR == -SDF_SOLID
constexpr double SOLID_THRESHOLD = 0.0;    // VoxelConstants.SDF_SOLID_THRESHOLD
constexpr int OP_UNION = 0;                // STORE_OP_UNION == CsgState.Op.ADD

enum CsgShapeKind { // CsgSdf.Shape
	CSG_BOX,
	CSG_CYLINDER,
	CSG_SPHERE,
};

// SdfLattice's geometry and field. The region it rewrites is always the whole cube here.
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

	Vector3 point(int x, int y, int z) const {
		return origin + Vector3(x, y, z) * cell;
	}

	Vector3 region_hi() const {
		return origin + Vector3(1, 1, 1) * (double(dim - 1) * cell);
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

// SdfLattice._rewrites_1d.
bool rewrites_1d(const Lattice &lat, double v, int axis) {
	const double leaf = Math::floor(v / lat.cell) * lat.cell;
	return leaf < lat.region_hi()[axis] && leaf + lat.cell > lat.origin[axis];
}

// SdfLattice._trilerp: the leaf with lattice corner `i0`, at fractions `f` across it.
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

// SdfLattice.cells along one axis: every cell whose sample point sits in a rewritten leaf.
LocalVector<int> rewritten_cells(const Lattice &lat, int axis) {
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

// SdfLattice.flips (value_at, then CellFlips._add per cell), in its z-y-x order. False when a
// rewritten cell's sample point falls outside the lattice, where GDScript fails on the index: the
// whole prediction is refused rather than returned missing cells.
bool flips(const EditStore &store, const Lattice &lat, TypedArray<Vector3i> &solid, TypedArray<Vector3i> &air) {
	const LocalVector<int> xs = rewritten_cells(lat, 0);
	const LocalVector<int> ys = rewritten_cells(lat, 1);
	const LocalVector<int> zs = rewritten_cells(lat, 2);
	const float *sdf = lat.sdf.ptr();
	for (const int z : zs) {
		for (const int y : ys) {
			for (const int x : xs) {
				const Vector3i c(x, y, z);
				const Vector3 p = Vector3(c) + Vector3(1, 1, 1) * CELL_SAMPLE_OFFSET;
				const Vector3 l = (p - lat.origin) / lat.cell;
				const Vector3i i0(int64_t(Math::floor(l.x)), int64_t(Math::floor(l.y)), int64_t(Math::floor(l.z)));
				ERR_FAIL_COND_V_MSG(MIN(i0.x, MIN(i0.y, i0.z)) < 0 || MAX(i0.x, MAX(i0.y, i0.z)) > lat.dim - 2, false,
						"A rewritten cell's sample point lies outside the lattice: the cell size does not tile the unit grid.");
				const double was = store.sample(p);
				const double now = trilerp(lat, sdf, i0, l - Vector3(i0));
				if (was >= SOLID_THRESHOLD && now < SOLID_THRESHOLD) {
					solid.push_back(c);
				} else if (was < SOLID_THRESHOLD && now >= SOLID_THRESHOLD) {
					air.push_back(c);
				}
			}
		}
	}
	return true;
}

Dictionary result(const EditStore &store, const Lattice &lat) {
	TypedArray<Vector3i> solid;
	TypedArray<Vector3i> air;
	if (!flips(store, lat, solid, air)) {
		return Dictionary();
	}
	Dictionary out;
	out["origin"] = lat.origin;
	out["cell"] = lat.cell;
	out["dim"] = lat.dim;
	out["sdf"] = lat.sdf;
	out["region_lo"] = lat.origin;
	out["region_hi"] = lat.region_hi();
	out["writes"] = lat.writes;
	out["solid"] = solid;
	out["air"] = air;
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

} // namespace

// SdfLattice.sphere_stamp.
Dictionary EditStore::predict_sphere_stamp(Vector3 center, double radius, int op, double min_leaf) const {
	const Vector3 pad = Vector3(1, 1, 1) * (radius + min_leaf);
	const Vector3 first = ((center - pad) / min_leaf).floor();
	const Vector3 span = ((center + pad) / min_leaf).ceil() - first;
	Lattice lat(first * min_leaf, min_leaf, int(MAX(span.x, MAX(span.y, span.z))) + 1);
	fill(*this, lat, [&](const Vector3 &p, double before) {
		const double brush = p.distance_to(center) - radius;
		return op == OP_UNION ? MIN(before, brush) : MAX(before, -brush);
	});
	return result(*this, lat);
}

// VoxelImprint.lattice (world_box inlined).
Dictionary EditStore::predict_imprint(int shape, const PackedFloat64Array &dims, Transform3D xform, int op, double cell) const {
	ERR_FAIL_COND_V_MSG(csg_dim_count(shape) < 0, Dictionary(), "Unknown CsgSdf.Shape.");
	ERR_FAIL_COND_V_MSG(dims.size() != csg_dim_count(shape), Dictionary(), "Wrong dims count for the shape.");
	const double *d = dims.ptr();
	const Transform3D inverse = xform.affine_inverse();
	const AABB box = xform.xform(csg_local_aabb(shape, d)).grow(IMPRINT_MARGIN);
	const Vector3i lo = Vector3i((box.position / cell).floor()) - Vector3i(1, 1, 1);
	const Vector3i hi = Vector3i(((box.position + box.size) / cell).ceil()) + Vector3i(1, 1, 1);
	const Vector3i span = hi - lo;
	Lattice lat(Vector3(lo) * cell, cell, MAX(span.x, MAX(span.y, span.z)) + 1);
	fill(*this, lat, [&](const Vector3 &p, double existing) {
		const double dist = CLAMP(csg_sdf(shape, d, inverse.xform(p)), -SDF_BAND, SDF_BAND);
		return op == OP_UNION ? MIN(existing, dist) : MAX(existing, -dist);
	});
	return result(*this, lat);
}

// StoreWrite.lattice: the current field over the points' box plus a 1-cell margin, with each
// point overwritten in order (a repeated point compares against the earlier overwrite).
Dictionary EditStore::predict_work(const TypedArray<Vector3i> &points, const PackedFloat64Array &sdfs) const {
	ERR_FAIL_COND_V_MSG(points.is_empty(), Dictionary(), "No work: StoreWrite.lattice needs at least one point.");
	ERR_FAIL_COND_V_MSG(points.size() != sdfs.size(), Dictionary(), "One SDF value per point.");
	Vector3i lo = points[0];
	Vector3i hi = points[0];
	for (int64_t k = 0; k < points.size(); ++k) {
		const Vector3i p = points[k];
		lo = lo.min(p);
		hi = hi.max(p);
	}
	const Vector3i span = hi - lo + Vector3i(2, 2, 2);
	const Vector3i lo_cell = lo - Vector3i(1, 1, 1);
	Lattice lat(Vector3(lo_cell), 1.0, MAX(span.x, MAX(span.y, span.z)) + 1);
	fill(*this, lat, [](const Vector3 &, double before) { return before; });
	float *w = lat.sdf.ptrw();
	for (int64_t k = 0; k < points.size(); ++k) {
		const Vector3i i = Vector3i(points[k]) - lo_cell;
		const int at = voxel_dc::flat_index(i.x, i.y, i.z, lat.dim);
		lat.writes = lat.writes || double(w[at]) != sdfs[k];
		w[at] = float(sdfs[k]);
	}
	return result(*this, lat);
}
