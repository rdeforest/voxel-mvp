# Volumetric, stratified worldgen

*What the answer is.* The worldgen generator stops being heightfield-shaped and
becomes a true volumetric, stratified field — overhangs, caves, and layered
geology that an amateur geologist reads as *"this could actually have happened."*

- Literature behind this: [`reference/07-worldgen-research.md`](../reference/07-worldgen-research.md).
- Work-order: [`implementation/planned/18-volumetric-worldgen.md`](../implementation/planned/18-volumetric-worldgen.md).
- Authority: [`MANIFESTO.md`](../../MANIFESTO.md) non-negotiable #2 (caves are
  first-class, same continuous volume) and the substrate view in
  [`06-channel-architecture.md`](06-channel-architecture.md).

## The realization that shrinks the problem

**We are already not a heightfield.** The substrate is a full 3D SDF +
material field; the octree, mesher, EditStore, and streaming all operate on
`f(position) -> (sdf, material)`. The *only* place a heightfield survives is the
**shape of the generator function** in
[`engine/voxel_dc/terrain_field.h`](../../../engine/voxel_dc/terrain_field.h):

```cpp
double sample(const Vector3 &p) const override { return p.y - surface(p.x, p.z); }
```

`p.y - surface(x,z)` is single-valued in `y`, so it can't fold back over itself —
no overhangs. Material is two depth-bands (Natural / Bedrock). That's the whole
limitation. The manifesto objection to heightfields is **already satisfied at the
substrate level**; we just aren't exploiting it yet. The fix is rewriting one
`sample()`/`material()` pair — *not* the data model, octree, mesher, or
streaming.

## The requirement, stated precisely

Not physical realism. **Plausibility-as-story:** an amateur geologist walking the
world should be able to reconstruct a believable history from what they see. That
bar is read primarily from **structure and stratigraphy** — layering, folding,
faulting, unconformities, caprock undercuts, caves following a water table — and
only secondarily from accurate surface drainage (a hydrologist's tell, not a
geologist's).

This matters because structure is **purely evaluable per-point**; accurate
drainage is **global, expensive, and untileable** (see research doc, "the crux").
The requirement points at the cheap half.

## The two levers, separated

Earlier reasoning bundled "realism" and "overhangs" into one decision. They are
independent:

- **Overhangs / caves / strata** — a *representation* choice. A generator whose
  `sample()` isn't monotonic in `y`. Pure, per-point, tiles infinitely.
- **Geomorphological plausibility (drainage)** — a *simulation* choice. Global
  flow, O(area), no published seamless tiling.

Breaking purity buys the *second* lever. The thing we actually want lives mostly
in the *first*.

## The three-tier plan

1. **Volumetric stratified generator — PURE, per-point.** Strata as a function of
   depth-below-surface with the depth coordinate warped by a folding/faulting
   field; 3D noise carving for caves/karst; overhangs and caprock undercuts fall
   out of the boolean. Replaces `sample()`/`material()`. Still `f(position)`, so
   it tiles infinitely with zero seam problem. **This is the spine and it
   delivers most of the geologist test.**

2. **Sparse global river graph — cheap precompute, near-pure local eval.** A
   coarse 1D drainage network computed once (curves, not volume — O(rivers), not
   O(area)), queried per-point as distance-to-nearest-river to carve valleys.
   Rivers, valleys, and **waterfalls emerge where a river crosses a hard caprock
   stratum** — the river undercuts the soft rock below, the caprock overhangs.
   The motivating waterfall example falls out of tiers 1+2 composing, not a
   special case. A *mild* purity break (one sparse, streamable global structure),
   not the erosion wall.

3. **Regional erosion bake — full purity break, unsolved tiling.** Stream-power
   erosion baked per tile for accurate drainage. **Deferred, off the critical
   path.** Only if tiers 1+2 still look fake to a real geologist.

## Manifesto reconciliation (this is not a half-measure)

The no-compromise goal — overhangs, caves, layered geology that tells a story —
is **fully met by tiers 1+2**. Keeping purity there is not settling for a lesser
solution; it's that the lesser solution (heightfield) is what we're *leaving*.

Tier 3's global erosion buys **drainage realism**, which is a *different,
additional* goal — not a better version of tiers 1+2. Per the manifesto, it's
deferred because it is genuinely later-phase work that the stated requirement
(amateur-geologist plausibility) does not need, **not** because it's the hard
part of this phase being dodged. The hard part of *this* phase — stop being a
heightfield — is done now, completely, and happens to be pure.

If tier 3 is ever taken on, it's taken on without compromise then: the unsolved
seamless-tiling problem gets solved, not papered over.

## Why purity survives tier 1 (the load-bearing bet)

A heightfield is impure-free because `y - surface(x,z)` is closed-form. Folded
strata and 3D-noise caves are *also* closed-form per-point:

- Strata: `material = layer_of(warp(depth, p))` — pure.
- Caves: `sdf = max(terrain_sdf, -cave_field(p))` where `cave_field` is 3D noise
  (worley worms / ridged) — pure.
- Overhangs: a direct consequence of the cave boolean and folded surfaces — pure.

The open risk (research doc, open question #1): whether the richest features from
Paris-2019 construction-tree amplification can be evaluated lazily per-point, or
need a baked pass. Tier 1 as specified above stays inside the provably-pure
subset; importing Paris-2019's full repertoire is a tier-1.5 question to settle
by prototype, not assumption.

## What this does not change

- The substrate, octree, EditStore, DC mesher, streaming, LOD — untouched.
- Edits remain first-class: a generated overhang and a dug overhang are the same
  field, same mesher (see [[edits-first-class]]).
- Bedrock stays a material property of depth, now one stratum among several.
