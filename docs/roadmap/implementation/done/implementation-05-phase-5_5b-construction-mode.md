# Completed: Phase 5.5b — Construction Mode + Honest-Failure Terrain Ops

Maps to [`../started/05-phase-5_5-architectural-maturation.md`](../started/05-phase-5_5-architectural-maturation.md)
section 5.5b.

**Commits:** `15308bd` (5.5b1 + 5.5b2), `d2b7bbd` (5.5b3)

## What shipped

The placeholder fill/dig/flatten verbs were replaced with construction-
mode equivalents that respect [design principle #7](../../design/01-principles.md):
terrain ops should fail honest, not fake a surface.

### 5.5b1 — `AdditiveAction` base class (`15308bd`)

- `AdditiveAction` base declaring the verbs that can bury the player
  (Fill / Flatten / Construction).
- `PLAYER_CLEARANCE` lifted into the base.
- The subtractive verbs (Dig and the Empty* variants) are
  structurally incapable of fall-through and so don't inherit from
  `AdditiveAction`.

### 5.5b2 — Honest column-based flatten (`15308bd`)

- `FlattenAction` rewritten with column-based work computation: cells
  in the cut box are bucketed by lateral projection onto the plane.
- Each column cuts only if it reaches existing air within radius, and
  fills only if it reaches existing solid.
- Symmetric box around `plane_point`.
- Per-work-cell endanger check catches both "fill into player capsule"
  and "remove player's support cell."
- Bug 2a closed by this work — flatten no longer leaves the lateral
  sheet artefact.

### 5.5b3 — Voxel-aware preview UI (`d2b7bbd`)

- `Action.preview() -> ActionPreview` returning the cells the action
  would change, classified by intent.
- `VoxelPreviewRenderer` (world-space) reads this each frame and
  draws the cells.
- Cells highlighted by intent: air = red, solid = blue, part = yellow.
- Refusal lerps colors toward grey.
- Two-pass visible/obscured rendering.
- Idealised sphere/plane previews dropped from Dig / Fill / Flatten.
- `IntegrityDebug` rewritten on `ImmediateMesh` with spatial filter
  and obscured-pass toggle.

## Key decisions taken

- **The principle that survived:** *subtractive-only editing
  structurally cannot cause fall-through; additive editing always
  can.* Encoded in the type hierarchy via `AdditiveAction`.
- **Column-based work, not sheet-based.** A horizontal flatten that
  can't lower cleanly because there's material above the cut should
  *open a small cave*, not invent a floor. This is the principle-#7
  payoff in action.
- **Preview-as-data, not preview-as-rendering.** The action computes
  which cells it would change; rendering reads that classification.
  This makes the preview correct-by-construction (it can never disagree
  with what `execute()` will do) and lets refusal show up visually
  without separate code paths.

## Lessons learned

- **The earlier scaffolding fix told us where to go.** Phase 2's
  `_push_player_above_terrain` was working code but the wrong design.
  The right design — refuse via `validate()` — surfaced once the
  taxonomy was clear (additive vs. subtractive). The phase 5.5b1 work
  was just *naming* what we'd already discovered.
- **"Honest failure" reads as a higher-quality game feel.** The first
  time you flatten and the result is "well, that opened up a hole" it
  feels *real*, not broken. The Valheim flatten-fakes-a-surface
  comparison is direct, and ours wins.
- **Preview-as-data composes beautifully with refusal.** Once the
  cells were classified by intent, lerping toward grey on refusal
  was a one-line change. The principle-driven design was the work;
  the implementation was downstream of it.

## Deferred (with reasons)

- **Particle effects on cut/fill** — v0.2 art pass.
- **Sound feedback on refusal** — v0.2 audio pass.
- **Preview Z-fight with the surface it's matching** (known limit) —
  cosmetic; cleanest fix is a small forward offset on the preview
  plane normal.

## Validation

Horizontal flatten with material above the cut opens a void instead of
faking a floor. Fill refuses inside player capsule. Preview cells
correctly reflect refusal state. Bug 2a closed.
