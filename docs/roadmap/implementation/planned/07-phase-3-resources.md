# Phase 3: Resource Harvesting

**Goal:** Chop trees, mine rocks, gather materials.
**Version target:** 0.1
**Status:** Pending.

Spec for the continuous-work-action UX at
[`../../design/08-continuous-work-actions.md`](../../design/08-continuous-work-actions.md).

## Tasks

- **FEAT008**: Destructible resource nodes — trees, rocks, ore
  deposits, bushes.
- **FEAT009**: Continuous work actions — state machine
  (IDLE → TARGETING → WORKING → INTERRUPTED → RESUMING), progress bar,
  speed depends on tool/material.
- **FEAT010**: Directional tree felling — notch cut, choose fall
  direction; tree falling physics.
- **FEAT011**: Resource drops as collectible items.
- **FEAT012**: Item data model — ID, name, icon, stack size, category,
  weight.
- **FEAT013**: Voxel material types for ore (copper voxel → drops
  copper when mined).
- **FEAT014**: Interaction system — raycast → detect → prompt →
  execute.

## Key decisions

- **Continuous actions** are a significant UX improvement over
  Valheim's click-spam. State machine implementation is well-trodden;
  the tuning (animation timing, camera behavior during work) needs
  manual feel-testing.
- **Directional tree felling** is a real woodcutting technique. More
  realistic and more engaging than "hit tree, tree falls randomly."
- **Voxel material types:** godot_voxel supports material IDs per
  voxel. Ore IS the terrain.

## Risk

Tree physics jank. Keep collision simple, despawn after a few seconds.

## Done when

You can select a tree, choose where it falls, watch your avatar work,
pick up wood. Mine a rock face by specifying depth, get stone and
copper ore. Get interrupted by a creature, fight it, then resume
mining where you left off.
