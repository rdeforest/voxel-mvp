#include "carve_solver.h"

#include "core/math/math_funcs.h"

#include "octree_geometry.h"
#include "sdf_field.h"

// Dual coordinate ascent toward the least-squares projection of `target` onto the cells'
// half-spaces within the bounds (Hildreth's method with the bounds folded into the primal: v =
// clamp(target + sum of the cells' pushes)). Each cell's row has 8 entries, so a sweep costs
// O(cells) and memory is O(points): it scales to the thousands of cells a thaw plans, where a dense
// simplex tableau would not. Its iterates approach the feasible set from outside, so each cell aims
// at `scale` times its margin and the solve stops at the first iterate whose float32 values meet the
// true margins: a feasible field near the projection, not the projection itself.
//
// When no values exist, the multipliers of the cells in conflict grow without bound along a Farkas
// ray. Their growth over a stretch of sweeps is a candidate ray; prove_infeasible checks it exactly
// against the bounds, so a reported conflict is a proof, never a timeout guessed as one. A ray can
// prove only the scaled margins impossible while the true ones hold; then the scale's excess over 1
// halves and the solve restarts, so such a plan is solved rather than left to the sweep budget.

namespace voxel_dc {
namespace {

constexpr int MAX_SWEEPS = 20000;
constexpr int CHECK_EVERY = 8;   // sweeps between tests of the float32 values against the margins
constexpr int RAY_EVERY = 256;   // sweeps between infeasibility proofs attempted
constexpr double FIRST_SCALE = 2.0;
constexpr double LAST_SCALE = 1.0 + 1.0 / 64.0;
constexpr double RAY_FLOOR = 1e-6; // a ray component this small against the largest is noise
constexpr double PROOF_SLACK = 1e-9;

struct Rows {
	int cells = 0;
	LocalVector<int> corners;        // 8 lattice points per cell, in CB order
	LocalVector<double> step_scale;  // 1 / how fast the cell's reading moves with its multiplier
};

struct Iterate {
	LocalVector<double> lambda;  // per cell
	LocalVector<double> pushed;  // per point: target plus every cell's push, before the bounds
	LocalVector<double> value;   // per point: pushed, clamped to the bounds
};

Rows build_rows(const CarveProblem &p) {
	const int n = p.dim - 1;
	Rows rows;
	rows.cells = n * n * n;
	rows.corners.resize(rows.cells * 8);
	rows.step_scale.resize(rows.cells);
	for (int z = 0; z < n; ++z) {
		for (int y = 0; y < n; ++y) {
			for (int x = 0; x < n; ++x) {
				const int c = flat_index(x, y, z, n);
				int movable = 0;
				for (int k = 0; k < 8; ++k) {
					const int pt = flat_index(x + CB[k][0], y + CB[k][1], z + CB[k][2], p.dim);
					rows.corners[c * 8 + k] = pt;
					movable += p.lo[pt] < p.hi[pt] ? 1 : 0;
				}
				rows.step_scale[c] = 64.0 / double(MAX(movable, 1));
			}
		}
	}
	return rows;
}

Iterate start(const CarveProblem &p, const Rows &rows) {
	Iterate it;
	it.lambda.resize(rows.cells);
	it.pushed.resize(p.target.size());
	it.value.resize(p.target.size());
	for (int c = 0; c < rows.cells; ++c) {
		it.lambda[c] = 0.0;
	}
	for (uint32_t pt = 0; pt < p.target.size(); ++pt) {
		it.pushed[pt] = p.target[pt];
		it.value[pt] = CLAMP(p.target[pt], p.lo[pt], p.hi[pt]);
	}
	return it;
}

double reading(const Rows &rows, const LocalVector<double> &value, int c) {
	double sum = 0.0;
	for (int k = 0; k < 8; ++k) {
		sum += value[rows.corners[c * 8 + k]];
	}
	return sum / 8.0;
}

// One pass of exact-step coordinate ascent on each cell's multiplier (conservative where a corner
// sits at a bound, since the step assumes every movable corner moves).
void sweep(const CarveProblem &p, const Rows &rows, double scale, Iterate &it) {
	for (int c = 0; c < rows.cells; ++c) {
		const double short_by = scale * p.margin[c] - p.side[c] * reading(rows, it.value, c);
		const double next = MAX(0.0, it.lambda[c] + short_by * rows.step_scale[c]);
		const double push = (next - it.lambda[c]) * p.side[c] / 8.0;
		if (push == 0.0) {
			continue;
		}
		it.lambda[c] = next;
		for (int k = 0; k < 8; ++k) {
			const int pt = rows.corners[c * 8 + k];
			it.pushed[pt] += push;
			it.value[pt] = CLAMP(it.pushed[pt], p.lo[pt], p.hi[pt]);
		}
	}
}

// The cells whose reading misses its margin once the values are stored as float32 and read back by
// the store's own trilerp at the centre.
LocalVector<int> unmet(const CarveProblem &p, const Rows &rows, const LocalVector<float> &stored) {
	LocalVector<int> out;
	for (int c = 0; c < rows.cells; ++c) {
		float corners[8];
		for (int k = 0; k < 8; ++k) {
			corners[k] = stored[rows.corners[c * 8 + k]];
		}
		if (p.side[c] * trilerp(corners, 0.5, 0.5, 0.5) < p.margin[c]) {
			out.push_back(c);
		}
	}
	return out;
}

LocalVector<float> stored(const Iterate &it) {
	LocalVector<float> out;
	out.resize(it.value.size());
	for (uint32_t pt = 0; pt < it.value.size(); ++pt) {
		out[pt] = float(it.value[pt]);
	}
	return out;
}

// Farkas: with y >= 0, every solution has sum_c y_c side_c reading_c >= sum_c y_c margin_c. That sum
// is linear in the values, so its largest value within the bounds puts each value at one of its
// bounds; if even that falls short, no solution exists. A weight on a held point (`pinned`) means the
// proof may be the held values' doing.
struct Proof {
	bool infeasible = false;
	bool pinned = false;
};

Proof prove_infeasible(const CarveProblem &p, const Rows &rows, const LocalVector<double> &y, double margin_scale) {
	LocalVector<double> weight;
	weight.resize(p.target.size());
	for (uint32_t pt = 0; pt < weight.size(); ++pt) {
		weight[pt] = 0.0;
	}
	double need = 0.0;
	for (int c = 0; c < rows.cells; ++c) {
		need += y[c] * margin_scale * p.margin[c];
		for (int k = 0; k < 8; ++k) {
			weight[rows.corners[c * 8 + k]] += y[c] * p.side[c] / 8.0;
		}
	}
	Proof proof;
	double best = 0.0;
	double scale = need;
	for (uint32_t pt = 0; pt < weight.size(); ++pt) {
		best += weight[pt] > 0.0 ? weight[pt] * p.hi[pt] : weight[pt] * p.lo[pt];
		scale += Math::abs(weight[pt]) * MAX(Math::abs(p.lo[pt]), Math::abs(p.hi[pt]));
		proof.pinned = proof.pinned || (weight[pt] != 0.0 && p.lo[pt] == p.hi[pt]);
	}
	proof.infeasible = need > 0.0 && best < need - PROOF_SLACK * scale;
	return proof;
}

// The multipliers' growth since `before`, with noise-sized components dropped: a candidate ray.
LocalVector<double> growth(const Iterate &it, const LocalVector<double> &before) {
	LocalVector<double> y;
	y.resize(it.lambda.size());
	double largest = 0.0;
	for (uint32_t c = 0; c < y.size(); ++c) {
		y[c] = MAX(0.0, it.lambda[c] - before[c]);
		largest = MAX(largest, y[c]);
	}
	for (uint32_t c = 0; c < y.size(); ++c) {
		y[c] = y[c] > RAY_FLOOR * largest ? y[c] : 0.0;
	}
	return y;
}

LocalVector<int> support(const LocalVector<double> &y) {
	LocalVector<int> out;
	for (uint32_t c = 0; c < y.size(); ++c) {
		if (y[c] > 0.0) {
			out.push_back(int(c));
		}
	}
	return out;
}

} // namespace

CarveResult solve_carve(const CarveProblem &p) {
	const Rows rows = build_rows(p);
	Iterate it = start(p, rows);
	LocalVector<double> before = it.lambda;
	double scale = FIRST_SCALE;
	CarveResult result;
	for (result.sweeps = 0; result.sweeps < MAX_SWEEPS; ++result.sweeps) {
		if (result.sweeps % CHECK_EVERY == 0) {
			result.values = stored(it);
			if (unmet(p, rows, result.values).is_empty()) {
				result.solved = true;
				return result;
			}
		}
		if (result.sweeps > 0 && result.sweeps % RAY_EVERY == 0) {
			const LocalVector<double> y = growth(it, before);
			const Proof proof = prove_infeasible(p, rows, y, 1.0);
			if (proof.infeasible) {
				result.proven = true;
				result.pinned = proof.pinned;
				result.conflict = support(y);
				result.values.clear();
				return result;
			}
			if (scale > LAST_SCALE && prove_infeasible(p, rows, y, scale).infeasible) {
				scale = 1.0 + (scale - 1.0) / 2.0;
				it = start(p, rows);
			}
			before = it.lambda;
		}
		sweep(p, rows, scale, it);
	}
	result.values = stored(it);
	result.conflict = unmet(p, rows, result.values);
	result.solved = result.conflict.is_empty();
	if (!result.solved) {
		result.values.clear();
	}
	return result;
}

} // namespace voxel_dc
