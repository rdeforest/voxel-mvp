#ifndef DC_EDIT_STORE_SOURCE_H
#define DC_EDIT_STORE_SOURCE_H

// The world-fixed field source (doc 16 THE GOAL): samples the EditStore field (generator + edits)
// DIRECTLY, with a transient graded min/max accel (a Clipmap reused as the prune structure) baked
// over the resident window. This is the substrate the persistent/incremental world octree grows on.

#include "dc_clipmap_source.h" // Clipmap (the accel) + Level + SdfSource
#include "dc_mesh_common.h"    // g_mesh_threads, parallel_for
#include "edit_store.h"

#include "core/math/math_funcs.h"
#include "core/templates/local_vector.h"

namespace voxel_dc {
namespace dc_mesh {

// World-fixed field source (doc 16 THE GOAL): samples the EditStore field (generator + edits)
// DIRECTLY at each cell — no concentric clipmap levels, no geomorph blend. The octree's lattice is
// world-anchored (1 lattice unit = base_cell metres; lattice (0,0,0) sits at world_origin), so a
// fixed feature always falls in the same cells regardless of viewpoint. `surface_free` returns false
// for now (dense build to the floor — the exact sparse prune over direct sampling is a later stage;
// per manifesto #8 the extra worker-thread cost is detail-scaling, never framerate).
struct EditStoreSource : public SdfSource {
	const EditStore *store;
	Vector3 world_origin; // lattice coords of octree (0,0,0)
	double base_cell;     // world metres per lattice unit

	// (P1+P2, doc 17) transient GRADED min/max acceleration structure for the prune: concentric levels in
	// OCTREE-LOCAL lattice, res 2^k doubling outward (fine near, coarse far — same per-level sample count, so
	// the bake is bounded even over the horizon). `Clipmap::surface_free` ANDs the levels: the finest level
	// covering a box decides, so it can't miss a crossing at the build floor's resolution. Skips building the
	// ~99.8% empty cells at EVERY distance — grading the floor alone doesn't (far empties still build coarse).
	Clipmap accel;
	LocalVector<PackedFloat32Array> accel_held; // backs the levels' data ptrs
	bool has_accel = false;
	Vector3i accel_win_lo, accel_win_hi;        // octree-local window the current accel covers — reused while unchanged
	int bake_count = 0;                         // full accel bakes run so far (a test/perf signal; reuse leaves it flat)
	static const int ACCEL_DIM = 65;            // samples per level axis. Small on purpose: the accel bake is
	                                            // a fixed mesh-lag cost (independent of eps), so keeping it
	                                            // cheap frees the lag budget for the controller to refine eps.

	// (P2, doc 17) graded data floor: the build descends only as fine as a cell would RENDER. A cell of
	// size s at distance d projects to ~s*proj/d px, so the floor where that ≈ eps_px is s = eps_px*d/proj
	// → floor_k = eps_px/proj. Far cells stop coarse (few cells → horizon coverage is affordable); near
	// cells reach 1. World-fixed grid, camera-driven depth — the same screen-error rule as the collapse
	// (doc 10 §"world-fixed cell grid, camera-driven refinement"; doc 13 §B3). 0 = uniform fine floor.
	Vector3 cam;           // camera in OCTREE-LOCAL lattice (set per build)
	double floor_k = 0.0;
	double floor_cap = 1e9;

	EditStoreSource(const EditStore *s, const Vector3 &wo, double bc) :
			store(s), world_origin(wo), base_cell(bc) {}

	Vector3 to_world(const Vector3 &p) const { return (world_origin + p) * base_cell; }

	double value(const Vector3 &p) const override {
		return store->sample(to_world(p));
	}

	// Sample one accel level into accel_held[slot] and register it: a dim³ grid at `res` lattice spacing,
	// octree-local origin `lo`. (accel_held is pre-sized so its ptrs stay valid as levels are added.)
	void bake_accel_level(int slot, const Vector3i &lo, int res, int dim) {
		PackedFloat32Array &data = accel_held[slot];
		data.resize(int64_t(dim) * dim * dim);
		float *d = data.ptrw();
		// One worker-grab per z-slab; value()->store->sample is const/read-only, so concurrent reads
		// are safe and each slab writes a disjoint block. Load-balanced across the accel's many levels.
		const int nthreads = (g_mesh_threads > 1 && dim >= 4) ? g_mesh_threads : 1;
		parallel_for(dim, nthreads, [this, d, dim, &lo, res](int z) {
			for (int y = 0; y < dim; ++y) {
				for (int x = 0; x < dim; ++x) {
					d[voxel_dc::flat_index(x, y, z, dim)] =
							float(value(Vector3(lo.x + x * res, lo.y + y * res, lo.z + z * res)));
				}
			}
		});
		Level lv;
		lv.data = data.ptr();
		lv.origin = Vector3(lo);
		lv.cell = res;
		lv.dim = dim;
		accel.levels[slot] = lv;
	}

	// Bake the GRADED accel over the OCTREE-LOCAL window [win_lo, win_hi]. floor_k == 0 → one res-1 level
	// sized to cover the whole window (uniform). Else concentric ACCEL_DIM³ levels centred on `cam_local`,
	// res doubling, until the coarsest covers the whole window — so every in-window box is decided by a level
	// at ~its build-floor resolution (fine near, coarse far), bounding both the bake and the build.
	void bake_accel(const Vector3i &win_lo, const Vector3i &win_hi, const Vector3 &cam_local, double fk) {
		accel.levels.clear();
		LocalVector<Vector3i> origins; // decide specs first so accel_held can be pre-sized (stable ptrs)
		LocalVector<int> reslist;
		LocalVector<int> dimlist;
		Vector3i c(int(Math::round(cam_local.x)), int(Math::round(cam_local.y)), int(Math::round(cam_local.z)));
		int reach = MAX(MAX(c.x - win_lo.x, win_hi.x - c.x), MAX(MAX(c.y - win_lo.y, win_hi.y - c.y), MAX(c.z - win_lo.z, win_hi.z - c.z)));
		if (fk <= 0.0 || reach <= ACCEL_DIM / 2) {
			// One res-1 level sized to the window: the whole window is within one fine level (floor ≈ 1
			// throughout), so concentric levels would buy nothing — and this avoids a 129³ bake for a small
			// window. Covers the uniform case (fk==0) and every all-fine resident bubble.
			int span = MAX(win_hi.x - win_lo.x, MAX(win_hi.y - win_lo.y, win_hi.z - win_lo.z)) + 1;
			origins.push_back(win_lo);
			reslist.push_back(1);
			dimlist.push_back(span);
		} else {
			int res = 1;
			for (int k = 0; k < 16; ++k) {
				int half = (ACCEL_DIM / 2) * res;
				origins.push_back(c - Vector3i(half, half, half));
				reslist.push_back(res);
				dimlist.push_back(ACCEL_DIM);
				if (half >= reach) {
					break; // this level covers the whole window
				}
				res *= 2;
			}
		}
		accel_held.resize(origins.size());
		accel.levels.resize(origins.size());
		for (uint32_t k = 0; k < origins.size(); ++k) {
			bake_accel_level(int(k), origins[k], reslist[k], dimlist[k]);
		}
		accel.build_mips();
		has_accel = true;
		accel_win_lo = win_lo;
		accel_win_hi = win_hi;
		++bake_count;
	}

	Vector3 gradient(const Vector3 &p) const override {
		const double h = 1.0; // one lattice cell — central difference, same convention as Clipmap
		Vector3 g(
				value(p + Vector3(h, 0, 0)) - value(p - Vector3(h, 0, 0)),
				value(p + Vector3(0, h, 0)) - value(p - Vector3(0, h, 0)),
				value(p + Vector3(0, 0, h)) - value(p - Vector3(0, 0, h)));
		return g.length_squared() > 0.0 ? g.normalized() : Vector3(0, 1, 0);
	}

	// Graded data floor (P2): build only as fine as a cell renders. floor_k == 0 → uniform fine (floor 1).
	double target_cell_size(const Vector3 &p) const override {
		if (floor_k <= 0.0) {
			return 1.0;
		}
		return CLAMP(floor_k * (p - cam).length(), 1.0, floor_cap);
	}

	// Surface-sparse prune (P1+P2): `Clipmap::surface_free` ANDs the concentric levels — the finest level
	// covering the box decides, coarser ones abstain where they don't reach — so a box is pruned only if a
	// level at ~its build-floor resolution proves no crossing. The coarsest level covers the whole window,
	// so every in-window cell is decided (out-of-window cells aren't built). Can't miss a crossing at the
	// floor it would be built to, and matches the floor grading so it never over-prunes a visible cell.
	bool surface_free(const Vector3 &cmin, const Vector3 &cmax) const override {
		return has_accel && accel.surface_free(cmin, cmax);
	}
	bool is_finest_level(const Vector3 &p) const override { return false; } // no clipmap core to pin

	// Material id of the solid a vertex bounds — the inward-scan from Clipmap::index_prefer_explicit,
	// sampling the store's material channel instead of a baked grid (a vertex bounds the body straight
	// inward of its normal; sideways neighbours excluded so ground beside a part stays natural).
	int index_prefer_explicit(const Vector3 &p, const Vector3 &n) const override {
		int id = store->material_at(to_world(p));
		if (id > 0) {
			return id;
		}
		int best = 0;
		double best_d2 = 1e30;
		for (int dz = -1; dz <= 1; ++dz) {
			for (int dy = -1; dy <= 1; ++dy) {
				for (int dx = -1; dx <= 1; ++dx) {
					if (dx == 0 && dy == 0 && dz == 0) {
						continue;
					}
					Vector3 off(dx, dy, dz);
					if (off.normalized().dot(n) >= -0.9) {
						continue; // not aligned with -n (straight inward)
					}
					int nid = store->material_at(to_world(p + off));
					if (nid <= 0) {
						continue;
					}
					double d2 = double(dx * dx + dy * dy + dz * dz);
					if (d2 < best_d2 || (d2 == best_d2 && nid < best)) {
						best_d2 = d2;
						best = nid;
					}
				}
			}
		}
		return best;
	}
};

} // namespace dc_mesh
} // namespace voxel_dc

#endif // DC_EDIT_STORE_SOURCE_H
