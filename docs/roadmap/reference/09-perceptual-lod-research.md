# Perceptual LOD research — where the refine budget goes, and what else is possible

*Drafted by Claude (research agent), 2026-09-27, and revised after a skeptical review. Research for
Robert's "compelling, not accurate" design session. It is evidence and options only, and it makes
no decisions. Nothing in the mesher was changed.*

Harness: [`scripts/dev/probe_perceptual_lod.gd`](../../../scripts/dev/probe_perceptual_lod.gd). It has
four independent tests, meant to run as parallel processes:

```
godot --path . --headless -s addons/gut/gut_cmdln.gd \
    -gtest=res://scripts/dev/probe_perceptual_lod.gd -gunit_test_name=test_stones
```

The other three are `test_steady_state` (a few minutes), `test_bloom_drawn` and
`test_bloom_frontier` (tens of minutes each; every refine pop is its own `grow_world` call).
`test_stones` takes about 15 minutes. The refine budget is a fixed pop count, not wall-clock
time, so every number reproduces exactly from run to run.

## The short version

1. **Refinement order is not why the stones look bad.** The stones are at the 1 m floor from the
   first build, so they never enter the refine frontier. In 400 traced pops, none went to them. At
   the floor, with no collapse (the most detail this data gives), the triangles *on* the stones are
   **6–13 px off the stored field at p50 and 17–40 px at p95**, depending on where the faces fall
   against the lattice. The distant ridge crest is **0.00 / 0.23 px**. Collapse at any eps up to 8
   leaves the stone numbers unchanged.
2. **The data holds the stones. The reconstruction loses them.** Every lattice corner the mesher
   reads near the stones equals the analytic field min(generator, boxes) exactly. The damage comes
   from two steps that turn corner values into surface:
   - the linear crossing between two corners, across an SDF that kinks inside the cell;
   - the gradient normal taken at h = 1 m.

   Crossings land up to **0.25–0.40 m off (p95)**, and normals are **17–39° off the true face
   normal (median)**. **19–70% of the exposed face area is more than 0.25 m from any mesh.**
   There is one topological hole. When the faces sit exactly on lattice planes, the face corners
   read exactly 0, which counts as outside. A 1 m part then has no inside corner at all: **the
   lintels vanish completely**.
3. **Exact Hermite data at the same 1 m lattice fixes the stones, except in the on-plane case.**
   With the stored signs but exact crossings and analytic normals, the QEF vertex on a stone cell
   is **0.000 m off at p50, and 0.00–0.27 m at p95**. Today's recipe gives **0.07–0.13 m at p50 and
   0.35–0.50 m at p95**. That comes at 1 m cell cost, not the 64× of a 0.25 m lattice.
4. **A 0.25 m lattice also fixes them**, at 27× the cells in a ±32 m window. With faces off the
   0.25 m lattice, the stone error is **0.37 / 1.75 px**, the median face-to-mesh distance is
   **4 mm**, and no face is missing. Imprint and mesh have to move together. Refining only one of
   them leaves 47–66% of the face area more than 0.25 m from the mesh.
5. **The drain refines the whole residency to the floor, by design, then collapses most of it
   away.** `reconcile` queues every cell that isn't `want_leaf`. `refine_selected` grows each
   popped cell all the way to the floor, whatever its error. **Every visible candidate's screen
   key was already below eps (100%, at eps 7.2 and at 0.5).** 100 drains of 256 pops grew the tree
   from **0.47 M to 3.46 M cells** (about 1 GB). Over the same drains the drawn mesh grew from
   36.4 k to 41.1 k triangles, and by only 2.9% over the last 75.
6. **The `dcinval` overlay flagged only floor cells, at every eps from 48 down to 0.5.** Across
   the whole descent, in both the drawn and the no-collapse runs, **0 flagged triangles had an
   owner above its floor**. EDIT triangles are flagged from eps ≈ 35 down. Ridge triangles are
   flagged only below eps ≈ 1.2–1.8. At the stones, the overlay shows residual that no refinement
   will remove, not a backlog.
7. **Screen density runs backwards from attention.** Triangles on the stones cover about
   **450–1 000 px² each on screen**, depending on phase. At the floor, the ridge crest's cover **6 px²** and distant
   crease triangles **5 px²**.

Robert saw two things in the "pending" view, and both are real. Neither has the cause the view
suggests. The distant edges aren't waiting for refinement; they're floor cells with residual. The
foreground stones aren't starved of budget; they're at the floor already. The floor's scalar
reconstruction (linear crossings, 1 m gradients) is what can't hold them. Meanwhile the budget
goes into refining cells that are already under eps.

## Scene and method

| Item | Value |
|---|---|
| Field | `EditStoreManager.setup()`, the live generator (seed 1337) |
| Camera | eye (224, 98.1, −384), 1.7 m above flat ground. It looks at a sharp generator crest at (320, −344), 104 m away and 70 m above |
| Projection | vp 1080 px, fov 75°, 16:9, so `proj` is 703.7 px per unit at unit distance. The horizontal fov is 107.5° |
| Stones | 10 axis-aligned boxes, Stone material, 8–20 m away: three trilithons (1×4×1.5 uprights, 1×1×4.5 lintels) and a fallen 3.5×1.5×1 block. Each box's **min corner** sits `phase` past a lattice plane on every axis. Its max faces land wherever its size puts them, so a 1.5 m or 4.5 m side ends at `phase` + 0.5. `phase` = 0.25 unless a table says otherwise. Construction placement is free (`build_placement_pos` = hit + offset), so real parts land at any phase |
| Imprint | The construction write path: `EditStore.predict_imprint` → `SdfLattice.write` with `materials()`, which is what `VoxelImprint.apply` does, minus its events. It was checked against `EditStore.stamp_box`: 0 sign mismatches, and a difference of 0.0000 on the 825 corners that lie on a sign-changing lattice edge. It also equals min(generator, analytic boxes) at those corners, to 0.0000. The two differ only away from the surface, where `stamp_box` leaves the generator's larger values (up to 7.4) |
| Mesher calls | `DcWorldPreview`'s own: DEPTH 13, ROOT_SNAP 64, drawn ±128 m, residency ±256 m, `mesh_world` then `grow_world`, eps 48 × 0.9 per job down to 0.5, then drains |
| Budget | 256 single-candidate pops per job and per drain (`refine_budget = 0` refines exactly one candidate per `grow_world`). The first grow of a job rebuilds the frontier for the new eps, as the live job does. In the original wall-clock run, the queue fell by roughly 240–500 candidates per 8 ms drain, so 256 per drain is of the same order |

**What each number measures:**

- **err m / err px**: mesh-to-stored-field distance. For each triangle, the harness takes the max
  of |f| / |∇f| (∇ by central difference at h = 0.05 m) over the centroid and the three edge
  midpoints. Pixels are that distance × `proj` / d. It is first-order and one-sided, and it can't
  see a feature the mesh skipped; "intent" covers that. All EDIT triangles are measured, and 1 in
  7 elsewhere.
- **intent**: the analytic box faces, sampled on a 0.25 m grid. Faces whose outward point is solid
  in the intent field (buried in ground, or against another stone) are skipped. Two numbers per
  sample:
  - **nearest mesh**: the true point-to-triangle distance to the nearest mesh triangle, exact up
    to 0.5 m (it reads "≥ 0.5" beyond that). "> 0.25 m" is the share of face area with no mesh
    within a quarter metre.
  - **along-normal miss**: no mesh on the face normal within ±3 m. This is a stricter "missing"
    test: the nearest mesh may still be 0.3–0.5 m away sideways.

  The mesh near the stones is watertight at 1 m (0 open edges).
- **key**: the owner cell's `we` × `proj` / d. It is the quantity `collapse_test` and `dcinval` use,
  read from `get_last_triangle_owner_errors`. **Flagged** means key > 2·eps (`DIAG_LARGE_MULT`),
  split by whether the owner is at its graded floor or above it (a deferred candidate).
- **Frontier**: the `test_bloom_frontier` run, with `error_driven = false` and the residency ring
  drawn. With no collapse, every owner that emits a triangle is a structural leaf, and one above
  its graded floor *is* a deferred candidate, whose owner error equals its heap key. Candidates
  that emit no triangle are invisible here and are reported as "queue minus visible". This is
  reconstructed from emitted owners, not read from the heap.
- **Pop trace**: 400 single pops. Each popped cell is recovered from the new owners that the
  incremental emit appends.
- **Regions**:
  - **EDIT** means the owner cell overlaps a stone's box grown by 1 m. It splits into **EDIT
    stone** (triangle centroid at least 0.3 m above the generator ground) and **EDIT apron** (the
    ground around the stones' feet). This split uses height, not "centroid within 0.1 m of a
    face". At 1 m the stone surface is itself 0.1–0.5 m off the faces, so a distance test would
    push most of the stone into the apron.
  - **RIDGE** means within 25 m horizontally of the crest point and at least 60 m away.
  - **feat** means the triangle's vertex normals spread at least 20°.
  - **In view** is a centroid-in-frustum test that ignores occlusion.
- **screen px²/tri**: the area of the triangle's three projected vertices on screen, averaged over
  in-view triangles. It includes foreshortening.

**Limits, stated once:**

- This is one scene, one seed and one camera.
- The stones are axis-aligned, the best case for DC.
- The frustum test ignores occlusion.
- The eps floor of 0.5 is an assumption. Live eps is driven by frame time
  (`_frame_ms < frame_budget·0.8`) and gated by `max_cells`, and nothing here shows that Robert's
  session reached 0.5. The tables therefore report eps 48, 8, 2 and 0.5, and the dcinval census
  covers every eps of the descent.
- The mesher has no frustum or occlusion term, so "in view" describes where the work lands and
  doesn't change it.

## Finding 1: the stones' error is fixed at the floor, and collapse doesn't add to it

Steady state: a full `mesh_world` (the path an edit's rebuild takes), then `remesh` at other eps.
Phase 0.25.

| Mesh | Region | Tris | Mean owner (m) | Screen px²/tri | Key px (mean) | Flagged at floor / above | err px p50 / p95 / max |
|---|---|---|---|---|---|---|---|
| floor, no collapse | EDIT stone | 278 | 1.00 | 694 | 18.0 | 76.3% / 0% | 8.73 / 40.16 / 57.1 |
| floor, no collapse | EDIT apron | 290 | 1.00 | 330 | 5.3 | 68.3% / 0% | 0.78 / 7.98 / 22.7 |
| floor, no collapse | RIDGE | 8 670 | 1.00 | 5.8 | 0.09 | 3.0% / 0% | 0.00 / 0.23 / 2.30 |
| floor, no collapse | gen 90–130 m feat | 1 299 | 1.00 | 5.0 | 1.06 | 35.4% / 0% | 0.57 / 1.72 / 2.57 |
| floor, no collapse | ALL | 260 332 | 1.00 | 21.9 | 0.06 | 0.9% / 0% | 0.00 / 0.03 / 57.1 |
| collapse eps 0.5 | EDIT stone | 274 | 1.00 | 770 | 18.4 | 79.2% / 0% | 8.72 / 40.16 / 52.8 |
| collapse eps 0.5 | RIDGE | 2 015 | 1.49 | 24.9 | 0.42 | 12.5% / 0% | 0.03 / 0.69 / 2.30 |
| collapse eps 0.5 | ALL | 41 298 | 2.05 | 131 | 0.40 | 6.0% / 0% | 0.03 / 3.36 / 52.8 |
| collapse eps 2 | EDIT stone | 268 | 1.00 | 787 | 18.7 | 70.1% / 0% | 8.72 / 40.16 / 52.8 |
| collapse eps 2 | RIDGE | 908 | 1.91 | 55.9 | 0.44 | 0% / 0% | 0.06 / 0.47 / 2.30 |
| collapse eps 8 | EDIT stone | 256 | 1.02 | 828 | 19.3 | 52.3% / 0% | 8.73 / 40.16 / 52.8 |
| collapse eps 8 | RIDGE | 281 | 3.79 | 180 | 1.07 | 0% / 0% | 0.12 / 1.47 / 3.71 |
| collapse eps 48 | EDIT stone | 188 | 1.08 | 1 454 | 21.1 | 0% / 0% | 10.29 / 47.17 / 273 |
| collapse eps 48 | RIDGE | 56 | 8.21 | 943 | 6.7 | 0% / 0% | 0.38 / 1.48 / 1.48 |

- Collapse is very efficient on smooth ground. At eps 0.5 it removes 84% of the triangles
  (260 k to 41 k), and ridge error stays under a pixel at p95.
- Collapse isn't what's hurting the stones: their error is the same with and without it at every
  eps up to 8. The stone triangles are 1 m floor cells 9–20 m away. The "huge foreground
  triangles" are the floor itself, seen close up.
- The ALL row's p95 comes almost entirely from EDIT.

## Finding 2: the stones are in the data, and the scalar reconstruction loses them

**The stored corners are right.** Every corner on a sign-changing edge equals min(generator,
analytic boxes) to 0.0000 (see Scene). In the first version of this scene the faces sat at x.8. A
1×1 m lintel's corner row there reads −0.20 all along its length, and so do the uprights' (the
reviewer's sample, reproduced).

**The linear crossing puts the surface in the wrong place.** Take a 1 m box from x+0.8 to x+1.8.
Its lattice corners read:
- +0.8 at x;
- −0.2 at x+1, measured to the nearer, −x face;
- +0.2 at x+2, measured to the +x face.

Between x+1 and x+2 the SDF kinks, because the nearest face changes.
- The crossing on the edge from x to x+1 lands at x+0.8, which is exact.
- The crossing on the edge from x+1 to x+2 lands at x+1.5. The true face is at x+1.8.

The mesh is a box 0.7 m thick, shifted toward −x, and where these errors line up on thin parts it
drops faces entirely. The reviewer cast rays through a lintel's 1 m mesh and found exactly that: a
tube 0.3–0.7 m thick, missing along one strip.

**The normals are wrong.** `EditStoreSource::gradient` takes central differences at h = 1 lattice
unit, so at 1 m the step spans the whole block. The harness compares that normal, at the crossings
`leaf_qef` samples, with the analytic normal of the box face there. It also reports the comparison
with the stored field's own fine gradient (h = 0.05), which is the trilinear interpolant's slope;
the original version of this note used that and called it truth.

**Intent error and normals across placement phase (1 m imprint, 1 m mesh, floor, no collapse):**

| Phase | Stone tris | Stone err px p50 / p95 | Nearest mesh p50 | Face area > 0.25 m from mesh | Along-normal miss (upright / lintel / fallen) | Mesher normal vs analytic, p50 / p90 | Mesher normal vs interpolant, p50 |
|---|---|---|---|---|---|---|---|
| 0.00 | 14 | 13.9 / 31.5 | ≥ 0.5 m | 90.2% | 84.6% (81 / **100** / 5%) | 75.8° / 99.0° (43 crossings) | 0.0° |
| 0.10 | 284 | 6.1 / 17.5 | 0.488 m | 69.7% | 52.9% (55 / 54 / 7%) | 38.8° / 67.9° | 14.9° |
| 0.25 | 278 | 8.7 / 40.2 | 0.305 m | 57.8% | 28.5% (28 / 31 / 9%) | 16.9° / 54.1° | 8.8° |
| 0.50 | 245 | 12.9 / 36.2 | 0.151 m | 19.3% | 11.4% (12 / 9 / 17%) | 19.5° / 54.8° | 5.1° |
| 0.75 | 335 | 7.9 / 23.8 | 0.210 m | 44.9% | 15.4% (7 / 34 / 4%) | 34.1° / 64.6° | 19.4° |

On generator ground, beside the stones, the mesher's normal is within 0.1° of the truth at every
phase. The collapse eps 0.5 numbers match the floor numbers to within a few percent at every phase.

**Phase 0 is a topology hole, not a precision problem.** When the faces sit on lattice planes, the
face corners read exactly 0, and `leaf_qef` counts 0 as outside (`(fa < 0) == (fb < 0)`). A box
1 m thick then has no inside corner along that axis, so its sign data is empty. The lintels vanish
(100% missing), and so do most of the uprights. Construction placement is free, so any snapping
that parts might get later would make this the common case, not an edge case.

## Finding 3: exact Hermite data at the same 1 m lattice, an oracle

The harness solves each 1 m leaf's QEF near the stones two ways. Both use the store's corner signs,
so the topology is the store's.

- **scalar** is `leaf_qef`'s recipe: the linear crossing plus the h = 1 gradient.
- **hermite** is the exact crossing of min(generator, analytic boxes) on the same edge (found by
  bisection) plus that surface's analytic normal.

The solve is a GDScript port of `Qef::solve`, eigen truncation included. **Port check:** in
97–100% of the cells that hold a mesher vertex, the ported scalar solve matches that vertex to
within 1 mm.

| Phase | Stone cells | Crossing shift, linear vs exact, p95 / max | Vertex error, scalar, p50 / p95 | Vertex error, exact Hermite, p50 / p95 |
|---|---|---|---|---|
| 0.00 | 11 | 0.75 / 1.00 m | 0.160 / 0.500 m | 0.091 / 0.500 m |
| 0.10 | 137 | 0.40 / 0.69 m | 0.065 / 0.400 m | **0.000 / 0.265 m** |
| 0.25 | 135 | 0.25 / 0.65 m | 0.107 / 0.500 m | **0.000 / 0.175 m** |
| 0.50 | 118 | 0.11 / 0.97 m | 0.100 / 0.354 m | **0.000 / 0.000 m** |
| 0.75 | 157 | 0.25 / 0.36 m | 0.125 / 0.473 m | **0.000 / 0.000 m** |

The error is |intent signed distance| at the vertex, over cells whose exact vertex lies on a stone.
This is the Ju et al. premise, measured on these stones. DC at 1 m with exact crossings and normals
puts the vertices on the true box faces, edges and corners. Hermite data can't recover phase 0,
because the signs themselves are empty there.

**Limits:** this checks vertex positions, not the triangles between them. For axis-aligned boxes,
vertices on the true faces and corners give planar faces. The parts here are all at least 1 m
thick. A part thinner than a cell can have no inside corner at any phase, and then Hermite data
alone can't bring it back.

## Finding 4: the 0.25 m lattice, measured

Fresh store for each row, window ±32 m. At 1 m the same window holds 0.051 M cells, and at 0.25 m
it holds 1.38–1.40 M (27×). Phases 0, 0.25, 0.5 and 0.75 are multiples of 0.25, so at 0.25 m they
put every face exactly on a lattice plane, the favourable case. **Phase 0.1 is the honest row.**

| Mesh / imprint | Phase | Stone tris | Stone err px p50 / p95 / max | Nearest mesh p50 / p95 | Face area > 0.25 m from mesh | Along-normal miss | Non-manifold edges near stones |
|---|---|---|---|---|---|---|---|
| 1 m / 1 m (live) | 0.25 | 278 | 8.73 / 40.16 / 57.1 | 0.305 / ≥ 0.5 m | 57.8% | 28.5% | 1 |
| **0.25 m / 0.25 m** | **0.10** | 5 047 | **0.37 / 1.75 / 3.8** | **0.004 / 0.030 m** | **0.1%** | **0%** | 0 |
| 0.25 m / 0.25 m, collapse eps 0.5 | 0.10 | 3 992 | 0.49 / 1.89 / 3.8 | 0.002 / 0.030 m | 0.1% | 0% | — |
| 0.25 m / 0.25 m | 0.00–0.75 (aligned) | 3 693–4 186 | 0.00 / 0.00 / 4.5–6.8 | 0.000 / 0.003–0.027 m | 0.3–1.0% | 0% | **311–336** |
| 0.25 m mesh / 1 m imprint | 0.25 | 3 015 | 0.70 / 6.02 / 8.8 | 0.308 / ≥ 0.5 m | 65.6% | 25.4% | 0 |
| 1 m mesh / 0.25 m imprint *(low confidence)* | 0.25 | 279 | 14.2 / 40.2 / — | 0.233 / ≥ 0.5 m | 46.8% | 19.3% | 1 |

- **Both resolutions have to move together.** A fine mesh over a coarse imprint faithfully meshes
  the imprint's wrong shape. A coarse mesh over a fine imprint samples 0.25 m detail at 1 m.
- **The last row's error columns are low confidence.** Under a 1 m facet the 0.25 m field's
  |∇f| goes to near zero, and the |f| / |∇f| estimator blows up (its max is meaningless). Treat
  the intent columns as that row's measurement.
- **The aligned 0.25 m rows show over 300 non-manifold edges.** These are the same exact-zero
  corners as Finding 2's phase 0, meshed at a finer lattice. Phase 0.1 has none. This is worth a
  look if this direction is taken.

## Finding 5: where the refine budget goes

**The mechanism, from the code (`dc_octree.h`):**

- `reconcile` pushes a `RefineCand` for every in-window cell that has no children and fails
  `want_leaf`. `want_leaf` is true only at the graded floor, for a pruned (provably surface-free)
  cell, or at size 1.
- `refine_selected` pops by `we` and calls `grow_subtree(x)`. That calls `build()` on each child,
  which recurses until `want_leaf`, so a popped cell always goes all the way to the floor.

`we` sets the order and never decides *whether* a cell is refined. At eps 0.5 the graded floor is
1 m across the whole residency box; the unclamped value eps·d/proj stays below 1 m out to about
1 400 m. So draining eventually refines every non-pruned cell of the ±256 m residency to 1 m.
Collapse then draws most of it back at 2–8 m, and retention (doc 20 M) keeps the refined subtrees.
This is how refine-to-floor-then-collapse is designed; it doesn't need another explanation.

**It's measurable.** In the no-collapse run, **every visible candidate's screen key `we`·proj/d was
already ≤ eps**: 12 194 of 12 194 at job 19 (eps 7.2) and 3 754 of 3 754 at job 45 (eps 0.5).
Refining any of them can't change a collapse decision at that eps.

| Drawn run (collapse), eps 0.5 | +0 drains (job 45) | +25 drains | +100 drains |
|---|---|---|---|
| Cells | 0.47 M | 0.60 M | **3.46 M** (≈ 1 GB at 296 B per cell) |
| Queue | 78.2 k | 71.8 k | 52.6 k |
| Drawn tris | 36 429 | 39 994 | 41 143 |

From +25 to +100 drains, 19 200 pops add 2.9 M cells (about 150 per pop), and the drawn mesh
changes by 1 149 triangles (2.9%).

**What the frontier holds.** Rank is the best heap position any candidate of that region holds.

*Mid-descent (job 19, eps 7.2): queue 84 739, visible candidates 12 194.*

| Region | Cands | In view | Mean dist | we p50 / max (lattice) | Screen key p50 / max (px) | Best rank by `we` | Best rank by screen key |
|---|---|---|---|---|---|---|---|
| RIDGE | 168 | 100% | 115 m | 0.005 / 0.015 | 0.03 / 0.11 | 155 | 320 |
| gen 20–40 smooth | 667 | 32% | 35 m | 0.004 / 0.010 | 0.08 / 0.24 | 2 761 | 0 |
| gen 40–60 smooth | 1 896 | 27% | 50 m | 0.004 / 0.010 | 0.05 / 0.15 | 2 639 | 38 |
| gen 60–90 smooth | 1 438 | 18% | 78 m | 0.006 / 0.015 | 0.06 / 0.17 | 22 | 16 |
| gen 90–130 smooth | 4 168 | 16% | 112 m | 0.007 / 0.015 | 0.04 / 0.12 | 11 | 215 |
| gen 130+ smooth | 3 799 | 6% | 151 m | 0.005 / 0.016 | 0.02 / 0.08 | 0 | 1 552 |
| EDIT | **0** | — | — | — | — | — | — |

- Top 200 by `we` (the live order): 130+ m 122, 90–130 m 58, 60–90 m 14, ridge 4, undrawn ring 2.
  In view: 26.
- Top 200 by screen key (doc 20 P's original): 20–40 m 121, 60–90 m 60, 40–60 m 19. In view: 72.

*At the eps floor (job 45, eps 0.5): queue 78 179, visible candidates 3 754.* Every region's `we`
is ≤ 0.007 and its screen key ≤ 0.16 px.

- Top 200 by `we`: 40–60 m 60, 130+ m 52, 20–40 m 35, 60–90 m 23, 90–130 m 20, ridge 6, ring 4.
  In view: 52.
- Top 200 by screen key: 20–40 m 170, 40–60 m 30. In view: 50.

**Pop trace, the first 400 single pops at eps 0.5:**

| Went to | Pops |
|---|---|
| gen 130+ m | 134 |
| gen 90–130 m | 110 |
| gen 60–90 m | 62 |
| gen 40–60 m | 45 |
| gen 20–40 m | 17 |
| RIDGE | 12 |
| gen 130+ m, undrawn ring | 5 |
| EDIT | **0** |
| no triangle produced | 15 |

The median distance of the visible pops was 117 m (p10 49 m, p90 164 m).

**Invisible candidates.** At job 45, 74 k of the 78 k queued candidates emit no triangle. The
original wall-clock run found 105–110 of 400 pops producing no triangle. The deterministic run
finds 15, so the count depends on the state the descent leaves behind.

**Inference, not verified:** the invisible candidates may be cells the graded prune accel can't
prove empty. Its levels double in size outward, so a shell near the surface reads as "maybe
surface". Verifying this needs a frontier dump that isn't bound (see the end of this note).

## Finding 6: the `dcinval` overlay flags floor cells, not a backlog

- `_emit_diagnostic` flags a triangle when its owner's `we`·proj/d > 2·eps.
- A collapsed node can never be flagged, because `collapse_test` collapses only when that key is
  ≤ eps.
- So a flagged owner is either a floor leaf or a not-yet-refined candidate.

The harness counted both kinds at every job of the descent, inside the drawn ±128 m window:

| Run | Eps range | Flagged with owner above floor (candidates) | Where flagged floor triangles appear |
|---|---|---|---|
| drawn (collapse) | 48 → 0.5, all 45 jobs | **0** | EDIT from eps 35 (8) to 0.5 (419). RIDGE only at eps ≤ 1.2 (6 → 198). Other ground from eps 5.3 (2 → 1 669) |
| no collapse | 48 → 0.5, all 45 jobs | **0** | EDIT from eps 35 (4) to 0.5 (410). RIDGE only at eps ≤ 1.83 (7 → 206) |

The reviewer's worry was that at eps ≥ ~7 the floor at the 104 m ridge rises above 1 m, so ridge
cells can be real candidates. They are candidates (168 of them at eps 7.2), but their screen key
is ≤ 0.11 px, far below the 14.4 px flag threshold.

**Scope:** this is this scene and this descent. The eps Robert was at when he saw the view is
unknown, and so is his scene. What this scene says:

- **Flagged ridge edges point to an eps of about 1–2 or below.**
- **At no eps did the overlay show refinement that was still coming.**

His `dcworld` status-line eps would pin this down.

## Finding 7: no view term, which is a deliberate choice

`reconcile`, `refine_selected`, `collapse_test` and `target_cell_size` use only distance, with no
frustum, facing or occlusion term (`dc_octree.h`, `dc_edit_store_source.h`,
`dc_octree_mesher.cpp`).

- 72–75% of the emitted triangles are outside the frustum. That is mostly geometry. A
  camera-centred square window seen through a 107.5° horizontal fov is **74.7% out of view by
  construction** (a flat plane at ground height, vertical fov included).
- The residency ring and the camera-independent heap key are deliberate doc 20 choices (M and I).
  §I dropped the camera term so the heap survives camera moves. The out-of-view work is the known
  cost of those decisions.

Doc 20's P+ already plans view weighting for *spare* budget. Nothing weights the *main* budget.

## Prior art (survey)

"Verified" means I read the claim in the source itself: the abstract, the project page, or the
first pages of the paper. "Secondary" means it comes from a summary or a reimplementation. Anything
else is marked as inference.

### Feature-aware and perceptual LOD metrics

- **Hoppe, "View-dependent refinement of progressive meshes", SIGGRAPH 1997**
  ([project page](https://hhoppe.com/proj/vdrpm/), [pdf](https://hhoppe.com/vdrpm.pdf)).
  Verified (abstract): refinement criteria "based on the view frustum, surface orientation, and
  screen-space geometric error". Secondary: normal cones coarsen back-facing regions and refine
  near silhouettes. This is the canonical precedent for putting frustum and silhouette terms in the
  refine test.
- **Luebke & Hallen, "Perceptually Driven Simplification for Interactive Rendering", EGWR 2001**
  ([pdf](https://luebke.us/publications/pdf/perceptual.ir.pdf)). Secondary: each local
  simplification is tested against a contrast sensitivity model, using the contrast and spatial
  frequency it would induce, and is skipped if perceptible. It adds gaze-directed simplification in
  the periphery. Relevant because a low-contrast watercolour surface tolerates more error than a lit
  crease does.
- **Lindstrom & Turk, "Image-Driven Simplification", ACM TOG 19(3), 2000**
  ([ACM](https://dl.acm.org/doi/10.1145/353981.353995)). Verified (abstract): decides what to
  simplify by comparing rendered images instead of geometric distance. This settles how to weight
  position against normals and shading. It's the extreme form of "compelling, not accurate".
- **Williams, Luebke, Cohen et al., "Perceptually guided simplification of lit, textured meshes",
  I3D 2003** ([ACM](https://dl.acm.org/doi/10.1145/641480.641503)). This extends the CSF approach to
  lighting and texture (secondary).
- **Lee, Varshney & Jacobs, "Mesh Saliency", SIGGRAPH 2005**
  ([ACM](https://dl.acm.org/doi/abs/10.1145/1186822.1073244),
  [project](http://www.cs.umd.edu/projects/gvil/projects/mesh_saliency.shtml)). Verified (abstract):
  a centre-surround operator on Gaussian-weighted mean curvature, which gives better simplification
  than raw curvature. It is a ready-made "where the eye goes" weight computable from geometry alone.
- **Nanite (Karis, Stubbe, Wihlidal), SIGGRAPH 2021 Advances**
  ([course](https://advances.realtimerendering.com/s2021/)). Secondary
  ([reimplementation notes](https://jglrxavpok.github.io/2024/04/02/recreating-nanite-runtime-lod-selection.html)):
  a cluster is drawn when its projected error sphere is ≤ threshold (about 1 px) and its parent's is
  greater. A search summary (I didn't read the page myself) of the
  [meshoptimizer discussion](https://github.com/zeux/meshoptimizer/discussions/783) says projected
  positional error alone is not enough, and normals and attributes need weights. This is
  the shipped state of the art for "screen-space error, about 1 px".

### LOD for SDF, dual-contouring and voxel terrain

- **Ju, Losasso, Schaefer & Warren, "Dual Contouring of Hermite Data", SIGGRAPH 2002**
  ([ACM](https://dl.acm.org/doi/10.1145/566654.566586)). Verified (abstract): this is the QEF-based
  octree simplification this mesher implements, where collapse is driven by the QEF residual. The
  method takes *exact* intersection points and normals as input. Finding 3 measures what feeding
  it linear crossings and 1 m gradients instead costs.
- **Schaefer, Ju & Warren, "Manifold Dual Contouring", IEEE TVCG 13(3), 2007**
  ([pdf](https://people.engr.tamu.edu/schaefer/research/dualsimp_tvcg.pdf)). Verified (pp. 1–2):
  "a problem of DC … is the restriction … [to] no more than one contour vertex within each grid
  cell". MDC allows multiple contour components per cell with a topology-safe clustering rule. This
  bears on sub-cell parts (Finding 3's limit), where two sheets pass through one cell.
- **Kobbelt, Botsch, Schwanecke & Seidel, "Feature Sensitive Surface Extraction from Volume Data",
  SIGGRAPH 2001** ([pdf](https://graphics.stanford.edu/courses/cs164-10-spring/Handouts/paper_p57-kobbelt.pdf)).
  Verified (abstract): grid sampling aliases sharp features. The paper proposes a directed distance
  field (exact distances along the grid axes) plus feature-aware extraction. That is the
  scalar-versus-Hermite problem of Findings 2 and 3.
- **Barry & Wood, "Direct Extraction of Normal Mapped Meshes from Volume Data", ISVC 2007**
  ([Springer](https://link.springer.com/chapter/10.1007/978-3-540-76858-6_78),
  [pdf](https://users.csc.calpoly.edu/~zwood/research/pubs/mbarry_isvc_v2.pdf)). Verified (abstract):
  it extracts a simplified DC surface and bakes a normal map from the fine volume as it goes. This
  is the closest published match to "coarse geometry, fine shading" for this pipeline.
- **Cohen, Olano & Manocha, "Appearance-Preserving Simplification", SIGGRAPH 1998**
  ([pdf](https://gamma.cs.unc.edu/APS/APS.pdf)). Verified (abstract): normals move into maps, and the
  simplification bounds how far the maps shift on screen in pixels. This is the original argument
  that shading detail can carry what geometry drops.
- **Lengyel, Transvoxel (dissertation, UC Davis 2010)** ([site](https://transvoxel.org/),
  [pdf](https://transvoxel.org/Lengyel-VoxelTerrain.pdf)). Marching-cubes voxel terrain with
  crack-free LOD transition cells (secondary). This is the prior-art baseline for editable voxel
  terrain LOD. It is distance-banded, not feature-weighted.
- **No Man's Sky, GDC 2017 (McKendrick)**
  ([GDC Vault](https://www.gdcvault.com/play/1024265/Continuous_World_Generation_in__No_Man_s_Sky_)).
  This covers a shipped voxel-to-polygon terrain pipeline (secondary summary). I didn't verify its
  LOD metric.

### "Error budget where the eye goes" in shipped or practical systems

- **Far Cry 5 terrain, GDC 2018 (Moore)** ([slides](https://media.gdcvault.com/gdc2018/presentations/TerrainRenderingFarCry5.pdf)).
  GPU quadtree LOD, culling and stitching for a heightfield. Secondary: tiles are streamed by
  LOD and distance. It shows that frustum culling at the LOD-selection stage is standard in shipped
  terrain.
- **Guenter et al., "Foveated 3D Graphics", SIGGRAPH Asia 2012**
  ([MSR](https://www.microsoft.com/en-us/research/publication/foveated-3d-graphics/)). Verified
  (abstract): 5–6× savings from acuity falloff with gaze tracking. Without an eye tracker, the
  screen centre and the edit or cursor focus act as proxies (inference).
- **Dreams (Media Molecule), Evans, "Learning from Failure", 2015**
  ([MM blog](https://www.mediamolecule.com/blog/article/alex_at_umbra_ignite_2015_learning_from_failure_video)).
  Secondary: CSG edits evaluated to SDFs and rendered as dense multiresolution point splats, with a
  painterly look. It's the closest shipped analogue to "player-authored SDF, stylized, compelling
  over accurate". It keeps the edit list, not only the evaluated field (secondary), which is the
  data choice of Option 2 below.

### Detail faked in shaders, and the line-art look

- **Parallax occlusion mapping**: Tatarchuk, "Practical parallax occlusion mapping with approximate
  soft shadows for detailed surface rendering", ACM SIGGRAPH 2006 Courses
  ([ACM](https://dl.acm.org/doi/10.1145/1185657.1185830),
  [sketch pdf](https://cgg.mff.cuni.cz/~pepca/lectures/pdf/Tatarchuk-ParallaxOcclusionMapping-Sketch-print.pdf)).
  Verified (abstract): per-pixel height-field ray intersection with self-occlusion and a directable
  LOD. It fakes relief *inside* a silhouette. It can't restore a missing lintel.
- **Triplanar normal mapping**: Golus
  ([article](https://bgolus.medium.com/normal-mapping-for-a-triplanar-shader-10bf39dca05a),
  [shaders](https://github.com/bgolus/Normal-Mapping-for-a-Triplanar-Shader)). Whiteout and RNM
  blends for UV-less meshes (verified, repo). It fits DC meshes, which have no UVs.
- **Edge and line rendering from G-buffers**: Saito & Takahashi, "Comprehensible Rendering of 3-D
  Shapes", SIGGRAPH 1990 ([ACM](https://dl.acm.org/doi/10.1145/97879.97901)). Verified (abstract):
  edges and contours come from depth and normal buffers as 2-D image operations.
- **Suggestive contours**: DeCarlo et al., SIGGRAPH 2003
  ([project](https://gfx.cs.princeton.edu/gfx/proj/sugcon/)). Lines that convey shape beyond
  occluding contours (verified, project page).
- **Sable's Moebius look**: fullscreen depth, normal and colour edge detection plus hatching
  (secondary: [Heckel](https://blog.maximeheckel.com/posts/moebius-style-post-processing/),
  [Veron](https://coleslow.dev/blog/moebius-shaders-1/)). This is the same family as the project's
  watercolour post-process.

**Inference for this project:** a line pass driven by the G-buffer draws edges where the *mesh's*
normals and depth break. At 1 m, the stones' mesh normals are 17–39° off at the median (Finding 2),
and their shapes are thinned and shifted. So a line pass would draw confident ink on the wrong
shape. Stylization amplifies whatever geometry it gets. It hides faceting on correct shapes, but it
doesn't rescue wrong ones.

## Options (not chosen)

Each option names its signal, where it plugs in, the effect this scene's numbers predict, its cost,
and its risks. They aren't exclusive. **Options 1 and 2 are the only ones that change the stones.**
Options 3–5 change where the budget goes, and 6–7 change how the result is shown.

### Option 1: a sub-metre floor where the eye goes (data and mesh together)

- **Signal:** edits, plus a foreground radius (and later, attention).
- **Where it plugs in:** the imprint cell (`predict_imprint`'s `cell`, today `RENDER_BASE_CELL`) and
  `EditStoreSource::target_cell_size`, which would allow a floor below 1 lattice unit near edits
  and the camera. It generalizes the global `RENDER_SUBDIV_LOG2` knob into a local, graded one.
- **Expected effect:** Finding 4. At an unaligned phase the stones go from 19–70% of their face
  area off the mesh to 0.1%. Stone error goes from 6–13 / 17–40 px (p50 / p95) to 0.37 / 1.75 px.
- **Cost:** 27× the cells in the ±32 m window (1.38 M against 0.051 M). Graded, it would be paid
  only near edits and the foreground.
- **Risks:**
  - It touches the edit store's leaf size, the save format, and the 1 m construction and
    structural grid.
  - It's a data change, not an LOD change.
  - Aligned phases at 0.25 m produce 300+ non-manifold edges; see the exact-zero note under
    Option 2.

### Option 2: exact Hermite data for edited leaves (brush-exact crossings and normals)

- **Signal:** none new. It changes what the floor is built from.
- **Where it plugs in:** `leaf_qef` and `EditStoreSource::gradient`, for leaves an edit touched.
  There are three ways to supply the data:
  - keep each brush (or its per-edge Hermite data) alongside the scalar imprint;
  - evaluate the analytic brush at crossing time, bisecting the true min(field, brush) on each
    sign-changing edge and taking its analytic normal;
  - store per-edge crossings and normals when the imprint is written.

  This conflicts with the "imprinting, not CSG" rule (doc 03 §4, `VoxelImprint`: "the brush's
  identity is discarded"). Keeping Hermite data per edge instead of brushes may sidestep that.
- **Expected effect:** Finding 3. At every phase except 0, the stone vertices go from 0.07–0.13 m
  (p50) / 0.35–0.50 m (p95) off to 0.000 m / 0.00–0.27 m, **at 1 m cell cost**. Normals become the
  true face normals, which fixes Finding 2's 17–39° as well.
- **What it can't do:**
  - It can't recover phase 0 (faces on lattice planes), where the signs themselves are empty.
  - It can't recover parts thinner than a cell. Those need a sign rule for exact zeros (for
    example, treat 0 as inside for a union imprint, or nudge the imprint lattice), or Option 1.

  The exact-zero rule is small and separate. It would also clear Option 1's non-manifold edges.
- **Cost:** moderate, plus per-edge storage or brush retention in the edit store. It competes
  directly with Option 1: one fixes the reconstruction at 1 m cost, the other raises the sampling
  rate at 27–64×. They also compose. A 0.25 m floor with exact Hermite data would handle sub-cell
  parts too.
- **Risks:**
  - Save format and undo.
  - Collapse, where exact crossings raise the stones' residual `we`, so they coarsen less (which
    is right).
  - The oracle checks vertices, not the rendered faces.

### Option 3: key the frontier by on-screen error, with a view term

- **Signal:** `we`·proj/d (doc 20 P's original key), times a frustum or facing weight (Hoppe's
  criteria).
- **Where it plugs in:** the `RefineCand` key in `reconcile` and the `refine_selected` heap. Doc 20
  §I keyed by camera-independent `we` so the heap would survive moves. Reinstating a camera term
  brings back re-keying on moves; bucketed keys, or re-keying only the visible band, are the known
  mitigations.
- **Expected effect here:** it reorders sub-pixel work. Every visible candidate is below eps.
  The top 200 would move from 60–150 m to 20–60 m.
- **Cost:** low.
- **Risk:** it only matters during the bloom. It can't touch the stones (Finding 1).

### Option 4: an error threshold on candidacy (stop refining what's already under eps)

- **Signal:** the candidate's own screen key. Don't queue (or don't pop) a candidate whose
  `we`·proj/d is already ≤ eps, or ≤ some fraction of it.
- **Where it plugs in:** the `RefineCand` push in `reconcile` (or a gate in `refine_selected`). It
  changes what the drain does from "refine every non-pruned cell to the floor" into "refine where
  it changes the drawn mesh".
- **Expected effect:** Finding 5. 100% of the visible candidates fail this test at both eps 7.2 and
  eps 0.5, so the drain would stop. That covers the 3.0 M cells added over 100 drains while the
  drawn mesh changed by 13% (2.9% over the last 75).
- **Caveat:** a coarse cell's `we` is the residual of *its own* QEF, built from its own 12 edges.
  It can miss sub-cell detail its corners don't see. That is exactly what refinement exists to
  find. A threshold would need a conservative bound (the prune accel's, or a per-cell curvature
  proxy) so it doesn't skip real features. Once the tree has been built to the floor, the
  accumulated QEF doesn't have this blind spot, but a candidate's leaf QEF does.
- **Cost:** low for the gate, moderate for a safe bound.
- **Risk:** the gate is only as good as its bound. It needs a regression scene with
  small-but-real sub-cell features (a thin ridge, a pit) that the corners miss.

### Option 5: stop spending on what can't show

- **Signal:** "would this pop emit anything visible?"
- **Where it plugs in:** the candidate test in `reconcile`. Skip or deprioritize candidates with an
  empty QEF, or outside the drawn window (5 of 400 pops went to the undrawn ring). Possibly also the
  accel's resolution near the surface.
- **Expected effect:** smaller than Option 4. In this deterministic run only 15 of 400 pops
  produced no triangle. The invisible 74 k candidates are the bigger target, if they're real.
- **Cost:** low.
- **Risk:** the mechanism is inferred, not verified. It needs the frontier-dump binding first.

### Option 6: move "compelling" into the shader, with geometry tuned to support it

- **Signal:** none in the mesher. The mesher keeps coarse collapse on smooth ground. The shader
  adds:
  - triplanar detail normals;
  - SDF-derived normal maps for edited surfaces (Barry & Wood);
  - G-buffer line art (Saito–Takahashi, Sable).
- **Where it plugs in:** `TERRAIN_MATERIAL_PATH` and the watercolour post-process.
- **Expected effect:** smooth ground and far creases already sit under about 1–3 px of error, where
  the shader can carry the look. The stones need Option 1 or 2 first, or the lines will draw the
  wrong shape. Analytic edit normals (Option 2) are also exactly what an edit normal map would
  sample.
- **Cost:** shader work plus a GPU-side edit-normal source.
- **Risk:** it needs GPU eyes to judge; headless can't.

### Option 7: an attention map as a multiplier on eps

- **Signal:** screen centre, the edit or cursor focus, and recent edit age, as a per-cell multiplier
  on eps (Luebke–Hallen and foveated rendering, without a tracker).
- **Where it plugs in:** `collapse_test` (a local eps) and the graded floor `floor_k`.
- **Expected effect:** a coarser periphery and back, with the finest detail where the player works.
  About three-quarters of the window is out of view by geometry (Finding 7). It composes with
  Options 1, 2 and 4.
- **Cost:** moderate.
- **Risks:** popping when attention moves, and it needs a hysteresis design.

## Bindings the harness wanted and didn't have

- **A frontier dump:** per candidate, index, origin, size, `we`, absent, and QEF count. Finding 5 is
  reconstructed from emitted owners and single pops instead.
- **A per-leaf "at floor or collapsed" flag on owners:** the harness recomputes the floor from
  `_floor_at`. A flag would make `dcinval`-style views exact.
- **Hermite data per leaf** (crossings plus normals): Finding 3 reimplements `leaf_qef` and
  `Qef::solve` in GDScript. The port matches the mesher's vertices in 97–100% of cells, and a
  binding would remove the port.
