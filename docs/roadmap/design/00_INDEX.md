# docs/roadmap/design — Index

The non-implementation specs: *what the answer is*, independent of when it
ships. Each entry below notes *why the doc exists*, not what it contains.
Once a chapter ships, its rationale graduates into
[`../../architecture.md`](../../architecture.md) and the chapter is deleted
or condensed.

## Files

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
