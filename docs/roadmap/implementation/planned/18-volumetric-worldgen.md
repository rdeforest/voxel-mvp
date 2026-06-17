# Volumetric worldgen — implementation work-order

*The temporal axis for [`design/19-volumetric-worldgen.md`](../../design/19-volumetric-worldgen.md).*
Status: **planned, not begun.** Research: [`reference/07-worldgen-research.md`](../../reference/07-worldgen-research.md).

The whole change is concentrated in one file —
[`engine/voxel_dc/terrain_field.h`](../../../../engine/voxel_dc/terrain_field.h) —
plus the `MaterialPalette` it must stay in sync with. The substrate, octree,
mesher, EditStore, and streaming are untouched (see design doc).

## What `TerrainField` is today

```cpp
double surface(double x, double z)  // base + amp * ridged(x,z)
double sample(const Vector3 &p)     // p.y - surface(x,z)         -- height-shaped
int    material(const Vector3 &p)   // depth-band: Natural | Bedrock
```

`sample()` being single-valued in `y` is the heightfield. Everything below
replaces these two functions; `surface()` survives as the *base elevation* input,
no longer the whole story.

## Tier 1 — volumetric stratified generator (PURE)

The deliverable. No purity break, no new global state, tiles infinitely.

### 1a. Stratified material

Define strata as a stack of bands measured in **depth below the local surface**,
with the depth coordinate **warped** so layers fold and fault instead of lying
flat:

```
depth      = surface(x,z) - p.y                     // >0 inside solid
warped     = depth + fold_field(p)                  // low-freq 3D noise -> folding
faulted    = warped + fault_offset(p)               // piecewise step field -> faults
material   = stratum_at(faulted)                    // lookup in an ordered band table
```

- `stratum_at` is a **data table** (ordered thickness + material id), not an
  if-chain — matches the project's lookup-over-branching standard. Bedrock
  becomes the deepest band rather than a special case.
- The band table is the single source of truth for the geological column; expose
  its tunables the way terrain params are exposed now (`terrain_defaults`).
- Per [[bedrock-and-terrain-materials]]: terrain → layered materials, bedrock the
  always-supporting floor. This is where that lands.

### 1b. Volumetric shape (overhangs + caves)

Make `sample()` non-monotonic in `y` by composing the base solid with a 3D carve
field:

```
base_sdf = p.y - surface(x,z)                       // the old field, now just the base
cave_sdf = cave_field(p)                            // 3D noise: worley worms / ridged tunnels
sdf      = max(base_sdf, -cave_sdf)                 // carve caves; boolean subtraction
```

- Overhangs and arches are a consequence of `cave_sdf` cutting under solid and of
  folded strata — no special case.
- `cave_field` must be genuinely 3D (function of `p.y`, not just `x,z`), or it
  collapses back to a heightfield.
- Keep it inside the **provably-pure subset** (closed-form noise). The richer
  Paris-2019 construction-tree features are a tier-1.5 prototype question
  (research open Q#1), not a tier-1 commitment.

### 1c. Validation

Per [[validate-on-faithful-field]] and [[dc-sdf-not-unit-distance]]: the carve
boolean makes `sdf` even less a true unit-distance field than before. Any mesher
heuristic that treats `|sdf|` as distance must be re-checked against this field,
not just the analytic sphere. Add a generator-level test that asserts:
- an overhang exists (some column has solid above air above solid),
- strata ordering is monotonic in unwarped depth,
- caves are connected to the surface where intended.

## Tier 2 — sparse global river graph (mild purity break)

After tier 1 reads convincing. A coarse 1D drainage network, precomputed once,
queried per-point.

- Build: a sparse graph of river polylines over the world (seeded
  deterministically from the same seed, so it's reproducible and streamable in
  chunks). O(rivers), not O(area).
- Query: `dist_to_river(p)` carves a valley profile into `surface()` and lowers
  the water-table input to cave generation.
- **Waterfalls fall out:** where a river segment crosses a hard caprock stratum
  (tier 1a), the softer rock below carves faster → caprock overhang + plunge
  pool. Emergent, not special-cased — this is the motivating example.
- Purity note: this introduces one global structure. Keep it sparse and
  deterministic so a tile can be generated from the seed + the graph alone, with
  no neighbour dependency beyond the river polylines crossing the tile.

## Tier 3 — regional erosion bake (deferred)

Off the critical path. Stream-power erosion (research Camp 2) baked per tile for
accurate drainage. Only if tiers 1+2 look fake to a real geologist. Taking this
on means solving the **unsolved** seamless-tiling problem (halo overlap +
boundary seeding) — a research-grade task, scheduled only when justified.

## Build sequence

1. Tier 1a (strata table + warped depth) — material only, shape unchanged. Cheap,
   visible, low-risk. Verify in-game material banding + the strata test.
2. Tier 1b (cave carve) — the overhang/cave payoff. Verify mesher watertightness
   on the carved field (the risky interaction).
3. Re-check budget controller / frame time — the carve adds surface area; confirm
   we're still inside the [[frame-time-budget]] (< 20 ms) and that the cost grows
   with *detail*, not *world size* (manifesto non-negotiable #8).
4. Tier 2 (river graph) — separate work item; revisit after tier 1 ships.

## Risks / open

- **Mesher × carved field.** The DC mesher has never seen a generator-produced
  overhang; the edit-driven overhangs it handles come through the EditStore. The
  carve boolean is the first *generated* non-monotone field. Watch for the
  known crack/prune classes ([[dc-thin-feature-collapse-bug]], inside-coverage
  cracks in `docs/bugs/`).
- **Build = rebuild.** `terrain_field.h` is compiled into the module; changes
  need `tools/build` and the field re-evaluates everywhere (no migration — the
  generator is the source of truth, EditStore edits ride on top).
- **Paris-2019 laziness** (research open Q#1) gates how far tier 1b can reach
  before tier 3. Settle by prototype, not assumption.
