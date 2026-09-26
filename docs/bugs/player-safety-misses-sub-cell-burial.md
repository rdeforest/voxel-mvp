# Player safety misses a burial that lands between its test points

*Filed by Claude (agent), overnight 2026-09-26. Split out of `misc-low-severity` item 7, which had
the direction backwards. Found by the Track I2 author, which failed that chunk rather than ship a
partial rule, and reproduced by Claude on `f6e45ac` with the probe below.*

**Status:** Open. Severity **med**: a safety check that says "safe" when it isn't. Needs two calls
from Robert before an exact fix can be written.

## Symptom
`PlayerSafeAction.endangered_by` can let a write bury the player, or remove the ground under them,
when the write moves the surface by less than half a cell inside the capsule or support box.

Probe `scripts/dev/probe_turns_in_exactness.gd`, run with
`bin/godot --path . --headless -s addons/gut/gut_cmdln.gd -gtest=res://scripts/dev/probe_turns_in_exactness.gd`,
on 1 m leaves at y = 500:

| Case | Reported | Truth |
|---|---|---|
| Prior `y_frac - 0.1`, write `y_frac - 0.3`: new solid over y in [0.1, 0.3) | `solidifies_in` = false | true (missed burial) |
| The mirror for air | `empties_in` = false | true (missed carve-out) |
| Prior is -1 below a leaf face and +1 above it; the box ends on that face | `solidifies_in` = true | false (false refusal) |

A small raise or carve on a slope has exactly the first two shapes.

## Cause
`EditStore::lattice_turns_in` (`engine/voxel_dc/edit_store_predict.cpp`, reached through
`SdfLattice.solidifies_in` / `empties_in`) finds exactly where the *written* field changes side,
but judges the *prior* field only at piece corners and cell sample points. New solid strictly
between those points goes unseen. The false refusal is a read-side artefact: `store.sample()` at a
max face reads the leaf above, outside the box.

## Why no fix landed tonight
Being exact in both directions needs two decisions:

1. **The prior over an unedited leaf** is the analytic generator (y minus ridged-noise
   surface(x, z)), and nothing bounds it exactly. Options: (a) the analytic generator with a
   Lipschitz tolerance (and which way should the tolerance err?); (b) the generator as the store would
   materialise it, the trilerp of its corner values, which makes both sides trilinear so an exact
   rule exists; (c) something else.
2. **The bar over edited leaves.** Both fields are trilinear per piece. The exact question ("is
   there a point with prior solid-side < t and written >= t?") needs roots on edges, a rational
   minimisation on faces, and the critical points of f on the surface g = t inside the piece. The
   alternative is a sound rule that never misses but may refuse when the two surfaces touch.

The false refusal needs no decision: split the pieces per prior store leaf and judge each closed
piece against its own leaf. On its own that would be a partial fix, so it's left to land with the rest.

## References
`engine/voxel_dc/edit_store_predict.cpp` `lattice_turns_in`; `test/support/lattice_oracle.gd` (the
GDScript oracle, which must move in lockstep); `scripts/actions/player_safe_action.gd`.
