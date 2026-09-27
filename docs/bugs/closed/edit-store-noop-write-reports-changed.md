# A corner-identical write still moves the leaves it re-represents

*Filed by Claude (agent), overnight 2026-09-26, while fixing `edit-store-subdivide-float32-neighbours`
(Track I1).*

**Status:** **CLOSED — accepted behaviour** (2026-09-27). `changed` means "some rewritten cell's sample
moved", which is exact; it is not "the corners differ". See *Verdict* at the end. Severity was low
(latent); no flip seen.

## Symptom
A lattice that is the store's own field (`lattice_writes` false: every corner it would write equals
what the leaf holds, at float32) still reports `changed = true` from `write_region_flips` whenever a
leaf it rewrites does not already hold its field as its own corners. That covers three kinds of leaf:

- an edited leaf coarser than the lattice cell;
- an **inherited** leaf at the write's own cell size: the ring of subdivided children every write and
  stamp leaves around itself (Track I1 made those read their source's field, not rounded corners);
- a stamp's padded leaves that the brush doesn't reach (`min(before, brush) == before`): the stamp
  rewrites them as their own corners all the same.

`scripts/dev/probe_noop_write_changed.gd`, on the game store with a box stamped at 2 m or 4 m leaves,
writing the store's own field as a 1 m lattice and sampling the probed 1 m leaf at 0.125 m (729 points):

| leaf re-represented                                  | `lattice_writes` | `changed` | moved   | worst  |
|------------------------------------------------------|------------------|-----------|---------|--------|
| coarse 2 m leaf                                      | false            | true      | 576/729 | 1.5e-8 |
| coarse 4 m leaf                                      | false            | true      | 648/729 | 6.0e-8 |
| inherited 1 m leaf, leaf+(3,1,1) after a 1 m write   | false            | true      | 720/729 | 3.0e-8 |
| inherited 1 m leaf, leaf+(0,0,0) after a 1 m write   | false            | true      | 647/729 | 6.0e-8 |

A 0.5 m subtract stamp moves 331 of 550 points inside its region box that lie beyond brush reach, by
up to 2.6e-8. An identical write repeated afterwards reports `changed = false` in every case, and
nothing outside the rewritten leaves moves (Track I1 fixed that).

**What I1 changed.** Before I1, `_subdivide` re-rounded every child's corners at subdivision time, so
the inherited ring moved by up to 1.45e-7 silently (no event), and a later corner-identical write on
one of those children was then a strict no-op. After I1 subdivision moves nothing, and the same (smaller,
<= 6e-8) move happens at the later write instead, where it is reported. Same consequence class, now
visible; the inherited-leaf case is new to this bug's scope, not a new kind of drift.

## Mechanism
Inside its region a write replaces the field with the lattice's trilerp over its cells, which is
what every prediction (`lattice_flips`, `lattice_turns_in`, the GDScript oracle) assumes; a stamp
likewise stores each overlapped leaf as its own float32 corners. A leaf whose field is not already its
own corners (a coarse leaf's trilerp, or an inherited leaf's source's trilerp) is not bit-identical to
the trilerp of that field rounded at its corners, so the field really moves, by ~1e-8, and `changed`
is telling the truth. It is `lattice_writes` that answers a different question: corners, not samples.
Unedited ground behaves the same way: writing the generator's own values materialises the leaves,
and their samples move from the generator to a trilerp of it.

## Consequence today
CsgAction refuses on `lattice_writes`, so it never issues such a write. The MPM thaw and the other
`StoreWrite` users write regardless; a thaw that lands on a coarse or inherited leaf emits one
extra `terrain_sdf_changed` (a re-mesh) the first time. The second identical thaw reports no
change, so the scout does not loop.

## Options
- Keep a rewritten leaf's field (coarse, inherited, or a stamp's untouched padding) when all eight of
  its new corners equal the ones it holds, so `lattice_writes` false means a strict no-op. Then the
  region's field is no longer the lattice's trilerp for those leaves, and `lattice_flips` /
  `lattice_turns_in` and the oracle in `test/support/lattice_oracle.gd` must read the kept leaf, or preview and measurement can differ at
  a cell within ~1e-8 of zero. Unedited leaves raise a material question: a write that leaves the SDF
  unchanged can still paint.
- Accept it as it is and document `changed` as "some sample moved", which is exact.

## Verdict (2026-09-27)
*Recorded by Claude from Robert's answer to Q12 in
[`overnight-2026-09-26-questions.md`](../../roadmap/implementation/done/overnight-2026-09-26-questions.md).*

The second option: accept it and document `changed` as "some sample moved". Robert agreed, and
expects bigger work to moot it. Keeping a leaf's field when its corners match would complicate
every prediction path and the oracle for a ~1e-8 effect.

Documented where `changed` is read: `CellFlips.changed` (`scripts/actions/cell_flips.gd`) now says
it is true when any rewritten cell's sample moved, even by ~1e-8, and so can be true when
`SdfLattice.writes` / `EditStore.lattice_writes` is false. The C++ comment on `write_region_flips`
(`engine/voxel_dc/edit_store.h`) already says "whether any of those cells' sample value moved at
all", which is exact. The one consumer that acts on it, the MPM thaw's re-mesh gate
(`scripts/structural/mpm_structure.gd`), costs at most one extra re-mesh on the first thaw over
such a leaf, as *Consequence today* says.
