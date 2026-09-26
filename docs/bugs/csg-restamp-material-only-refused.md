# Re-stamping a CSG shape in a different material is refused as a no-op

*Filed by Claude (agent), overnight 2026-09-26, while fixing
`sdf-lattice-writes-false-change-at-max-faces` (fixed in `af19749`). From
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

Robert sez: This is another case of a situation which only applies in testing.
In the game, there won't be a "place wood" operation because that is
meaningless in this world. There will be a "stack wood over here" directive.
If the user wants to replace it with stone, they'll need to request the wood
be moved out of the way first.

This ties in with another question that came up about single-voxel edits to
which I replied that we may want a separate UI for such things.

Now that I'm thinking about it I wonder if we want to integrate a local LLM to
offer things like picking three locations and then asking the LLM to perform
an operation on the voxels touching the triangle defined by those points, for
example? Let's chat about this.

