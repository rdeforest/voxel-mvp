# Edit re-mesh padding gap — stale-seam missing triangle near a block border

**Status:** **CLOSED — obsolete.** Filed against the clipmap render; that render and its godot_voxel
notification path were deleted in `d58e8ce`. The mechanism has no live code path. Closed 2026-09-25 by
code reachability, not by reproducing a fix.

*Closing note drafted by Claude, 2026-09-25, at Robert's request.*

## The original report

An edit (dig/build) near a block border left a missing triangle / stale seam at the border until the area
was reloaded. Cause: godot_voxel padded only 1 cell when notifying/re-meshing, but the DC mesher reads a
3-cell stencil — so an edit within 2 cells of a block border didn't dirty enough neighbouring data and the
seam wasn't re-meshed. The file already flagged the doubt: the world-octree path (docs 16/17) re-meshes
from the EditStore field directly, so it might not survive the clipmap's retirement.

It didn't.

## Why it can't fire

The notifier is gone, along with everything it notified:

- **No godot_voxel classes are referenced from `scripts/` or `scenes/`** — one vestigial `VoxelViewer`
  node in `scenes/player/player.tscn` with no terrain for it to drive, and nothing else.
- **`DCTerrainManager` (the clipmap render) is deleted.** It survives only in stale comments in
  `test/test_dc_octree_mesher.gd` and `test/test_edit_store.gd`.
- **No godot_voxel data store.** `EditStore` replaced `VoxelData`; the only mention left in
  `engine/voxel_dc/` is the comment in `edit_store.h` saying so.
- `mesh_clipmap`/`remesh` do survive, but their only non-test caller is `DCCollisionManager`, which
  re-meshes its whole cook region every cook and drives the dirty box through `EditStore::fill_region` —
  not through a godot_voxel block notification. The 1-vs-3 padding mismatch has nothing to attach to.

The render is `dcworld`, which either rebuilds fully on edit (the default) or re-meshes the accumulated
edit box via `edit_world`.

## Where the live version of this defect lives

The *class* of bug — dirty region narrower than the stencil the mesher actually reads — is real and
still open on the incremental path. It is tracked as
[dc-incremental-emit-ring-insufficient](../dc-incremental-emit-ring-insufficient.md): the one-ring re-emit
expansion isn't provably complete. That is the active dropped-triangle work, and `incremental_edits`
defaults **off** partly because `edit_world`'s localized result is still ~6% off a fresh build (doc 20 §E).

If a seam artifact near an edit shows up in the demo, it belongs on that bug, not this one.

## Loose end this turned up

The `VoxelViewer` node in `scenes/player/player.tscn` is vestigial — it exists to feed a godot_voxel
terrain that no longer exists. Harmless, but it should go with the rest of the godot_voxel retirement.
