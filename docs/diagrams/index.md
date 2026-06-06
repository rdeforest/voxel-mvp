# Diagrams

Visual maps of how the game's systems fit together — one diagram per file.
Authored in [draw.io / diagrams.net](https://www.diagrams.net/): each `.drawio`
file is the editable source (install the *Draw.io Integration* VS Code extension
for drag-and-drop). For an inline image in a `.md` page, *Save As* `…​.drawio.svg`
or export an SVG from the editor and embed it.

Companion to: `CLAUDE.md` (where code lives), `docs/architecture.md` (mechanism
rationale), `docs/roadmap` (version strategy).

## Index

| Diagram | What it shows | Audience |
|---------|---------------|----------|
| [System data-flow](system-data-flow.md) | How a click becomes physics and physics becomes terrain again — the event-driven feedback loop across actions, tracking, PBD, collapse, and rendering. | You · devs |

### Planned

- **PBD solver pipeline** — the per-tick core: build → XPBD solve → axial force → fatigue → break → detachment → collapse, with sleeping as the perf gate.
- **Conceptual physics** — the Poly-Bridge ∪ World-of-Goo idea for a general audience: tension/compression, force-based breakage, fatigue grace, specific tensile strength, emergent anchors/suspension.
- **Lifecycles + rendering** — falling-body states, the world-ready gate, save/quiescence; and the DC-render vs per-block-collision terrain split.
