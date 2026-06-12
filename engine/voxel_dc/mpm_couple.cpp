#include "mpm_sim.h"

#include "core/math/math_funcs.h"
#include "core/templates/hash_map.h"

// Thaw/freeze coupling between MpmSim and the EditStore (doc 12 — the one remaining research
// risk: moving material between the simulated particle representation and the static field).
// FREEZE: rasterise settled particles back into the field as SDF + material. (THAW — seeding
// particles from a field region — joins this file next.)

// Nearest-particle distance to `wp`, searching only the bins within ±R of node (ix,iy,iz).
static double nearest_particle_dist(const Vector3 &wp, int ix, int iy, int iz, int dim, int R,
		const HashMap<int, LocalVector<int>> &bins, const LocalVector<Vector3> &x) {
	double dmin = 1e30;
	for (int dz = -R; dz <= R; dz++) {
		const int bz = iz + dz;
		if (bz < 0 || bz >= dim) {
			continue;
		}
		for (int dy = -R; dy <= R; dy++) {
			const int by = iy + dy;
			if (by < 0 || by >= dim) {
				continue;
			}
			for (int dx = -R; dx <= R; dx++) {
				const int bx = ix + dx;
				if (bx < 0 || bx >= dim) {
					continue;
				}
				HashMap<int, LocalVector<int>>::ConstIterator it = bins.find(bx + by * dim + bz * dim * dim);
				if (!it) {
					continue;
				}
				const LocalVector<int> &list = it->value;
				for (uint32_t k = 0; k < list.size(); k++) {
					dmin = MIN(dmin, wp.distance_to(x[list[k]]));
				}
			}
		}
	}
	return dmin;
}

// Rasterise the current particles into the EditStore over their bounding box: each grid point's
// SDF is (distance to the nearest particle − radius), so the surface is a union of spheres
// around the cloud; cells inside take `material_index`. A spatial bin-hash makes it
// O(grid + particles); returns {origin, dim} of the region written.
//
// The freeze is a DEPOSIT, not a replace: it unions with the existing field (min of the two
// SDFs) so it only ADDS the settled material and never erases the terrain the cloud's bounding
// box spans. (write_region overwrites the whole box, so without the union every cell the cloud
// doesn't occupy would punch the mountain to air — a cloud-sized cube carved out around the
// chunk.) Existing solid keeps its own material; only cells the cloud newly fills take material_index.
Dictionary MpmSim::rasterize_to_store(Ref<EditStore> store, double cell, double radius, int material_index) {
	Dictionary out;
	if (store.is_null() || _x.is_empty()) {
		return out;
	}
	Vector3 lo = _x[0], hi = _x[0];
	for (uint32_t i = 0; i < _x.size(); i++) {
		lo = lo.min(_x[i]);
		hi = hi.max(_x[i]);
	}
	const double margin = Math::ceil(radius) + cell; // room for the surface band + apron
	const Vector3 origin(Math::floor(lo.x - margin), Math::floor(lo.y - margin), Math::floor(lo.z - margin));
	const double span = MAX(hi.x - origin.x, MAX(hi.y - origin.y, hi.z - origin.z)) + margin;
	const int dim = int(Math::ceil(span / cell)) + 1;
	const double inv_cell = 1.0 / cell;

	// Bin particles by their cell (relative to origin); key = linear bin index. Lets each grid
	// point test only nearby particles — O(grid + particles), not O(grid·particles).
	HashMap<int, LocalVector<int>> bins;
	for (uint32_t p = 0; p < _x.size(); p++) {
		const int bx = int(Math::floor((_x[p].x - origin.x) * inv_cell));
		const int by = int(Math::floor((_x[p].y - origin.y) * inv_cell));
		const int bz = int(Math::floor((_x[p].z - origin.z) * inv_cell));
		if (bx < 0 || by < 0 || bz < 0 || bx >= dim || by >= dim || bz >= dim) {
			continue;
		}
		bins[bx + by * dim + bz * dim * dim].push_back(int(p));
	}
	const int R = int(Math::ceil(radius * inv_cell)) + 1; // bins to search around each node

	PackedFloat32Array sdf;
	PackedByteArray idx;
	sdf.resize(dim * dim * dim);
	idx.resize(dim * dim * dim);
	float *sp = sdf.ptrw();
	uint8_t *ip = idx.ptrw();
	for (int iz = 0; iz < dim; iz++) {
		for (int iy = 0; iy < dim; iy++) {
			for (int ix = 0; ix < dim; ix++) {
				const Vector3 wp = origin + Vector3(ix, iy, iz) * cell;
				const double p_sdf = nearest_particle_dist(wp, ix, iy, iz, dim, R, bins, _x) - radius;
				const double existing = store->sample(wp);
				const int n = ix + iy * dim + iz * dim * dim;
				sp[n] = float(MIN(existing, p_sdf)); // union: deposit, never erase existing terrain
				if (existing < 0.0) {
					ip[n] = uint8_t(store->material_at(wp)); // existing terrain keeps its material
				} else {
					ip[n] = (p_sdf < 0.0) ? uint8_t(material_index) : 0; // cloud fills this cell, or air
				}
			}
		}
	}
	store->write_region(sdf, idx, dim, origin, cell);
	out["origin"] = origin;
	out["dim"] = dim;
	return out;
}

// THAW: seed particles from the solid cells of a store region. Each cell whose centre samples
// solid gets `ppa`³ particles (at rest, F = identity). The thaw half of the coupling — what
// converts a region of static terrain into simulated material when it loses support. Returns
// the number of particles added. `origin`/`dim`/`cell` describe a region of `dim` cells per axis.
int MpmSim::thaw_from_store(Ref<EditStore> store, Vector3 origin, int dim, double cell, int ppa, double mass, double volume) {
	if (store.is_null()) {
		return 0;
	}
	const double step = cell / double(ppa);
	const Vector3 half(0.5 * cell, 0.5 * cell, 0.5 * cell);
	int added = 0;
	for (int iz = 0; iz < dim; iz++) {
		for (int iy = 0; iy < dim; iy++) {
			for (int ix = 0; ix < dim; ix++) {
				const Vector3 c0 = origin + Vector3(ix, iy, iz) * cell;
				if (store->sample(c0 + half) >= 0.0) {
					continue; // air cell — nothing to thaw
				}
				for (int sz = 0; sz < ppa; sz++) {
					for (int sy = 0; sy < ppa; sy++) {
						for (int sx = 0; sx < ppa; sx++) {
							add_particle(c0 + Vector3((sx + 0.5) * step, (sy + 0.5) * step, (sz + 0.5) * step), mass, volume);
							added++;
						}
					}
				}
			}
		}
	}
	return added;
}
