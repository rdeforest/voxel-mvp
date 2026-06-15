# docs/diagrams — Index

Visual maps of how the game's systems fit together — one diagram per file.
Each entry notes *why the doc exists*, not what it contains.

Diagrams are authored in [draw.io / diagrams.net](https://www.diagrams.net/):
each `.drawio` file is the editable source, and its companion `.md` page
holds the prose explanation. For an inline image, export an SVG from the
editor and embed it.

Companion to: `CLAUDE.md` (where code lives), [`../roadmap/design/architecture.md`](../roadmap/design/architecture.md)
(mechanism rationale), [`../roadmap/`](../roadmap/00_INDEX.md) (version strategy).

## Files

- [`system-data-flow.md`](system-data-flow.md) — explains the event-driven
  feedback loop by which a click becomes physics and physics becomes
  terrain again.
- `system-data-flow.drawio` — the editable draw.io source for the diagram
  above.

## Planned

Diagrams identified as worth authoring but not yet drawn:

- `pbd-solver-pipeline.md` — the per-tick PBD core (build → solve → force →
  fatigue → break → detach → collapse).
- `physics-concepts.md` — the Poly-Bridge ∪ World-of-Goo physics idea for a
  general audience.
- `lifecycles.md` — falling-body states, the world-ready gate, and the
  render-vs-collision terrain split.
- `class-diagram.md` — the classes we created plus the Godot / godot_voxel
  classes they talk to.
