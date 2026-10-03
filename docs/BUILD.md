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

## After a pull

```
git pull
tools/build
```

That is the whole ritual, including after switching between machines. Besides
the engine, `tools/build` refreshes Godot's global-class registry every run
(a few seconds) and checks that every `class_name` in the project ended up in it.

The registry lives in `.godot/global_script_class_cache.cfg`, which is
untracked local state, so a `class_name` added on the other machine is invisible
here until an editor pass rewrites it. A stale cache looks like broken code: the
game starts with no world and a wall of `Could not find type "…"` parse errors,
and GUT reports `Invalid call. Nonexistent function 'new' in base 'GDScript'`
and silently drops test files it can't resolve.

The pass writes `.godot/`, so `tools/build` refuses to run it while an editor
GUI is open on this engine binary (see the clobber section below). Close the
editor and re-run. By hand, the same pass is
`bin/godot --path . --headless --editor --quit`.

*Section drafted by Claude.*


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

Concurrent runs on one machine, in one checkout or several, are safe: every test file lives under
the run's own `user://test_runs/<pid>/`, and the game's save and recording roots are pointed there
too, so no run touches another's files or the player's saves (`test/support/run_paths.gd`, wired
in by the hooks in `.gutconfig.json`; drafted by Claude). A run's start sweeps out the directories
of runs whose pid is gone, so runs sharing `user://` from another host or pid namespace would be
swept.

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

- **Class-cache regen** (`bin/godot --headless --editor --quit`, which `tools/build`
  runs every time) writes `.godot/`. Run it only with the GUI closed; `tools/build`
  refuses to run it while an editor is open.
