# docs/bugs — deferred bug tracker

One file per known bug we've chosen to defer. The thesis is **get the major changes done first**; bugs are
parked here (with diagnosis + a proposed fix where we have one) so nothing is lost and any can be picked up
cold. A bug graduates out by being fixed (delete the file) — not by aging.

When you defer a bug: add a file here (`<area>-<slug>.md`), a line below, and a one-liner where it surfaced
(STATUS known-limits, the relevant doc). Keep severity honest.

## Open

| Bug | Area | Severity | Notes |
|-----|------|----------|-------|
| [dc-inside-coverage-cracks](dc-inside-coverage-cracks.md) | DC world-octree render | **blocks doc 17 P3** | Graded-floor coarse leaves place misaligned vertices → LOD-seam holes. Reproduced headlessly; proactive accumulate-fine-QEF fix proposed. |
| [dc-reversed-triangles-ridges](dc-reversed-triangles-ridges.md) | DC meshing (shared) | low (rare) | Back-facing triangle on convex ridges; pre-existing, in the live render too (~1/few-thousand tris). |
| [dc-crease-normals-soft](dc-crease-normals-soft.md) | DC meshing | low (conditional) | Sharp edges shade soft; needs Hermite/crease-split in C++. v0.2 art pass. |
| [edit-remesh-padding-gap](edit-remesh-padding-gap.md) | edit re-mesh (clipmap) | low | Missing triangle near a block border until reload; may be moot once the clipmap retires. |
| [distant-shadow-shimmer](distant-shadow-shimmer.md) | rendering / shadows | cosmetic | CSM far-cascade crawl when panning. v0.2 polish. |
