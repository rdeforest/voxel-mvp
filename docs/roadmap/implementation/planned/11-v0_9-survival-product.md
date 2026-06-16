# v0.9: Can I Make It Into A Real Product?

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

- **FEAT065**: Survival loop — health, stamina, hunger, food buffs,
  comfort.
- **FEAT069**: Death / respawn / bed placement.

## Combat

- **FEAT066**: Enemy AI + combat — raycast steering for outdoor
  enemies; 3D nav grid or HPA* for dungeon enemies (see
  [pathfinding in known hard problems](../../design/07-known-hard-problems.md)).
- **FEAT067**: Boss encounters as progression gates.
- **FEAT068**: Procedural dungeons — generated cave complexes; no
  loading screens.
- **FEAT071**: Material fatigue — cumulative strain history. Only
  meaningful with mobs hammering on structures.

## Locomotives

- **FEAT070**: Locomotive-class vehicles — boiler / firebox / pressure-
  driven pistons. Cellular automata for heat + pressure. The "wow,
  *that's* what this engine does" demo; depends on multi-grid +
  fracture + per-channel data all being mature.

## Polish

- **FEAT072**: Settings menu, keybinding, accessibility.
- **FEAT073**: Snap-point authoring UI — the v0.0 data exists; UI
  ships here.
- **FEAT074**: In-game Schematic editor — make new Parts at runtime.
- **FEAT075**: Workbench radius (Valheim mechanic — build only near
  workbench). Tentative; may not survive scrutiny.
