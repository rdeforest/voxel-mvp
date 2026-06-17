#include "dc_octree_mesher.h"

#include "dc_qef.h"
#include "edit_store.h"
#include "octree_geometry.h"
#include "sdf_field.h"

#include "core/math/math_funcs.h"
#include "core/templates/local_vector.h"
#include "scene/resources/mesh.h"

// CB (cube corners by xyz bits), EDGES (12 corner-pairs), RING (4 cells around an edge),
// and Qef all come from voxel_dc — shared with the octree storage and mesher so
// the corner order can't drift between them.
using namespace voxel_dc;

namespace {

const double QUERY_EPS = 0.25; // perpendicular offset to land just across an edge

inline Vector3 to_v3(const Vector3i &v) {
	return Vector3(real_t(v.x), real_t(v.y), real_t(v.z));
}

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
		return int(idx[x + dim * (y + dim * z)]);
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
								int src = sx + parent_dim * (sy + parent_dim * sz);
								block_min = MIN(block_min, parent_min[src]);
								block_max = MAX(block_max, parent_max[src]);
							}
						}
					}
					int dst = x + child_dim * (y + child_dim * z);
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

// The octree's field source: everything the build + mesh need to know about the field, abstracted
// so the octree doesn't care WHERE the SDF comes from. Two implementations: the camera-centered
// `Clipmap` (concentric baked grids — the godot_voxel-era render path) and `EditStoreSource` (samples
// the world-fixed EditStore field directly — the world-fixed-octree substrate, doc 16 THE GOAL).
struct SdfSource {
	virtual ~SdfSource() {}
	virtual double value(const Vector3 &p) const = 0;
	virtual Vector3 gradient(const Vector3 &p) const = 0;
	virtual double target_cell_size(const Vector3 &p) const = 0;        // the data-resolution floor at p
	virtual bool surface_free(const Vector3 &cmin, const Vector3 &cmax) const = 0; // no zero-crossing in box
	virtual int index_prefer_explicit(const Vector3 &p, const Vector3 &n) const = 0; // material id behind a vertex
	virtual bool is_finest_level(const Vector3 &p) const = 0;           // for uniform_core (pin the fine bubble)
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
		for (int z = 0; z < dim; ++z) {
			for (int y = 0; y < dim; ++y) {
				for (int x = 0; x < dim; ++x) {
					d[x + dim * (y + dim * z)] =
							float(value(Vector3(lo.x + x * res, lo.y + y * res, lo.z + z * res)));
				}
			}
		}
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

struct Cell {
	Vector3i origin;
	int size = 0;
	int children[8];
	int vertex = -1;
	bool leaf = true;
	bool absent = false; // window_mode: a leaf OUTSIDE the resident window — no QEF, no vertex, not
	                     // meshed. The window boundary is the resident mesh's open rim (like the clipmap's
	                     // outer edge). Distinct from a splice's build-box-miss leaf, which IS meshed.
	Qef qef; // accumulated up the tree (own crossings for a leaf; children's sum otherwise)
};

// Builds + meshes one octree over a clipmap: subdivide to the clipmap's
// per-position target size (the data-resolution floor), then — when error_driven —
// COLLAPSE bottom-up wherever one vertex represents the surface within eps_px on
// screen, so flat regions coarsen and curved ones stay fine. One QEF vertex per
// surviving leaf, then minimal-edge meshing with point-location (the smallest cell
// owns each edge; a coarser neighbour returned twice collapses the quad to a
// triangle -> seamless across the size jumps the collapse introduces).
struct Octree {
	const SdfSource *src = nullptr;  // field source (Clipmap or EditStoreSource); set by the caller, must outlive run()
	int root_size = 0;
	int max_depth = 0;
	Vector3 camera;          // viewpoint in root-local lattice space (screen-error LOD)
	double proj = 0.0;       // viewport_height / (2*tan(fov/2)) — px per world unit at unit distance
	double eps_px = 0.0;     // screen-space error threshold (px): collapse when we*proj/dist <= eps_px
	bool error_driven = false;
	int max_leaf_size = 0;   // min-grid floor: never collapse above this (a flat world keeps >=2 cells/axis, so it meshes instead of collapsing to one empty cell)
	Vector3i world_origin;   // world coords of lattice (0,0,0): converts a cell's local origin to its world position for the emit/build boxes
	bool emit_color = false;       // sample material ids and emit per-vertex colours
	PackedColorArray palette;      // material id -> albedo (index 0 = natural)
	bool uniform_core = false;     // keep the finest level (level 0) at 1m — never collapse it,
	                               // so the fine field has clean cell boundaries an edit patch
	                               // can splice against (incremental meshing). Outer levels still
	                               // collapse by screen error.
	double prune_safety = 0.0;     // >0 enables the surface-sparse build: stop subdividing a cell
	                               // proven surface-free by a locally-estimated Lipschitz bound, so
	                               // the tree is O(surface) not O(volume). The factor pads the
	                               // gradient estimate against nonlinearity (≈1.5 safe). 0 = the
	                               // old dense build-to-floor everywhere.
	bool emit_filter = false;      // emit only triangles owned by cells inside [emit_min, emit_max)
	Vector3i emit_min;             // (WORLD lattice) — the incremental patch's core box
	Vector3i emit_max;
	bool build_box = false;        // restrict the build to cells overlapping [build_min, build_max)
	Vector3i build_min;            // (WORLD lattice) — a splice builds only the edit box + apron, on the
	Vector3i build_max;            // FULL build's frame, so its cells share that lattice → crack-free
	bool window_mode = false;      // mesh_world only: a build-box-miss leaf is ABSENT (not sampled, not
	                               // meshed) — the box is the resident WINDOW, its edge the mesh rim. A
	                               // splice leaves window_mode off: its out-of-box cells ARE meshed so the
	                               // patch rim can stitch to them (the full build supplies their triangles).
	int build_samples = 0;         // leaves whose Hermite data was sampled this build (accumulate_qef) —
	                               // the field-derived build cost. A grow re-samples only the new band, so
	                               // this proves the retained interior was NOT resampled (the B1 win).
	LocalVector<Cell> cells;
	LocalVector<int> free_list;    // (B1b) indices of cells killed by eviction, reused by the next grow so
	                               // `cells` stays bounded across a long traverse instead of leaking.
	PackedVector3Array verts;
	PackedVector3Array normals;
	PackedColorArray colors;       // per-vertex material colour (rgb); a=0 material, a=1 natural
	PackedInt32Array indices;
	PackedVector3Array tri_owners;      // WORLD owner-cell origin per emitted triangle
	PackedFloat32Array tri_owner_sizes; // parallel: owner cell SIZE (lattice units)

	// World-lattice origin of a cell (cells store origin relative to the octree root).
	Vector3i cell_world_origin(int idx) const {
		return cells[idx].origin + world_origin;
	}

	bool owner_in_emit_box(int idx) const {
		Vector3i o = cell_world_origin(idx);
		return o.x >= emit_min.x && o.x < emit_max.x && o.y >= emit_min.y && o.y < emit_max.y && o.z >= emit_min.z && o.z < emit_max.z;
	}

	// Does a cell (lattice origin + size) overlap the build box (WORLD lattice)? A splice descends
	// only overlapping cells, so the tree is a thin spine to the edit box plus the box at full res.
	bool cell_overlaps_build_box(const Vector3i &origin, int size) const {
		Vector3i o = origin + world_origin;
		return o.x + size > build_min.x && o.x < build_max.x && o.y + size > build_min.y && o.y < build_max.y && o.z + size > build_min.z && o.z < build_max.z;
	}

	// Should this cell stop subdividing and become a leaf? True at the data floor, when
	// the cell is provably surface-free (prune), or when size is already atomic. This is
	// the shared predicate build() and reconcile() both check — one definition, no drift.
	bool want_leaf(int size, const Vector3i &origin) const {
		Vector3 center = to_v3(origin) + Vector3(1, 1, 1) * (size * 0.5);
		return size <= 1
			|| double(size) <= src->target_cell_size(center)
			|| (prune_safety > 0.0 && src->surface_free(
					to_v3(origin), to_v3(origin) + Vector3(1, 1, 1) * double(size)));
	}

	// Assign this leaf's Hermite data from its own edges and charge the build counter.
	// Call sites that are transitioning an absent leaf to present must set absent=false
	// themselves (the extra step stays inline so this helper stays narrowly scoped).
	void sample_leaf(int idx) {
		cells[idx].qef = leaf_qef(idx);
		++build_samples;
	}

	// Free all 8 children of idx (recursively) and reset their slots for reuse.
	// No-op when idx is already a structural leaf (children[0] < 0).
	void discard_children(int idx) {
		if (cells[idx].children[0] < 0) {
			return;
		}
		for (int i = 0; i < 8; ++i) {
			kill_subtree(cells[idx].children[i]);
			cells[idx].children[i] = -1;
		}
	}

	// A leaf's QEF, built from the 12 cube edges that cross the isosurface (the cell's
	// own Hermite data at its own size).
	Qef leaf_qef(int idx) const {
		Qef qef;
		Vector3i o = cells[idx].origin;
		int s = cells[idx].size;
		for (int e = 0; e < 12; ++e) {
			const int *pa = CB[EDGES[e][0]];
			const int *pb = CB[EDGES[e][1]];
			Vector3i ca = o + Vector3i(pa[0], pa[1], pa[2]) * s;
			Vector3i cb = o + Vector3i(pb[0], pb[1], pb[2]) * s;
			double fa = src->value(to_v3(ca));
			double fb = src->value(to_v3(cb));
			if ((fa < 0.0) == (fb < 0.0) || fa == fb) {
				continue;
			}
			double t = fa / (fa - fb);
			Vector3 p = to_v3(ca).lerp(to_v3(cb), t);
			qef.add_plane(p, src->gradient(p));
		}
		return qef;
	}

	// Recursively orphan a node's whole subtree (mark every descendant non-leaf), so a
	// collapsed node is the sole leaf over its region regardless of how its descendants
	// had decided. Leaves have children[i] == -1, so this stops there.
	void orphan_subtree(int idx) {
		for (int i = 0; i < 8; ++i) {
			int ch = cells[idx].children[i];
			if (ch < 0) {
				continue;
			}
			orphan_subtree(ch);
			cells[ch].leaf = false;
		}
	}

	// Bottom-up pass: give every cell its accumulated QEF (a leaf's own crossings; an
	// internal node = sum of its children's, so the node carries ALL the fine Hermite
	// data within it — no coarse-corner undersampling). When error_driven, collapse a
	// node into a single leaf if one vertex fits that accumulated data within the
	// world-residual tolerance (and the node isn't above the min-grid floor). The
	// accumulated QEF's residual already refuses to collapse over real detail, so no
	// "all children are leaves" gate is needed — collapsing just orphans the subtree;
	// point-location meshing stitches the resulting size jumps crack-free.
	// FIELD-derived pass (expensive, run ONCE per build): give every node its accumulated QEF — a
	// structural leaf's own crossings (leaf_qef samples the field), an internal node = the sum of its
	// children's, so the node carries ALL the fine Hermite data within it (no coarse-corner
	// undersampling). NO collapse here; that is camera-derived and re-runnable (collapse_pass). Uses
	// the STRUCTURAL leaf (no children), not the leaf flag, so it is correct even after a prior
	// collapse_pass dirtied the flags (Stage 2: the retained octree re-collapses without re-sampling).
	void accumulate_qef(int idx) {
		if (cells[idx].children[0] < 0) {
			// An absent leaf (outside the window) contributes an empty QEF (count 0) — a bit-exact no-op
			// in its ancestors' sums, so a windowed/incremental build's QEFs equal a full build's.
			if (cells[idx].absent) {
				cells[idx].qef = Qef();
			} else {
				sample_leaf(idx);
			}
			return;
		}
		Qef sum;
		for (int i = 0; i < 8; ++i) {
			int ch = cells[idx].children[i];
			accumulate_qef(ch);
			sum.add(cells[ch].qef);
		}
		cells[idx].qef = sum;
	}

	// Reset every node's leaf flag to its STRUCTURAL state (leaf iff it has no children) and clear the
	// placed vertex, so collapse_pass + meshing can re-run from scratch on a camera re-walk.
	void reset_leaves() {
		for (uint32_t i = 0; i < cells.size(); ++i) {
			cells[i].leaf = cells[i].children[0] < 0;
			cells[i].vertex = -1;
		}
	}

	// CAMERA-derived pass (cheap, re-runnable, NO field sampling): collapse a node into one leaf when a
	// single vertex represents its accumulated QEF within eps_px on screen. Bottom-up; a parent collapse
	// orphans its subtree, so the coarsest collapsing ancestor wins.
	//
	// Collapse error = the L2 residual of the accumulated QEF at the merged vertex, NOT divided by plane
	// count: the undivided residual is ~0 on flat/cliff/gently-curved regions (flat planes contribute
	// exactly 0) and spikes where one vertex can't represent a feature, so a thin feature vetoes its own
	// collapse. Screen-space-error LOD projects that world residual to pixels (we * proj / dist): keep
	// refined while it exceeds eps_px (~2px), collapse otherwise — a feature coarsens as it recedes and a
	// narrow FOV (telescope) raises proj to refine distant terrain.
	void collapse_pass(int idx) {
		if (cells[idx].children[0] < 0) {
			return; // structural leaf — nothing to collapse
		}
		for (int i = 0; i < 8; ++i) {
			collapse_pass(cells[idx].children[i]);
		}
		if (!error_driven || cells[idx].qef.count == 0 || cells[idx].size > max_leaf_size) {
			return;
		}
		Vector3 cmin = to_v3(cells[idx].origin);
		Vector3 cmax = cmin + Vector3(1, 1, 1) * double(cells[idx].size);
		// Never collapse the finest level when uniform_core: a 1m fine core gives edit patches clean
		// cell boundaries to splice against (incremental meshing). Outer levels still coarsen.
		if (uniform_core) {
			Vector3 c = cmin + Vector3(1, 1, 1) * (cells[idx].size * 0.5);
			if (src->is_finest_level(c)) {
				return;
			}
		}
		Vector3 v = cells[idx].qef.solve(cmin, cmax);
		double we = Math::sqrt(cells[idx].qef.residual(v));
		Vector3 ctr = cmin + Vector3(1, 1, 1) * (cells[idx].size * 0.5);
		double dist = MAX((ctr - camera).length(), 1e-3);
		if (we * proj / dist > eps_px) {
			return; // on-screen error too large — surface here needs more than one vertex
		}
		cells[idx].leaf = true; // collapse: this node is the leaf; its subtree is orphaned
		orphan_subtree(idx);
	}

	// Tree depth of a cell of the given lattice size (root_size → 0; size 1 → max_depth). Used by the
	// incremental grow to resume build() at the right depth when expanding an existing leaf into a subtree.
	int cell_depth(int size) const {
		int d = 0;
		for (int s = root_size; s > size; s >>= 1) {
			++d;
		}
		return d;
	}

	// Allocate a cell slot — reusing one freed by eviction (B1b) before growing `cells`, so a long
	// traverse churns slots in place instead of leaking. The returned slot is reset by build().
	int alloc_cell() {
		if (!free_list.is_empty()) {
			int i = free_list[free_list.size() - 1];
			free_list.resize(free_list.size() - 1);
			return i;
		}
		int i = int(cells.size());
		cells.push_back(Cell());
		return i;
	}

	int build(const Vector3i &origin, int size, int depth) {
		int idx = alloc_cell();
		{
			Cell &c = cells[idx]; // reset fully — a reused slot may carry stale state
			c.origin = origin;
			c.size = size;
			c.leaf = true;
			c.absent = false;
			c.vertex = -1;
			c.qef = Qef();
			for (int i = 0; i < 8; ++i) {
				c.children[i] = -1;
			}
		}
		if (depth >= max_depth || size <= 1) {
			return idx;
		}
		if (build_box && !cell_overlaps_build_box(origin, size)) {
			if (window_mode) {
				cells[idx].absent = true; // outside the resident window — placeholder leaf, never meshed
			}
			return idx; // outside the box — leaf, don't descend (no data sampled)
		}
		// Surface-sparse prune + data-floor check — the same predicate reconcile() evaluates
		// per retained cell; want_leaf() is the single definition for both paths.
		if (want_leaf(size, origin)) {
			return idx;
		}
		// Always build down to the data floor; error-driven coarsening happens bottom-up
		// in accumulate() (build fine, then collapse where the fine data fits one vertex),
		// which measures the real surface instead of undersampling at coarse corners.
		int half = size >> 1;
		cells[idx].leaf = false; // index-access only; cells may reallocate during recursion
		for (int i = 0; i < 8; ++i) {
			Vector3i co = origin + Vector3i(CB[i][0], CB[i][1], CB[i][2]) * half;
			int child = build(co, half, depth + 1);
			cells[idx].children[i] = child;
		}
		return idx;
	}

	int find_leaf(const Vector3 &p) const {
		if (p.x < 0.0 || p.y < 0.0 || p.z < 0.0) {
			return -1;
		}
		if (p.x >= root_size || p.y >= root_size || p.z >= root_size) {
			return -1;
		}
		int idx = 0;
		while (!cells[idx].leaf) {
			const Cell &c = cells[idx];
			Vector3 center = to_v3(c.origin) + Vector3(1, 1, 1) * (c.size * 0.5);
			int i = (p.x >= center.x ? 1 : 0) | (p.y >= center.y ? 2 : 0) | (p.z >= center.z ? 4 : 0);
			idx = c.children[i];
		}
		return idx;
	}

	// Place this leaf's vertex from its accumulated QEF. For a collapsed leaf the QEF
	// holds all the fine crossings within it, so the vertex and normal reflect the real
	// surface, not a coarse re-sample.
	void place_vertex(int idx) {
		const Qef &qef = cells[idx].qef;
		Vector3 cmin = to_v3(cells[idx].origin);
		Vector3 cmax = cmin + Vector3(1, 1, 1) * double(cells[idx].size);
		Vector3 v = qef.solve(cmin, cmax);
		Vector3 n = qef.nsum.length_squared() > 0.0 ? qef.nsum.normalized() : Vector3(0, 1, 0);
		cells[idx].vertex = int(verts.size());
		verts.push_back(v);
		normals.push_back(n);
		if (emit_color) {
			// Sample the solid voxel just behind the surface: the normal points
			// outward, so step inward to land in the cell that carries the id. Prefer an
			// inward explicit material so a placed part's faces read the part, while a terrain
			// vertex beside the part stays natural (the body it bounds is inward, not sideways).
			int id = src->index_prefer_explicit(v - n * 0.5, n);
			if (id > 0 && id < int(palette.size())) {
				const Color &c = palette[id];
				colors.push_back(Color(c.r, c.g, c.b, 0.0)); // a=0 -> explicit material colour
			} else {
				colors.push_back(Color(0, 0, 0, 1.0)); // a=1 -> natural (slope-shaded; also the
													   // default for meshes with no colour array)
			}
		}
	}

	static bool origin_less(const Vector3i &a, const Vector3i &b) {
		if (a.x != b.x) {
			return a.x < b.x;
		}
		if (a.y != b.y) {
			return a.y < b.y;
		}
		return a.z < b.z;
	}

	// This leaf owns the edge iff it is a smallest cell around it and, among equal
	// smallest cells, the lexicographically least origin (so exactly one emits).
	bool owns_edge(int leaf_idx, const int ring_cells[4]) const {
		int min_size = cells[leaf_idx].size;
		for (int k = 0; k < 4; ++k) {
			int ci = ring_cells[k];
			if (ci >= 0 && cells[ci].size < min_size) {
				min_size = cells[ci].size;
			}
		}
		if (cells[leaf_idx].size != min_size) {
			return false;
		}
		for (int k = 0; k < 4; ++k) {
			int ci = ring_cells[k];
			if (ci >= 0 && cells[ci].size == min_size && origin_less(cells[ci].origin, cells[leaf_idx].origin)) {
				return false;
			}
		}
		return true;
	}

	// Emit one triangle wound so its front face points `outward` (Godot is CW-from-front,
	// so reverse when the right-hand normal already points outward). `owner` (world lattice)
	// is the cell that owns this edge — tagged per triangle for the incremental splice.
	// `owner_size` is the owner cell's size in lattice units, for the B1 alignment fix.
	void emit_tri(int i0, int i1, int i2, const Vector3 &outward, const Vector3 &owner, float owner_size) {
		Vector3 n = (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0]);
		if (n.dot(outward) >= 0.0) {
			indices.push_back(i0); indices.push_back(i2); indices.push_back(i1);
		} else {
			indices.push_back(i0); indices.push_back(i1); indices.push_back(i2);
		}
		tri_owners.push_back(owner);
		tri_owner_sizes.push_back(owner_size);
	}

	// Decide winding PER TRIANGLE, not once for the whole quad: a quad spanning a LOD
	// size jump is non-planar, so a single flip decision leaves one of its two triangles
	// back-facing — a culled, see-through gap. Orienting each triangle to `outward`
	// independently keeps the surface consistently wound across the seam.
	void emit_poly(const int ring[], int rc, const Vector3 &outward, const Vector3 &owner, float owner_size) {
		emit_tri(ring[0], ring[1], ring[2], outward, owner, owner_size);
		if (rc == 4) {
			emit_tri(ring[0], ring[2], ring[3], outward, owner, owner_size);
		}
	}

	void try_edge(int leaf_idx, int axis, int u, int w, int su, int sw) {
		Vector3i lo = cells[leaf_idx].origin;
		int s = cells[leaf_idx].size;
		lo[u] += su * s;
		lo[w] += sw * s;
		Vector3i hi = lo;
		hi[axis] += s;
		double fa = src->value(to_v3(lo));
		double fb = src->value(to_v3(hi));
		if ((fa < 0.0) == (fb < 0.0) || fa == fb) {
			return;
		}
		Vector3 mid = (to_v3(lo) + to_v3(hi)) * 0.5;
		Vector3 udir, wdir;
		udir[u] = 1.0;
		wdir[w] = 1.0;
		int ring_cells[4];
		for (int k = 0; k < 4; ++k) {
			Vector3 q = mid + udir * (RING[k][0] * QUERY_EPS) + wdir * (RING[k][1] * QUERY_EPS);
			ring_cells[k] = find_leaf(q);
		}
		if (!owns_edge(leaf_idx, ring_cells)) {
			return;
		}
		if (emit_filter && !owner_in_emit_box(leaf_idx)) {
			return; // incremental patch: only the core box's own triangles
		}
		int ring[4];
		int rc = 0;
		for (int k = 0; k < 4; ++k) {
			int ci = ring_cells[k];
			if (ci < 0 || cells[ci].vertex < 0) {
				return;
			}
			int v = cells[ci].vertex;
			if (rc == 0 || ring[rc - 1] != v) {
				ring[rc++] = v;
			}
		}
		if (rc > 1 && ring[0] == ring[rc - 1]) {
			--rc;
		}
		if (rc < 3) {
			return;
		}
		// Winding reference = the surface normal (gradient), which is the most accurate direction and
		// is needed where the surface grazes the edge (then the axial facing alone is ambiguous). BUT
		// the gradient is a finite difference stepped by the cell size, so where two surfaces sit
		// closer than a cell — a part resting on sloped ground, leaving a thin air wedge — it samples
		// ACROSS the gap into the far solid and, on our non-true-distance SDF, flips, back-facing the
		// wedge. The edge's own endpoints give the facing along `axis` unambiguously (solid→air =
		// sign(fb - fa); fa, fb are opposite-signed, checked above). So trust the gradient, but if its
		// axial component CONTRADICTS that sign it jumped a thin feature — veto it to the axial facing.
		double t = fa / (fa - fb);
		Vector3 outward = src->gradient(to_v3(lo).lerp(to_v3(hi), t));
		double axis_face = (fb > fa) ? 1.0 : -1.0;
		if (outward[axis] * axis_face < 0.0) {
			outward = Vector3();
			outward[axis] = axis_face;
		}
		emit_poly(ring, rc, outward, to_v3(cell_world_origin(leaf_idx)), float(cells[leaf_idx].size));
	}

	void emit_leaf_edges(int leaf_idx) {
		for (int axis = 0; axis < 3; ++axis) {
			int u = (axis + 1) % 3;
			int w = (axis + 2) % 3;
			for (int su = 0; su < 2; ++su) {
				for (int sw = 0; sw < 2; ++sw) {
					try_edge(leaf_idx, axis, u, w, su, sw);
				}
			}
		}
	}

	void run() {
		build_samples = 0;
		build(Vector3i(0, 0, 0), root_size, 0);
		// Keep a flat world at >=2 cells/axis so it meshes (a fully-collapsed flat region
		// is one empty cell — no quad). half the root => the 8 root children may collapse,
		// nothing coarser.
		max_leaf_size = MAX(1, root_size >> 1);
		accumulate_qef(0);       // QEF up the tree (field-derived, once)
		recollapse_and_mesh();   // collapse + mesh (camera-derived, re-runnable)
	}

	// Re-decide collapse against the current camera/proj/eps over the already-built tree + QEFs, then
	// re-mesh. No build, no field sampling — this is the Stage 2 movement re-walk (and the tail of a
	// fresh build). Clears prior output so it is idempotent.
	void recollapse_and_mesh() {
		verts.clear();
		normals.clear();
		colors.clear();
		indices.clear();
		tri_owners.clear();
		tri_owner_sizes.clear();
		reset_leaves();
		collapse_pass(0);
		// Pass 1: a vertex per surviving surface leaf. Pass 2: stitch edges.
		int n = int(cells.size());
		for (int i = 0; i < n; ++i) {
			if (cells[i].leaf && cells[i].qef.count > 0) {
				place_vertex(i);
			}
		}
		for (int i = 0; i < n; ++i) {
			if (cells[i].leaf && cells[i].vertex >= 0) {
				emit_leaf_edges(i);
			}
		}
	}

	// --- Incremental window growth (doc 16 Stage B) -------------------------------------------------
	// Expand an existing absent leaf into a full subtree at its place in the tree, building children with
	// the current window box (so in-window descendants reach the floor, out-of-window ones are absent) —
	// identical structure to what a from-scratch windowed build() would produce for this node.
	void grow_subtree(int idx) {
		Vector3i origin = cells[idx].origin;
		int size = cells[idx].size;
		int half = size >> 1;
		int d = cell_depth(size) + 1;
		cells[idx].leaf = false;
		cells[idx].absent = false;
		for (int i = 0; i < 8; ++i) {
			Vector3i co = origin + Vector3i(CB[i][0], CB[i][1], CB[i][2]) * half;
			int child = build(co, half, d); // build() may reallocate cells — re-index after each call
			cells[idx].children[i] = child;
		}
	}

	// Clear an orphaned subtree and return every slot to the free-list (B1b) for the next grow to reuse.
	// A freed slot is left inert — empty QEF (count 0) + detached + leaf — so even before reuse the
	// flat-array mesh loops skip it (a vertex is placed only for a leaf with qef.count > 0).
	void kill_subtree(int idx) {
		for (int i = 0; i < 8; ++i) {
			int ch = cells[idx].children[i];
			if (ch >= 0) {
				kill_subtree(ch);
			}
			cells[idx].children[i] = -1;
		}
		cells[idx].qef = Qef();
		cells[idx].vertex = -1;
		cells[idx].leaf = true;
		cells[idx].absent = true;
		free_list.push_back(idx);
	}

	// Make this cell into a present leaf at its own size: discard any subtree (coarsen) and sample its own
	// Hermite data. The from-scratch equivalent of a build() that stops here (floor or pruned).
	void make_leaf(int idx) {
		discard_children(idx);
		cells[idx].leaf = true;
		cells[idx].absent = false;
		sample_leaf(idx);
	}

	// Reconcile the retained tree to the CURRENT window + camera floor (build_min/max + target_cell_size),
	// touching only what changed: graft cells that entered the window, evict cells that left, REFINE cells
	// the camera approached (floor now finer), and COARSEN cells it receded from (floor now coarser). The
	// result is structurally identical to a from-scratch build at this camera/window — same leaf/internal/
	// absent decision per cell as build() — so the mesh equals a fresh build, but unchanged cells are reused
	// (not resampled): a move re-meshes only the changed band, not the whole vicinity (doc 17 P2.5 / 13 B3).
	void reconcile(int idx) {
		int sz = cells[idx].size;
		if (!cell_overlaps_build_box(cells[idx].origin, sz)) {
			// Left the window → absent leaf (the placeholder a fresh build leaves here).
			discard_children(idx);
			cells[idx].leaf = true;
			cells[idx].absent = true;
			return;
		}
		// In window. build()'s own leaf test: at the data floor, or provably surface-free (pruned).
		if (want_leaf(sz, cells[idx].origin)) {
			if (cells[idx].children[0] >= 0) {
				make_leaf(idx); // receded: coarsen the subtree back to one leaf here
			} else if (cells[idx].absent) {
				cells[idx].absent = false; // entered the window at the floor
				sample_leaf(idx);
			}
			// else: a present leaf already at the floor — unchanged, reused (not resampled)
		} else if (cells[idx].children[0] >= 0) {
			for (int i = 0; i < 8; ++i) {
				reconcile(cells[idx].children[i]); // still internal — recurse
			}
		} else {
			grow_subtree(idx);   // approached/entered: subdivide to the (finer) floor — samples only this band
			accumulate_qef(idx);
		}
	}

	// Roll accumulated QEFs back up the tree from the (cached) leaf QEFs — NO field sampling. A retained
	// leaf keeps its cached QEF; an absent leaf contributes empty; an internal node = the in-order sum of
	// its children. Bit-identical to a full accumulate_qef() because the summands and order are identical.
	void reaccumulate(int idx) {
		if (cells[idx].children[0] < 0) {
			if (cells[idx].absent) {
				cells[idx].qef = Qef();
			}
			return; // present leaf: keep cached QEF (the no-resample property)
		}
		Qef sum;
		for (int i = 0; i < 8; ++i) {
			int ch = cells[idx].children[i];
			reaccumulate(ch);
			sum.add(cells[ch].qef);
		}
		cells[idx].qef = sum;
	}
};

} // namespace

// The retained octree (Stage 2): a full build keeps its tree + per-node QEFs + the field snapshot
// alive so remesh() can re-decide collapse against a new camera without re-sampling. Octree is
// .cpp-local, so this is a pimpl the header forward-declares.
struct DCOctreePersist {
	Octree oct;
	Clipmap clip;                              // clipmap path: the field source oct.src points at
	LocalVector<PackedFloat32Array> held;      // keeps level SDF data alive (Level.data points in)
	LocalVector<PackedByteArray> held_idx;     // ...and the per-level material indices
	// World-fixed path (mesh_world): the EditStore field source oct.src points at, plus a Ref keeping the
	// store alive — so remesh() can re-collapse the retained world octree against a new camera (no resample).
	Ref<EditStore> world_store;
	EditStoreSource world_src{ nullptr, Vector3(), 1.0 };
};

// Pack an octree's meshed surface into a Mesh.ARRAY_* array (empty if no surface).
static Array pack_output(const Octree &oct) {
	Array out;
	if (oct.verts.is_empty()) {
		return out;
	}
	out.resize(Mesh::ARRAY_MAX);
	out[Mesh::ARRAY_VERTEX] = oct.verts;
	out[Mesh::ARRAY_NORMAL] = oct.normals;
	if (!oct.colors.is_empty()) {
		out[Mesh::ARRAY_COLOR] = oct.colors;
	}
	out[Mesh::ARRAY_INDEX] = oct.indices;
	return out;
}

DCOctreeMesher::~DCOctreeMesher() {
	if (_persist != nullptr) {
		memdelete(_persist);
	}
}

// Re-walk the retained octree against a new camera/proj/eps and re-mesh — no build, no field
// sampling (Stage 2 movement path). Requires a prior full mesh_clipmap to have retained a tree.
Array DCOctreeMesher::remesh(Vector3 camera, double proj, double eps_px) {
	if (_persist == nullptr) {
		return Array(); // nothing retained yet — a benign no-op (caller falls back to mesh_clipmap)
	}
	Octree &oct = _persist->oct;
	oct.camera = camera;
	oct.proj = proj;
	oct.eps_px = eps_px;
	oct.recollapse_and_mesh();
	_last_tri_owners = oct.tri_owners;
	_last_tri_owner_sizes = oct.tri_owner_sizes;
	return pack_output(oct);
}

Array DCOctreeMesher::mesh_clipmap(
		const TypedArray<PackedFloat32Array> &level_data,
		int dim,
		const PackedVector3Array &level_origins,
		const PackedFloat32Array &level_cells,
		Vector3 center,
		double half0,
		int depth,
		Vector3 camera,
		double proj,
		double eps_px,
		bool error_driven,
		Vector3i lattice_world_origin,
		const TypedArray<PackedByteArray> &level_indices,
		const PackedColorArray &palette,
		bool uniform_core,
		double prune_safety,
		Vector3i emit_min,
		Vector3i emit_max,
		Vector3i build_min,
		Vector3i build_max) {
	Array out;
	const int n = level_data.size();
	if (n == 0 || dim < 2 || level_origins.size() != n || level_cells.size() != n || depth < 1) {
		ERR_PRINT("DCOctreeMesher: bad arguments");
		return out;
	}

	// Retain ONLY a full build (no emit/build box) so remesh() can re-walk it; a splice is restricted
	// to a sub-box, so it builds into a transient octree and leaves the retained full build intact.
	const bool retain = (emit_min == emit_max) && (build_min == build_max);
	Octree transient_oct;
	Clipmap transient_clip;
	LocalVector<PackedFloat32Array> transient_held;
	LocalVector<PackedByteArray> transient_held_idx;
	Octree *octp = &transient_oct;
	Clipmap *clipp = &transient_clip;
	LocalVector<PackedFloat32Array> *heldp = &transient_held;
	LocalVector<PackedByteArray> *held_idxp = &transient_held_idx;
	if (retain) {
		if (_persist != nullptr) {
			memdelete(_persist);
		}
		_persist = memnew(DCOctreePersist);
		octp = &_persist->oct;
		clipp = &_persist->clip;
		heldp = &_persist->held;
		held_idxp = &_persist->held_idx;
	}

	// Hold the level arrays for the call so their data pointers stay valid.
	LocalVector<PackedFloat32Array> &held = *heldp;
	held.resize(n);
	LocalVector<PackedByteArray> &held_idx = *held_idxp;
	held_idx.resize(n);
	const int64_t per_level = int64_t(dim) * dim * dim;
	const bool with_indices = level_indices.size() == n && palette.size() > 0;

	Octree &oct = *octp;
	Clipmap &clip = *clipp;
	oct.src = &clip;
	oct.emit_color = with_indices;
	oct.palette = palette;
	oct.uniform_core = uniform_core;   // keep the 1m fine core uniform so edit patches splice cleanly
	oct.prune_safety = prune_safety;   // >0: surface-sparse build (skip provably-empty regions)
	oct.root_size = 1 << depth;
	oct.max_depth = depth;
	oct.camera = camera;
	oct.proj = proj;
	oct.eps_px = eps_px;
	oct.error_driven = error_driven;
	oct.world_origin = lattice_world_origin;
	// Emit-box filter: when emit_min != emit_max (caller set them), restrict output to
	// triangles owned by cells inside [emit_min, emit_max).
	if (emit_min != emit_max) {
		oct.emit_filter = true;
		oct.emit_min = emit_min;
		oct.emit_max = emit_max;
	}
	// Build-box restriction: a splice builds on the FULL frame (root_origin/_ROOT_DEPTH) but descends
	// only cells overlapping [build_min, build_max) (the edit box + apron), so its cells land on the
	// full build's lattice and neighbours — no offset sub-octree, no seam divergence.
	if (build_min != build_max) {
		oct.build_box = true;
		oct.build_min = build_min;
		oct.build_max = build_max;
	}
	clip.center = center;
	clip.half0 = half0;
	clip.levels.resize(n);
	for (int k = 0; k < n; ++k) {
		held[k] = level_data[k];
		if (held[k].size() != per_level) {
			ERR_PRINT("DCOctreeMesher: level data size mismatch");
			return out;
		}
		Level lv;
		lv.data = held[k].ptr();
		lv.origin = level_origins[k];
		lv.cell = level_cells[k];
		lv.dim = dim;
		if (with_indices) {
			held_idx[k] = level_indices[k];
			if (held_idx[k].size() == per_level) {
				lv.idx = held_idx[k].ptr();
			}
		}
		clip.levels[k] = lv;
	}

	if (prune_safety > 0.0) {
		clip.build_mips(); // min/max pyramids for the exact surface-sparse prune
	}
	oct.run();

	_last_tri_owners      = oct.tri_owners;
	_last_tri_owner_sizes = oct.tri_owner_sizes;
	return pack_output(oct);
}

// World-fixed octree (doc 16 THE GOAL, scaffold): build + mesh ONE octree rooted at the WORLD-aligned
// box [world_origin, world_origin + 2^depth) (lattice units; 1 unit = base_cell metres), sampling the
// EditStore field DIRECTLY — no concentric clipmap, no geomorph. Bottom-up exact: build to the floor
// where there is surface, accumulate fine QEF up the tree, collapse by screen-error (we*proj/dist vs
// eps_px) from real fine data. camera is the viewpoint in this lattice frame (world/base_cell -
// world_origin). Returns Mesh.ARRAY_* (lattice-local; caller scales by base_cell + positions at
// world_origin). This is the seam the persistent/incremental world octree grows from; the live render
// still runs mesh_clipmap until this path is trusted.
Array DCOctreeMesher::mesh_world(
		Ref<EditStore> store,
		Vector3i world_origin,
		int depth,
		double base_cell,
		Vector3 camera,
		double proj,
		double eps_px,
		bool error_driven,
		const PackedColorArray &palette,
		Vector3i win_min,
		Vector3i win_max) {
	Array out;
	if (store.is_null() || depth < 1 || base_cell <= 0.0) {
		ERR_PRINT("DCOctreeMesher::mesh_world: bad arguments");
		return out;
	}
	// Retain the world octree (like a full mesh_clipmap) so remesh() can re-collapse it against a new
	// camera with no field resampling — the persistent-octree foundation for incremental movement. The
	// EditStoreSource + a Ref to the store live in the persist so oct.src stays valid across remesh().
	if (_persist != nullptr) {
		memdelete(_persist);
	}
	_persist = memnew(DCOctreePersist);
	_persist->world_store = store;
	_persist->world_src = EditStoreSource(store.ptr(), Vector3(world_origin), base_cell);
	Octree &oct = _persist->oct;
	oct.src = &_persist->world_src;
	oct.emit_color = palette.size() > 0;
	oct.palette = palette;
	oct.root_size = 1 << depth;
	oct.max_depth = depth;
	oct.camera = camera;
	oct.proj = proj;
	oct.eps_px = eps_px;
	oct.error_driven = error_driven;
	oct.world_origin = world_origin;
	oct.uniform_core = false; // the whole world octree collapses by screen-error; no fine bubble to pin
	oct.prune_safety = 0.0;   // off unless a window is set (below) — a windowless build stays dense to floor
	// Resident WINDOW (doc 16 Stage B): when win_min != win_max, build only the cells overlapping the
	// window box (WORLD lattice) and mark the rest absent — the large root can span the roam region while
	// the build cost stays bounded to the window. Default (win_min == win_max) = build the whole root.
	// P2 (doc 17): graded data floor DERIVED from the single eps_px knob — build only as fine as a cell
	// renders. A size-s cell at distance d projects to ~s·proj/d px, = eps_px at s = eps_px·d/proj, so
	// floor_k = eps_px/proj. No separate dial: the budget controller drives eps_px (start coarse, tighten to
	// the frame/WORK budget) and the floor follows. (proj==0 → no camera → uniform fine.)
	double floor_k = (proj > 0.0 && eps_px > 0.0) ? eps_px / proj : 0.0;
	_persist->world_src.cam = camera;
	_persist->world_src.floor_k = floor_k;
	if (win_min != win_max) {
		oct.build_box = true;
		oct.window_mode = true;
		oct.build_min = win_min;
		oct.build_max = win_max;
		// Bake the surface-sparse accel (P1+P2) over the window and turn the prune on. Uniform (floor_k==0)
		// → one res-1 level covering the window; graded → concentric levels (fine near camera, coarse far),
		// so a large window stays affordable.
		_persist->world_src.bake_accel(win_min - world_origin, win_max - world_origin, camera, floor_k);
		oct.prune_safety = 1.0;
	}
	oct.run();

	_last_tri_owners      = oct.tri_owners;
	_last_tri_owner_sizes = oct.tri_owner_sizes;
	_last_build_samples   = oct.build_samples;
	return pack_output(oct);
}

// Incremental window growth (doc 16 Stage B): re-window the RETAINED world octree (from a prior
// mesh_world) to [win_min, win_max) (WORLD lattice) — graft the cells that newly entered, sampling ONLY
// them; evict the cells that left — then re-collapse + mesh against camera/proj/eps. The interior cells
// (in both windows) keep their tree, QEFs, and vertices: a move re-samples just the leading-edge band,
// not the whole vicinity. By construction the result is byte-identical to a from-scratch mesh_world of
// the new window. Benign no-op (empty Array) if nothing is retained — caller falls back to mesh_world.
Array DCOctreeMesher::grow_world(Vector3 camera, double proj, double eps_px, Vector3i win_min, Vector3i win_max) {
	if (_persist == nullptr) {
		return Array();
	}
	Octree &oct = _persist->oct;
	oct.build_box = true;
	oct.window_mode = true;
	oct.build_min = win_min;
	oct.build_max = win_max;
	// P1/P2: re-bake the accel over the NEW window so the leading-edge band is covered (an uncovered box
	// would prune the band away). Keep the build's floor_k; recentre the accel on the new camera. The
	// retained interior isn't rebuilt — its prune decisions stand (geometrically identical, empty either
	// way). NOTE: grow does not re-grade interior cells whose floor changed with the camera — that's the
	// incremental band-diff (a later increment); a graded dcworld full-rebuilds on larger moves meanwhile.
	if (_persist->world_src.has_accel) {
		double floor_k = (proj > 0.0 && eps_px > 0.0) ? eps_px / proj : 0.0; // same single-knob derivation
		_persist->world_src.cam = camera;
		_persist->world_src.floor_k = floor_k;
		_persist->world_src.bake_accel(win_min - oct.world_origin, win_max - oct.world_origin, camera, floor_k);
		oct.prune_safety = 1.0;
	}
	oct.build_samples = 0;
	oct.reconcile(0);    // graft leading edge (samples only new cells) + evict trailing edge
	oct.reaccumulate(0); // roll up ancestor QEFs from cached children — no field sampling
	oct.camera = camera;
	oct.proj = proj;
	oct.eps_px = eps_px;
	oct.recollapse_and_mesh();
	_last_tri_owners      = oct.tri_owners;
	_last_tri_owner_sizes = oct.tri_owner_sizes;
	_last_build_samples   = oct.build_samples;
	return pack_output(oct);
}

// Total slots in the retained octree's cell array (live + free). With B1b's free-list this plateaus
// across a long traverse (evicted slots reused), instead of growing every move — the bound the test gates.
int DCOctreeMesher::get_octree_cell_count() const {
	return _persist != nullptr ? int(_persist->oct.cells.size()) : 0;
}

void DCOctreeMesher::_bind_methods() {
	ClassDB::bind_method(
			D_METHOD("mesh_clipmap", "level_data", "dim", "level_origins", "level_cells", "center", "half0", "depth",
					"camera", "proj", "eps_px", "error_driven", "lattice_world_origin", "level_indices", "palette",
					"uniform_core", "prune_safety", "emit_min", "emit_max", "build_min", "build_max"),
			&DCOctreeMesher::mesh_clipmap,
			DEFVAL(Vector3()), DEFVAL(0.0), DEFVAL(0.0), DEFVAL(false), DEFVAL(Vector3i()),
			DEFVAL(TypedArray<PackedByteArray>()), DEFVAL(PackedColorArray()), DEFVAL(false), DEFVAL(0.0),
			DEFVAL(Vector3i()), DEFVAL(Vector3i()), DEFVAL(Vector3i()), DEFVAL(Vector3i()));
	ClassDB::bind_method(
			D_METHOD("mesh_world", "store", "world_origin", "depth", "base_cell",
					"camera", "proj", "eps_px", "error_driven", "palette", "win_min", "win_max"),
			&DCOctreeMesher::mesh_world,
			DEFVAL(Vector3()), DEFVAL(0.0), DEFVAL(0.0), DEFVAL(false), DEFVAL(PackedColorArray()),
			DEFVAL(Vector3i()), DEFVAL(Vector3i()));
	ClassDB::bind_method(
			D_METHOD("grow_world", "camera", "proj", "eps_px", "win_min", "win_max"),
			&DCOctreeMesher::grow_world);
	ClassDB::bind_method(D_METHOD("remesh", "camera", "proj", "eps_px"), &DCOctreeMesher::remesh);
	ClassDB::bind_method(D_METHOD("get_last_build_sample_count"), &DCOctreeMesher::get_last_build_sample_count);
	ClassDB::bind_method(D_METHOD("get_octree_cell_count"),      &DCOctreeMesher::get_octree_cell_count);
	ClassDB::bind_method(D_METHOD("get_last_triangle_owners"),      &DCOctreeMesher::get_last_triangle_owners);
	ClassDB::bind_method(D_METHOD("get_last_triangle_owner_sizes"), &DCOctreeMesher::get_last_triangle_owner_sizes);
}
