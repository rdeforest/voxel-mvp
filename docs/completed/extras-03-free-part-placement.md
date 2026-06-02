# Completed: Free Part Placement

**Commit:** `9f2e36a`

## What shipped

Parts no longer snap to cell boundaries by default. Free placement
along view axes lets construction feel like *placement*, not *cell-
filling*.

- Drop the cell-snap from part placement.
- **Shift+W / Shift+A / Shift+E + mouse wheel** adjusts the offset
  along view axes (forward/back, left/right, up/down relative to the
  camera).
- Shift suppresses WASD movement universally — Shift+key is a
  *distinct* input from key alone.
- Part-stress proximity visibility — strain indicators on nearby parts
  show only when the camera is close enough (matches the existing
  `IntegrityDebug` pattern for voxel strain).

## Key decisions taken

- **Shift is reserved as a chord modifier.** This isn't just for part
  placement — it's a project-wide commitment that Shift+key is its
  own input. Required surfacing in player input handling generally,
  not just construction mode.
- **View-axis offsets, not world-axis.** Camera-relative offsets feel
  natural (always "push it away from me," "slide it left from my
  perspective"). World-axis would require a mental rotation when the
  camera isn't aligned to a cardinal direction.
- **No snap by default.** Snap modifiers will come later (FEAT031);
  free placement is the base behaviour because that's what the
  thesis wants — *off-grid surfaces*, principle-driven, not workaround-
  driven.

## Lessons learned

- **This is closer to KSP than to Minecraft, and that's correct.**
  Part placement should feel like assembling things, not like
  decorating a grid. The grid is an artefact of the data
  representation, not a design constraint.
- **The phantom-voxel deregistration bug surfaced during this work.**
  Free placement exposed a class of edits where `TerrainSupport` was
  registering newly-exposed cells correctly but not deregistering
  cells whose SDF had become air. Fixed in the same cycle (see
  [phantom-voxel fix](extras-06-tools-activities-ui.md)).

## Deferred

- **Snap-modifier hotkeys** — opt-in grid alignment on top of free
  placement. → FEAT031.
- **Rotation snap** — finer-than-90° rotations with a snap modifier.
  → FEAT032.
- **In-game parametric part resize** — drag handles or chord keys to
  change a part's dimensions. → FEAT033.
- **Vertical-on-horizontal beam support bug** — known limit; surfaces
  when welding (FEAT030) lands. → FEAT046.
