# docs/bugs — deferred bug tracker

One file per known bug we've chosen to defer. The thesis is **get the major changes done first**; bugs are
parked here (with diagnosis + a proposed fix where we have one) so nothing is lost and any can be picked up
cold. A bug graduates out by being fixed (delete the file) — not by aging. A bug that turns out not to be a
bug, or whose mechanism a refactor deleted, moves to `closed/` with the verdict written into it and a
row in the Closed table below; that costs one file and saves re-litigating it from the same code read.

When you defer a bug: add a file here (`<area>-<slug>.md`), a line below, and a one-liner where it surfaced
(STATUS known-limits, the relevant doc). Keep severity honest.

## Open

| Bug | Area | Severity | Notes |
|-----|------|----------|-------|
| [actions-preview-gdscript-slow](actions-preview-gdscript-slow.md) | actions (preview perf) | **med (regression, next up)** | Exact field prediction runs in GDScript every frame; previews 5–10× slower (CSG 2.5 ms). Fix: build the lattice in C++. |
| [single-voxel-edits-unexpected](single-voxel-edits-unexpected.md) | actions (FillVoxel/EmptyVoxel) | **characterized** | Fill makes a ~2.5 m³ smooth mound (target ~half full, paint off-centre), Empty refuses 48 % of clicks and can't dig down; questions for Robert in file. |
| [part-index-sub-cell-parts-untracked](part-index-sub-cell-parts-untracked.md) | structural (PartIndex) | low (design call) | A part that makes no cell solid gets no record: identity is cell-granular. Needs a decision on sub-cell identity. |
| [sdf-lattice-writes-false-change-at-max-faces](sdf-lattice-writes-false-change-at-max-faces.md) | actions (CSG no-op refusal) | low | "Writes anything" samples the neighbour leaf at the upper faces; an identical CSG re-stamp into air is never refused. |
| [mpm-thaw-events-unmeasured](mpm-thaw-events-unmeasured.md) | MPM thaw | low | Emits `voxel_removed` from its plan, not measured flips; neighbour flips go unreported. |
| [event-bus-reentrancy](event-bus-reentrancy.md) | event bus | med (latent) | No reentrancy guard; prunes dead subs mid-iteration. Reachable by design; no channel self-chains *yet*. |
| [dig-action-no-validate-no-safety](dig-action-no-validate-no-safety.md) | actions (dig) | low-med | Ghost and action now agree on the empty carve; no player-safety guard yet (change specified in file, needs `preview()`). |
| [mmap-arena-no-mmap-fallback](mmap-arena-no-mmap-fallback.md) | EditStore (mmap arena) | low-med | Crashes on `mmap` failure of a valid fd instead of using the anon fallback. Env-dependent. |
| [dc-incremental-emit-ring-insufficient](dc-incremental-emit-ring-insufficient.md) | DC world-octree emit | med (live edge) | One-ring re-emit expansion isn't provably complete; the active dropped-triangle work. |
| [dc-budget-controller-coarsen-bias](dc-budget-controller-coarsen-bias.md) | DC render (eps controller) | low-med | Coarsen ratchet near cell ceiling; re-tunes only on job completion. Recovers — confirm intent. |
| [save-honesty-gaps](save-honesty-gaps.md) | persistence | low | Silent non-quiescent save after 100k-iter guard; silent save-discard on version bump. Both fail quietly. |
| [sdf-float-precision-planet-scale](sdf-float-precision-planet-scale.md) | EditStore / terrain field | low (far from origin) | SDF corners + noise quantize through float, contradicting the double planet-scale claim. Document or fix. |
| [dc-mesher-latent-arg-traps](dc-mesher-latent-arg-traps.md) | DC mesher entry points | low (no live caller) | Unenforced preconditions in `mesh_clipmap`/`grow_world`. Filed before someone hits them. |
| [mpm-physics-fidelity-notes](mpm-physics-fidelity-notes.md) | MPM | note (not a bug) | Drucker-Prager coeff is a knob; grid vs particle contact differ. Design simplifications recorded. |
| [misc-low-severity](misc-low-severity.md) | various | low | Bundle: fill-voxel 0.5 nudge, raymarch first-segment gap, perf ring buffers, input if-chains. |
| [dc-inside-coverage-cracks](dc-inside-coverage-cracks.md) | DC world-octree render | **blocks doc 17 P3** | Graded-floor coarse leaves place misaligned vertices → LOD-seam holes. Reproduced headlessly; proactive accumulate-fine-QEF fix proposed. |
| [dc-reversed-triangles-ridges](dc-reversed-triangles-ridges.md) | DC meshing (shared) | low (rare) | Back-facing triangle on convex ridges; pre-existing, in the live render too (~1/few-thousand tris). |
| [dc-crease-normals-soft](dc-crease-normals-soft.md) | DC meshing | low (conditional) | Sharp edges shade soft; needs Hermite/crease-split in C++. v0.2 art pass. |
| [distant-shadow-shimmer](distant-shadow-shimmer.md) | rendering / shadows | cosmetic | CSM far-cascade crawl when panning. v0.2 polish. |


## Closed

Not open work. Kept because the reasoning is worth being able to look up — each file carries the verdict
and, where the report was wrong, why.

| Bug | Area | Verdict | Notes |
|-----|------|---------|-------|
| [mpm-svd-reflection-sign](closed/mpm-svd-reflection-sign.md) | MPM (mat3 SVD) | not a bug (2026-09-25) | Reported double σ₂ flip is correct: a reflected F fires one `if`, not both; the both-fire case is `det F > 0`. Four-case table in the file. The *test* gap it found is real — assert `det_u`/`det_v`/`s2` before the fast-SVD rewrite. |
| [edit-remesh-padding-gap](closed/edit-remesh-padding-gap.md) | edit re-mesh (clipmap) | obsolete (2026-09-25) | Filed against the clipmap render + godot_voxel notification; both deleted in `d58e8ce`, so the mechanism has no live code path. Live successor: [dc-incremental-emit-ring-insufficient](dc-incremental-emit-ring-insufficient.md). |
