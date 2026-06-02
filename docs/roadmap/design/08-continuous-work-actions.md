# Continuous Work Actions

The click-spam replacement for mining and logging. Spec-level; the
state machine implementation belongs in Phase 3.

## Why this matters

Valheim's "hit tree, watch hit count" is one of its weakest design
choices. It turns intentional, skilled work — felling a tree in a
chosen direction, mining a vein at a chosen depth — into RSI training.

Continuous work actions are a real UX improvement *and* a thesis
alignment: in a world where geometry is honest and physics matter, the
act of changing the world should also be honest. You don't tap a rock
ten times; you mine it for a duration that depends on its material and
your tool.

## Tree felling

1. Select tree with interaction key.
2. UI shows tree info (type, size, estimated resources).
3. Choose fall direction (rotate ghost outline of fallen tree).
4. Confirm → avatar begins notch cut sequence.
5. Camera pulls to a comfortable third-person angle during work.
6. Progress bar shows completion.
7. Tree cracks, falls in chosen direction, impacts ground.
8. Logs and branches become collectible.
9. If interrupted (damage taken), work pauses; player regains control.
10. After dealing with interruption, can resume (progress preserved).

Directional tree felling is a real woodcutting technique (the notch
cut). This is both more realistic and more engaging than Valheim's
"hit tree, tree falls randomly."

## Mining

1. Select surface with mining tool.
2. UI shows material type, hardness.
3. Drag to set mining volume (width × height × depth).
4. Confirm → avatar begins mining.
5. Debris piles up nearby (collectible resource nodes).
6. Structural integrity evaluates in real-time as material is removed.
7. If ceiling integrity drops to red, mining auto-pauses with warning.
8. Player can reinforce, then resume.
9. If interrupted by creature, work pauses; resume after.

This is where the cave-reinforcement loop comes alive. You can't just
strip-mine; the ceiling tells you when you're in trouble.

## Vertical/horizontal smoothing

1. Select surface area to smooth.
2. Choose operation: vertical flatten, horizontal flatten, smooth.
3. Confirm → avatar works with chisel/tool.
4. Duration depends on: material hardness, area size, tool quality,
   player skill.
5. SDF values interpolate toward target surface over the work duration.
6. Like a crafting station: start the job, wait, result appears.

## State machine

The shared shape across all three:

```
IDLE → TARGETING → WORKING → (INTERRUPTED → RESUMING)? → COMPLETE
```

- **IDLE:** No active work; player free to move.
- **TARGETING:** Player has selected a target and is configuring
  parameters (fall direction, mining depth, smoothing area).
- **WORKING:** Avatar animation playing, progress accumulating, edits
  being applied incrementally (not all at the end).
- **INTERRUPTED:** Damage taken or player explicitly cancels. Progress
  preserved.
- **RESUMING:** Player returns to the same target; progress continues
  from where it stopped.
- **COMPLETE:** Resources awarded, target consumed.

Implementation belongs in Phase 3 (Resource Harvesting). The state
machine pattern is well-trodden; the tuning (animation timing, camera
behavior during work) needs manual feel-testing.
