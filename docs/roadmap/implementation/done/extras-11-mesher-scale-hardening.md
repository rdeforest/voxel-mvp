# Mesher scale-hardening (M2 follow-on)

## STATUS: DONE — the world-octree render survives the M-thesis scale (hundreds of millions of cells)

Running the `dcworld` render at `RENDER_SUBDIV_LOG2=4` (0.0625 m cells) with retention on
pushed the octree to **725M cells / 200 GB arena**. That exposed a cluster of crashes,
stalls, and a silent-fallback risk that M2 (the disk-paged cell arena) had uncovered but
not closed. This batch hardened the path so the big world is *usable* — not yet *fast*
under motion (that's c4, still pending — see
[design doc 20 §I](../../design/20-continuous-incremental-mesh.md)).

### What landed

- **Arena temp-file pop-up.** If `MmapArena` can't get a disk-backed temp file (no writable
  `$DC_ARENA_DIR` / `./tmp` / `/var/tmp`, or only tmpfs) it falls back to anonymous RAM and
  the OOM-killer is back in play. That must never be silent: the arena now tries real-disk
  dirs in order (skipping tmpfs via `statfs`), flags any fallback, and the game raises a modal
  `AcceptDialog`. `is_arena_disk_backed()` exposes the flag. (`dc_mmap_arena.h`,
  `dc_octree_mesher.*`, `dc_world_preview.gd`.)

- **Build cell-budget (the SIGILL fix).** `mesh_world` grew the arena level-by-level with **no
  budget** — only grow-refinement was gated by `max_cells`. A re-root into dense LOG2=4 terrain
  built past the arena's `1<<30` int-index cap and `resize_uninitialized` hard-aborted (M2 had
  turned the old OOM into this abort). The build now stops descending at `min(max_cells, arena
  cap)`, keeping the frontier as valid coarse leaves instead of crashing. `max_cells` is plumbed
  GDScript → `mesh_world` → `oct.cell_budget`; build and grow now honor one budget. (`dc_octree.h`,
  `dc_octree_mesher.*`, `dc_world_preview.gd`.)

- **Bounded move-grow (stop the unbounded climb).** Moves were unbudgeted *and* ungated, so
  walking refined each new band to the eps floor and retention kept all of it. Moves now always
  re-window (you can walk; eviction frees behind) but **budget** sub-floor refinement, cut to 0
  past `max_cells` — deferred work drains through the gated path. The world holds at the budget.
  (`dc_world_preview.gd`.)

- **Off-thread mesh pack (tier-2 lite).** `_finish` rebuilt the whole `ArrayMesh` and re-uploaded
  it every grow — the ~1 s main-thread stall. The pack now runs in `_run_job` on the worker
  (RenderingServer is a multithreaded command queue, no main-thread guard — verified); `_finish`
  is a cheap RID swap. Per-range partial GPU upload (3b) stays shelved unless the worker-side full
  repack bottlenecks. (`dc_world_preview.gd`.)

- **Telemetry off the main thread + two `_persist` races.** The RAM-resident `mincore` scan ran on
  the main thread (a hitch at hundreds of GB) and an over-strict idle guard pinned it at 0.0 while
  the world meshed continuously. It now computes in `_run_job` (the worker owns `_persist` that
  job) — cells/arena every job, RAM every 10th. Also closed a `_persist` use-after-free: `mesh_world`
  nulls `_persist` before freeing the old one, so the debug server (the other main-thread reader)
  reads null → 0, never a dangling pointer. (`dc_world_preview.gd`, `dc_octree_mesher.cpp`.)

### Verified

`tools/build` clean; editor parse check clean; DC suites green (`test_dc_world_octree` 15/15 +1
known-pending, `test_dc_octree_mesher` 10/10, `test_dc_real_terrain` 6/6). Off-thread `ArrayMesh`
build smoke-tested headless (real-GPU confirmation was Robert's live run). Live-confirmed by Robert:
RAM readout fixed, retention holds, re-root sheds + rebuilds with no surprises, no crashes.

### Not done (next)

- **c4 — incremental reconcile for moves.** A move still re-walks the whole retained tree
  (`reconcile` rebuilds the frontier; the distance-graded floor shifts candidates tree-wide). At
  725M cells that's ~3.8 s; flying over a mountain lags meshing ~10×. The asymptotic fix. See doc 20 §I.
- **Cell shrink — float QEF** (`sizeof(Cell)` 296 → ~190 B). A constant-factor win on footprint +
  grow-walk bandwidth that stacks with c4. Queued behind it. See doc 20 §I.

*`scripts/voxel_constants.gd` (`RENDER_SUBDIV_LOG2=4`) is Robert's local experiment — intentionally
uncommitted.*
