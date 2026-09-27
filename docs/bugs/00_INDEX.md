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
| [store-write-reencode-flips-unplanned-cells](store-write-reencode-flips-unplanned-cells.md) | actions (StoreWrite box writers) | low (needs a call) | A box rewrite re-encodes the field and can flip cells the edit never named. Fixed for the thaw (predict_carve) and one_cell; Bell/Flatten/Fill/Dig/CSG/VoxelImprint/instruments/freeze still do it. |
| [mpm-freeze-flips-unmeasured](mpm-freeze-flips-unmeasured.md) | MPM freeze (events) | low | `MpmSim.rasterize_to_store` writes without measuring, so the freeze's matter-changed events carry no flips: its new cells are tracked only by TerrainSupport's box scan (as Stone), and a cell its rewrite empties never releases a part. Needs a C++ change (`write_region_flips`). |
| [actions-lattice-dry-run-double-generator](actions-lattice-dry-run-double-generator.md) | actions (preview perf) | low (left until doc 19) | A no-op-looking preview reads the generator at each lattice point in the build, then again in the `lattice_writes` dry run: ~0.045 ms of the buried refused preview's 0.34 ms. Robert: leave it; re-measure on the volumetric generator. |
| [player-safety-misses-sub-cell-burial](player-safety-misses-sub-cell-burial.md) | actions (player safety) | **med (needs a call)** | `lattice_turns_in` judges the prior field only at test points, so a sub-half-cell raise or carve inside the player's box goes unrefused (probe reproduces it). An exact rule needs a prior model for generator leaves. |
| [single-voxel-edits-unexpected](single-voxel-edits-unexpected.md) | actions (FillVoxel/EmptyVoxel) | low (superseded) | Not a player verb (Robert, 2026-09-27): exact-control testing moves to doc 22's instrument layer; closes when that ships. Characterization and Robert's expected result in file. |
| [part-index-sub-cell-parts-untracked](part-index-sub-cell-parts-untracked.md) | structural (PartIndex) | low (parked) | A part that makes no cell solid gets no record: identity is cell-granular. Decided: key parts by assembly path (doc 22); parked until assemblies exist. |
| [mpm-svd-ill-conditioned-u](mpm-svd-ill-conditioned-u.md) | MPM (mat3 SVD) | low (latent) | U loses orthonormality as σ₂/σ₀ drops (det U 0.93 at 1e-8, 0.16 at 1e-9). Rank ≤ 1 fixed 2026-09-27. Game thaws measured ≥ 0.19 at the damping-capped landing speed (only dt ≥ 0.1 gets close). Acceptance bar for the fast-SVD rewrite; pending test in `test_mpm_svd.gd`. |
| [dc-incremental-emit-ring-insufficient](dc-incremental-emit-ring-insufficient.md) | DC world-octree emit | med (deprioritised) | One-ring re-emit expansion isn't provably complete. A one-shot frontier drain reproduces it (pending test in `test_dc_world_octree.gd`). Robert (2026-09-27): deprioritise; bigger mesher work may moot it. |
| [edit-store-blob-inherited-corners-unchecked](edit-store-blob-inherited-corners-unchecked.md) | EditStore (deserialize) | low (latent) | Load doesn't check an inherited leaf's stored corners against its source's trilerp; a corrupt blob would render one field and stamp against another. |
| [edit-store-1m-write-flattens-finer-leaves](edit-store-1m-write-flattens-finer-leaves.md) | EditStore (write_region) | low (latent) | A 1 m lattice write resamples leaves finer than 1 m inside its box, silently losing sub-metre detail. Latent while every writer is at 1 m; blocks `RENDER_SUBDIV_LOG2 > 0`. |
| [dc-mesher-box-value-sentinels](dc-mesher-box-value-sentinels.md) | DC mesher API (mesh_world/grow_world) | low (latent) | `win_min == win_max` / `emit_min == emit_max` still mean "no box"; flat boxes aren't refused. The clipmap's explicit-presence fix (H1) not yet applied here. |
| [dc-budget-controller-coarsen-bias](dc-budget-controller-coarsen-bias.md) | DC render (eps controller) | low-med | Coarsen ratchet near cell ceiling; re-tunes only on job completion. Recovers — confirm intent. |
| [sdf-float-precision-planet-scale](sdf-float-precision-planet-scale.md) | EditStore / terrain field | low (far from origin) | SDF corners + noise quantize through float, contradicting the double planet-scale claim. Document or fix. |
| [event-bus-lambda-and-bound-callables](event-bus-lambda-and-bound-callables.md) | events (bus subscriptions) | low (latent) | A lambda or `.bind()`ed subscription logs a script error at its first delivery, delivers nothing and is pruned: the bus keeps only object + method name. No caller does it today. |
| [mpm-physics-fidelity-notes](mpm-physics-fidelity-notes.md) | MPM | note (not a bug) | Drucker-Prager coeff is a knob; grid vs particle contact differ. Design simplifications recorded. |
| [dc-inside-coverage-cracks](dc-inside-coverage-cracks.md) | DC world-octree render | **blocks doc 17 P3** | Graded-floor coarse leaves place misaligned vertices → LOD-seam holes. Reproduced headlessly; proactive accumulate-fine-QEF fix proposed. |
| [dc-reversed-triangles-ridges](dc-reversed-triangles-ridges.md) | DC meshing (shared) | low (rare) | Back-facing triangle on convex ridges; pre-existing, in the live render too (~1/few-thousand tris). |
| [dc-crease-normals-soft](dc-crease-normals-soft.md) | DC meshing | low (conditional) | Sharp edges shade soft; needs Hermite/crease-split in C++. v0.2 art pass. |
| [distant-shadow-shimmer](distant-shadow-shimmer.md) | rendering / shadows | cosmetic | CSM far-cascade crawl when panning. v0.2 polish. |


## Closed

Not open work. Kept because the reasoning is worth being able to look up — each file carries the verdict
and, where the report was wrong, why.

| Bug | Area | Verdict | Notes |
|-----|------|---------|-------|
| [dig-action-no-validate-no-safety](closed/dig-action-no-validate-no-safety.md) | actions (dig) | moot under directives (2026-09-27) | Validate/preview half fixed 2026-09-26. No player-safety guard, by Robert's call: players expect to dig under themselves, and directives will replace the verb. |
| [edit-store-noop-write-reports-changed](closed/edit-store-noop-write-reports-changed.md) | EditStore (write_region) | accepted (2026-09-27) | A corner-identical write re-representing a coarse or inherited leaf moves samples ~1e-8 and reports `changed`. Accepted and documented: `changed` = "some sample moved" (`CellFlips`). |
| [mpm-svd-reflection-sign](closed/mpm-svd-reflection-sign.md) | MPM (mat3 SVD) | not a bug (2026-09-25) | Reported double σ₂ flip is correct: a reflected F fires one `if`, not both; the both-fire case is `det F > 0`. Four-case table in the file. The *test* gap it found is closed: `test/test_mpm_svd.gd` (2026-09-26). |
| [fill-voxel-half-nudge-tie](closed/fill-voxel-half-nudge-tie.md) | actions (FillVoxel targeting) | not a bug (2026-09-26) | `floor(hit + n*0.5)` ties only with the hit exactly on a cell centre; the 0.5 picks the first air-centred cell on both faces. Switching to `SURFACE_NUDGE` would change the target, which is [single-voxel-edits-unexpected](single-voxel-edits-unexpected.md) Q2 (withdrawn 2026-09-27: no single-voxel player verb). |
| [raymarch-first-segment-unsampled](closed/raymarch-first-segment-unsampled.md) | aim (TerrainRaymarch) | not a bug (2026-09-26) | The first segment is sampled at both ends like every other (origin test + `t = step`); the header's "never stepped over" was reworded to "at least `step` thick". |
| [edit-remesh-padding-gap](closed/edit-remesh-padding-gap.md) | edit re-mesh (clipmap) | obsolete (2026-09-25) | Filed against the clipmap render + godot_voxel notification; both deleted in `d58e8ce`, so the mechanism has no live code path. Live successor: [dc-incremental-emit-ring-insufficient](dc-incremental-emit-ring-insufficient.md). |
