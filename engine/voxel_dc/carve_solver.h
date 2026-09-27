#ifndef CARVE_SOLVER_H
#define CARVE_SOLVER_H

// Corner values for a cube of cells that each read the mean of their 8 lattice corners (a cell's
// sample point is its centre, where the trilerp is that mean), such that every cell reads past zero
// on its required side by its margin. EditStore::predict_carve poses it for a thaw.

#include "core/templates/local_vector.h"

namespace voxel_dc {

struct CarveProblem {
	int dim = 0;                 // lattice points per axis; the cells are (dim - 1)^3, x fastest
	LocalVector<double> target;  // per point: the value wanted there if no cell needs otherwise
	LocalVector<double> lo;      // per point: the range it may take (lo == hi fixes it)
	LocalVector<double> hi;
	LocalVector<double> side;    // per cell: +1 must read >= margin (air), -1 <= -margin (solid)
	LocalVector<double> margin;  // per cell
};

struct CarveResult {
	bool solved = false;
	bool proven = false;         // unsolved: `conflict` carries a proof that no values exist
	bool pinned = false;         // proven: the proof leans on points held fixed (lo == hi), so it
	                             // proves only that no values exist with those points held
	int sweeps = 0;
	LocalVector<float> values;   // solved: per point, as a lattice stores it
	LocalVector<int> conflict;   // unsolved: cells (flat index) that cannot all hold together, or,
	                             // unproven, the cells still unmet when the sweep budget ran out
	                             // (a plan that meets its margins but not 1/64 more than them can
	                             // end here although it is solvable)
};

// Values within the bounds that meet every cell, found by dual ascent toward the least-squares
// projection of `target` and stopped at the first that meet (so near it, not nearest), or why none.
CarveResult solve_carve(const CarveProblem &problem);

} // namespace voxel_dc

#endif // CARVE_SOLVER_H
