#include "edit_store.h"

#include "edit_store_lattice.h"
#include "octree_geometry.h"

// EditStore.lattice_writes: write_region as a dry run, settling whether a predicted lattice changes
// any stored corner. Split from edit_store_predict.cpp.

using edit_store_lattice::is_write_leaf;
using edit_store_lattice::overlaps;

// A write_region call as lattice_writes walks it. A lattice point is a corner of up to eight
// leaves, so `written` and `settled` keep per lattice point (x fastest) what one leaf worked out there
// for the next: the array and the generator are read once per point rather than once per leaf corner.
struct EditStore::RegionWrite {
	static constexpr uint8_t WRITTEN_READ = 1;   // `written` holds the array's value here
	static constexpr uint8_t GENERATOR_KEPT = 2; // an unedited leaf's corner here keeps the generator's value

	voxel_dc::ArrayField field;
	double cell;
	Vector3 rmin;
	Vector3 rmax;
	LocalVector<double> axis_points[3]; // lattice point k's coordinate on each axis
	int corner_step[8];                 // corner i's slot minus corner 0's
	LocalVector<float> written;
	LocalVector<uint8_t> settled;

	RegionWrite(const PackedFloat32Array &sdf, int dim, const Vector3 &origin, double p_cell) :
			field(sdf.ptr(), dim, origin, p_cell), cell(p_cell), rmin(origin),
			rmax(origin + Vector3(1, 1, 1) * (double(dim - 1) * p_cell)) {
		for (int axis = 0; axis < 3; ++axis) {
			axis_points[axis].resize(dim);
			for (int k = 0; k < dim; ++k) {
				axis_points[axis][k] = origin[axis] + double(k) * cell;
			}
		}
		for (int i = 0; i < 8; ++i) {
			corner_step[i] = voxel_dc::flat_index(voxel_dc::CB[i][0], voxel_dc::CB[i][1], voxel_dc::CB[i][2], dim);
		}
		written.resize(uint32_t(sdf.size()));
		settled.resize(uint32_t(sdf.size()));
		memset(settled.ptr(), 0, settled.size());
	}

	// The slot of the leaf's corner 0 when each of its corners is a lattice point to the bit (so leaves
	// share a slot only at an identical corner), else -1: a leaf finer than the cell, or past the lattice.
	int corner_slot(const Vector3 &o, double s) const {
		const Vector3 lo = voxel_dc::corner(o, s, 0);
		const Vector3 hi = voxel_dc::corner(o, s, 7);
		int slot = 0;
		int stride = 1;
		for (int axis = 0; axis < 3; ++axis) {
			const int k = int(Math::round((lo[axis] - field.origin[axis]) / cell));
			if (k < 0 || k + 1 >= field.dim || axis_points[axis][k] != lo[axis] || axis_points[axis][k + 1] != hi[axis]) {
				return -1;
			}
			slot += k * stride;
			stride *= field.dim;
		}
		return slot;
	}
};

// lattice_writes: _write_region (edit_store.cpp) without the write — the same descent, stopping at
// the first corner it would change.
bool EditStore::lattice_writes(const PackedFloat32Array &sdf, int dim, Vector3 origin, double cell) const {
	ERR_FAIL_COND_V_MSG(dim < 2 || !(cell > 0.0) || sdf.size() != int64_t(dim) * dim * dim, false,
			"Not a lattice: sdf must hold dim^3 values, dim >= 2, cell > 0.");
	if (nodes.is_empty()) {
		return false;
	}
	RegionWrite write(sdf, dim, origin, cell);
	return _write_changes(0, write);
}

bool EditStore::_write_changes(int idx, RegionWrite &write) const {
	const Node &n = nodes[idx];
	if (n.is_leaf()) {
		return _leaf_write_changes(n.origin, n.size, _leaf_field(idx), write);
	}
	if (!overlaps(n.origin, n.size, write.rmin, write.rmax)) {
		return false;
	}
	for (int i = 0; i < 8; ++i) {
		if (_write_changes(n.children[i], write)) {
			return true;
		}
	}
	return false;
}

// A leaf as _write_region finds it, holding node `field`'s field (-1 = unedited, the generator). One
// coarser than the write's cell is split as _subdivide splits it: its children hold the same field,
// and the corners compared are the ones they would store (_held_corner).
bool EditStore::_leaf_write_changes(const Vector3 &o, double s, int field, RegionWrite &write) const {
	if (!overlaps(o, s, write.rmin, write.rmax)) {
		return false;
	}
	if (is_write_leaf(s, write.cell)) {
		const int slot = write.corner_slot(o, s);
		for (int i = 0; i < 8; ++i) {
			const int at = slot < 0 ? -1 : slot + write.corner_step[i];
			// An unedited leaf's corner depends on the point alone, so another unedited leaf settled it.
			if (field < 0 && at >= 0 && (write.settled[at] & RegionWrite::GENERATOR_KEPT)) {
				continue;
			}
			const float held = field < 0 ? 0.0f : _held_corner(field, o, s, i);
			if (_corner_changes(voxel_dc::corner(o, s, i), at, field < 0 ? nullptr : &held, write)) {
				return true;
			}
		}
		return false;
	}
	const double half = s * 0.5;
	for (int i = 0; i < 8; ++i) {
		const Vector3 child_origin = o + Vector3(voxel_dc::CB[i][0], voxel_dc::CB[i][1], voxel_dc::CB[i][2]) * half;
		if (_leaf_write_changes(child_origin, half, field, write)) {
			return true;
		}
	}
	return false;
}

// Whether the write changes corner `c`, which holds *held (null: the generator's value), at lattice
// point `slot` (-1: none), recording in `write` what the next leaf sharing the point can reuse.
bool EditStore::_corner_changes(const Vector3 &c, int slot, const float *held, RegionWrite &write) const {
	if (slot < 0) {
		return float(write.field.sample(c)) != (held ? *held : float(_gen.sample(c)));
	}
	uint8_t &settled = write.settled[slot];
	if (!(settled & RegionWrite::WRITTEN_READ)) {
		write.written[slot] = float(write.field.sample(c));
		settled |= RegionWrite::WRITTEN_READ;
	}
	if (held) {
		return write.written[slot] != *held;
	}
	if (write.written[slot] != float(_gen.sample(c))) {
		return true;
	}
	settled |= RegionWrite::GENERATOR_KEPT;
	return false;
}
