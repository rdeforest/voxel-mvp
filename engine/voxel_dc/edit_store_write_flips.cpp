#include "edit_store.h"

#include "edit_store_lattice.h"

// write_region measured: the cells the write flipped, each rewritten cell's sample read just before
// and just after it (the ground truth the events and the structural sim follow — see
// SdfLattice.write). test_lattice_write_flips gates it against the GDScript measurement it replaced
// (CellFlips.snapshot / since, now in test/support/lattice_oracle.gd).

using namespace edit_store_lattice;

namespace {

// Each rewritten cell's sample value before the write, and its material where it was solid (what
// a cell the write empties was made of: material_at reads it from the leaf the write may repaint;
// a byte, as a leaf stores it and write_region's indices carry it).
struct Before {
	LocalVector<Vector3i> cells;
	LocalVector<double> values;
	LocalVector<uint8_t> materials;
};

} // namespace

Dictionary EditStore::write_region_flips(const PackedFloat32Array &sdf, const PackedByteArray &indices, int dim,
		Vector3 origin, double cell) {
	const Lattice lat(sdf, dim, origin, cell);
	ERR_FAIL_COND_V_MSG(!lat.is_valid(), Dictionary(), "Not a lattice: sdf must hold dim^3 values, dim >= 2, cell > 0.");
	Before before;
	for_each_rewritten_cell(lat, [&](const Vector3i &c) {
		const Vector3 p = cell_sample_point(c);
		const double was = sample(p);
		before.cells.push_back(c);
		before.values.push_back(was);
		before.materials.push_back(was < SOLID_THRESHOLD ? uint8_t(material_at(p)) : 0);
		return true;
	});

	write_region(sdf, indices, dim, origin, cell);

	TypedArray<Vector3i> solid;
	TypedArray<Vector3i> air;
	PackedByteArray air_materials;
	bool changed = false;
	for (uint32_t i = 0; i < before.cells.size(); ++i) {
		const double now = sample(cell_sample_point(before.cells[i]));
		changed = changed || now != before.values[i];
		const Flip f = flip(before.values[i], now);
		if (f == FLIP_TO_SOLID) {
			solid.push_back(before.cells[i]);
		} else if (f == FLIP_TO_AIR) {
			air.push_back(before.cells[i]);
			air_materials.push_back(before.materials[i]);
		}
	}
	Dictionary out;
	out["solid"] = solid;
	out["air"] = air;
	out["air_materials"] = air_materials;
	out["changed"] = changed;
	return out;
}
