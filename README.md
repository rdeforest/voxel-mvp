# Voxel MVP

A voxel-first survival sandbox prototype. Proof of concept that a voxel engine,
built today with modern tools, delivers Valheim-style gameplay without the
compromises a heightmap engine forces — no loading screens for caves, no
floating buildings, real terrain modification, real overhangs.

## What this is

A tech demo answering the v0.0 question: *is voxel-first as good an idea as I
think it is?*

The thesis defense is a single playable scenario: dig a wide cave, watch the
ceiling cells strain in real time (blue → green → yellow → orange → red as the
unsupported span grows), and reinforce it with wooden beams before it
collapses. The structural-integrity algorithm that governs the cave ceiling
is the same algorithm that governs player-placed parts. One system, one set of
physical rules, one visual language — that's the architectural payoff.

What works in v0.0:

- Procedural double-precision voxel terrain (godot_voxel Transvoxel meshing)
- Terrain editing: dig, fill, flatten
- Part placement system with parametric dimensions (board, plank, stud, beam)
- Multi-axis 90° rotation
- Material variety (wood, stone, metal, dirt, sand) with material-dependent
  decay constants — wood pillars hold less than stone pillars, dirt fails fast
- Unified structural integrity: terrain and parts propagate support through
  the same propagation algorithm with the same material-decay rules
- Lazy expansion: support propagates through suspended mass column-by-column,
  terminated by material decay budget — natural caves develop strain gradients
  whose width depends on the rock's material properties
- Cave reinforcement via placed pillars: a wood beam in the cave shows up as a
  supporter for the ceiling cells above it, repairing the gradient
- Falling collapse: unsupported components become physics-driven RigidBody3Ds

What's deferred:

- See `docs/STATUS.md` for the deferred list. v0.0 is intentionally a tech
  demo, not a game — no biomes, resources, inventory, crafting, enemies, or
  survival loop yet.

## Build

Prerequisites: `git`, `scons`, `python3`, and a C/C++ compiler.

The Godot and godot_voxel repositories must exist as siblings of this project
at the paths in `tools/versions.env`. `tools/build` pins both repos to the
versions in that file and builds them with double-precision coordinates plus
the godot_voxel module:

```
tools/build              # build Godot + godot_voxel (idempotent, stamp-checked)
bin/godot --path . -e    # open this project in the editor
bin/godot --path .       # run the project
```

Re-running `tools/build` is fast when nothing has changed (the build step is
stamp-checked).

## Controls

| Key                          | Action                                      |
|------------------------------|---------------------------------------------|
| WASD                         | Move                                        |
| Space                        | Jump                                        |
| Mouse                        | Look                                        |
| Left click                   | Apply the current edit mode at the cursor   |
| Right click (window focused) | Re-capture mouse if released                |
| TAB                          | Cycle edit mode (Dig, Fill, Flatten, Build, Remove) |
| Q                            | Quit                                        |
| F                            | Toggle wireframe rendering                  |
| V                            | Toggle structural-integrity debug cubes     |
| **In Build mode**            |                                             |
| `[` / `]`                    | Cycle Part shape (board / plank / stud / beam) |
| M                            | Cycle Part material (wood / stone / metal / dirt / sand) |
| R                            | Rotate around Y axis (yaw)                  |
| T                            | Rotate around X axis (pitch)                |
| Y                            | Rotate around Z axis (roll)                 |

The HUD label shows the current mode and, in Build mode, the selected
part shape and material as `Build: <part> (<material>)`.

## Architecture

The thesis architecture and implementation notes live in three documents:

- `docs/roadmap.md` — version strategy, phase definitions, and the elevator
  pitch / competitive context.
- `docs/STATUS.md` — current state, what's working, what's deferred, what's
  architecturally locked in.
- `CLAUDE.md` — system-by-system implementation notes, written as a brief for
  contributors (human or AI).

If you're poking at the code, start with `scripts/structural_integrity.gd` —
that's where the central thesis lives.

## License

This project is dual-licensed:

- **Software** — MIT License (see `LICENSE-MIT`). Source code, shaders, and the
  Godot project/scene/resource files.
- **Original documentation and art** — CC BY-SA 4.0 (see `LICENSE-CC-BY-SA`).
  The `docs/` prose, design documents, and project-authored art.

`LICENSE` defines exactly which files fall on each side. The split follows
Creative Commons' own guidance that software should carry a software license
rather than a CC one.

### Third-party dependencies

- **Godot Engine** — MIT License — <https://github.com/godotengine/godot>
- **godot_voxel** (Zylann) — MIT License — <https://github.com/Zylann/godot_voxel>
- **GUT** and **Limbo Console** — MIT License — vendored under `addons/`

These retain their original licenses; nothing in this project's licensing
affects them.
