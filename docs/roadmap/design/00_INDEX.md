# docs/roadmap/design — Index

The non-implementation specs: *what the answer is*, independent of when it
ships. Each entry below notes *why the doc exists*, not what it contains.
Once a chapter ships, its rationale graduates into
[`architecture.md`](architecture.md) and the chapter is deleted
or condensed.

## Files

- [`architecture.md`](architecture.md) — the graduation target: mechanism
  rationale for shipped code (how the gears mesh), so the *why* outlives
  memory. Distinct from the numbered specs — it records what already ships.
- [`01-principles.md`](01-principles.md) — states the load-bearing design
  principles the rest of the corpus rests on.
- [`02-architectural-commitments.md`](02-architectural-commitments.md) —
  records shipped decisions worth not relitigating.
- [`03-dc-qef-geometry.md`](03-dc-qef-geometry.md) — specifies the unified
  field-based geometry (DC + QEF) that erases the terrain-vs-object split.
- [`04-event-bus.md`](04-event-bus.md) — preserves the spec for the event
  bus (mostly shipped) so the design intent survives the code.
- [`05-network-architecture.md`](05-network-architecture.md) — captures the
  far-horizon decentralized op-log multiplayer vision.
- [`06-channel-architecture.md`](06-channel-architecture.md) — defines the
  multi-channel spatial-database view of the voxel grid.
- [`07-known-hard-problems.md`](07-known-hard-problems.md) — parks open
  architectural questions so they aren't rediscovered from scratch later.
- [`08-continuous-work-actions.md`](08-continuous-work-actions.md) —
  specifies the duration-based mechanic that replaces click-spam.
- [`09-world-setting.md`](09-world-setting.md) — holds the creative-
  direction placeholder (iron-age, distinctly non-Norse).
- [`10-adaptive-octree-substrate.md`](10-adaptive-octree-substrate.md) —
  specifies the persistent world-fixed octree substrate that will replace
  both render and data layers and fix LOD seams.
- [`11-octree-edit-store.md`](11-octree-edit-store.md) — the detailed design
  for doc 10's Phase B core: a persistent sparse EditStore (edits only,
  deferring to the generator) that replaces godot_voxel as the data layer.
- [`12-mpm-structural-substrate.md`](12-mpm-structural-substrate.md) — the
  target structural simulation: continuum physics via the Material Point
  Method, replacing PBD so terrain/parts/debris deform, fracture, and settle
  under one solver (Stages 5–6 become emergent). Vision + spike plan.
- [`13-incremental-lod-splice.md`](13-incremental-lod-splice.md) — make edits
  patch the displayed mesh incrementally at any distance/LOD (not full-rebuild),
  and size detail to a runtime budget instead of a constant fine core. B1 (multi-
  LOD splice) + B2 (budget-driven eps_px); B3 (incremental LOD on camera move)
  deferred but recorded.
- [`14-consensus-reality.md`](14-consensus-reality.md) — "excuse-driven magic":
  unrealistic abilities (double-jump, glide) default **on** until the player proves
  they know better, then re-enable via in-world "excuse" artifacts. A diegetic
  dream-tell; the belief-domain state machine that gates them. Disillusionment
  trigger deferred to the damage model.
- [`15-pets-and-companions.md`](15-pets-and-companions.md) — defines animal
  companionship as fed-not-tamed behavior (unfed animals raid instead), with
  the @CanYouPetTheDog bar as a real acceptance test.
- [`16-character-customization.md`](16-character-customization.md) — specifies
  avatar authoring: high fidelity plus an affirmative full range of atypical
  bodies, the unremovable dream-wounds, and the one deliberate (mechanical)
  exclusion.
