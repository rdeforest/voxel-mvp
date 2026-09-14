#ifndef DC_CLIPMAP_SOURCE_H
#define DC_CLIPMAP_SOURCE_H

// The baked-grid field source: nested concentric SDF grids (the godot_voxel-era render path, still
// used for collision, falling chunks, and the trusted reference mesher in tests). `Level` is one
// baked grid; `Clipmap` picks the finest level covering a point and samples it.

#include "dc_sdf_source.h"
#include "sdf_field.h" // voxel_dc::flat_index / sample_trilinear

#include "core/math/math_funcs.h"
#include "core/templates/local_vector.h"

#include <cstring>

namespace voxel_dc {
namespace dc_mesh {

// One baked SDF grid (a clipmap level): trilinear value (shared voxel_dc sampler) plus
// the material-index channel. Reads are clamped at the grid edge.
struct Level {
	const float *data = nullptr;
	const uint8_t *idx = nullptr; // optional CHANNEL_INDICES bytes, same layout as data
	Vector3 origin;
	double cell = 1.0;
	int dim = 0;

	// Nearest material id at a world point (ids are discrete — no interpolation).
	int index_nearest(const Vector3 &world) const {
		if (idx == nullptr) {
			return 0;
		}
		int x = int(Math::round((world.x - origin.x) / cell));
		int y = int(Math::round((world.y - origin.y) / cell));
		int z = int(Math::round((world.z - origin.z) / cell));
		x = CLAMP(x, 0, dim - 1);
		y = CLAMP(y, 0, dim - 1);
		z = CLAMP(z, 0, dim - 1);
		return int(idx[voxel_dc::flat_index(x, y, z, dim)]);
	}

	double at(const Vector3 &world) const {
		return voxel_dc::sample_trilinear(data, dim, origin, cell, world);
	}

	// --- Surface-sparse prune: exact min/max pyramid over `data` ---
	// Unlike a gradient ESTIMATE, this checks the ACTUAL samples, so it can never miss a sub-cell ridge
	// (never over-prunes). build_mip() makes a min/max pyramid; surface_free(box) is O(1) (≤8 blocks).
	LocalVector<LocalVector<float>> mip_min;
	LocalVector<LocalVector<float>> mip_max;
	LocalVector<int> mip_dim;

	void build_mip() {
		// Build the min/max pyramid bottom-up: level 0 is the raw grid, each coarser level is
		// the 2x2x2 min/max of its parent. surface_free() then reads it top-down.
		mip_min.clear();
		mip_max.clear();
		mip_dim.clear();
		append_base_level();
		for (int level_dim = dim; level_dim > 1;) {
			level_dim = append_reduced_level(level_dim);
		}
	}

	void append_base_level() {
		// Level 0: each cell's min and max are just its own sample — a bulk copy of the raw grid.
		// resize() leaves float storage uninitialized, so these memcpys are the only write.
		int64_t cell_count = int64_t(dim) * dim * dim;
		LocalVector<float> base_min, base_max;
		base_min.resize(cell_count);
		base_max.resize(cell_count);
		memcpy(base_min.ptr(), data, sizeof(float) * cell_count);
		memcpy(base_max.ptr(), data, sizeof(float) * cell_count);
		mip_min.push_back(base_min);
		mip_max.push_back(base_max);
		mip_dim.push_back(dim);
	}

	int append_reduced_level(int parent_dim) {
		// One pyramid step: each child cell takes the min/max over the (up to) 8 parent cells it
		// covers. Returns the child dimension so the build loop knows when to stop.
		int child_dim = (parent_dim + 1) / 2;
		const LocalVector<float> &parent_min = mip_min[mip_min.size() - 1];
		const LocalVector<float> &parent_max = mip_max[mip_max.size() - 1];
		LocalVector<float> child_min, child_max;
		child_min.resize(int64_t(child_dim) * child_dim * child_dim);
		child_max.resize(int64_t(child_dim) * child_dim * child_dim);
		for (int z = 0; z < child_dim; ++z) {
			for (int y = 0; y < child_dim; ++y) {
				for (int x = 0; x < child_dim; ++x) {
					float block_min = 1e30f, block_max = -1e30f;
					for (int oz = 0; oz < 2; ++oz) {
						for (int oy = 0; oy < 2; ++oy) {
							for (int ox = 0; ox < 2; ++ox) {
								int sx = x * 2 + ox, sy = y * 2 + oy, sz = z * 2 + oz;
								if (sx >= parent_dim || sy >= parent_dim || sz >= parent_dim) {
									continue;
								}
								int src = voxel_dc::flat_index(sx, sy, sz, parent_dim);
								block_min = MIN(block_min, parent_min[src]);
								block_max = MAX(block_max, parent_max[src]);
							}
						}
					}
					int dst = voxel_dc::flat_index(x, y, z, child_dim);
					child_min[dst] = block_min;
					child_max[dst] = block_max;
				}
			}
		}
		mip_min.push_back(child_min);
		mip_max.push_back(child_max);
		mip_dim.push_back(child_dim);
		return child_dim;
	}

	// True if NO zero-crossing in the lattice box [cmin, cmax] in this level's grid (1-cell margin to
	// catch a crossing on the box face). If the box doesn't overlap this level's grid, returns true
	// (this level has no data here — it abstains; the caller checks every level).
	bool surface_free(const Vector3 &cmin, const Vector3 &cmax) const {
		if (mip_dim.is_empty()) {
			return false;
		}
		int g0x = MAX(int(Math::floor((cmin.x - origin.x) / cell)) - 1, 0);
		int g0y = MAX(int(Math::floor((cmin.y - origin.y) / cell)) - 1, 0);
		int g0z = MAX(int(Math::floor((cmin.z - origin.z) / cell)) - 1, 0);
		int g1x = MIN(int(Math::ceil((cmax.x - origin.x) / cell)) + 1, dim);
		int g1y = MIN(int(Math::ceil((cmax.y - origin.y) / cell)) + 1, dim);
		int g1z = MIN(int(Math::ceil((cmax.z - origin.z) / cell)) + 1, dim);
		if (g0x >= g1x || g0y >= g1y || g0z >= g1z) {
			return true; // no overlap with this level's grid
		}
		int span = MAX(g1x - g0x, MAX(g1y - g0y, g1z - g0z));
		int m = 0;
		while ((1 << (m + 1)) <= span && m + 1 < int(mip_dim.size())) {
			++m;
		}
		int bs = 1 << m;
		int md = mip_dim[m];
		const LocalVector<float> &pmn = mip_min[m];
		const LocalVector<float> &pmx = mip_max[m];
		float lo = 1e30f, hi = -1e30f;
		for (int z = g0z / bs; z <= (g1z - 1) / bs; ++z) {
			for (int y = g0y / bs; y <= (g1y - 1) / bs; ++y) {
				for (int x = g0x / bs; x <= (g1x - 1) / bs; ++x) {
					int i = x + md * (y + md * z);
					lo = MIN(lo, pmn[i]);
					hi = MAX(hi, pmx[i]);
				}
			}
		}
		return !(lo <= 0.0f && hi >= 0.0f); // free iff all strictly one side of the isosurface
	}
};

// The clipmap: pick the finest level whose box contains the point (single-valued
// in position -> crack-free), sample it. target_cell_size drives subdivision.
struct Clipmap : public SdfSource {
	LocalVector<Level> levels;
	Vector3 center;
	double half0 = 1.0;

	int level_index(const Vector3 &p) const {
		double d = MAX(Math::abs(p.x - center.x), MAX(Math::abs(p.y - center.y), Math::abs(p.z - center.z)));
		int n = int(levels.size());
		for (int k = 0; k < n; ++k) {
			if (d <= half0 * double(1 << k)) {
				return k;
			}
		}
		return n - 1;
	}

	// Geomorphed sample: blend level k into level k+1 across the OUTER HALF of level k's
	// band, so the field is CONTINUOUS across every LOD boundary (at the boundary the
	// blend equals level k+1, which is exactly what the next band uses at its inner edge).
	// A hard level switch steps the surface where the coarse mip drops detail the fine
	// level has, and the crack-free stitch bridges that step with near-vertical slivers;
	// blending removes the step. Still single-valued in position -> still crack-free.
	//
	// EXCEPT the finest level (k==0) is kept PURE: its blend factor depends on
	// distance-from-camera, so blending coarse LOD1 data into the fine band makes a
	// close object's field — and thus its mesh — change as the camera orbits it (the
	// "< 10 m structure shifts with view angle" bug). The whole build region lives in
	// level 0, so it must read pure fine data, identical from every angle. Geomorph
	// still smooths the coarser, farther transitions (k>=1) where the camera-distance
	// dependence isn't noticeable. (The proper fix — one fine field + error-collapse,
	// no discrete LOD levels near the player — retires geomorph entirely; substrate
	// Phase A. This keeps the finest band stable until then.)
	double value(const Vector3 &p) const override {
		int k = level_index(p);
		double v = levels[k].at(p);
		if (k > 0 && k + 1 < int(levels.size())) {
			double d = MAX(Math::abs(p.x - center.x), MAX(Math::abs(p.y - center.y), Math::abs(p.z - center.z)));
			double boundary = half0 * double(1 << k);
			double inner = boundary * 0.5; // band is (boundary/2, boundary]
			if (d > inner) {
				double t = CLAMP((d - inner) / (boundary - inner), 0.0, 1.0);
				v = Math::lerp(v, levels[k + 1].at(p), t);
			}
		}
		return v;
	}

	Vector3 gradient(const Vector3 &p) const override {
		double h = double(1 << level_index(p)); // local cell size
		Vector3 g(
				value(p + Vector3(h, 0, 0)) - value(p - Vector3(h, 0, 0)),
				value(p + Vector3(0, h, 0)) - value(p - Vector3(0, h, 0)),
				value(p + Vector3(0, 0, h)) - value(p - Vector3(0, 0, h)));
		return g.length_squared() > 0.0 ? g.normalized() : Vector3(0, 1, 0);
	}

	double target_cell_size(const Vector3 &p) const override {
		return double(1 << level_index(p));
	}

	// The finest clipmap level (level 0, the 1m core bubble) — uniform_core pins it against collapse.
	bool is_finest_level(const Vector3 &p) const override {
		return level_index(p) == 0;
	}

	void build_mips() {
		for (uint32_t k = 0; k < levels.size(); ++k) {
			levels[k].build_mip();
		}
	}

	// A node is surface-free only if EVERY level's grid agrees (no level sees a crossing in the box).
	// The finest level covering the box catches sub-cell features a coarser mip smoothed away, so this
	// never over-prunes regardless of the blend.
	bool surface_free(const Vector3 &cmin, const Vector3 &cmax) const override {
		for (uint32_t k = 0; k < levels.size(); ++k) {
			if (!levels[k].surface_free(cmin, cmax)) {
				return false;
			}
		}
		return true;
	}

	int index_at(const Vector3 &p) const {
		return levels[level_index(p)].index_nearest(p);
	}

	// Material of the solid a surface vertex BOUNDS. A vertex bounds the body on the side its
	// normal points away from, so we look STRAIGHT INWARD (toward -n): if the nearest cell is
	// Natural(0) (the one-cell per-leaf boundary shell), scan the neighbours aligned with -n
	// (offset·n̂ < -0.9, i.e. within ~25° of straight inward) and take the closest nonzero id
	// (ties -> lowest, deterministic).
	//
	// Near-straight-inward, NOT a hemisphere, on purpose. A part's own face/edge/corner vertex
	// has its normal pointing out of the part, so the cell straight behind it (axis for a face,
	// the matching diagonal for an edge/corner) is the part interior -> it reads the part. But a
	// terrain-surface vertex BESIDE a part points up out of the ground; the part is a sideways or
	// down-AND-sideways neighbour — those offsets are not aligned with -n, so they're excluded and
	// the ground stays natural instead of bleeding the part's material outward. (A plain inward
	// hemisphere still bled: a down-sideways diagonal is "inward" yet reaches the part beside it.)
	// Scan at the level's own cell size so it stays single-level -> crack-free.
	int index_prefer_explicit(const Vector3 &p, const Vector3 &n) const override {
		const Level &lv = levels[level_index(p)];
		int id = lv.index_nearest(p);
		if (id > 0) {
			return id;
		}
		const double c = lv.cell;
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
						continue; // not aligned with -n (straight inward); sideways neighbours excluded
					}
					int nid = lv.index_nearest(p + off * c);
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

#endif // DC_CLIPMAP_SOURCE_H
