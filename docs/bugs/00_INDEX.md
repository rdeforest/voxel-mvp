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
| [csg-restamp-material-only-refused](csg-restamp-material-only-refused.md) | actions (CSG no-op refusal) | low (needs a call) | `writes` is SDF-only, so re-stamping the same shape in a new material is refused as a no-op. Was allowed by accident in high air before the max-face fix. |
| [edit-store-stamp-union-repaints-terrain](edit-store-stamp-union-repaints-terrain.md) | EditStore (C++ stamp paint) | low (latent, needs a call) | UNION `stamp_sphere`/`stamp_box` paint every leaf left with a solid corner, terrain included; `SdfLattice.materials()` keeps terrain's material. Only tests and dev harnesses call them. |
| [actions-lattice-dry-run-double-generator](actions-lattice-dry-run-double-generator.md) | actions (preview perf) | low (needs a call) | A no-op-looking preview reads the generator at each lattice point in the build, then again in the `lattice_writes` dry run: ~0.045 ms of the buried refused preview's 0.34 ms. |
| [single-voxel-edits-unexpected](single-voxel-edits-unexpected.md) | actions (FillVoxel/EmptyVoxel) | **characterized** | Fill makes a ~2.5 m³ smooth mound (target ~half full, paint off-centre), Empty refuses 48 % of clicks and can't dig down; questions for Robert in file. |
| [part-index-sub-cell-parts-untracked](part-index-sub-cell-parts-untracked.md) | structural (PartIndex) | low (design call) | A part that makes no cell solid gets no record: identity is cell-granular. Needs a decision on sub-cell identity. |
| [mpm-svd-ill-conditioned-u](mpm-svd-ill-conditioned-u.md) | MPM (mat3 SVD) | low (latent) | U loses orthonormality as σ₂/σ₀ drops (det U 0.93 at 1e-8, 0.16 at 1e-9); singular U at rank ≤ 1 via an uninitialized read. Acceptance bar for the fast-SVD rewrite; pending test in `test_mpm_svd.gd`. |
| [mpm-thaw-carve-leaves-planned-cells](mpm-thaw-carve-leaves-planned-cells.md) | MPM thaw | low | The corner carve can't empty a planned cell that touches kept terrain: a terrain `mpmthaw` r=5 empties 143 of 176 planned cells, a lone buried cell none. |
| [event-bus-reentrancy](event-bus-reentrancy.md) | event bus | med (latent) | No reentrancy guard; prunes dead subs mid-iteration. Reachable by design; no channel self-chains *yet*. |
| [dig-action-no-validate-no-safety](dig-action-no-validate-no-safety.md) | actions (dig) | low-med | Ghost and action now agree on the empty carve; no player-safety guard yet (change specified in file, needs `preview()`). |
| [mmap-arena-disk-full-sigbus](mmap-arena-disk-full-sigbus.md) | DC cell arena (mmap) | low-med (needs a call) | A full disk SIGBUSes the sparse `MAP_SHARED` arena (worse on btrfs COW). Fix needs a disk-full policy: migrate to RAM or stop refining. |
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
| [mpm-svd-reflection-sign](closed/mpm-svd-reflection-sign.md) | MPM (mat3 SVD) | not a bug (2026-09-25) | Reported double σ₂ flip is correct: a reflected F fires one `if`, not both; the both-fire case is `det F > 0`. Four-case table in the file. The *test* gap it found is closed: `test/test_mpm_svd.gd` (2026-09-26). |
| [edit-remesh-padding-gap](closed/edit-remesh-padding-gap.md) | edit re-mesh (clipmap) | obsolete (2026-09-25) | Filed against the clipmap render + godot_voxel notification; both deleted in `d58e8ce`, so the mechanism has no live code path. Live successor: [dc-incremental-emit-ring-insufficient](dc-incremental-emit-ring-insufficient.md). |
