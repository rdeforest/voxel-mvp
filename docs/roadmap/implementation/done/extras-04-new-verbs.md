# Completed: New Terrain Verbs — Raise / Lower / FillVoxel / EmptyVoxel

**Commit:** `3ebf5cf` (shared with Tools/Activities UI)

## What shipped

Four new terrain modification verbs that extend the
[`Action`](../../design/02-architectural-commitments.md) infrastructure:

- **Raise / Lower** — bell-shaped brushes that smoothly elevate /
  depress a region. The brush falls off radially; centre cells move
  most, edge cells barely.
- **FillVoxel / EmptyVoxel** — surgical single-cell verbs for
  one-voxel-at-a-time work. The "I need *exactly* this cell" answer.

## Key decisions taken

- **Bell-shaped brushes for Raise/Lower, not flat brushes.** A flat
  brush would produce sheer cylindrical lifts/drops; a bell shape
  produces natural-looking mounds and depressions. The principle: the
  *math* of the brush should match the *physical metaphor*.
- **FillVoxel / EmptyVoxel are intentionally narrow.** They do one
  cell. They exist because the existing radius-based verbs always
  affect a sphere, and there are situations (test setups, surgical
  repair after a glitch, fine detail work) where you want exactly
  one cell.
- **All four route through `Action`.** Just like Dig/Fill/Flatten.
  The bus emits the same events; structural integrity reacts the
  same way; preview-as-data works the same way.

## Lessons learned

- **The `Action` infrastructure shows its value when you add new
  verbs.** Each of the four new actions is a small file. The bus
  emission, preview computation, undo-via-quiescence, and structural
  integrity reaction all came for free from the existing infrastructure.
  The action-as-data commitment from Phase 2 was paying down debt the
  whole time.
- **Bell-shape brush math is well-trodden.** Standard smoothstep or
  Gaussian falloff; the implementation was an afternoon. The decision
  was just "yes, bell-shaped, not flat."

## Deferred

- **Tunable brush parameters per-verb** — currently hardcoded; Limbo
  Console `set` command can adjust at runtime. UI for this is v0.5+.
- **More verbs** — Smooth (Laplacian smoothing of SDF), Carve (long
  thin tunnels), Imprint (apply a stored Mold) — all natural fits
  for the existing infrastructure; will land as needed.
