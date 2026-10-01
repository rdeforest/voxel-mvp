# v0.9: Can I Make It Into A Real Product?

> **Contradictions open:** the combat, boss, dungeon, workbench-radius and
> survival-stat items conflict with the pillars and the 2026-09-28 creature
> decisions. See [`../../reference/12-known-contradictions.md`](../../reference/12-known-contradictions.md)
> (C2, C4, C5) before building any of them.

**Goal:** Survival subsystems. Combat. Locomotives. **Single-player.**
**Status:** Pending; after v0.2.

This is the version that turns the tech demo into a forty-hour
single-player game. **Multiplayer is *not* part of this version** — or
this project at all. Networking is the successor game; see the scope
boundary in
[`../01-version-strategy.md`](../01-version-strategy.md) and the
[network design doc](../../design/05-network-architecture.md). The
decentralized-replication groundwork stays captured so the successor
isn't foreclosed, but nothing here depends on it.

## Survival loop

- **FEAT065** ([#115](https://github.com/rdeforest/voxel-mvp/issues/115)): Survival loop — health, stamina, hunger, food buffs,
  comfort.
- **FEAT069** ([#116](https://github.com/rdeforest/voxel-mvp/issues/116)): Death / respawn / bed placement.

## Combat

- **FEAT066** ([#117](https://github.com/rdeforest/voxel-mvp/issues/117)): Enemy AI + combat — raycast steering for outdoor
  enemies; 3D nav grid or HPA* for dungeon enemies (see
  [pathfinding in known hard problems](../../design/07-known-hard-problems.md)).
- **FEAT067** ([#118](https://github.com/rdeforest/voxel-mvp/issues/118)): Boss encounters as progression gates.
- **FEAT068** ([#119](https://github.com/rdeforest/voxel-mvp/issues/119)): Procedural dungeons — generated cave complexes; no
  loading screens.
- **FEAT071** ([#120](https://github.com/rdeforest/voxel-mvp/issues/120)): Material fatigue — cumulative strain history. Only
  meaningful with mobs hammering on structures.

## Locomotives

- **FEAT070** ([#121](https://github.com/rdeforest/voxel-mvp/issues/121)): Locomotive-class vehicles — boiler / firebox / pressure-
  driven pistons. Cellular automata for heat + pressure. The "wow,
  *that's* what this engine does" demo; depends on multi-grid +
  fracture + per-channel data all being mature.

## Polish

- **FEAT072** ([#122](https://github.com/rdeforest/voxel-mvp/issues/122)): Settings menu, keybinding, accessibility.
- **FEAT073** ([#123](https://github.com/rdeforest/voxel-mvp/issues/123)): Snap-point authoring UI — the v0.0 data exists; UI
  ships here.
- **FEAT074** ([#124](https://github.com/rdeforest/voxel-mvp/issues/124)): In-game Schematic editor — make new Parts at runtime.
- **FEAT075** ([#125](https://github.com/rdeforest/voxel-mvp/issues/125)): Workbench radius (Valheim mechanic — build only near
  workbench). Tentative; may not survive scrutiny.
