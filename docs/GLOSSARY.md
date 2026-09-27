# Glossary

*Drafted by Claude, 2026-09-26, for getting back up to speed. One or two lines per term, with a
pointer to where the detail lives. Where this disagrees with the doc it points at, that doc wins.
Add terms as they come up.*

## World and data

- **Matter / terrain / material.** *Matter* is any solid the voxels describe, natural or built.
  *Terrain* is naturally generated ground only. *Material* is the per-cell type (stone, wood, ...).
  The terrain → matter rename in code is still pending.
- **SDF (signed distance field).** The field every solid is stored as: negative is solid, positive is
  air, and the surface is at zero. Ours is *not* a true distance, so |value| isn't metres from the
  surface.
- **Cell.** The 1 m gameplay voxel. A cell's solidity is the field's value at its **sample point**, the
  cell centre, which is the average of its 8 corners.
- **Render cell.** The meshing grid; `RENDER_SUBDIV` render cells per gameplay cell per axis. It's 1
  today, so render and gameplay cells coincide.
- **Generator / `TerrainField`.** The C++ function that defines untouched terrain. Tweak terrain in
  `terrain_field.h`.
- **Bedrock.** A deep, diggable material that always counts as supported; the floor that the flood
  fill checking whether something is still attached must reach.
- **EditStore.** The terrain's data store: a sparse octree holding only *edits*, deferring to the
  generator everywhere else. C++. → `roadmap/design/11-octree-edit-store.md`
- **Leaf.** An EditStore node that holds a field: 8 float32 corner values (trilinear inside) plus one
  material byte. Leaf sizes run from the 16 km root down to 0.25 m.
- **Field state.** What a node's field is (since `c0292ac`): `NO_FIELD` (reads the generator),
  `OWN_FIELD` (its own corners), `INHERITED_FIELD` (reads the field of the coarser leaf it was split
  from, unchanged), `FIELD_SOURCE` (an internal node that was split and still supplies that field).
- **Blob.** The EditStore's binary save file (`world.editstore`). `SAVE_VERSION` 3; its header carries
  the save id it shares with the WorldSnapshot, and a save loads only as a matching pair.

## Rendering

- **DC (dual contouring).** The mesher: one vertex per surface cell, placed by solving a QEF, which is
  how sharp edges survive. → `roadmap/design/03-dc-qef-geometry.md`
- **QEF (quadratic error function).** The small least-squares problem solved per cell to place its
  vertex. Its residual doubles as the collapse error.
- **World octree / `dcworld` / `DcWorldPreview`.** The live terrain render: a single world-fixed
  octree meshed incrementally, the only render path. → `CODE-MAP.md`
- **eps (`eps_px`).** The screen-error level-of-detail knob: how many pixels of error a coarse cell may
  show before it's refined. A budget controller drives it from frame time and mesh lag.
- **Refine / coarsen.** Splitting a render cell into finer ones where screen error is too high, and
  merging where it's low.
- **Frontier.** The saved heap of cells waiting to refine, drained across frames so refinement never
  stalls a frame. → `roadmap/design/20-continuous-incremental-mesh.md`
- **`mesh_world` / `grow_world`.** A fresh build of the render octree, versus an incremental update
  after a camera move or eps change that re-meshes only the band that changed.
- **Emit / incremental emit.** Producing triangles from the octree; the incremental version re-emits
  only the changed band. `dcdrop` is the console catcher for triangles it drops.
- **Splice.** Re-meshing one box of the world and stitching it into the existing mesh instead of
  rebuilding everything (`mesh_clipmap_splice`). → `roadmap/design/13-incremental-lod-splice.md`
- **Clipmap.** The retired camera-centred render. `mesh_clipmap` survives as a meshing harness and
  for collision.
- **Arena (cell arena, `CellArena`).** The storage for the octree's cells: fixed-size RAM blocks that
  grow without copying, capped by a RAM budget (`DC_CELL_RAM_BUDGET`, 16 GiB ≈ 68 M cells). At the cap,
  refinement stops at the current detail with a one-time warning. The earlier disk-backed (mmap)
  arena was removed on 2026-09-27 (Q4). → `engine/voxel_dc/dc_cell_arena.h`
- **Collision (`DCCollisionManager`).** A collision mesh built just in time around the player,
  separate from the render.

## Edits and actions

- **Action.** One edit verb as an object (`DigAction`, `CsgAction`, ...): `validate()`, `preview()`,
  `execute()`. Built fresh for each use; the ghost builds one every frame.
- **Ghost / preview.** The translucent picture of what an action would change, drawn every frame.
  A desaturated ghost means the action would be refused.
- **Lattice (`SdfLattice`).** The exact field an edit is predicted to write. Built in C++ (the
  `predict_*` methods), with the old GDScript kept as a bit-exact test oracle.
- **Flips (`CellFlips`).** The cells whose centre crosses between solid and air across a write,
  measured in C++. They drive events, ghosts and safety checks.
- **CSG.** The add and subtract stamps of box, cylinder and sphere shapes.
- **Imprint (`VoxelImprint`).** Writing a part's or CSG shape's field and material into the store.
- **Part / `PartIndex`.** A placed construction piece (beam, log, plank); PartIndex is the sidecar that
  records which cells each part owns, since the field itself carries only SDF and material.
- **Player safety (`endangered_by`).** The check that refuses an edit that would bury the player or
  remove the ground under them. It currently misses sub-cell burials
  (`bugs/player-safety-misses-sub-cell-burial.md`).

## Structure and physics

- **MPM (Material Point Method).** The continuum physics sim that makes structures sag, crumble and
  settle. We use **PB-MPM**, a position-based variant that stays stable with big timesteps.
  → `roadmap/design/12-mpm-structural-substrate.md`
- **Thaw / freeze.** Thaw carves cells out of the store into MPM particles, leaving a hole the mesher
  re-meshes. Freeze writes settled particles back into the store as matter.
- **PBD (position-based dynamics).** The previous structural sim, which MPM replaced. Removed.
- **SVD / McAdams.** Each MPM particle needs a 3×3 singular value decomposition every step, and it
  dominates the cost. "McAdams" is the planned fast, branch-free 3×3 SVD (McAdams et al. 2011) that
  also fixes the near-singular accuracy bug. The next MPM step, currently paused.
- **DetachmentScout / GroundFlood.** After an edit, the scout flood-fills the affected solid down
  toward bedrock; a piece that never reaches ground is detached and thawed, so it falls.
- **TerrainSupport / StructuralIntegrity.** The support bookkeeping for tracked cells, and the
  structural coordinator. `StructuralIntegrity.is_quiescent()` ("nothing in flight") gates saving.
- **Quiescent / settled.** No structural work pending: MPM idle and support work drained. F5 and
  recording both wait for it.

## Testing and tooling

- **GUT.** The Godot unit-test framework (`test/`). **Pending** tests are known gates for filed bugs.
- **Class-cache pass.** `bin/godot --path . --headless --editor --quit`: registers new `class_name`s
  so GUT can see them. Run it after pulls that add classes. → `BUILD.md`
- **Faithful field.** Test on the game's real multi-level field, never a raw analytic SDF; a
  raw-field test once hid a bug that deleted 45 % of the surface.
- **Oracle / byte-identical gate.** A test that compares the C++ implementation bit for bit against
  the original GDScript, kept for that purpose in `test/support/lattice_oracle.gd`.
- **Editor clobber.** The Godot editor GUI overwrites external edits to `.tscn` and `.godot/` on save;
  keep it closed while agents work. → `BUILD.md`
- **Review loop.** How agent work lands: an author, two adversarial reviewers (correctness and
  completeness), then a fixer who commits only on green GUT.

## Scenario languages (design doc 22, draft)

- **Test/play split.** Exact, grid-aware **instruments** for testing, versus intent-driven
  **directives** for play ("make this space empty"). → `roadmap/design/22-scenario-languages.md`
- **Instrument layer.** The test tools: an extended probe, exact console writes, named saves.
- **Field capture.** A raster `.npz` of SDF plus material over a region; bit-exact test fixture.
  Not "snapshot".
- **WorldSnapshot.** The F5 save of player, parts and tunables (the snapshot half of a save).
- **Method / step.** An HTN-style description of how to do something: tasks decompose into steps
  (resolved actions). Recordings, test scenarios and assembly processes are all methods.
- **Assembly.** A method (the build process) plus a product description (what the finished thing
  is), built by demonstration and parameterized.
- **Directive.** A player's stated intent that the avatar carries out over time. Not built yet.
- **HTN (hierarchical task network).** The planning model methods follow: goals decompose through
  methods into steps.
- **Pint units.** Quantities are stored as authored (`"5.5 foot"`), using a unit table in Pint's
  definition format.
