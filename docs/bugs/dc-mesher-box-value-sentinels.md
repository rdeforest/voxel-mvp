# `mesh_world` / `grow_world` still read "no box" from a box's value

*Filed by Claude (agent), overnight 2026-09-26, while fixing the mesh_clipmap box sentinel (Track H1). From
reading the code; no test has run these cases.*

**Status:** Open. Severity low (latent: the only live caller cannot produce a degenerate box). Changing it
changes the GDScript signatures of `mesh_world` and `grow_world`, the live preview's entry points.

## Symptom
The same trap Track H1 removed from `mesh_clipmap` (now `mesh_clipmap_splice` for the boxed case, with
presence carried by the entry point and a box without extent refused) survives in two sibling entry points
of `DCOctreeMesher` (engine/voxel_dc/dc_octree_mesher.cpp):

- **`mesh_world` window** — `if (win_min != win_max)` picks the windowed build. An equal but nonzero box
  such as (5,5,5)..(5,5,5) silently builds the whole root. A box flat on one axis (corners differ) takes the
  window path with no extent check, and meshes the un-descended root cell rather than nothing.
- **`grow_world` emit box** — `oct.emit_filter = (emit_min != emit_max)`. Equal corners draw the whole
  residency box; a box flat on one axis turns the filter on and silently draws nothing.
- **`grow_world` residency box** — `win_min`/`win_max` go straight into `build_min`/`build_max` with no
  check at all.

So the class has three conventions for "is a box present": pointer presence with `LatticeBox::has_extent()`
(the clipmap), the min==max value sentinel (above), and no check.

## Why nothing hits it today
`scripts/dc/dc_world_preview.gd` is the only live caller. `_window_at` builds c±r clamped to the root with
`win_radius_m >= 2`, and `_outside_root` re-roots before a window gets within `win_radius_m + 32` of a root
face, so no axis collapses. Tests pass the default `Vector3i()` pair or real windows.

## Proposed fix
Apply the H1 design rather than a fourth convention: give the unwindowed build / whole-residency emit their
own entry point (or explicit presence), and refuse (`ERR_FAIL`, empty result, retained tree untouched) any
passed box that fails `has_extent()`, including `grow_world`'s residency box. Update the preview's calls in
the same change; add GUT tests on the real EditStore field like `test/test_dc_mesher_arg_contracts.gd`.
