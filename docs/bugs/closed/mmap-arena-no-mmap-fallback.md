# mmap arena: crashes on mmap failure instead of falling back to anonymous memory

**Status:** **CLOSED — fixed** on `perf/preview-lattice-cpp` (chunk A3, overnight 2026-09-26). The related
SIGBUS note is split out, still open, as [mmap-arena-disk-full-sigbus](../mmap-arena-disk-full-sigbus.md).
Resolution section drafted by Claude (agent).

## Symptom
On a transient `mmap` failure of an otherwise-valid temp-file fd, the engine hard-crashes
(`CRASH_COND_MSG`) instead of using the anonymous-memory fallback that exists for exactly this case.

## Cause
`engine/voxel_dc/dc_mmap_arena.h:88-94`. The disk-backed path tries
`mmap(..., MAP_SHARED, fd, 0)`; if it returns `MAP_FAILED` it falls straight through to `CRASH_COND_MSG`
(`:94`). The anonymous fallback (`MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE`) is only taken when `fd < 0`
(temp file couldn't be opened) — not when a valid fd's `mmap` fails. So the documented "fallback if the
temp file is unavailable" design doesn't cover mmap-time failure.

Related, lower-priority: `ftruncate` to a large sparse size can succeed on a filesystem that doesn't truly
support sparse files, then later page-fault writes hit ENOSPC → SIGBUS, which isn't caught (`:57-63`).
*(Split out, open: [mmap-arena-disk-full-sigbus](../mmap-arena-disk-full-sigbus.md).)*

## Proposed fix
On `MAP_FAILED` from the disk path, fall back to the anonymous mapping instead of crashing (the fallback
block already exists — just route the mmap-failure case into it).

## Resolution
`_ensure` now tries each temp dir through `_map_disk(dir)`, which does mkstemp, unlink, ftruncate and the
`MAP_SHARED` mmap as one unit. Any failure closes that dir's fd (the file is already unlinked, so that is
the whole cleanup) and moves on to the next dir. Only when every dir fails does the arena take the anonymous
mapping and set `g_arena_anon_fallback`. So a mapping refused in `$DC_ARENA_DIR` can still land on disk in
`./tmp` or `/var/tmp`. `g_arena_dir` is now set only once a mapping succeeds.

The test is `test/test_dc_mmap_arena.gd`. A real mmap failure on a valid fd can't be triggered on demand,
so `dc_arena_disk_mmap` refuses the mapping when `DC_ARENA_FAIL_DISK_MMAP` names the dir being tried, or is
`*` (every dir). One test runs three stages in order, because `is_arena_disk_backed()` reads the sticky
process-wide `g_arena_anon_fallback`: a disk-backed control; `$DC_ARENA_DIR` refused, which must still end
disk-backed on the next dir; every dir refused, which must end anonymous with no fd leaked and a mesh
identical to the control. The fd check reads `/proc/self/fd` and pends where that doesn't exist.

Mutations run against it:
- The old control flow with the hook (its earlier all-dirs form) aborted with `MmapArena: mmap failed` (signal 4).
- Stopping the dir search after the first refused mapping failed the "moves on to the next disk dir" assert.
- The fix without `close(file)` leaked 12 fds over 3 calls (2 arenas x 2 dirs x 3), and the fd assert failed.

The knob is live in shipping builds, so a stray `DC_ARENA_FAIL_DISK_MMAP` turns disk paging off. The
existing "no disk paging" pop-up still fires, so it is not silent.

Precondition: `./tmp` or `/var/tmp` must be on a real disk. `./tmp` is gitignored and not created by any
tool; on a clean clone the arena uses `/var/tmp`, and the control fails only on a host whose `/var/tmp` is
tmpfs with no `DC_ARENA_DIR` set.

## References
`engine/voxel_dc/dc_mmap_arena.h` `_ensure`, `_map_disk`, `dc_arena_disk_mmap`.
