# docs/completed — Index

Per-chapter records of work already shipped. Each entry below notes *why
the doc exists*, not what it contains. The `implementation-*` files mirror
the roadmap's implementation chapters as completed; the `extras-*` files
record work that landed outside the numbered phases.

## Files

- [`extras-01-persistence.md`](extras-01-persistence.md) — records the
  save/load infrastructure that makes the v0.0 demo survive across sessions.
- [`extras-02-fallen-dirt-as-terrain.md`](extras-02-fallen-dirt-as-terrain.md)
  — records how falling debris reintegrates into the voxel terrain once
  fully embedded.
- [`extras-03-free-part-placement.md`](extras-03-free-part-placement.md) —
  records the removal of grid-snapping so construction feels like assembly,
  not cell-filling.
- [`extras-04-new-verbs.md`](extras-04-new-verbs.md) — records the four
  added terrain verbs (Raise, Lower, FillVoxel, EmptyVoxel) extending the
  Action infrastructure.
- [`extras-05-grass-shader.md`](extras-05-grass-shader.md) — records the
  slope-based grass/dirt blend shader with wind animation.
- [`extras-06-tools-activities-ui.md`](extras-06-tools-activities-ui.md) —
  records the tools/activities UI, the Limbo Console, and a phantom-voxel
  deregistration fix.
- [`extras-07-cleanup-pass.md`](extras-07-cleanup-pass.md) — records the
  refactoring pass that turned thesis-defending code into v0.1-extendable
  code.
- [`extras-08-voxel-grid-overlay.md`](extras-08-voxel-grid-overlay.md) —
  records the dev-time voxel-grid visualization used to debug placement and
  structural math.
- [`extras-09-bugs-closed.md`](extras-09-bugs-closed.md) — the running log
  of cross-cutting named bugs closed outside individual phases.
- [`extras-10-octree-edit-store.md`](extras-10-octree-edit-store.md) —
  records the EditStore becoming the sole terrain layer and godot_voxel's
  removal from the running game (Phase B S4–S5).
- [`implementation-02-phase-0-foundation.md`](implementation-02-phase-0-foundation.md)
  — records the Phase 0 foundation: procedural terrain, FPS controller,
  gravity, day/night.
- [`implementation-03-phase-2-terrain-modification.md`](implementation-03-phase-2-terrain-modification.md)
  — records the first terrain verbs (Dig, Fill, Flatten) and the
  Action-as-data pattern.
- [`implementation-04-phase-5-building-system.md`](implementation-04-phase-5-building-system.md)
  — records the Phase 5 unification of voxel and part support under one
  structural-integrity system.
- [`implementation-05-phase-5_5a-event-bus.md`](implementation-05-phase-5_5a-event-bus.md)
  — records the event bus that decouples voxel editing from its consumers.
- [`implementation-05-phase-5_5b-construction-mode.md`](implementation-05-phase-5_5b-construction-mode.md)
  — records construction-mode-aware edit verbs that fail honestly instead
  of faking surfaces.
