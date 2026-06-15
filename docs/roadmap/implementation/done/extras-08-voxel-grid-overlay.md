# Completed: Voxel Grid Overlay

**Commit:** `d761cb4`

## What shipped

A dev-time visualisation: press **G** to toggle a Chebyshev-shell
voxel grid overlay around the player.

- G toggles visibility.
- Renders as concentric Chebyshev shells (max-norm distance from
  the player) — cubes at integer cell distances, not Euclidean
  spheres.
- Useful for orienting against the underlying voxel grid when
  parts placement, structural visualisation, or terrain edits get
  ambiguous about cell boundaries.

## Key decisions taken

- **Chebyshev shells, not Euclidean shells.** Voxels are cubes;
  the visualisation should match. Euclidean spheres would mislead
  about what's "near" in voxel terms.
- **Toggle, not always-on.** Dev tool; off by default; cheap to
  flip on when needed.
- **One key, no chord modifier.** G is plenty.

## Lessons learned

- **Visualisations that match the underlying data structure clarify
  bugs faster than visualisations that *look pretty*.** Euclidean
  spheres would have been more aesthetic; Chebyshev shells match the
  data and surface "this cell is two grid units away, not 1.7." Pays
  off when reasoning about structural integrity propagation, which
  also works in cell-graph terms, not Euclidean.
