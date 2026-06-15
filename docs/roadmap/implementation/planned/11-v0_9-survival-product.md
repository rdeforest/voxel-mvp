# v0.9: Can I Make It Into A Real Product?

**Goal:** Survival/MMO-y subsystems. Multiplayer. Combat.
Locomotives.
**Status:** Pending; after v0.2.

This is the version where the network architecture work
([`../../design/05-network-architecture.md`](../../design/05-network-architecture.md))
finally has to land. Multiplayer is gated on the decentralized op-log
replication design being ready to build.

## Multiplayer

- **FEAT064**: Multiplayer — full decentralized op-log replication;
  see the [network transition chapter](15-network-transition.md).

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
