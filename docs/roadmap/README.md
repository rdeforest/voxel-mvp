# Project Roadmap — Index

This roadmap is split into four sections. Read them in order on a first
visit; jump directly to the relevant chapter on a return visit.

The manifesto at [`../MANIFESTO.md`](../MANIFESTO.md) supersedes anything
in here. If a chapter and the manifesto disagree, the manifesto wins.

## Layout

```
docs/
├── MANIFESTO.md                      # The vision document — read first.
├── STATUS.md                         # Current state, updated per session.
├── architecture.md                   # Mechanism rationale for shipped code.
├── art-wishlist.md                   # Asset asks for artists.
├── code-cleanup-plan.md              # Refactoring queue for shipped code.
├── completed/                        # Per-chapter records of completed work.
└── roadmap/
    ├── README.md                     # This file.
    ├── vision/                       # Why this project exists.
    ├── design/                       # The non-implementation specs.
    ├── implementation/               # Per-phase plans on the time axis.
    └── reference/                    # Tables, lookups, answered questions.
```

## Section 1 — Vision

The "why." Read before making any decision that feels architectural.

- [`vision/01-elevator-pitch.md`](vision/01-elevator-pitch.md) — the
  thirty-second version.
- [`vision/02-competitive-landscape.md`](vision/02-competitive-landscape.md)
  — what exists, what's missing, where this project fits.
- [`vision/03-hytale-case-study.md`](vision/03-hytale-case-study.md) —
  how to burn $100M shipping nothing. The cautionary tale.

## Section 2 — Design

The non-implementation specs. Each is "what the answer is," not "when
we'll build it." Forward-looking docs that haven't shipped yet; once
they ship, their rationale graduates into `docs/architecture.md`.

- [`design/01-principles.md`](design/01-principles.md) — the seven
  load-bearing design principles.
- [`design/02-architectural-commitments.md`](design/02-architectural-commitments.md)
  — decisions worth not relitigating.
- [`design/03-dc-qef-geometry.md`](design/03-dc-qef-geometry.md) — the
  Miguel/Cepero field-based representation. The current long pole.
- [`design/04-event-bus.md`](design/04-event-bus.md) — the voxel event
  bus design (mostly shipped; spec preserved).
- [`design/05-network-architecture.md`](design/05-network-architecture.md)
  — decentralized op-log replication. Far-horizon.
- [`design/06-channel-architecture.md`](design/06-channel-architecture.md)
  — the multi-channel spatial database view.
- [`design/07-known-hard-problems.md`](design/07-known-hard-problems.md)
  — sub-meter precision, FEM, pathfinding, planet-scale.
- [`design/08-continuous-work-actions.md`](design/08-continuous-work-actions.md)
  — the click-spam replacement.
- [`design/09-world-setting.md`](design/09-world-setting.md) — creative
  direction; not Norse mythology.

## Section 3 — Implementation

The temporal axis. Phases, versions, and the work-order that ties the
designs to delivery checkpoints.

- [`implementation/01-version-strategy.md`](implementation/01-version-strategy.md)
  — the v0.0 / v0.1 / v0.5 / v0.2 / v0.9 / v1.0 / v1.1 / v1.x ladder.
- [`implementation/02-phase-0-foundation.md`](implementation/02-phase-0-foundation.md)
  — walking around a procedural voxel world. (Complete.)
- [`implementation/03-phase-2-terrain-modification.md`](implementation/03-phase-2-terrain-modification.md)
  — dig, fill, flatten. (Complete.)
- [`implementation/04-phase-5-building-system.md`](implementation/04-phase-5-building-system.md)
  — parts + structural integrity. (Complete for v0.0.)
- [`implementation/05-phase-5_5-architectural-maturation.md`](implementation/05-phase-5_5-architectural-maturation.md)
  — bus, construction mode, fracture, honest destruction.
- [`implementation/06-phase-1-biomes.md`](implementation/06-phase-1-biomes.md)
  — biomes & terrain character.
- [`implementation/07-phase-3-resources.md`](implementation/07-phase-3-resources.md)
  — trees, rocks, ore, harvesting.
- [`implementation/08-phase-4-inventory-crafting.md`](implementation/08-phase-4-inventory-crafting.md)
  — items, recipes, stations.
- [`implementation/09-v0_5-playtester-drop.md`](implementation/09-v0_5-playtester-drop.md)
  — first external eyes.
- [`implementation/10-v0_2-art-pass.md`](implementation/10-v0_2-art-pass.md)
  — visual identity, vehicles, channels.
- [`implementation/11-v0_9-survival-product.md`](implementation/11-v0_9-survival-product.md)
  — multiplayer, combat, locomotives.
- [`implementation/12-v1_0-steam-release.md`](implementation/12-v1_0-steam-release.md)
  — open-source release with Steam extras.
- [`implementation/13-v1_x-wild-dreams.md`](implementation/13-v1_x-wild-dreams.md)
  — planet-scale, sailing.
- [`implementation/14-dc-qef-transition.md`](implementation/14-dc-qef-transition.md)
  — the migration off godot_voxel's Transvoxel meshing onto our own
  DC-QEF stack. One-shot; will become history when done.
- [`implementation/15-network-transition.md`](implementation/15-network-transition.md)
  — the migration to decentralized op-log replication. One-shot.

## Section 4 — Reference

Lookup material. Not narrative.

- [`reference/01-answered-questions.md`](reference/01-answered-questions.md)
  — Godot master vs. stable, iGPU as test target, voxels as the right
  primitive.
- [`reference/02-performance-budget.md`](reference/02-performance-budget.md)
  — frame-time budget table.
- [`reference/03-folder-structure.md`](reference/03-folder-structure.md)
  — target tree (aspirational; current state differs).
- [`reference/04-asset-sources.md`](reference/04-asset-sources.md) — CC0
  asset providers.
- [`reference/05-elevator-pitch-long.md`](reference/05-elevator-pitch-long.md)
  — the full Valheim-comparison pitch.

## How chapters relate

The four sections answer four different questions:

| Question                                  | Section          |
|-------------------------------------------|------------------|
| Why are we doing this?                    | Vision           |
| What is the answer (when we get there)?   | Design           |
| When and in what order does it happen?    | Implementation   |
| Where do I look up <fact>?                | Reference        |

A given concern lives in multiple sections. The DC-QEF rework is a
*design* chapter (the spec), an *implementation* chapter (the transition
work plan), and is referenced from the *vision* (the Miguel-was-right
argument). When information has both a permanent shape and a one-shot
migration, the permanent shape lives in design and the migration lives
in implementation.

When a design chapter ships, two things happen:
1. Its mechanism rationale moves into `docs/architecture.md`.
2. Its decisions are added to `design/02-architectural-commitments.md`.

The design chapter itself is then either deleted (if it was purely
forward-looking) or condensed (if it has a long enduring spec component).
