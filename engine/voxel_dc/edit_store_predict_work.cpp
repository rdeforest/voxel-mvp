#include "edit_store.h"

#include "core/templates/hash_map.h"

#include "edit_store_lattice.h"

// The lattice-point writers: StoreWrite.lattice (a work set's field) and the work sets the
// BellSculptAction (raise / lower) and FlattenAction reshapes generate. Bit-exactness rules:
// edit_store_lattice.h.

using namespace edit_store_lattice;

namespace {

// A work set: new SDF values at store lattice points (LatticeEdit, less the material).
struct Work {
	LocalVector<Vector3i> points;
	LocalVector<double> sdfs;

	void add(const Vector3i &point, double sdf) {
		points.push_back(point);
		sdfs.push_back(sdf);
	}
};

// StoreWrite.lattice: the current field over the points' box plus a 1-cell margin, with each
// point overwritten in order (a repeated point compares against the earlier overwrite).
Lattice work_lattice(const EditStore &store, const Work &work) {
	Vector3i lo = work.points[0];
	Vector3i hi = work.points[0];
	for (const Vector3i &p : work.points) {
		lo = lo.min(p);
		hi = hi.max(p);
	}
	const Vector3i span = hi - lo + Vector3i(2, 2, 2);
	const Vector3i lo_cell = lo - Vector3i(1, 1, 1);
	Lattice lat(Vector3(lo_cell), 1.0, MAX(span.x, MAX(span.y, span.z)) + 1);
	fill(store, lat, [](const Vector3 &, double before) { return before; });
	float *w = lat.sdf.ptrw();
	for (uint32_t k = 0; k < work.points.size(); ++k) {
		const Vector3i i = work.points[k] - lo_cell;
		const int at = voxel_dc::flat_index(i.x, i.y, i.z, lat.dim);
		const float now = float(work.sdfs[k]);
		lat.writes = lat.writes || w[at] != now;
		w[at] = now;
	}
	return lat;
}

Dictionary work_prediction(const EditStore &store, const Work &work) {
	if (work.points.is_empty()) {
		return Dictionary();
	}
	Lattice lat = work_lattice(store, work);
	return prediction(store, lat);
}

// VoxelUtils.for_each_in_bounding_box: every integer point from floor(origin) up to (excluding)
// ceil(origin + size), x outermost.
template <typename Visit>
void for_each_in_box(const Vector3 &origin, const Vector3 &size, Visit visit) {
	const Vector3i from(origin.floor());
	const Vector3i to((origin + size).ceil());
	for (int x = from.x; x < to.x; ++x) {
		for (int y = from.y; y < to.y; ++y) {
			for (int z = from.z; z < to.z; ++z) {
				visit(Vector3i(x, y, z));
			}
		}
	}
}

// One FlattenAction column: whether the cut reaches an existing surface on each side of the plane.
struct Column {
	bool pos_has_air = false;
	bool neg_has_solid = false;
};

struct Candidate {
	Vector3i point;
	Vector3i column;
	double plane_dist = 0.0;
	bool was_solid = false;
};

} // namespace

Dictionary EditStore::predict_work(const TypedArray<Vector3i> &points, const PackedFloat64Array &sdfs) const {
	ERR_FAIL_COND_V_MSG(points.is_empty(), Dictionary(), "No work: StoreWrite.lattice needs at least one point.");
	ERR_FAIL_COND_V_MSG(points.size() != sdfs.size(), Dictionary(), "One SDF value per point.");
	Work work;
	for (int64_t k = 0; k < points.size(); ++k) {
		work.add(points[k], sdfs[k]);
	}
	return work_prediction(*this, work);
}

// BellSculptAction._compute_work: every lattice point in the brush's XZ disc takes its current value
// plus a quartic bell of height `peak` at the centre column.
Dictionary EditStore::predict_bell(Vector3 center, double radius, double peak) const {
	const double r2 = radius * radius;
	Work work;
	for_each_in_box(center - Vector3(1, 1, 1) * radius, Vector3(1, 1, 1) * (radius * 2.0), [&](const Vector3i &point) {
		const double dx = double(point.x) - center.x;
		const double dz = double(point.z) - center.z;
		const double d2 = dx * dx + dz * dz;
		if (d2 >= r2) {
			return;
		}
		const double t = d2 / r2;
		const double falloff = (1.0 - t) * (1.0 - t);
		work.add(point, sample(Vector3(point)) + peak * falloff);
	});
	return work_prediction(*this, work);
}

// FlattenAction._compute_work: each lattice point within `radius` of the plane takes its signed
// distance to it, where that cuts solid above the plane or fills air below it — but only in a
// column (the points sharing a rounded lateral position) whose cut reaches an existing surface on
// that side. Emitted in visiting order, not FlattenAction's column order; no point repeats, so the
// field is the same.
Dictionary EditStore::predict_flatten(Vector3 plane_point, Vector3 normal, double radius) const {
	LocalVector<Candidate> candidates;
	HashMap<Vector3i, Column> columns;
	for_each_in_box(plane_point - Vector3(1, 1, 1) * radius, Vector3(1, 1, 1) * (radius * 2.0), [&](const Vector3i &point) {
		const double plane_dist = normal.dot(Vector3(point) - plane_point);
		if (Math::abs(plane_dist) > radius) {
			return;
		}
		const Vector3 lateral = Vector3(point) - normal * plane_dist;
		const Vector3i key(int64_t(Math::round(lateral.x)), int64_t(Math::round(lateral.y)), int64_t(Math::round(lateral.z)));
		const bool is_solid = sample(Vector3(point)) < SOLID_THRESHOLD;
		Column &column = columns[key];
		column.pos_has_air = column.pos_has_air || (plane_dist > 0.0 && !is_solid);
		column.neg_has_solid = column.neg_has_solid || (plane_dist < 0.0 && is_solid);
		candidates.push_back({ point, key, plane_dist, is_solid });
	});
	Work work;
	for (const Candidate &c : candidates) {
		const Column &column = columns[c.column];
		if ((c.plane_dist > 0.0 && column.pos_has_air && c.was_solid) ||
				(c.plane_dist < 0.0 && column.neg_has_solid && !c.was_solid)) {
			work.add(c.point, c.plane_dist);
		}
	}
	return work_prediction(*this, work);
}
