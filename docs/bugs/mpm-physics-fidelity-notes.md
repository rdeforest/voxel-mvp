# MPM physics-fidelity notes (knobs standing in for physical constants)

**Status:** Deferred (2026-06-22). Diagnosed by code review. **Not bugs** — design simplifications that are
fine for a game but diverge from the physical model. Recorded so the divergence is a known choice, not a
forgotten one.

## 1. Drucker-Prager yield coefficient is a knob, not the Lamé formula
`engine/voxel_dc/mpm_material.cpp:96`. The sand return-mapping uses `(_elasticity_ratio + 1.0)` as the
coefficient on the `tr(e)` term where Klár 2016 uses a function of the Lamé parameters `(d·λ + 2μ)/(2μ)`.
With `_elasticity_ratio` defaulting to 1.0 that's `2·tr·α`. Sand yields, but the friction angle won't map
to a true Drucker-Prager cone slope. Conflates the elastic-blend knob with the plastic-flow constant.

## 2. Grid vs. particle contact use opposite strategies
Grid contact (`_apply_collider`, `engine/voxel_dc/mpm_sim.cpp:181-204`) removes only the *excess* inward
velocity component (gentle, no depth ejection — deliberately, to avoid violent response in thick solid).
The particle-level correction (`_integrate`, `engine/voxel_dc/mpm_material.cpp:126-133`) does **full depth
ejection** (`x -= normal·sd`). If a particle deep-penetrates, this snaps it to the surface in one step —
re-introducing the behaviour the grid layer was written to avoid. Probably intended as a hard backstop;
confirm it's not the primary contact path.

## 3. `sand_target` clamp gated on `logjp == 0` (unverified against the paper)
`engine/voxel_dc/mpm_material.cpp:37-51`. The ≥1 singular-value clamp only applies when `logjp == 0`, so a
particle mid-hardening (`logjp != 0`) can compress in the shape target. Plausibly the intended
elastic-predictor / plastic-corrector split, but could not be verified without Lewin 2024 in hand. Marked
uncertain.

## References
`engine/voxel_dc/mpm_material.cpp`, `engine/voxel_dc/mpm_sim.cpp`. Klár 2016 (Drucker-Prager sand),
Lewin 2024 (PB-MPM).
