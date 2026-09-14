# mmap arena: crashes on mmap failure instead of falling back to anonymous memory

**Status:** Deferred (2026-06-22). Diagnosed by code review. Environment-dependent; rare.

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

## Proposed fix
On `MAP_FAILED` from the disk path, fall back to the anonymous mapping instead of crashing (the fallback
block already exists — just route the mmap-failure case into it).

## References
`engine/voxel_dc/dc_mmap_arena.h` `_ensure`.
