# The save's two files aren't checked against each other

*Filed by Claude (agent) on 2026-09-26, from review of the save-honesty-gaps fix.*

**Status:** Open, needs a design call. Severity low: every save so far is a test save.

## Symptom
The save is two files, the WorldSnapshot and the EditStore blob. `SavedWorld`
(`scripts/persistence/saved_world.gd`) refuses the pair when either half exists but this build can't
read it. It doesn't catch two other ways the halves can disagree:

- **One half is missing.** A snapshot without a blob applies its tracked voxels' support records over
  fresh procedural terrain. A blob without a snapshot loads terrain and parts with no support records.
  Either way the load toasts "Loaded save.", and the next F5 writes a pair that looks consistent.
- **The halves come from different saves.** `SavedWorld.save` writes the snapshot, then the blob. If
  the blob write fails after an earlier save, a new snapshot sits next to an old blob. Both read fine.

HEAD before the fix loaded each half on its own existence check, so neither case is a regression.

## Why it isn't just a refusal
- A snapshot-only pair is also a legacy save: the blob became the terrain/parts store at S4 (bfb6856),
  and `world_snapshot.gd` says "Older saves load with `parts` ignored." Refusing a lone snapshot breaks
  that, and a refused pair blocks F5 until console `reset`.
- An existence check doesn't catch the mismatched pair, which is the likelier outcome of a failed
  write once a save exists.

## Proposed fix
Tie the halves together: a shared save id written into both (or a manifest), plus an atomic pair write
(write both to temp names, then rename). Then decide what a lone or mismatched half does: refuse and
keep, or load with a warning. That decision is Robert's, including whether the pre-S4 snapshot-only
compat is still worth keeping now that all saves are test saves.
