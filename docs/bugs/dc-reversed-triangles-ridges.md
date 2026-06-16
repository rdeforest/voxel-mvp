# DC: reversed (back-facing) triangles on convex ridges

**Status:** Deferred (2026-06-15). Pre-existing — present in the LIVE clipmap render too, so NOT introduced
by the world-octree. Rare. Render-only.

## Symptom
An occasional back-facing (reversed-winding) triangle on a mountain ridge — found by eyeballing `dcworld`,
but the same class exists on the shipping clipmap render.

## Measured
Orientation audit over 81 sample 64³ regions on real terrain, with collapse on:
`mesh_world` = **18** reversed triangles, `mesh_clipmap` (live) = **24**. So ~1 per few-thousand triangles,
and the world-octree path is actually marginally cleaner.

## Root cause (hypothesis)
A quad straddling a convex ridge is **non-planar**, but `emit_poly` orients **both** its triangles to ONE
shared `outward` (the gradient at the edge crossing). The triangle whose true facing opposes that single
reference comes out back-facing. The earlier per-triangle-winding fix (`747d9d0`) made each triangle check
its *own* geometric normal, but still against a *shared* outward — incomplete for the bent-quad case.

## Proposed fix
Give each triangle its OWN outward: the mean of its three vertices' QEF normals (free — already computed) or
the field gradient at its centroid (independent). Touches the SHARED meshing/winding code → fixes the live
render too → needs GPU verification. Gate with an orientation audit (the 81-region one above) → reversed
count drops toward 0, plus full GUT green.

## References
`engine/voxel_dc/dc_octree_mesher.cpp` `emit_poly`/`emit_tri`; commit `747d9d0` (the partial fix).
