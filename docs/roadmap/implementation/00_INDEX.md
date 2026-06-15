# docs/roadmap/implementation — Index

The temporal axis: phases, versions, and the work-order tying designs to
delivery checkpoints. Each entry below notes *why the doc exists*, not what
it contains. Docs are bucketed by status: [`started/`](started/) (work
underway), [`planned/`](planned/) (not yet begun), [`done/`](done/00_INDEX.md)
(shipped). A doc moves between these as its status changes.

## Files

- [`01-version-strategy.md`](01-version-strategy.md) — defines the version
  ladder where each release answers one specific feasibility question. (The
  framework that organizes the rest; not itself a phase.)

## Started

Work underway — partially landed or actively in progress.

- [`started/05-phase-5_5-architectural-maturation.md`](started/05-phase-5_5-architectural-maturation.md)
  — the decoupling refactor that readies the architecture for v0.1 (5.5a/b
  shipped; later sub-phases pending).
- [`started/14-dc-qef-transition.md`](started/14-dc-qef-transition.md) — the
  one-shot plan for migrating off Transvoxel onto our DC-QEF stack (F1 shipped;
  seam work in progress).
- [`started/16-persistent-octree-substrate.md`](started/16-persistent-octree-substrate.md)
  — staged plan to make the render octree persistent + world-fixed (B3 / doc-10
  completion), so movement refines incrementally instead of full-rebuilding.

## Planned

Scoped but not yet begun.

- [`planned/06-phase-1-biomes.md`](planned/06-phase-1-biomes.md) — scopes
  biomes, caves, water, and vegetation for an explorable world.
- [`planned/07-phase-3-resources.md`](planned/07-phase-3-resources.md) —
  scopes destructible resource nodes and continuous harvesting.
- [`planned/08-phase-4-inventory-crafting.md`](planned/08-phase-4-inventory-crafting.md)
  — scopes inventory, equipment, and tiered crafting.
- [`planned/09-v0_5-playtester-drop.md`](planned/09-v0_5-playtester-drop.md) —
  defines the pre-art-pass milestone for first external feedback.
- [`planned/10-v0_2-art-pass.md`](planned/10-v0_2-art-pass.md) — scopes the
  visual-identity pass: textures, models, shaders.
- [`planned/11-v0_9-survival-product.md`](planned/11-v0_9-survival-product.md)
  — scopes multiplayer, survival, combat, and dungeons.
- [`planned/12-v1_0-steam-release.md`](planned/12-v1_0-steam-release.md) —
  scopes the open-source release with Steam extras and content depth.
- [`planned/13-v1_x-wild-dreams.md`](planned/13-v1_x-wild-dreams.md) — parks
  blue-sky post-release ambitions (planet-scale, sailing).
- [`planned/15-network-transition.md`](planned/15-network-transition.md) — the
  one-shot plan for building the decentralized replication layer.

## Done

Shipped work lives in [`done/`](done/00_INDEX.md) — the fully-landed phase
scope docs (02, 03, 04) alongside their `implementation-*` completed records
and the `extras-*` records for work outside the numbered phases.
