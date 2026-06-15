# Completed: The Octree EditStore — godot_voxel removed from the game

**Commits:** `bfb6856`, `bf9ec2f`, `a98f492`, `e8e0252`, `cc343d3`, `3d3f3cb`
**Design:** `docs/roadmap/design/11-octree-edit-store.md` (Phase B core of doc 10)

## What shipped

The terrain data layer moved off godot_voxel onto our own **EditStore** — a sparse
octree (C++, `engine/voxel_dc/edit_store.{h,cpp}`) that holds only the player's edits
(SDF + material) over the procedural `TerrainField` generator: `sample(p) = has_edit(p) ?
stored(p) : generator(p)`. It is now the single source for terrain across persistence,
render, collision, edits, and structural reads. godot_voxel is gone from the running game.

- **Edits write the store directly.** Dig/Fill → `stamp_sphere` (exact analytic);
  Flatten/CSG/Raise/Lower/FillVoxel/EmptyVoxel → `StoreWrite.cells` (a dense-box write —
  a grid point is a corner shared by 8 leaves, so per-cell writes go through a region).
  Every read (validation, `TerrainSupport` solidity, falling-body classification, PBD
  carve, probe) samples the store. `ActionFactories` resolves it lazily via
  `world.edit_store_ref()`; `StructuralIntegrity.set_store` fans it to `TerrainSupport`.
  The dual-write shadow (S2) is gone.
- **Render** (`DCTerrainManager`) sources SDF + material from a `duplicate()` store
  snapshot on a worker thread (`fill_region` / `fill_indices_region`) instead of the old
  godot_voxel region read.
- **Persistence** (S4): the EditStore serialises to `user://saves/world.editstore`
  (magic + version header) — F5 saves it beside the snapshot, `world._ready` restores it.
  Replaces the `VoxelStreamSQLite` stream.
- **Streaming became a non-problem:** the store + analytic generator are resident from
  frame one, so the world-ready gate fires immediately (no streaming wait).
- **godot_voxel removed (S5):** the `VoxelLodTerrain` node + its sub-resources (stream,
  generator graph, mesher, on-node material) deleted from `world.tscn`; the grass material
  extracted to `assets/materials/terrain_surface.tres`; the godot_voxel-only console
  commands (`vdebug`, `lod`, `dcsolo`) and the engine classes `VoxelMesherDC` +
  `DCRegionReader` + the `.tres` generator graph + `build_terrain_graph.gd` + their tests
  deleted. The godot_voxel *module* still links into `engine/voxel_dc` (for VoxelData
  types); only its runtime use in the game is gone.

## The bug that delayed it

`EditStore::deserialize` built node origins with
`Vector3(get_double(), get_double(), get_double())`. C++ leaves the order of evaluation of
function arguments unspecified; GCC evaluates right-to-left, so the X bytes landed in Z and
vice versa — **every save/load transposed the octree X↔Z.** A transpose is its own inverse,
so two cycles looked correct, which masked it on near-symmetric terrain. Fixed (`bf9ec2f`)
by reading each component into a named local first; `test_serialize_preserves_xz_orientation`
pins it. Lesson recorded: never pass side-effecting reads as constructor arguments.

## Known follow-ups

- The `dcgen` substrate preview's homogeneity prune undersamples coarse nodes (the "Y=128
  holes") — a separate limitation of that debug render, not the default `DCTerrainManager`.
- Single-mesher consolidation, C++ crease normals, and incremental edit re-mesh remain as
  noted in design doc 10.
