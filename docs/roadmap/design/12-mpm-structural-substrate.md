# The MPM Structural Substrate (Continuum Physics)

*The design spec for replacing the structural simulation — currently **PBD**
(`PbdStructure` + the C++ `PbdSim`) — with **continuum mechanics**, specifically the
**Material Point Method (MPM)**, so that terrain, parts, and debris deform, fracture,
flow, and settle under one physically-grounded solver. The data/render substrate it
rides on is the EditStore + DC mesher ([`11-octree-edit-store.md`](11-octree-edit-store.md),
[`03-dc-qef-geometry.md`](03-dc-qef-geometry.md)); the unification thesis ("parts and
terrain are the same data") is [`03`](03-dc-qef-geometry.md) §"Imprinting". This doc
extends that thesis one layer up: **the same simulation, too.***

> **Status: spike done — VERDICT = GO (2026-06-11).** The isolated CPU spike is built and
> headless-tested (`engine/voxel_dc/mpm_sim.*`, `mpm_material.*`, `mat3.*`;
> `test/test_mpm_sim.gd`). All physics scenes behave; the cost is per-particle-linear and
> SVD-dominated, well inside reach of the planned GPU port. See "Spike results" below before
> the staging plan. The target (MPM as the structural substrate) stands; next is graduating
> the core toward real-time (fast 3×3 SVD, multi-thread/GPU) then the EditStore thaw/freeze
> coupling — *then* it replaces PBD and closes parts-as-voxels Stages 5–6.

## Spike results (2026-06-11)

Built as an isolated `MpmSim` (MLS-MPM, APIC transfer, double precision), not wired into the
game. Every claim is pinned by a headless GUT test.

**Behaviour — all green:**
- **Core loop stable**: an elastic block falls under gravity and rests on a floor without
  blowing up (P2G → grid → G2P with APIC).
- **3×3 SVD verified** directly (reconstruction, proper-rotation U/V, Πσ = det, signed
  reflection convention) — caught a Jacobi angle-sign bug in the process.
- **Fixed-corotated** elasticity (stiff bodies hold shape) and **neo-Hookean** both run.
- **SDF contact (the bug-fix mechanism)**: a stiff body dropped on a stamped EditStore-SDF
  pillar is *caught and rests on it*, doesn't pass through — the grid-resolved contact PBD
  structurally lacked (the beam-swings-through-mountain fix). Note: ~1 cell of contact
  *softness* at dx = 1 m (finer grid / a penetration push-out tightens it).
- **Drucker-Prager sand**: a tall column slumps into a stable repose pile; a friction sweep
  showed the *internal* friction sets the angle (radius saturates independent of the floor).
  Calibrates to ~20° vs the 35° input — a known MPM-sand resolution/calibration gap.
- **Sparse sleeping (the boundary-elimination path)**: a settled structure goes fully asleep
  and steps as an *exact* no-op (state preserved to 1e-12 — lossless, the manifesto answer to
  the thaw/freeze worry); a dropped block wakes the sleeping pile (drift 0.0 → nonzero).

**Cost (single-threaded CPU, double precision):** per-particle-linear, SVD-dominated.

| Material | µs / particle / step | 8 k particles |
|---|---|---|
| neo-Hookean (no SVD) | 0.81 | 6.5 ms |
| fixed-corotated (SVD) | 2.44 | 19.5 ms |
| sand (SVD + return-map) | 2.22 | 17.7 ms |

Linear scaling (corotated): 1.7 k → 4.3 ms, 8 k → 19.6 ms, 22 k → 54 ms.

**Verdict — GO.** The physics is correct and the cost is exactly the shape we expected:
linear in active particles, dominated by the per-particle SVD. Single-threaded CPU is too
slow for real-time at scale (~8 k particles = one 20 ms frame, one substep) — *as planned*.
The runway to real-time is well-trodden: (1) a **fast 3×3 SVD** (McAdams 2011) is ~5–10× the
naive Jacobi-via-matmul used here; (2) the per-particle work is **embarrassingly parallel**
(24 cores ≈ 20×; GPU MLS-MPM does millions of particles at 60 fps — 100× our active counts);
(3) **sparse sleeping** means only active material costs anything. None of these are research
risks. The remaining *research* risk is the EditStore thaw/freeze coupling (risk #1), not the
solver. *(Update: see PB-MPM below — it removes the stability fragility the spike surfaced.)*

## PB-MPM: the solver formulation (adopt — Lewin 2024, EA SEED)

The spike used **explicit** MLS-MPM and hit its known weaknesses: a CFL timestep cap (small
`dt`), stiffness sensitivity, and fragile contact-friction tuning. **Position-Based MPM**
([Lewin 2024, EA SEED](https://media.contentapi.ea.com/content/dam/ea/seed/presentations/seed-siggraph2024-pbmpm-paper.pdf),
SIGGRAPH Talks) is a semi-implicit **compliant-constraint** reformulation that is
**unconditionally stable at any timestep**, "as easy to implement as an explicit integrator,"
and built for real-time games. We adopt it as the solver formulation. Crucially it is a *small
delta on what the spike already has* — Algorithm 1's only new lines (red in the paper) are a
constraint solve and an iteration wrapper:

```
UpdatePBMPM(P):
  for it in 1..iterationCount:          # PBD-style outer iteration (1 can suffice for stability)
    P ← SolveConstraints(P)             # NEW: per-particle local solve → deformation displacement Dᵢ
    G ← ParticleToGrid(P)               # MLS-MPM P2G (have it)
    G ← GridUpdate(G)                   # gravity + collider (have it)
    P ← GridToParticle(P, G)            # MLS-MPM G2P / APIC (have it)
  IntegrateParticles(P)                 # advect x + F once, at the end
```

`SolveConstraints` replaces explicit stress with a **deformation displacement Dᵢ** (the
candidate velocity gradient): the candidate `F* = Fᵢ(I + Dᵢ)` and Dᵢ is nudged toward the
material's constraint. **Co-rotational elastic** (Alg. 2): `A_shape = polar(F*)` (the polar SVD
we already have), `A_vol = F*/det(F*)`, `Dᵢ ← Fᵢ⁻¹(β·A_vol + (1−β)·A_shape) − I` (β trades volume
vs shape preservation). **Liquid**: hydrostatic + deviatoric impulses toward a tracked density
(no SVD). The result is reconciled through the same MLS-MPM grid each iteration.

**Why this is the right call:**
- **Removes the spike's stability fragility.** Unconditionally stable → big timesteps, no CFL,
  graceful under crush/over-constraint. Their dam-break: stable at **30 Hz / 1 iteration** vs
  explicit **240 Hz** — ~8× fewer steps for the same stability, which is also a perf win.
- **Reuses the whole spike.** MLS-MPM quadratic-B-spline transfers, the 3×3 polar SVD, the SDF
  collider, sparse sleeping, and the thaw/freeze coupling all carry over unchanged. The change
  is the per-particle constraint solve + the iteration loop + the Dᵢ/F* integration.
- **Real-time, parallel.** The paper runs it real-time on a 32-core CPU with AVX2; it's
  Jacobi-style (all constraints independent) → embarrassingly parallel, GPU-ready.

**Caveats to carry:** Jacobi-style convergence is slow → "artificial softness"; more iterations
= stiffer (tunable). Large timesteps make elastic `F` badly conditioned — the paper *deletes*
elastic particles with `cond(F) > 1e6` (liquids use an objective volume measure instead). An
**XPBD variant** (Macklin 2016) is noted as the path to finer material control if needed.

**Foundation:** the grid transfer is **MLS-MPM** ([Hu et al. 2018](https://github.com/yuanming-hu/taichi_mpm),
the 88-line reference) — exactly what the spike implemented; PB-MPM keeps it and changes only
the time integration. So our `MpmSim` is already most of the way there.

**Status — DONE (elastic), 2026-06-11.** `MpmSim` was converted to PB-MPM (`mpm_sim.cpp` +
`mpm_material.cpp`), following the EA reference ([github.com/electronicarts/pbmpm](https://github.com/electronicarts/pbmpm)).
Everything works in displacement; a step iterates [SolveConstraints → P2G → GridUpdate → G2P]
then integrates (gravity seeded as `d.y -= g·dt²`). The MLS-MPM transfers, 3×3 SVD, SDF collider
(now displacement-form contact), sparse sleeping, and thaw/freeze coupling all carried over.
**Unconditional stability confirmed**: a block runs stably at **dt = 0.2** (200× the explicit CFL
that NaN'd the old solver) and still falls + rests. Caveat: over-driving the constraint (high
relaxation + many iterations + the volume-preserving target) can diverge; the stable default is
an under-relaxed rotation target. **Next: PB-MPM sand** (Drucker-Prager on the integrated F +
`logJp` — the verbatim algorithm is in the EA `particleIntegrate` shader), then the static-terrain
thaw/freeze seam, then world wiring.

## TL;DR

PBD (Position Based Dynamics) is the fastest, least physical member of the
mass-spring family: nodes, springs, pinned anchors, no material model, no contact with
the world. It was the pragmatic game choice. Its failures are now visible — a beam on
a peak **sags like rope and swings *through* the mountain** because PBD has no
continuum stiffness and no terrain contact; a broken chunk **locks mid-fall** because
the falling-body classifier is a hand-rolled patch over the same gap.

The frame-rate-doesn't-matter world (jet-engine FEA, WETA/Pixar creatures, Disney
material FX) does **not** use mass-spring-and-a-pin. They solve the **continuum** — the
actual PDEs of elasticity/plasticity on the material — and resolve **contact as part of
the solve**. For a voxel world where terrain, parts, and debris are one field, the
continuum method that fits is **MPM**: its background grid *is* our voxel grid, it
handles **topology change (fracture *and* merge) intrinsically**, and it resolves
**environment contact on the grid for free**. Stages 5 (break-off) and 6 (merge-back)
stop being code we write and become **emergent behavior** of the solver.

This is the same *shape* of decision as godot_voxel → EditStore: keep PBD and we're
keeping the approximation for *effort* reasons, which the manifesto forbids — only
*hardware* may force a trade. So: target MPM, prove it with a localized spike, measure
the cost honestly (the dual-GPU lever below makes the hardware budget generous).

## Why PBD is the half-measure (the symptoms are the evidence)

| Symptom (observed) | Root cause in PBD |
|---|---|
| Beam on a peak sags and **swings through the mountainside**, hangs suspended | No continuum stiffness (springs rope under load); **no contact** with the terrain SDF — nodes pass through solid |
| It never falls though the stress-viz "predicted failure" | Stays one component connected to the peak anchor; finds a soft spring/gravity equilibrium instead of breaking free |
| Broken chunk **locks mid-fall, suspended** | The falling-body classifier (`_tick_falling_bodies`) is a separate hand-rolled "is it buried?" patch — not part of any physical solve, and brittle (see the corner-sampling false-freeze, fixed 2026-06-10) |

Every one of these is "we approximated the physics and then patched the approximation."
The patches multiply because the model can't express the thing (a stiff material resting
on a surface).

## What real simulators use

- **Engineering (GE / Rolls-Royce jet engines) → FEM/FEA.** ANSYS, Abaqus, MSC Nastran.
  Mesh the part into finite elements; solve continuum mechanics from a real constitutive
  model (modal, thermal, fatigue). Fracture is a layer on top: **cohesive-zone**,
  **XFEM** (cracks cut elements without remeshing), **phase-field fracture**, or
  **peridynamics** (Silling 2000 — integral reformulation where cracks emerge with no
  crack-tip bookkeeping).
- **WETA / Pixar creatures & cloth → implicit FEM.** WETA *Tissue* (flesh/muscle) and
  *Loki* (multiphysics); Pixar *Fizt* cloth. Implicit integration is the point — it makes
  things *stiff* without exploding, the exact thing PBD fakes.
- **Disney / Houdini materials that deform AND break AND flow → MPM.** Snow (Stomakhin
  2013, *Frozen*), sand (Drucker-Prager plasticity, Klár 2016), mud, foam, viscoelastic;
  fracture via CD-MPM (Wolper 2019). MLS-MPM (Hu 2018) is the fast, GPU-friendly variant.

The shared principle: **simulate the continuum; resolve contact in the solve.** Our two
bugs are precisely the absence of both.

## Why MPM is the voxel-native ideal

MPM is a hybrid: material lives on **particles** (carry mass, velocity, deformation
gradient `F`, material), simulated through a **background Eulerian grid** each step. For
*this* project the fit is uncanny:

- **The background grid *is* our voxel grid.** MPM needs exactly the structure we have.
- **Topology change is intrinsic.** Particles separate (fracture) and recombine (merge)
  on the grid with no special-casing. **Stage 5 (break-off) and Stage 6 (merge-back)
  become emergent**, not hand-coded lifecycle.
- **Environment contact is resolved on the grid.** Grid-node velocities get projected
  against boundaries each step — the beam rests *on* the mountainside because the grid
  transfer handles it. **No depenetration hack, no swing-through-rock.**
- **One solver, many materials.** Fixed-corotated elasticity for a wooden beam,
  Drucker-Prager for soil/granular collapse, von Mises for metal — same machinery,
  different constitutive model. "Parts and terrain are the same data" extends to "…and
  the same simulation."

## The model: thaw → simulate → freeze

We do **not** simulate the planet. The SDF field (EditStore) stays the **quiescent**
representation — cheap, static, the thing we render and persist. MPM is the **active**
representation — only the material that's currently moving. Three transitions, each of
which *generalizes* something we already have or are building:

1. **Field → particles (thaw).** When a region's support criterion fails (an overhang
   loses its footing; an impact arrives), seed MPM particles from those field cells —
   carrying their material. *This generalizes PBD's detachment + `VoxelChunkBody` spawn.*
2. **Simulate (MPM step).** Per active region, per substep:
   - **P2G:** scatter particle mass + momentum + stress (from `F` via the constitutive
     model) to grid nodes (quadratic B-spline / APIC or MLS transfer).
   - **Grid solve:** integrate velocity under gravity + internal forces; **apply
     boundary conditions against the static terrain SDF** (project node velocities out of
     solid — contact, for free).
   - **G2P:** gather velocity back to particles (APIC), update `F`, advect positions.
   - **Return-mapping:** plasticity/damage on `F` (Drucker-Prager yield for granular;
     damage threshold for fracture).
3. **Particles → field (freeze).** When a clump settles (kinetic energy below
   threshold, resting on solid), **rasterize it back into the EditStore** at its resting
   pose (SDF + material), free the particles. *This generalizes Stage 6 merge-back* —
   and it's the same `VoxelImprint`-style write the placement path already uses.

The render is unchanged for static terrain (DC mesher over the SDF field). **Active
material renders from its particles** — surfaced the same way `VoxelChunkBody` already
DC-meshes a chunk, but updated each frame from the live particle set (or a small
per-region field the particles rasterize into).

## Material models (depth we can dial)

- **Elastic solids (wood, stone, built parts):** fixed-corotated or Neo-Hookean. Stiff;
  a beam holds its shape and *snaps* rather than sagging.
- **Granular (soil, sand, gravel):** Drucker-Prager elastoplasticity (Klár 2016) — gives
  angle-of-repose piles and flowing collapse for free; ties straight into the existing
  `Materials.angle_of_repose`.
- **Fracture:** start with damage-on-overstretch (particles separate past a strain/stress
  threshold); upgrade to CD-MPM (Wolper 2019) if snap fidelity reads mushy.

## The thaw/freeze boundary and its error budget

The worry this raises is fair: is thaw/freeze a *second* dichotomy — like the LOD seam —
where information is lost and surprises appear? **No: it is not a new boundary. It is the
particle↔grid (P2G/G2P) transfer MPM already crosses every substep**, with the persistent
field being the grid *made durable*. The whole **PIC → FLIP → APIC → PolyPIC** lineage
exists precisely to bound that transfer's loss:

- **PIC** (grid overwrites particle velocity) — maximally dissipative.
- **FLIP** (transfer only the delta) — preserves detail, accumulates noise.
- **APIC** (Jiang 2015) — each particle carries a local *affine* velocity field, so modes
  the grid can't hold ride on the particle; conserves angular momentum, no FLIP noise. The
  standard floor.
- **PolyPIC** (Fu 2017) — higher-order polynomial modes; *theoretically lossless*
  interpolation when the particle basis spans the grid DOF.

So the "minimum acceptable error" dial for this boundary already exists, with a
provably-lossless endpoint — the direct analog of pixel-sufficiency.

**What freeze discards, and why it's ~free at rest.** A particle carries (position,
velocity, deformation gradient `F`, material); a plain SDF cell stores (SDF, material).
Freeze drops velocity and `F`. But: velocity ≈ 0 at the settle threshold (loss ≤ ε by
construction); **plastic deformation is already in the geometry** (a bent beam is *shaped*
bent — the SDF holds it); elastic strain ≈ 0 when relaxed. So for terrain, debris, and
relaxed material the field is a faithful rest-state record, quantized only to grid
resolution. **The one exception:** a load-bearing *static* structure holding internal
stress (an arch in compression, a pre-tensioned member) — motionless, so it passes the
settle test, but a plain SDF can't hold its stress state, so freeze→re-thaw returns it
relaxed. Identifiable and bounded (load-bearing static structures only, not the stress-free
99%).

**Accumulation.** Repeated thaw→freeze *cycling* re-quantizes geometry each cycle. Fix is
standard sleeping-engine practice: **hysteresis** — require sustained rest before freezing,
never freeze what just thawed — plus making the field canonical so re-thaw is exact w.r.t.
it. With hysteresis, boundary cycling doesn't occur.

### Recommended: design the boundary away (sparse sleeping MPM)

The stronger answer **eliminates the lossy conversion**. The sparse-MPM line — SPGrid
(Setaluri 2014), temporally-adaptive/async MPM (2018), and the 2024 unified-sparse and
CK-MPM work — only *steps* the grid where material moves; dormant material stays as
**particles that simply aren't simulated** (lossless: `F`, stress, everything preserved),
paying memory instead of error. Then:

- The static/dynamic split **coincides with the boundary we already have**: pure
  *generator* terrain (never touched) stays field; anything ever *disturbed* becomes
  persistent sleeping particles that never round-trip to field.
- The load-bearing-stress exception **vanishes** (sleeping particles keep their stress).
- Cost: store dormant particles for disturbed regions (sparse, bounded by play area) + the
  renderer must surface particles wherever material has been touched, not just the DC field.

This is the manifesto trade — pay memory + render to *delete* a lossy boundary rather than
bound it. **This is the recommended target**; the field↔particle freeze (above) is the
fallback if the dormant-particle memory/render cost proves worse than the bounded loss.

### Sufficiency, generalized

Pixel-sufficiency becomes **sufficient on every error axis**, each a dial set
below-perceptible — none an unbounded surprise:

| Axis | Dial | Lossless-ish endpoint |
|---|---|---|
| Spatial | grid res / particles-per-cell (8/cell std) | finer grid |
| Transfer | PIC → APIC → PolyPIC order | PolyPIC (theoretically lossless) |
| Dynamic state | settle threshold ε; keep-particles vs freeze | sparse sleeping (no conversion) |
| Material | channels stored on freeze (+ stress/`F` if needed) | persist particles |

## What it subsumes

- **`PbdStructure` + `PbdSim`** — replaced wholesale (the network/anchor/detachment model
  is the approximation we're retiring).
- **`VoxelChunkBody` (Stage 5)** — a settled-region surface is just the rendered active
  material; box-compound collision is gone (contact is on the grid).
- **`StructuralIntegrity._tick_falling_bodies` + the buried/partial/free classifier +
  `_cell_at` depenetration** — replaced by the freeze transition.
- **Stage 6 merge-back** — the freeze transition *is* Stage 6.
- **`TerrainSupport`'s scalar-support propagation** — survives only if MPM still wants a
  cheap "should this thaw?" gate; otherwise the thaw criterion is MPM-native (residual
  stress / unsupported mass) and the scalar retires too.

## The hard parts (honest risks)

1. **Field ↔ particle coupling fidelity** *(the real research risk)*. Thaw must seed
   particles that reproduce the field's surface; freeze must rasterize particles back to
   an SDF that the DC mesher renders crack-free against neighbouring static terrain.
   Getting the seam between *frozen* terrain and *just-thawed* material to not pop or gap
   is the crux. The error budget and the **sparse-sleeping path that designs this risk
   away** are analysed in "The thaw/freeze boundary and its error budget" above — sleeping
   particles in place (rather than rasterizing to field) removes the freeze direction
   entirely, at a memory/render cost. Validate the sleeping path first.
2. **Fracture realism.** Naive MPM "fractures" by particle separation, which can look
   mushy. A clean beam-snap may need CD-MPM or a damage model. Tunable depth, not a
   blocker.
3. **Rendering live material.** Per-frame surfacing of a moving particle set at
   interactive cost (re-DC a small region, or splat). Bounded by the active-region size.
4. **Persistence mid-sim.** Saving must still gate on quiescence — but now "quiescent"
   means "no active MPM regions" (all material frozen back to field). Clean, actually:
   the save model already gates on settle.
5. **Determinism.** GPU-parallel MPM reductions aren't bit-deterministic by default;
   matters only if/when the op-log multiplayer ([`05`](05-network-architecture.md)) needs
   lockstep. Park it.

## Performance & the dual-GPU lever

MPM is a full-grid transfer + solve per substep — heavier than PBD, but **localized**:
we only simulate active regions (a collapsing wall, a dirt slide), the same
"awake-region" thinking the DC collision manager already uses. Active particle counts are
thousands–~100k, not millions; GPU MPM (MLS-MPM compute kernels) runs that comfortably
above interactive rates.

**The hardware budget is deliberately generous** (manifesto: only hardware limits count,
and on a Moore's-law horizon today's high-end is ~$200 of 2036 hardware).

**Decision (2026-06-11): start single-GPU on the 5090.** The dual-GPU split (physics on one
card, render on the other) was the original instinct, but the analysis is that the second
card (a 4070 Ti) doesn't pay: its extra CUDA cores don't beat the **cross-GPU memory-bandwidth
cost** of shuttling the active region's state over PCIe every frame. The 5090 already drives
the primary screen, so physics + render co-resident on it is both simpler and faster to start.
Multi-GPU is revisited only if a single card genuinely can't hold the frame budget — at which
point the split is a *compute-context* placement detail, not a redesign. The GPU work itself
(P2G/solve/G2P as Vulkan/CUDA compute) is the enabling lever and is unchanged by this.

Measurement targets for the spike: substep cost vs. active-particle-count, the
field↔particle transfer cost per region, and whether a representative collapse stays
inside the frame budget on the physics GPU while the render GPU holds framerate.

## The spike (prove it before committing)

A throwaway, isolated MPM solver — *not* wired into the world — over a single region:

- **Scope:** MLS-MPM core (P2G / grid / G2P / return-mapping) with **APIC transfer**, two
  material models (fixed-corotated elastic, Drucker-Prager granular), the **static terrain
  SDF as a grid collider**, **sparse sleeping** (settled particles stop being stepped but
  persist), particle render via the existing DC path.
- **Test scene 1 — beam on a peak.** An elastic beam balanced on an SDF peak must
  **tip and rest on the mountainside (or slide off and fall)** — *not* sag through it.
  Directly kills the reported bug.
- **Test scene 2 — dirt slide.** A granular block on a slope must flow to its
  angle-of-repose and pile. Proves the granular model + grid contact.
- **Test scene 3 — sleeping load-bearer.** A static structure holding stress (a propped
  beam / simple arch) must keep holding *after it sleeps and re-activates* — proves
  sparse sleeping preserves the stress state the lossy freeze would drop.
- **Success:** all three behave physically; substep cost at each scene's particle count is
  measured and inside budget on a dedicated GPU; and a settled clump round-trips
  (sleep → re-activate, and — for the fallback path — rasterize to an SDF region the DC
  mesher renders without a seam).
- **Kill criteria:** field↔particle seam can't be made crack-free without unbounded
  work; or per-substep cost at realistic region sizes can't fit even one dedicated GPU.
  Either sends us back to a bounded PBD-plus-contact interim with eyes open.

## Staging (how it folds in)

1. **Spike** (above) — isolated, measured, throwaway. Decides go/no-go.
2. **MPM core in `engine/`** — the C++ solver as a module, headless-testable (a beam
   deflection vs. analytic Euler-Bernoulli; a sand pile's repose angle), no world wiring.
   *(Spike done; now convert it to **PB-MPM** — the compliant-constraint formulation above —
   for unconditional stability + big timesteps, reusing the spike's transfers/SVD/collider/
   sleeping/coupling. This replaces the explicit-MPM CFL/stiffness/friction tuning and is the
   real "graduate to real-time" lever, ahead of the fast-SVD / GPU micro-opts.)*
3. **Thaw/freeze coupling to the EditStore** — the field↔particle transitions; the
   crux from risk #1; validated against the DC render seam.
4. **Replace PBD** — route detachment/collapse/settle through MPM; retire `PbdStructure`,
   `VoxelChunkBody`, the falling-body classifier, and (if the thaw criterion goes
   MPM-native) the scalar support. Stages 5–6 close as emergent behavior.
5. **GPU compute** — P2G/solve/G2P as Vulkan/CUDA compute on the 5090 (single-GPU per the
   2026-06-11 decision). A multi-GPU split is a later option only if one card can't fit budget.

## Open questions (parked, not blocking the spike)

- Static terrain as a *rigid grid collider* vs. as *frozen MPM material that can re-thaw
  on big enough impact* (the second is more unified but far more expensive — probably a
  per-material "can this terrain thaw?" flag).
- Two-way coupling with the player `CharacterBody3D` and other rigid bodies (MLS-MPM has
  a rigid-coupling formulation; do we need it for v0.x?).
- Whether the EditStore's material channel carries enough to reconstruct particle
  constitutive state on thaw, or particles need their own persisted store for in-flight
  saves.
