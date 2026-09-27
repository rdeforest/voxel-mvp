# MPM contact: viscous friction, damping in free flight, and the SDF treated as a distance

*Filed by Claude (agent), overnight 2026-09-27, from a diagnosis of open question 6 (thawed floating
blocks slide about 130 m and never freeze). Harnesses: `scripts/dev/diag_slide.gd`,
`diag_slide_work.gd` (`DIAG_MODE=terrain|tilt`), `diag_slide_profile.gd`. Not fixed: these change how
MPM feels, so the fix is Robert's call.*

**Status:** Open. Severity med (physics fidelity). Needs Robert's call and GPU eyes on any fix.

## The observation was expected
The origin is the apex of a cone-shaped peak (h = 170 at (0,0)). The slope is 66° from r = 0.25 out
to r = 10, 64° at r = 40 and 59° at r = 70. tan 66° = 2.25, far above μ = 0.35 (19.3°), so no
friction model should hold a block there. What *is* wrong is how it slides: at a steady 3.6–3.9 m/s
instead of accelerating (~6.8 m/s²), because of the defects below.

## Defects
1. **Friction is viscous, not Coulomb** (`engine/voxel_dc/mpm_sim.cpp:196-200`). Each contact node's
   tangential displacement is multiplied by (1 − f) every inner iteration, with no static cone
   (|t| ≤ μ|n|). A tilted-gravity control on flat ground (4 m block, μ 0.35) creeps at a speed
   proportional to sin θ, with no holding threshold:
   0° 0, 5° 0.043, 10° 0.085, 15° 0.127, 19° 0.160, 25° 0.209, 35° 0.393 m/s.
   Only nodes pushing into the surface get friction.
2. **Damping acts in free flight** (`engine/voxel_dc/mpm_material.cpp:125`). A per-step 0.03 acts as
   heavy air drag: terminal fall speed 0.97/0.03·g·dt² ≈ 5.3 m/s, and it depends on dt. This, not
   friction, caps the slide speed. It is also what keeps MPM's worst deformation conditioning at
   about 0.2 (`mpm-svd-ill-conditioned-u`), so lowering it needs that re-measured.
3. **The SDF value is used as a distance** (`mpm_sim.cpp:183-186`, `mpm_material.cpp:131-135`). The
   terrain SDF is a vertical height difference; its gradient magnitude is 2.46 at the landing site.
   Nodes may therefore move 2.46× the real gap into the surface, and the particle push-out overshoots
   by the same factor. Normals are fine, since they're normalised.
4. **The settle rule hides creep** (`scripts/structural/mpm_structure.gd:17, 241-248`). "Max
   displacement < 0.01 m/step (0.6 m/s) for 30 frames" freezes slow sliders mid-slide, which masks
   defect 1 on gentle slopes: every tilted run froze at tick 37–80 while still creeping.

## Fix sketch
- Coulomb friction at contact nodes: with λ the normal correction, set t = 0 if |t| ≤ μλ, otherwise
  shrink t by μλ.
- Divide `sample()` by the gradient magnitude before using it as a gap or penetration depth.
- Make damping a time-based rate, or apply it only at contact.
- Settle on the centre of mass's drift over a window plus contact, not on per-step displacement.
- Regression test from the tilted-gravity control: a block stops below 19° and slides above it.
