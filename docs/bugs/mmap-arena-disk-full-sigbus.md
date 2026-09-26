# mmap arena: a full disk kills the process with SIGBUS

*Filed by Claude (agent), overnight 2026-09-26, split out of
`mmap-arena-no-mmap-fallback` (fixed in `16c977c`) while fixing it. Diagnosed from the code
and my understanding of Linux/btrfs behaviour. Not reproduced, and the btrfs claims were not tested here.*

**Status:** Open. Severity low-med. Needs Robert's call on policy (see Question).

## Symptom
Once the disk under the arena's temp file fills, the next write to an arena page that has no disk block
raises SIGBUS. Nothing catches it, so the process dies. The fault can land in any thread that touches a cell,
usually a `parallel_for` worker in the build.

## Cause
`MmapArena` (`engine/voxel_dc/dc_mmap_arena.h`) `ftruncate`s a sparse 384 GiB file and maps it `MAP_SHARED`.
Disk blocks are allocated in the page-fault path (`page_mkwrite`), and there ENOSPC can only surface as a
SIGBUS. The original note blamed filesystems without real sparse support. The more likely trigger is a
plain full disk, on any filesystem.

btrfs makes this worse, and Robert's `./tmp` is btrfs (`/mnt/nvme0n1p4`). The file is copy-on-write, so
rewriting a page that has already been written back needs new space too. A full disk can fault on
pages the arena has used before, not only on fresh growth.

## Why it wasn't fixed with the mmap-failure fallback
Reserving blocks ahead of growth (`posix_fallocate` in chunks from `push_back` / `resize_uninitialized`)
moves the failure out of the fault and into growth, where code can see it. That half is mechanical. It isn't
enough by itself, because:

1. **Growth has no failure path, and choosing one is a design call.** `alloc_cell` and the level-sync
   `resize_uninitialized` assume growth succeeds. There are two honest responses to a failed reservation:
   - **Migrate to RAM.** Convert the arena to anonymous memory in place: copy a chunk out, `mmap(MAP_FIXED
     | MAP_ANONYMOUS)` over it, copy it back. Addresses stay stable, and the file closes at the end. Then set
     `g_arena_anon_fallback`. For the pop-up to fire, `_check_arena_backing` (`scripts/dc/dc_world_preview.gd`)
     would have to keep checking instead of checking once. Refinement goes on with OOM risk.
   - **Stop refining.** Treat the reserved high-water as the arena's capacity, the way the cell budget is
     treated now. Every `alloc_cell` caller then needs a graceful stop. At the moment only the level-sync
     build checks `capacity()`.
2. **Reservation isn't a guarantee on copy-on-write filesystems.** On btrfs a preallocated block is only
   written in place the first time; later rewrites need new space. The guarantee would also need the
   file marked NOCOW (`FS_IOC_SETFLAGS` with `FS_NOCOW_FL`, set while the file is still empty, before
   `ftruncate`). ZFS has no equivalent. glibc emulates `posix_fallocate` there, and every rewrite is still
   copy-on-write. macOS has no `posix_fallocate` (`F_PREALLOCATE` works differently).
3. **The ENOSPC path can't be tested without a small filesystem to fill**, and a loop mount needs root. What
   a test can check is that the blocks are reserved: `st_blocks` covers the used bytes after growth.

A SIGBUS handler that remaps the faulting page to anonymous memory was considered and rejected. It would
fight Godot's crash handler, and on a copy-on-write rewrite it would have to copy data inside a signal
handler.

## Question for Robert
When the arena's disk fills, should terrain keep refining in RAM (with OOM risk and the existing warning
pop-up), or stop refining where it is? Either one needs the reservation work above. With stop-refining, the
arena never drops its disk backing.

## References
`engine/voxel_dc/dc_mmap_arena.h` `_ensure` / `_map_disk`; `engine/voxel_dc/dc_octree.h` `alloc_cell` and the
level-sync `capacity()` check.
