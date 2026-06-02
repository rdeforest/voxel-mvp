# Phase 4: Inventory & Crafting

**Goal:** Manage items, craft new ones at stations.
**Version target:** 0.1
**Status:** Pending.

## Tasks

- **FEAT015**: Grid-based inventory UI with drag-and-drop, stack
  splitting.
- **FEAT016**: Equipment slots (weapon, tool — minimal).
- **FEAT017**: Hotbar with number-key switching.
- **FEAT018**: Crafting recipe data model (inputs → output + station
  requirement).
- **FEAT019**: Placeable stations — workbench, forge, cooking fire.
- **FEAT020**: Station UI — available recipes filtered by station
  type.
- **FEAT021**: Recipe discovery — all visible, greyed until you have
  materials.
- **FEAT022**: 3-tier progression — hand-craft basics → workbench
  tools → forge metals.
- **FEAT023**: Item tooltips.
- **FEAT024**: Building material tiers — wood → stone → iron-
  reinforced parts.

## Key decisions

- **Data-driven recipes** (JSON or Godot Resources). Modding-friendly
  from day one.
- **3 crafting tiers max** for v0.1. Don't go deeper or you'll spend
  weeks on balance.

## Risk

UI polish time sink. Functional but ugly is fine for v0.1. Colored
rectangles with text labels.

## Done when

Open inventory, see gathered wood/stone, walk to workbench, craft
pickaxe, equip it, mine faster than bare hands.
