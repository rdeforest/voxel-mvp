# Field snapshots: VDB, Blender, and what the fixture format should be

*Research notes drafted by Claude (Opus 5.5), 2026-09-26. No repo files modified.*

Legend: **[V]** verified against the cited source (or run locally); **[I]** my inference; **[?]** unsure / not verified.

---

## 0. Local facts that shape the answer

- **[V]** `EditStore::serialize()` (engine/voxel_dc/edit_store_serialize.cpp) writes the *whole sparse tree*:
  68-byte header (root origin/size, generator params base/amp/period/octaves/seed, node count) then
  98 bytes/node (origin xyz + size as doubles, 8 child indices, 8 float32 corners, field-state byte,
  material byte). It is a delta over the procedural generator, not a raster: reading any unedited point
  needs `TerrainField` to be bit-identical to the one that wrote it.
- **[V]** `fill_region(origin, dim, cell, ...)` / `fill_indices_region(origin, dim, cell)` already produce
  exactly a raster capture: `dim^3` values, x fastest (`flat_index`), at lattice points
  `(origin + (x,y,z)) * cell`. SDF is `float(sample(p))` — double evaluated, rounded to float32; material
  is `material_at(p)` at the **same** lattice points (node-sampled, not cell-centred). So SDF and material
  share one transform.
- **[V]** Name collision: "snapshot" already means `WorldSnapshot` (scripts/persistence/world_snapshot.gd,
  the F5 save of parts/player/tunables; `user://saves/world.snapshot`). A field capture should get a
  different name (e.g. "field capture" / `FieldCapture`, `.fcap`) or this will confuse docs and code.
- **[V]** Local Blender is the Devuan package, **Blender 4.3.2**, linked to system `libopenvdb10.0t64`
  (10.0.1). Its Python (system 3.13.5) has **no `openvdb` module and no `numpy`**. It *does* have the
  Volume to Mesh modifier and GN nodes MeshToVolume / VolumeToMesh / VolumeCube / PointsToVolume.
- **[V]** Local `libopenvdb.so.10.0.1` is **59 MB** (Installed-Size 57.7 MB); Debian deps: libblosc1,
  libboost-iostreams, libimath, liblog4cplus, libtbb12, zlib. No `-dev` headers installed.

## 1. OpenVDB

**License.** **[V]** Relicensed MPL-2.0 → **Apache-2.0 as of OpenVDB 12.0.0**; copyright holders
(DreamWorks, NVIDIA, Ubisoft, Adobe, Disney, ILM, ...) signed off.
<https://www.openvdb.org/documentation/doxygen/changes.html>, <https://www.phoronix.com/news/ASF-OpenVDB-12.0>

**Versions.** **[V]** 13.1.0 (2026-09-16), 13.0.0 (2025-11-03), 12.1.1 (2025-09-30). Same changelog.
conda-forge has openvdb 13.0.0, Apache-2.0 (api.anaconda.org/package/conda-forge/openvdb).
**[V]** There is **no official `openvdb` wheel on PyPI** (pypi.org/pypi/openvdb/json → 404); `pyopenvdb`
0.1.4 on PyPI is an unofficial MPL-era docker wrapper — don't use it. **[?]** Whether conda-forge's build
includes the Python bindings: not checked.

**Build deps.** **[V]** Core library required: CMake ≥3.24, C++17, **TBB** (≥2020.3). Optional: Blosc
(≥1.17), zlib, Imath (≥3.2), **Boost iostreams (optional now)**, log4cplus, VCL.
<https://www.openvdb.org/documentation/doxygen/dependencies.html>. Boost.Python → pybind11 (10.1) →
**nanobind (12.0)** for Python bindings (changelog). **[I]** In practice Debian/Blender builds still link
Blosc+zlib+Boost-iostreams, and files written with Blosc need a Blosc-enabled reader; writing with zlib or
uncompressed avoids that.

**Data model.** **[V]** (<https://www.openvdb.org/documentation/doxygen/overview.html>)
- Default tree 5-4-3: leaf nodes are 8³ voxels; internal nodes 16³ and 32³ children; tiles hold constant
  values for whole child regions; every voxel/tile is active or inactive; each grid has a background value.
- Linear transform: one fixed voxel size Δ (plus translation/rotation; frustum transforms exist) **per grid**.
- **Level set** (GRID_LEVEL_SET): inactive outside region at constant +background, inactive inside region at
  constant −background, and an active narrow band "normally three voxels wide on either side of the surface".
  **[I/known convention]** background = half-width × voxel size, values in world units, and the level-set
  tools (rebuild, filters, offset, CSG, `volumeToMesh` adaptivity) assume |∇φ| ≈ 1.
- **Fog volume**: inactive 0 outside, active 1 inside, thin 0→1 band.
- Multiple named grids per file, each with its own transform and metadata. Grid types include Float,
  Double, Int32, Int64, Bool, Vec3*, Mask, point data. **[I]** No 8-bit integer grid is registered by default,
  so material goes in an Int32Grid (or FloatGrid for shader convenience).
- File I/O: optional "save float as half" (**lossy**), plus zlib/Blosc compression (lossless).

**File format spec.** **[I]** There is no formal written spec; the format is defined by `io/Archive` code.
vdb-rs "follows the original OpenVDB implementation" and lists **VDB writing** under known-missing features
**[V]** <https://github.com/Traverse-Research/vdb-rs>. vdb-js is an in-memory JS port; its README says nothing
about file I/O **[V]** <https://github.com/tmpvar/vdb-js>. **I found no maintained minimal pure-Python/JS/Rust
VDB writer.** A hand-rolled uncompressed writer (one float tree + one int tree, 5-4-3, no compression) is
plausibly a few hundred lines **[I]**, but it'd be reverse-engineered against the C++ and carry
file-version-compat risk **[?]** — not a boring choice.

**NanoVDB.** **[V]** Header-only (a few headers; standalone C++11 `NanoVDB.h` plus C99 variant); topology is
**static** (values mutable, tree shape not). <https://www.openvdb.org/documentation/doxygen/NanoVDB_FAQ.html>.
13.0 added level-set / fog / staggered grid-class semantics in NanoVDB and write helpers like
`nanovdb::writeUncompressedGrid` (changelog). **[I, fairly confident]** those write NanoVDB's own `.nvdb`
format; producing a **`.vdb`** from NanoVDB goes through `nanoToOpenVDB`, which requires the full OpenVDB
library. Blender imports `.vdb` only **[I]**, so NanoVDB alone doesn't get us into Blender.

## 2. Blender (current: 5.2 LTS per docs.blender.org manual header)

- **Import.** **[V]** Add > Volume > Import OpenVDB creates a Volume object; each grid appears under
  Object Data > Grids. <https://surf-visualization.github.io/blender-course/advanced/python_scripting/4_volumetric_data/>
  (also notes a 4.5 / early-5.0 bug where reloading a modified VDB needs a Blender restart).
- **Grid types Blender knows** **[V]** (`BKE_volume_enums.hh`, main): boolean, float, double, int, int64,
  mask, vec3 float/double/int, points. So an Int32 material grid imports.
- **Displaying an SDF.** **[V]** I grepped `volume.cc`, `volume_grid.cc`, `volume_render.cc` on main: **no
  level-set-specific handling**. **[I]** So an SDF VDB renders as *density*: negative interior clamps to
  nothing and the positive exterior band renders as a fog shell — not sensible out of the box. Sensible views:
  (a) Volume to Mesh at threshold 0; (b) a shader remapping the grid attribute (e.g. density = −sdf clamped);
  (c) GN 5.x grid nodes.
- **Volume → mesh.** **[V]** Volume to Mesh modifier (`MOD_volume_to_mesh`) and Grid to Mesh node both call
  `openvdb::tools::volumeToMesh(grid, ..., threshold, adaptivity)` directly (`blenkernel/intern/volume_to_mesh.cc`).
  Modifier threshold range is **[0, FLT_MAX]** — 0 is allowed, so the φ=0 surface is extractable. Tooltip says
  "voxels with a larger value are inside" (fog convention) **[?]** so face orientation for an SDF (negative inside)
  may come out flipped; check once, flip normals if so. Resolution mode "Grid" meshes at native resolution.
- **GN volume grids (5.0+).** **[V]** Blender 5.0 added a grid socket type and ~27 grid nodes
  (<https://code.blender.org/2025/10/volume-grids-in-geometry-nodes/>). In main I see: Field to Grid,
  Get/Store Named Grid, Sample Grid, Grid to Mesh, Mesh to SDF Grid, Points to SDF Grid, SDF Grid
  Boolean/Offset/Fillet/Mean/Median/Laplacian/Mean Curvature, Set Grid Background, Set Grid Transform,
  Grid Info, Prune, Voxelize, Advect, Dilate/Erode, ... The SDF nodes assume a real distance field **[I]** —
  Offset/Fillet on our non-unit SDF will give wrong distances.
- **Export.** **[V]** No File > Export VDB. The path is: produce volume geometry (Mesh to Volume modifier, or
  GN) → **Bake** node / GN bake; "each volume geometry is written to a separate .vdb file" in the bake blobs
  dir <https://projects.blender.org/blender/blender/pulls/117781>, <https://docs.blender.org/manual/en/latest/modeling/geometry_nodes/baking.html>.
  Materials aren't preserved in the standalone .vdb.
- **Python `openvdb` module.** **[V]** Official blender.org builds bundle it (`import openvdb`;
  `FloatGrid().copyFromArray(ndarray)`, `openvdb.write(path, grids=[...])`) — per the SURF course; distro
  builds may not **[V locally: Devuan 4.3.2 lacks it]**. So a Blender-side converter needs a blender.org build.
- **Houdini.** **[I, well known]** VDB is Houdini-native (SOP-level VDB tools, level-set display, VDB Convert);
  nothing beyond "it will read what we write".

## 3. How our data maps onto VDB

- **Multi-resolution.** VDB = one voxel size per grid. Options:
  1. **Resample one region at one cell size** (= `fill_region` output). Simple, what Blender shows well. Lossy
     where leaves are finer than the cell; wasteful where they're coarser.
  2. **One grid per leaf level** (sdf_L0 … sdf_Ln, each with Δ = leaf size, active only where leaves of that
     size exist). Preserves structure but Blender shows N separate grids; nothing merges them; T-junction
     seams between levels remain visible. **[I]** Usable for debugging the tree, not as the field.
- **Corner semantics.** Our leaves hold 8 corners, trilinear inside. A VDB voxel is one value per lattice
  point, trilinear by `BoxSampler`. **[I]** Mapping index (i,j,k) → world `origin + (i,j,k)·Δ` makes VDB
  lattice points coincide with leaf corners at that level, and VDB trilinear inside a same-size leaf
  reproduces ours in exact arithmetic. **But** VDB can store only *one* value per lattice point: wherever
  two adjacent leaves (OWN_FIELD vs neighbour/generator) disagree at a shared corner, or at coarse/fine
  T-junctions, our field is discontinuous and VDB must pick one side (our `sample()` picks the upper leaf,
  `sample_toward` the other). **The store is not losslessly representable as a VDB grid.**
- **Values/precision.** float32 in → float32 in the file is exact **only** with half-float saving off;
  zlib/Blosc are lossless. `fill_region` itself already rounds `double sample()` to float32 — deterministic,
  fine for fixtures. Background: dense capture means every voxel is active; background just needs to be
  documented (e.g. +far). Grid class: **don't tag GRID_LEVEL_SET** — the SDF isn't unit-distance, and
  level-set-aware tools (Blender SDF nodes, OpenVDB rebuild/offset) would silently mis-treat it. Leave
  GRID_UNKNOWN, record "non-unit SDF, surface at 0, negative = solid" in grid metadata. **[I]** If a true
  level set is wanted for Blender play, the exporter can `levelSetRebuild` a copy — explicitly lossy.
- **Material.** Int32Grid "material" with the **same** transform as the SDF grid (both node-sampled per
  `fill_indices_region`). Per-leaf material becomes per-lattice-point → the leaf/corner association is lost
  (lossy for the tree, exact for the raster). For shading in Blender a FloatGrid copy is handier **[I]**.
- **Scale.** 16 km root / 0.25 m = 65,536 index units per axis — fits VDB's int32 coord space trivially;
  sparse tiles make it cheap. Dense regional captures are the realistic use.

## 4. Alternatives

- **`.npy` / `.npz`** — **[V, numpy format]** `.npy` = magic + ASCII dict header (`descr`, `fortran_order`,
  `shape`) padded to 64 B, then raw bytes; `.npz` = zip of `.npy`. **[I]** Writable from GDScript in ~20 lines
  (Godot has `FileAccess` and `ZIPPacker`), readable by numpy/SciPy/anything, bit-exact float32 LE. Shape
  `(dim,dim,dim)` C-order `[z][y][x]` matches our x-fastest `flat_index`. Blender can't import it natively,
  but a 30-line Blender script turns it into a VDB (official build) or a mesh.
- **Raw `.raw` + sidecar** — same as npy but header lives elsewhere; npy is strictly better (self-describing).
- **glTF** — **[V]** no ratified voxel/3D-texture extension; `KHR_materials_volume` is surface thickness /
  attenuation for refraction, not voxel data. <https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Khronos/KHR_materials_volume/README.md>.
  **[I]** glTF is still the right way to ship the *mesh* (what the DC mesher produced) to Blender: Godot's
  built-in `GLTFDocument` can export a scene — zero deps. Complementary to a field capture, not a replacement.
- **OpenVDB point data** — points with arbitrary attributes (could hold one point per leaf with size +
  8 corners + material). **[?]** Blender's handling of point grids beyond listing them is unclear; I would
  not bet on it.
- **Own Blender add-on reading our format** — **[I]** Simplest honest option: an add-on that reads a
  `.npz` capture and (a) on an official build writes grids via bundled `openvdb`, or (b) calls Volume
  Cube/Field-to-Grid… (awkward: getting array data into a GN field has no direct path) — (a) is the
  practical one. Reading our *tree* blob in Python is also easy (fixed 98-byte records, `struct`), which
  enables the one-grid-per-level debug view without any C++ dependency.

## 5. Recommendation

**Keep our own formats canonical; treat VDB as an export for eyes, done out of engine.**

1. **Two fixture kinds, both ours, both exact:**
   - *Tree fixtures* = the existing EditStore blob (already versioned, validated on load by `_parse`).
     Use for store-state tests. Caveat: coupled to `TerrainField` bit-identity (generator change ⇒ fixture
     meaning changes silently for unedited reads).
   - *Field captures* (new; don't call them "snapshots" — `WorldSnapshot` owns that word) = `fill_region` +
     `fill_indices_region` output + meta (version, origin (Vector3i), cell, dim, generator params, sample
     convention). Store as `.npz` (sdf float32 `(d,d,d)`, material uint8 `(d,d,d)`, meta as JSON or a small
     npy). Generator-independent, bit-for-bit, readable by numpy and by Blender scripts.
   - **GUT loads** either via `FileAccess.get_buffer` → `PackedByteArray.to_float32_array()` after skipping
     the npy header (or a tiny `NpyReader` helper in test/support), then compares with `==` on the packed
     arrays (exact) — e.g. `store.fill_region(...) == fixture.sdf`. Host-endian caveat: `to_float32_array`
     is native-endian; fine on x86-64/ARM64, assert `descr == '<f4'`.
2. **VDB exporter: out-of-engine Python**, `tools/capture_to_vdb.py`, run with a **blender.org** Blender
   (`blender -b --python tools/capture_to_vdb.py -- in.npz out.vdb`): FloatGrid `sdf` (GRID_UNKNOWN,
   metadata "non-unit SDF, solid < 0"), Int32Grid `material`, shared linear transform
   (voxel size = cell, translation = origin·cell), no half-float. Optional `--tree` mode reads the blob
   and writes one grid per leaf level for structure debugging. Zero new engine deps.
   Cost: Robert's Devuan Blender lacks the module (verified) — needs a blender.org tarball (or
   conda-forge openvdb, Python bindings unverified).
3. **Don't link OpenVDB into the engine.** Weight: TBB required, typically Blosc/zlib/Imath/Boost-iostreams,
   ~59 MB shared lib, heavy template compile, a CMake project wedged into Godot's SCons build — for a
   debugging/export feature. **Don't adopt VDB as the fixture format**: the tree isn't losslessly
   representable (one value per lattice point, discontinuities at leaf boundaries, per-leaf material
   flattened), half-float saving is an easy foot-gun, and GUT can't read .vdb without that library.
4. Complement with **glTF export of the DC mesh** via Godot's `GLTFDocument` for "what did the mesher
   actually produce" in Blender — no deps, and it's the thing you usually want to look at.

On the manifesto check: this isn't a half-measure — the fixture requirement (bit-exact) actively rules VDB
out as canonical; VDB-as-export gives full Blender interop. The only thing deferred is in-engine VDB, and
it's deferred on dependency weight, not effort.
