# Voxel Farm and the ~2-voxel feature limit

*Drafted by Claude (research agent), 2026-09-27. Tags: [V] = verified by fetching the source page;
[S] = seen only in a search snippet (page not fetchable); [R] = my recollection or inference, not verified.*

## Short answer

Voxel Farm **acknowledged the limit and did not solve it in general.** Cepero said outright that
the engine cannot represent features below about 2 voxels (Nyquist). Around that limit it used
**workarounds**: (a) it stored one sub-voxel vertex per cell instead of pure scalar corners;
(b) it placed procedural content so it lined up with the coarse LOD grid ("lean trees"); and
(c) at distance it moved detail into textures and normal maps, not geometry. Landmark players
then exploited the per-cell vertex ("microvoxels"). This was an emergent hack, not a designed
thin-feature primitive.

## What Cepero said (read directly)

- **Nyquist, stated plainly** [V]. From a comment on *Going off-grid* (2013-05): the voxel size
  is 0.3 m, and "with that size you can only reconstruct features that are 0.6 meters (see
  Nyquist frequency). Beyond that you will get aliasing." Chandeliers are out; doorways and
  arches are fine. Rotated brushes ("off-grid") are handled because DC keeps sharp edges at
  arbitrary angles.
  https://procworld.blogspot.com/2013/05/going-off-grid.html
- **Thin features and LOD** [V]. From *Lean Trees* (2013-08): "Trees with thin trunks are
  problematic for a voxel engine. The reason is aliasing." Distant trunks vanish. He also wrote:
  "the limit is not really how thin a feature can be, but how close two thin features can be."
  The fix was to shift each tree "a clever amount" so its trunk lines up with the largest voxels
  that still have to show it. The result was trunks "an order of magnitude thinner than the
  voxels used to represent them". This is grid-alignment of the content, not a mesher fix. A
  commenter proposed encoding a sub-voxel offset in the normal. Cepero did not take it up.
  https://procworld.blogspot.com/2013/08/lean-trees.html
- **Why DC** [V]. From *From Voxels to Polygons* (2010-11): MC "cannot produce sharp features".
  He chose DC with a QEF for architecture.
  http://procworld.blogspot.com/2010/11/from-voxels-to-polygons.html
- **Voxelizing meshes into Hermite-like data** [V]. From *OpenCL Voxelization* (2011-04): he
  records intersection normals by casting rays along all 3 axes. "For a sharp edge to be
  reconstructed, you need at least two intersections inside a voxel." And: "An even number of
  intersections will mean the voxel is actually empty, since the mesh at that point is too thin
  to be represented by the voxel grid." In other words, he knowingly dropped sub-cell slabs.
  http://procworld.blogspot.com/2011/04/opencl-voxelization.html
- **The stored format is not full Hermite** [V]. From *Is voxel data bigger than polygon data*
  (2017-08), each voxel holds:
  - an 8-bit attribute byte
  - **one 3D point (3 x 8-bit)**
  - up to 12 UV/surface entries
  - a 16-bit inner material, attached to the voxel's origin corner

  So a cell stores its contoured dual vertex directly (quantised to 8 bits per axis), not
  per-edge intersections plus normals.
  http://procworld.blogspot.com/2017/08/is-voxel-data-bigger-than-polygon-data.html
- **The SDK exposes two representations** [V]. The "field" representation is a scalar that is
  contoured automatically, best for smooth shapes. The "voxel" representation is a material plus
  an optional "3D surface vector" and color, recommended for "sharp edges and points". The docs
  do not define the vector's semantics. [R] It is probably the same per-cell point.
  https://www.voxelfarm.com/help/VoxelGeneratorPrograms.html
- **LOD**:
  - Early LOD was built by mesh simplification: a randomized QEM edge collapse ("multiple choice"
    algorithm), cutting meshes of hundreds of thousands of triangles to about 1-2k per clipmap
    cell, with detail moved into normal and material maps [V].
    http://procworld.blogspot.com/2011/10/playing-dice-with-mesh-simplification.html
  - Seams were first handled with overlapping cells and skirts, then replaced by stored boundary
    seams (not Transvoxel) [V].
    https://procworld.blogspot.com/2011/10/popping-detail.html
    https://procworld.blogspot.com/search/label/Transvoxel
  - In 2017, far terrain was coarse geometry plus generated textures [V].
    http://procworld.blogspot.com/2017/01/prettier-faster-terrains.html
- **Topology** [V]. No post I found discusses manifold DC or preserving topology across LOD. The
  Dual Contouring label has 4 posts, and none mention manifoldness or Hermite by name.

## Landmark / EQN player experience

- Cepero reports that players invented "microvoxels", "antivoxels" and "zero-volume voxels"
  that "make a big difference" [V].
  http://procworld.blogspot.com/2014/03/landmark-voxel-creations.html
- The Landmark wiki pages (fandom.com) were not fetchable (HTTP 402). Search snippets say [S]:
  - repeated smoothing shrinks a voxel into a microvoxel
  - one voxel per grid cell
  - a microvoxel next to a full voxel pulls that voxel's vertex
  - a vertex can sit up to about 1.5 cell widths from the cell centre

  This is consistent with the one-point-per-cell storage above.
  https://landmark.fandom.com/wiki/Micro-Voxel
- The tools included smooth and bevel brushes [V].
  https://www.gamespot.com/articles/building-a-better-sandbox-in-everquest-next-landmark/1100-6416091/
- [R] My recollection is that community lore described builds as "snapping" to the grid and
  thin/free-floating slabs as hard to make without microvoxel tricks. I have no citation for
  this.

## Implications for voxel-mvp (inference)

- VF's one-vertex-per-cell storage is the same class of representation we have (one dual vertex
  per leaf). It has the same failure mode: two surface sheets inside one cell cannot both be
  represented.
- VF's escape routes were:
  - finer voxels (0.3 m, against our 1 m)
  - aligning content to the grid
  - textures for distance
- It never shipped a general sub-2-voxel solution. Our note 09 conclusions (exact Hermite fixes
  axis-aligned placed stones, and the Nyquist limit remains) agree with Cepero's own statements.

## General techniques (literature; recollection unless linked)

- **Hermite DC** (Ju et al. 2002). Sharp features within a cell, but still one vertex per cell,
  so it cannot hold two sheets per cell.
  https://people.engr.tamu.edu/schaefer/research/dualcontour.pdf [S]
- **Manifold DC** (Schaefer, Ju, Warren, TVCG 2007). Multiple vertices per cell, one per surface
  component, plus topology-safe clustering under simplification. This is the direct fix for
  thin-sheet and non-manifold artifacts, and for "flapping slivers" when collapsing.
  https://ieeexplore.ieee.org/abstract/document/4297690 [S]
- [R] Other techniques:
  - **Dual Marching Cubes** (Schaefer & Warren 2004)
  - **Extended MC** (Kobbelt 2001)
  - **Cubical Marching Squares** (Ho et al. 2005): multiple components per cell, handles thin
    features better
  - **Intersection-free contouring** (Ju & Udeshi 2006)
  - **Occupancy / adaptive refinement** where a sign-change test fails to detect a sheet
  - **Redistancing / distance correction of the SDF**
- [R] Fundamental: no contouring scheme recovers a sheet whose corner samples all share the same
  sign. That needs either finer sampling, extra per-edge data (a multi-crossing count),
  or a non-SDF primitive.
