# docs/bugs — deferred bug tracker

One file per known bug we've chosen to defer. The thesis is **get the major changes done first**; bugs are
parked here (with diagnosis + a proposed fix where we have one) so nothing is lost and any can be picked up
cold. A bug graduates out by being fixed (delete the file) — not by aging.

When you defer a bug: add a file here (`<area>-<slug>.md`), a line below, and a one-liner where it surfaced
(STATUS known-limits, the relevant doc). Keep severity honest.

## Open

| Bug | Area | Severity | Notes |
|-----|------|----------|-------|
| [sdf-sample-corner-vs-center](sdf-sample-corner-vs-center.md) | actions / structural / preview | **high (pervasive)** | No single source of truth for cell→sample-point; corner vs center disagree by ½ cell. Previews/events drift from the actual write. Code-read, not yet reproduced. |
| [actions-untyped-work-tuple](actions-untyped-work-tuple.md) | actions | med (structural) | Untyped positional work-array → preview/safety/geometry use different cell sets; `_endangers()` triplicated. Root of several action bugs. |
| [mpm-svd-reflection-sign](mpm-svd-reflection-sign.md) | MPM (mat3 SVD) | med | Double σ₂ flip → wrong polar rotation for inverted F. Existing SVD test can't catch it. |
| [event-bus-reentrancy](event-bus-reentrancy.md) | event bus | med (latent) | No reentrancy guard; prunes dead subs mid-iteration. Reachable by design; no channel self-chains *yet*. |
| [construction-bury-check-single-point](construction-bury-check-single-point.md) | actions (construction) | med | Bury check tests body origin only, not the capsule; a part across head/feet validates as safe. |
| [dig-action-no-validate-no-safety](dig-action-no-validate-no-safety.md) | actions (dig) | low-med | `validate()` always true (ghost disagrees); no player-safety guard unlike siblings. Confirm intent. |
| [mmap-arena-no-mmap-fallback](mmap-arena-no-mmap-fallback.md) | EditStore (mmap arena) | low-med | Crashes on `mmap` failure of a valid fd instead of using the anon fallback. Env-dependent. |
| [dc-incremental-emit-ring-insufficient](dc-incremental-emit-ring-insufficient.md) | DC world-octree emit | med (live edge) | One-ring re-emit expansion isn't provably complete; the active dropped-triangle work. |
| [dc-budget-controller-coarsen-bias](dc-budget-controller-coarsen-bias.md) | DC render (eps controller) | low-med | Coarsen ratchet near cell ceiling; re-tunes only on job completion. Recovers — confirm intent. |
| [save-honesty-gaps](save-honesty-gaps.md) | persistence | low | Silent non-quiescent save after 100k-iter guard; silent save-discard on version bump. Both fail quietly. |
| [sdf-float-precision-planet-scale](sdf-float-precision-planet-scale.md) | EditStore / terrain field | low (far from origin) | SDF corners + noise quantize through float, contradicting the double planet-scale claim. Document or fix. |
| [dc-mesher-latent-arg-traps](dc-mesher-latent-arg-traps.md) | DC mesher entry points | low (no live caller) | Unenforced preconditions in `mesh_clipmap`/`grow_world`. Filed before someone hits them. |
| [mpm-physics-fidelity-notes](mpm-physics-fidelity-notes.md) | MPM | note (not a bug) | Drucker-Prager coeff is a knob; grid vs particle contact differ. Design simplifications recorded. |
| [misc-low-severity](misc-low-severity.md) | various | low | Bundle: `voxel_utils` doc wrong, fill-voxel 0.5 nudge, raymarch first-segment gap, perf ring buffers, input if-chains. |
| [dc-inside-coverage-cracks](dc-inside-coverage-cracks.md) | DC world-octree render | **blocks doc 17 P3** | Graded-floor coarse leaves place misaligned vertices → LOD-seam holes. Reproduced headlessly; proactive accumulate-fine-QEF fix proposed. |
| [dc-reversed-triangles-ridges](dc-reversed-triangles-ridges.md) | DC meshing (shared) | low (rare) | Back-facing triangle on convex ridges; pre-existing, in the live render too (~1/few-thousand tris). |
| [dc-crease-normals-soft](dc-crease-normals-soft.md) | DC meshing | low (conditional) | Sharp edges shade soft; needs Hermite/crease-split in C++. v0.2 art pass. |
| [edit-remesh-padding-gap](edit-remesh-padding-gap.md) | edit re-mesh (clipmap) | low | Missing triangle near a block border until reload; may be moot once the clipmap retires. |
| [distant-shadow-shimmer](distant-shadow-shimmer.md) | rendering / shadows | cosmetic | CSM far-cascade crawl when panning. v0.2 polish. |
