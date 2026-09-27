#include "edit_store.h"

#include "core/templates/hash_set.h"

#include "carve_solver.h"
#include "edit_store_lattice.h"

// The thaw carve posed as a CarveProblem: every cell of the rewritten cube must end on its side (a
// planned cell air, every other cell where it is now), and the solver picks the corner values.

using namespace edit_store_lattice;

namespace {

constexpr double CARVE_MARGIN = 0.01;  // VoxelConstants.CELL_EDIT_SDF
constexpr double KEEP_MARGIN = 0.0001; // VoxelConstants.CELL_KEEP_SDF

struct Plan {
	HashSet<Vector3i> cells;
	Vector3i lo;
	Vector3i hi;
};

Plan make_plan(const TypedArray<Vector3i> &cells) {
	Plan plan;
	plan.lo = cells[0];
	plan.hi = cells[0];
	for (int64_t i = 0; i < cells.size(); ++i) {
		const Vector3i c = cells[i];
		plan.cells.insert(c);
		plan.lo = plan.lo.min(c);
		plan.hi = plan.hi.max(c);
	}
	return plan;
}

// The planned cells' corners plus `margin` cells on every side, squared to a cube, holding the field
// as it is (at margin 1, the box StoreWrite.lattice gives a work set of those corners). The solve
// holds the cube's faces as they are: the leaves beyond them keep their own corners there, so moving
// one would open a seam. The margin keeps every planned corner off them.
Lattice carve_lattice(const EditStore &store, const Plan &plan, int margin) {
	const Vector3i span = plan.hi - plan.lo + Vector3i(1, 1, 1);
	const Vector3i pad = Vector3i(1, 1, 1) * margin;
	Lattice lat(Vector3(plan.lo - pad), 1.0, MAX(span.x, MAX(span.y, span.z)) + 1 + 2 * margin);
	fill(store, lat, [](int, const Vector3 &, double before) { return before; });
	return lat;
}

struct CellSides {
	LocalVector<uint8_t> planned; // per cell
	LocalVector<uint8_t> solid;   // per cell: an unplanned cell that reads solid now, so must stay so
};

CellSides pose_cells(const EditStore &store, const Lattice &lat, const Plan &plan, voxel_dc::CarveProblem &p) {
	const int n = lat.dim - 1;
	const Vector3i origin(lat.origin);
	CellSides sides;
	sides.planned.resize(n * n * n);
	sides.solid.resize(n * n * n);
	p.side.resize(n * n * n);
	p.margin.resize(n * n * n);
	for (int z = 0; z < n; ++z) {
		for (int y = 0; y < n; ++y) {
			for (int x = 0; x < n; ++x) {
				const int c = voxel_dc::flat_index(x, y, z, n);
				const Vector3i cell = origin + Vector3i(x, y, z);
				const bool planned = plan.cells.has(cell);
				const bool solid = !planned && store.sample(cell_sample_point(cell)) < SOLID_THRESHOLD;
				sides.planned[c] = planned;
				sides.solid[c] = solid;
				p.side[c] = solid ? -1.0 : 1.0;
				p.margin[c] = planned ? CARVE_MARGIN : KEEP_MARGIN;
			}
		}
	}
	return sides;
}

// _carve_corners's rule (MpmStructure): a corner of a planned cell that no must-stay-solid cell
// touches is cleared to air. That clean-walled carve is what the solve stays closest to.
bool clears(const CellSides &sides, int n, int x, int y, int z) {
	bool planned = false;
	for (int k = 0; k < 8; ++k) {
		const int c = voxel_dc::flat_index(x - voxel_dc::CB[k][0], y - voxel_dc::CB[k][1], z - voxel_dc::CB[k][2], n);
		if (sides.solid[c]) {
			return false;
		}
		planned = planned || sides.planned[c];
	}
	return planned;
}

void pose_points(const Lattice &lat, const CellSides &sides, voxel_dc::CarveProblem &p) {
	const int d = lat.dim;
	const int total = d * d * d;
	p.target.resize(total);
	p.lo.resize(total);
	p.hi.resize(total);
	for (int z = 0; z < d; ++z) {
		for (int y = 0; y < d; ++y) {
			for (int x = 0; x < d; ++x) {
				const int i = voxel_dc::flat_index(x, y, z, d);
				const double now = lat.sdf[i];
				const bool inside = MIN(x, MIN(y, z)) > 0 && MAX(x, MAX(y, z)) < d - 1;
				p.target[i] = inside && clears(sides, d - 1, x, y, z) ? SDF_BAND : now;
				p.lo[i] = inside ? MIN(now, -SDF_BAND) : now;
				p.hi[i] = inside ? MAX(now, SDF_BAND) : now;
			}
		}
	}
}

voxel_dc::CarveProblem pose(const EditStore &store, const Lattice &lat, const Plan &plan) {
	voxel_dc::CarveProblem p;
	p.dim = lat.dim;
	pose_points(lat, pose_cells(store, lat, plan, p), p);
	return p;
}

TypedArray<Vector3i> world_cells(const Lattice &lat, const LocalVector<int> &flat) {
	const int n = lat.dim - 1;
	const Vector3i origin(lat.origin);
	TypedArray<Vector3i> out;
	for (const int c : flat) {
		out.push_back(origin + Vector3i(c % n, (c / n) % n, c / (n * n)));
	}
	return out;
}

Dictionary refusal(const Lattice &lat, const voxel_dc::CarveResult &solved, int margin) {
	Dictionary out;
	out["conflict"] = world_cells(lat, solved.conflict);
	out["proven"] = solved.proven;
	out["pinned"] = solved.pinned;
	out["margin"] = margin;
	out["sweeps"] = solved.sweeps;
	return out;
}

} // namespace

// A proof that leans on the cube's held faces may be the box's doing, not the plan's, so the box
// grows a cell on every side and the solve runs again, up to `max_margin`.
Dictionary EditStore::predict_carve(const TypedArray<Vector3i> &cells, int max_margin) const {
	ERR_FAIL_COND_V_MSG(cells.is_empty(), Dictionary(), "No cells to carve.");
	ERR_FAIL_COND_V_MSG(max_margin < 1, Dictionary(), "The carve's box needs a margin of at least 1 cell.");
	const Plan plan = make_plan(cells);
	for (int margin = 1;; ++margin) {
		Lattice lat = carve_lattice(*this, plan, margin);
		const voxel_dc::CarveResult solved = voxel_dc::solve_carve(pose(*this, lat, plan));
		if (!solved.solved) {
			if (solved.pinned && margin < max_margin) {
				continue;
			}
			return refusal(lat, solved, margin);
		}
		float *w = lat.sdf.ptrw();
		for (uint32_t i = 0; i < solved.values.size(); ++i) {
			w[i] = solved.values[i];
		}
		// fill() compared the pre-solve values; the dry run in prediction() answers for these.
		lat.writes = false;
		Dictionary out = prediction(*this, lat);
		out["conflict"] = TypedArray<Vector3i>();
		out["proven"] = false;
		out["pinned"] = false;
		out["margin"] = margin;
		out["sweeps"] = solved.sweeps;
		return out;
	}
}
