# The Octree Edit Store — replacing godot_voxel as the data layer

*The detailed design for the Phase B core of [`10-adaptive-octree-substrate.md`](10-adaptive-octree-substrate.md):
making our octree the **persistent store** so godot_voxel can be removed. Doc 10 is the
substrate spec and the staging (B1–B6); this doc resolves the open "decisions needed" and
lays out the reversible bite sequence. Render + collision are already ours; this is the
last load-bearing thing godot_voxel does.*

## TL;DR

godot_voxel is now **only the data layer**: SDF storage, the SQLite stream, streaming,
and the generator graph. Render (`DCTerrainManager` / the substrate) and collision
(`DCCollisionManager`) are already our DC mesh; the generator is already mirrored in C++
(`TerrainField`, [[terrain-generation-in-cpp]]). The one remaining crutch: **edits are
re-read from godot_voxel** (the substrate's overlay, `DCRegionReader`) instead of owned by
us.

The fix is an **EditStore**: a persistent, sparse, adaptive octree that holds **only the
player's edits** (SDF + material), deferring to `TerrainField` everywhere it has no data.
Edits write into it; render and collision imprint from `generator + EditStore`; it
persists to disk. Then godot_voxel goes.

The store is sparse because **we store nothing for unedited world** — the generator is
stateless and regenerated on demand (Robert's "I'd love to not store anything at all for
most of the world"). Edits are localized, so the whole store stays resident: **streaming
becomes a non-problem**, not a deferred feature.

## Why an EditStore and not "just keep imprinting"

The current substrate octree is **transient** — built around the camera from the field,
meshed, discarded. That's correct for a *render* structure. But edits must **persist** and
be **authoritative**, which a transient structure can't do. So there are two structures,
with different lifetimes:

| | EditStore (new) | Render/collision octree (have it) |
|---|---|---|
| Lifetime | persistent, authoritative | transient, rebuilt around camera/bodies |
| Holds | only edits (SDF + material) | generator + edits, full surface, LOD-graded |
| Resolution | the edit's resolution (sub-metre capable) | LOD-graded for the view |
| Persisted | yes (replaces the SQLite stream) | no (regenerated) |

The render/collision octrees already exist and already imprint `generator + edits`; this
design only changes **where the "edits" come from** — the EditStore instead of a
godot_voxel re-read.

## Core design

### The field, after this lands

```
field(p) = EditStore.has(p) ? EditStore.value(p) : TerrainField.sample(p)
```

`TerrainField` (C++) is stateless and always available. The EditStore is a sparse octree
keyed to world coordinates; a node exists only where the player edited. Everything that
needs the field (render imprint, collision cook, the SDF backstop, probes) samples through
this one function.

### Writing an edit (copy-on-write from the generator)

An edit is a brush + op (dig = subtract sphere, fill = union, CSG = a `CsgShape`, etc.).
Applying it to the EditStore:

1. For the edited region's cells **not yet in the store**: sample `TerrainField` there
   (the "before" — the generator value), apply the brush op, store the result. This is
   copy-on-write: the generator value is materialised into the store only at the moment
   it's first edited.
2. For cells **already in the store**: apply the brush op to the stored value.
3. The store subdivides to the brush's resolution (1 m today; sub-metre later — the octree
   does it natively, the win doc 10 is built for).

Only edited cells ever get stored, so the store stays sparse and bounded by *edit volume*,
not world volume.

### Decisions resolved (doc 10's "decisions needed")

**1. Edit representation: sampled sparse octree, NOT an op-log. (Recommended.)**
Store the *resulting field* (edited SDF + material) adaptively, not a log of operations.
Rationale:
- It handles **all** edit types uniformly — flatten/raise/lower are field modifications,
  not analytic brushes, so they're awkward as replayable op-log entries but trivial as
  stored results.
- It's bounded by edit *volume* (localized), and the octree gives sub-metre natively.
- It IS the substrate octree machinery we already have and trust (`SparseVoxelOctree`:
  stamp / sample / sub-metre / mesh).
- godot_voxel was effectively this (a sparse 1 m edit grid over the generator), so it's a
  proven model — we're replacing it with an adaptive, sub-metre-capable version we own.
- Full-resolution in the store (no lossy mips — the store is the truth; the render LODs
  down from it via accumulated QEF), so it's faithful ([[validate-on-faithful-field]],
  manifesto fidelity).

The **op-log** (doc 05) is the right representation for *multiplayer sync* — a transport,
orthogonal to the local store. It can be layered on later without changing this design; it
is NOT the local persistence format.

*Cost owned by this choice:* no free undo/redo (a sampled store has no op history). This
is fine — undo is **not** going to be a sampled-store concern. The planned model is a
**commit action**: enter an undoable "hypothetical" build mode, specify changes (recorded
as pending, not yet applied to the authoritative field), then commit. That also sidesteps
physics-instability during intermediate build steps (nothing is real until commit) and
ties into the future parts library. An op-log of the *pending* edits is the natural backing
for that mode — layered on when it's built, not part of the base store.

**2. Write API (B2): one sink the actions call.** Every edit currently ends at
`VoxelTool` (godot_voxel). Introduce one method — `EditStore.stamp(field, op, material)` —
and route every action's mutation through it, so the action layer changes in **one place**
(a shared helper / the `Action.execute` sink), not per-verb. The brush each action already
computes (sphere/box/`CsgShape`/column field) becomes the `field` argument.

**3. Persistence format (B3): a flat versioned blob of the edited nodes.** Serialize the
EditStore's node pool (origin, size, corner SDF, material) to a binary file under
`user://saves/`, versioned like the snapshot. Replaces `VoxelStreamSQLite`. The existing
`WorldSnapshot` (parts, player, tunables) stays and gains a pointer to / embeds the store
blob.

**4. Streaming/eviction: not needed initially — and that's honest, not deferred.** Because
the store is only edits (sparse, localized) and the generator is stateless on-demand, the
whole store fits resident for any realistic v0.1 play area. The architecture supports
adding spatial paging later (it's an octree keyed to world coords), but there's nothing to
page out now. We do NOT build streaming we don't need; we DO note the resident-size
assumption so a future huge-edit-area can flag it.

**5. Resolution: 1 m at parity, sub-metre for free later.** Start the store at 1 m (matches
today's edits, so the migration is behaviour-neutral). Sub-metre needs no store change —
just a finer brush min-leaf — so it lands when parts-as-voxels (B5) needs it.

## Migration: dual-write, then flip, then drop (each stage reversible)

godot_voxel stays authoritative until the EditStore is proven, so every stage falls back
cleanly:

- **S1 — EditStore (C++), headless-tested, unwired.** The sparse copy-on-write store:
  `stamp(field, op, material)`, `sample(p)` / `has(p)`, serialize/deserialize. Likely a
  thin specialisation of `SparseVoxelOctree` (it already stamps + samples + sub-metres;
  the new part is copy-on-write-from-generator and the unedited→generator sentinel). Tests:
  stamp a brush → sample reflects it; unedited → defers; serialize round-trips; a dig over
  generator terrain materialises + carves correctly.
- **S2 — Dual-write.** Edits write to godot_voxel (as now) **and** the EditStore. A *light*
  check that the two roughly agree over edited regions is enough — divergence only matters
  until godot_voxel is dropped at S5, and a little wrong for a while during the migration
  is acceptable (Robert's call; the saves are test-only). godot_voxel still drives
  everything — pure addition, reversible.
- **S3 — Flip render + collision to the EditStore.** Swap the substrate's overlay source
  and `DCCollisionManager`'s SDF source from `DCRegionReader` (godot_voxel) to
  `generator + EditStore`. This also **fixes the substrate's 64 m edit-overlay limit** (all
  edits are resident, not just near-player reads) and the **collision "region not streamed"
  gap** (the generator is always available). godot_voxel now only persists.
- **S4 — Flip persistence to the EditStore blob.** Save/load the store; stop using the
  SQLite stream. godot_voxel now does nothing load-bearing.
- **S5 — Drop godot_voxel.** Remove the dual-write, the `VoxelLodTerrain` node, the stream,
  the `.tres` graph + `build_terrain_graph.gd`, and the godot_voxel side of
  `DCRegionReader`. The generator is `TerrainField`; the store is the EditStore;
  render/collision/persistence are ours.

Each stage ships and is reversible on its own; godot_voxel is the fallback through S4.

## Open questions — resolved (2026-06-10)

All resolved with Robert; recorded here so the calls aren't relitigated.

- **Existing saves don't transfer → accept the reset.** All current saves are test-only,
  so no importer; the new store just starts fresh (precedent: the material-channel reset).
- **Dual-write divergence → tolerate it.** It only matters until godot_voxel is dropped at
  S5, after which there's one source and the question is moot. A little wrong during the
  migration is acceptable; a light agreement check, not a rigorous probe.
- **Edit-time copy-on-write resolution → as fine as practical, watch frame time.** We are
  NOT optimising storage or memory yet — only frame time, target **< 20 ms/frame (50 fps;
  picked over 30 fps because 1/30 is a repeating decimal)**. So materialise the generator
  at the brush's resolution (or finer) and only coarsen if a build's frame cost crosses
  that budget. Tunable later; not a blocker for the big bites.
- **No undo → deferred to the commit / hypothetical-build model** (see Decision 1) — not a
  sampled-store concern.
- **Render/collision correctness on the flip (S3) → that's what tests are for.** Proceed,
  watch the suite + an eyeball, deal with consequences if they surface. Same machinery,
  different source; dual-write is the fallback through S4.
- **Streaming at scale → resident-only now, paging later.** Confirmed; nothing to page out
  while edits are sparse, and the octree structure permits adding it when a huge-edit area
  ever needs it.

**Schedule note:** Robert is aiming to finish Phase 5.5 this week and is fine with the app
being broken or a little off during the migration — so bias toward forward progress over
defensive scaffolding between S1 and S5.

## Manifesto check

This is the no-half-measures path ([[no-half-measures]]): it removes the crutch (edits
re-read from godot_voxel) and reaches the actual vision — one field, one store, one mesher,
godot_voxel gone, sub-metre-capable, the foundation parts-as-voxels (B5) rides on. The
dual-write migration is a **safe sequence, not a permanent hedge** — godot_voxel is removed
at S5, not left "as-is." The only cost is execution effort across several bites, which the
manifesto explicitly does not count as a reason to avoid the right design. No correctness is
traded for speed, and no regression is shipped (the store is full-resolution and faithful;
each flip is guarded).

## When this lands

The rationale graduates into [`architecture.md`](architecture.md); the resolved
decisions into [`02-architectural-commitments.md`](02-architectural-commitments.md). Doc 10
stays as the substrate spec; this chapter is deleted once S5 ships.
