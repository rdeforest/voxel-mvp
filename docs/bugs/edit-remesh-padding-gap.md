# Edit re-mesh padding gap — stale-seam missing triangle near a block border

**Status:** Deferred. Real defect; clears on reload.

## Symptom
An edit (dig/build) made near a block border leaves a missing triangle / stale seam at the border until the
area is reloaded.

## Cause
godot_voxel pads only 1 cell when notifying/re-meshing, but the DC mesher reads a 3-cell stencil — so an
edit within 2 cells of a block border doesn't dirty enough neighbouring data, and the seam isn't re-meshed.

## Fix
Widen the edit-dirty region (or the re-mesh apron) so the full DC stencil around an edit is re-meshed,
including across block borders. Note: the world-octree path (doc 16/17) re-meshes from the EditStore field
directly, so this may not survive the clipmap's retirement — confirm whether it still reproduces on `dcworld`
before fixing the clipmap path.

## References
[[edit-remesh-padding-gap]] (memory).
