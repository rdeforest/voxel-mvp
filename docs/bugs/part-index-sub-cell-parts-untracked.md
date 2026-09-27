# A part that makes no cell solid has no PartIndex record

*Filed by Claude (agent) on 2026-09-26, from the fix for part-index-footprint-cells-never-released.*

**Status:** Open, re-scoped 2026-09-27, **parked until assemblies exist** (doc 22 build-order phase
3). Severity low: today PartIndex feeds only the `parts` console count, and `descendants_of` has no
caller.

## Symptom
Place a part thinner than a cell that covers no cell's sample point (a 0.5 m log lying between
cell-centre planes). The imprint writes real geometry, but the part never appears in PartIndex.

## Cause
PartIndex is cell-granular: a record owns the cells its imprint made solid (its solid flips) and
dies when a carve flips the last one back to air (`scripts/structural/part_index.gd`). A placement
that flips no cell has nothing to own and nothing a carve could release, so `_on_part_placed` makes
no record. Before this, such a part was registered under its AABB footprint instead: it had a record,
but one nothing could ever release.

## Open question
What identity should a sub-cell part carry? Options seen so far, none chosen:
- Release by field, not by cell: keep the record's region and re-test it on `terrain_sdf_changed`.
  The sidecar can't tell the part's solid from terrain's without reading material, and a union keeps
  existing terrain's material, so this needs care.
- A finer identity lattice once `RENDER_SUBDIV_LOG2 > 0` makes sub-metre cells real.

Test: `test/test_part_index_imprint.gd` `test_part_that_fills_no_cell_leaves_no_record` pins the
current behaviour.

## Decision (2026-09-27)
*Recorded by Claude from Robert's answer to Q7 in
[`overnight-2026-09-26-questions.md`](../roadmap/implementation/done/overnight-2026-09-26-questions.md).*

Neither option above. The resolution is **assembly-path identity**: key a part by its evaluated path
in its assembly (`north_wall/merlon[3]`), as
[doc 22](../roadmap/design/22-scenario-languages.md) proposes ("PartIndex can key parts by path"),
so every part has an identity whatever its size, and cells stop being what a record is keyed by.
Robert agreed ("100% agree"). Nothing to do until assemblies exist; solve it there, and retire or
rewrite the pinning test above with it.
