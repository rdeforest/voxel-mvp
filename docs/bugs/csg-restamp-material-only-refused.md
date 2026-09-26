# Re-stamping a CSG shape in a different material is refused as a no-op

*Filed by Claude (agent), overnight 2026-09-26, while fixing
[sdf-lattice-writes-false-change-at-max-faces](closed/sdf-lattice-writes-false-change-at-max-faces.md). From
reading the code; no test has run this case.*

**Status:** Open. Severity low. Needs Robert's call on intent.

## Symptom
Stamp a CSG ADD, then stamp the identical shape and transform with a different material. `CsgAction` refuses
the second stamp, but its write would repaint the leaves the brush makes solid (`SdfLattice.materials` gives
brush-solid points the part material).

## Cause
`SdfLattice.writes` looks only at SDF. `CsgAction` refuses when `not _writes`.

Before the max-face fix this was inconsistent rather than uniform. In high air (terrain SDF above `SDF_AIR`)
the flag was always true, so repainting by re-stamping worked by accident. Nearer the ground it was refused.

## Question
Should re-stamping be a way to repaint? If yes, `writes` needs a material side: compare `materials()` against
`material_at` for the rewritten leaves. `materials()` is GDScript and runs only at execute, so that also means
moving it to C++ or computing it at preview. If no, nothing to do beyond closing this.
