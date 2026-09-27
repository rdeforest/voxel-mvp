# docs/bugs — moved to GitHub issues

Bug and feature tracking moved to **[GitHub issues](https://github.com/rdeforest/voxel-mvp/issues)** on 2026-09-27. Every
bug file that lived here, open, closed as not-a-bug, or fixed (deleted), is now an issue with its
full text; closed ones are closed issues, so they stay searchable. Roadmap features (`FEATnnn`) are
issues too, linked from their roadmap bullets.

- Open defects: `gh issue list --label bug`
- Features: `gh issue list --label feature`
- Decisions waiting on Robert: `gh issue list --label needs-decision`

**Filing a bug:** `gh issue create --label bug --label sev:<high|med|low-med|low> --label
area:<...>`, with the diagnosis and a proposed fix, as the files here used to have. **Fixing one:**
reference it in the commit (`Fixes #N`) so it closes on merge to master.

## Open bugs at migration time

| Bug | Issue |
|-----|-------|
| A refused preview reads the generator twice per lattice point | [#1](https://github.com/rdeforest/voxel-mvp/issues/1) |
| DC budget controller: coarsen bias near the cell ceiling, re-tunes only on job completion | [#2](https://github.com/rdeforest/voxel-mvp/issues/2) |
| DC: crease normals not stored — sharp edges shade soft | [#3](https://github.com/rdeforest/voxel-mvp/issues/3) |
| A "20 ms" refine drain takes 32–76 ms: collapse and emit have no budget | [#4](https://github.com/rdeforest/voxel-mvp/issues/4) |
| DC incremental emit: neighbour-ring expansion is a heuristic, not provably sufficient | [#5](https://github.com/rdeforest/voxel-mvp/issues/5) |
| DC world-octree: cracks inside the coverage (graded LOD seam) | [#6](https://github.com/rdeforest/voxel-mvp/issues/6) |
| `mesh_world` / `grow_world` still read "no box" from a box's value | [#7](https://github.com/rdeforest/voxel-mvp/issues/7) |
| DC: reversed (back-facing) triangles on convex ridges | [#8](https://github.com/rdeforest/voxel-mvp/issues/8) |
| Distant shadow shimmer when panning (CSM) | [#9](https://github.com/rdeforest/voxel-mvp/issues/9) |
| EditStore: a 1 m lattice write flattens finer leaves inside it | [#10](https://github.com/rdeforest/voxel-mvp/issues/10) |
| EditStore: a loaded blob's inherited corners aren't checked against their source | [#11](https://github.com/rdeforest/voxel-mvp/issues/11) |
| Event bus: a lambda or `.bind()`ed subscription fails at its first delivery | [#12](https://github.com/rdeforest/voxel-mvp/issues/12) |
| Godot's float parser isn't correctly rounded, and reads tiny values as 0 | [#13](https://github.com/rdeforest/voxel-mvp/issues/13) |
| A chunked MPM freeze announces its flips after later writes | [#14](https://github.com/rdeforest/voxel-mvp/issues/14) |
| MPM contact: viscous friction, damping in free flight, and the SDF treated as a distance | [#15](https://github.com/rdeforest/voxel-mvp/issues/15) |
| MPM physics-fidelity notes (knobs standing in for physical constants) | [#16](https://github.com/rdeforest/voxel-mvp/issues/16) |
| MPM: `Mat3::svd` loses U's orthonormality as F approaches singular | [#17](https://github.com/rdeforest/voxel-mvp/issues/17) |
| A part that makes no cell solid has no PartIndex record | [#18](https://github.com/rdeforest/voxel-mvp/issues/18) |
| Player safety misses a burial that lands between its test points | [#19](https://github.com/rdeforest/voxel-mvp/issues/19) |
| The detachment scout ignores MPM freezes, because seeding from them loops | [#20](https://github.com/rdeforest/voxel-mvp/issues/20) |
| SDF + noise stored/sampled as float — contradicts the double-precision planet-scale claim | [#21](https://github.com/rdeforest/voxel-mvp/issues/21) |
| FillVoxel / EmptyVoxel don't do what Robert expected in play (known unknown) | [#22](https://github.com/rdeforest/voxel-mvp/issues/22) |
| StoreWrite's box rewrite flips cells nobody edited | [#23](https://github.com/rdeforest/voxel-mvp/issues/23) |
