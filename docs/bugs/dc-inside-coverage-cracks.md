# DC world-octree: cracks inside the coverage (graded LOD seam)

**Status:** Deferred (2026-06-15). Real, reproduced headlessly. Render-only; `dcworld` preview, not the
live clipmap render. Blocks doc 17 P3 (retiring the clipmap) but not the rest of doc 17.

## Symptom
`dcworld` on the laptop shows small see-through holes **inside** the coverage (not at the window rim),
on terrain. More of them at coarser `eps_px`.

## Reproduced (headless)
Faithful dcworld config — base_cell 0.25, depth 12, 128 m window, camera at centre, `proj=500`:
- `eps_px=94` (the in-game settle point): **6** interior count-1 edges, all >32 lattice from any window face.
- `eps_px=32`: **24**.
Detector: post-mesh edge histogram → interior edges used by only ONE triangle, both endpoints far from the
window faces (so not a legit open-rim cut). Probe: `tmp/probe_faithful_cracks.gd` (config above). A
uniform-fine floor (no grading) shows **0** — the grading is the trigger.

## Root cause (precise)
A **graded-floor coarse *leaf*** is built directly at a coarse size and carries only its **own coarse-edge
QEF**, so its vertex sits at the *coarse* surface position — misaligned from its fine neighbours' vertices.
The stitch quad across that LOD step degenerates → a missing triangle → hole. (Confirmed the holes are true
holes, not duplicate-vertex seams; they chain along the size-8↔16 transition.)

Doc 16's accumulate-QEF crack-fix only saves **collapsed** cells — those were built *fine first*, then
merged, so they carry accumulated fine data and place an aligned vertex. **Graded-floor leaves were never
built fine**, so they have no fine data → misaligned vertex → seam. This is the classic DC LOD-seam
(`docs/roadmap/design/07-known-hard-problems.md`), reintroduced by the graded floor that makes horizon
coverage affordable. It appears even at 2:1 steps (so an octree balance pass alone won't fix it).

## Proposed fix (preferred — root cause, no fragile detection)
Make a **graded-floor surface leaf accumulate its QEF from the FINE crossings within it** — sample the
cell's surface at base resolution and build the QEF from those, instead of from its 12 coarse edges. Its
vertex then lands on the fine surface, aligned with neighbours → **crack-free proactively, no detection**.
Cost is O(surface-in-cell), not O(volume), so only surface leaves pay and the prune already bounds those.
Same principle as accumulate-QEF, sourced by sampling rather than from built children.
- **Verify first:** that sampling-based accumulation yields shared-face crossings that *match* the fine
  neighbour's (bit- or near-exact), else there's a consistency wrinkle to handle.
- **Gate:** the headless repro above → 0 interior cracks at eps=94 AND eps=32, then GPU-confirm.

## Rejected / dead ends (don't repeat)
- **Detect-and-refine** (detect cracks → subdivide the offending cell → re-mesh until none): the *refine*
  half is sound, but reliable *detection of which cell to refine* defeated three attempts — `find_leaf(vertex)`
  does not reliably return a vertex's owning cell once collapse is in play, and coarse cells' boxes reach
  the window face, so a cell-box rim test mis-flags every interior crack as a rim cut. Would need
  per-triangle owner cell-INDEX + ring tracking during meshing. More fragile than the proactive fix.
- **Stitch-time `vertex<0`**: wrong mechanism — these cracks have vertices on both sides.

## References
doc 17 P3 gate; doc 16 (accumulate-QEF); doc 07 (LOD-seam); [[dc-sdf-not-unit-distance]].
