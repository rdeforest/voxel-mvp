# Refactor brief: split `engine/voxel_dc/dc_octree_mesher.cpp` (1966 lines)

*Self-contained task for a fresh session. Goal: shrink the .cpp by moving the
internal structs into per-concern headers, with **zero behaviour change**. Gate:
all tests green + the byte-identical invariants hold (this is pure code movement).*

## Why

The file accumulated to ~1966 lines through 3a/E/C/M. The style hook flags it.
It's actually several cohesive pieces glued into one anonymous namespace + the
public class. Separating them is a clean win; the core `Octree` struct is the one
irreducible big unit (one struct can't be split across files — accept its length).

## The split (header-only — keep ONE translation unit, no SCsub/ABI change)

Move each piece into a new header in `engine/voxel_dc/`, included by
`dc_octree_mesher.cpp` in dependency order. Headers are `#include`d, not compiled
separately, so **no SCsub change and no `VOXEL_ENABLE_*` ABI concern**
([[voxel-dc-abi-defines]]). Current line ranges in the .cpp:

1. **`dc_sdf_source.h`** ← `SdfSource` (210–218). Abstract base. Tiny.
2. **`dc_clipmap_source.h`** ← `Level` (71–204) + `Clipmap` (222–356). The
   baked-grid source (collision / falling chunks / test oracle). Deps: SdfSource,
   `dc_qef.h`, `octree_geometry.h`.
3. **`dc_edit_store_source.h`** ← `EditStoreSource` (364–531). Live field + accel
   bake. Deps: SdfSource, `edit_store.h`, `dc_qef.h`.
4. **`dc_octree.h`** ← `Cell` (533–557) + `Octree` (566–1521). The core algorithm
   (~990 lines, one struct — irreducible; that's fine, it's the "one class per
   file" case, cf. [[gdscript-relax-file-length]]). Deps: SdfSource, `dc_qef.h`,
   `octree_geometry.h`.

**`dc_octree_mesher.cpp` keeps** (~450 lines): `pack_output`, `DCOctreePersist`,
all `DCOctreeMesher::` methods (`remesh`/`mesh_clipmap`/`mesh_world`/`grow_world`/
`edit_world`/getters/`_bind_methods`). `DCOctreePersist` can now `#include
"dc_octree.h"` instead of forward-declaring `Octree`.

## Watch-outs

- **Namespace:** the structs are in an **anonymous** namespace today. In a header
  that's poor practice (works only because one TU includes it). Put them in a
  **named** internal namespace, e.g. `namespace voxel_dc { namespace dc_mesh {
  ... }}`, and `using` it in the .cpp. (Or keep anonymous if you confirm only the
  one .cpp ever includes these headers — single-includer makes it safe but ugly.)
- **`g_mesh_threads`** (file-static, line 22) is read by `Octree`'s parallel
  passes. Move it into `dc_octree.h` (as a `static`/inline in the named namespace)
  or pass it — it must stay visible to `Octree`.
- **Shared tables `CB`/`EDGES`** already come from `octree_geometry.h` — just
  include it in `dc_octree.h` (and `dc_clipmap_source.h` if it uses them).
- **`pack_output`** takes `const Octree&` — keep it in the .cpp after `dc_octree.h`
  is included, or move to `dc_octree.h`. Either is fine.
- **Header guards** on each new header (`#ifndef DC_SDF_SOURCE_H` …).

## Gate (no behaviour change — this is movement only)

- `tools/build` clean.
- `bin/godot --path . --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/` →
  **170 tests, 0 fail** (2 pending: `edit_world` §E + PB-MPM repose — both
  pre-existing). The byte-identical / grow==fresh / parallel==serial gates in
  `test_dc_world_octree.gd` are the real proof the movement changed nothing.
- Editor parse check unaffected (C++ only).

Commit as one `refactor(dc): split dc_octree_mesher.cpp into per-concern headers`
— no functional diff, so the test pass IS the review.
