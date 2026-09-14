# Build and Run

> Canonical build, run and test instructions. `README.md` and `CLAUDE.md` both
> point here rather than restating this.

## Prerequisites

`git`, `scons`, `python3`, and a C/C++ compiler.

The Godot and godot_voxel repositories must exist as siblings of this project
at the paths in `tools/versions.env`.

## Build

```
tools/build            # build Godot + godot_voxel (idempotent, stamp-checked)
bin/godot              # launch the built editor/game (pass Godot args directly)
bin/godot --path . -e  # open this project in the editor
bin/godot --path .     # run the project
```

`tools/build` pins both repos to `tools/versions.env` (Godot `89cea1439` =
4.6-stable, godot_voxel `v1.6`), wires the `godot/modules/voxel` symlink, and
skips the SCons build when the stamp matches. Re-running it is fast when
nothing has changed.

**`precision=double` is not optional** — it's compiled into the engine binary
for planet-scale coordinates.

**godot_voxel must be at `modules/voxel` exactly.** The module folder name is
derived from the directory; `custom_modules=` breaks symbol registration. The
symlink is the only supported path.

## Tests (GUT)

```
bin/godot --path . --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/
```

A single file:

```
bin/godot --path . --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/ \
  -gselect=test_gut_example.gd
```

Tests can also be run interactively from the GUT panel inside the editor.

## The editor ↔ external-edit clobber

The Godot **editor GUI** and external edits (VS Code, an agent, the CLI) both
write project files, and **the editor wins on save**. It re-saves any `.tscn` it
has open, silently reverting external `.tscn` edits; it regenerates
`.import`/`.uid`/`.godot/`; it pops "files changed on disk" dialogs.

This has already cost a play session: a `generate_collisions = false` edit was
eaten, producing double collision and a phantom "targeting bug."

Protocol:

- **Keep the editor GUI closed during co-dev.** Run and test via VS Code's
  godot-tools debug (F5, `--remote-debug`, output in the Debug Console) or
  `bin/godot --path .`. Neither needs the GUI.

- **Open the editor GUI only for deliberate visual scene work**, as an isolated
  mode switch: commit or stash pending changes first; when done, close it and
  reload any externally-changed files. Don't leave it open in the background.

- **Prefer code over `.tscn`** for settings set externally.
  `generate_collisions` is set in `world._enter_tree`, not in the scene. `.gd`
  files are edited outside the editor's save path, so they don't collide.

- **Class-cache regen** (`bin/godot --headless --editor --quit`, needed after
  adding a `class_name`) writes `.godot/` — run it only with the GUI closed.
