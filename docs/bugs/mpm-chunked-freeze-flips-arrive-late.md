# A chunked MPM freeze announces its flips after later writes

*Filed by Claude (agent), overnight 2026-09-27 (Track F3), while fixing `mpm-freeze-flips-unmeasured`.
Reproduced by a GUT test, which stays pending while the bug reproduces.*

**Status:** Open. Severity low: it needs a freeze region over `SINGLE_EMIT_MAX` (24 m), and none of
the measured freezes reach that (the largest bench freeze is dim 19). The design call is Claude's
and needs Robert's review.

## Symptom
`test_mpm_freeze_flips.gd`, `test_a_part_placed_before_a_chunked_freeze_is_announced_keeps_its_cell`:
1. A chunked freeze empties a cell X, a sub-metre sliver its 1 m rewrite flattens.
2. Before X's chunk is announced, a part is placed on X. X is solid, and PartIndex records the part.
3. X's chunk is announced with its air flip, and PartIndex releases X. The part's record is gone,
   but its cell is still solid.

## Mechanism
`MpmStructure._freeze` writes the whole region at once. `_queue_freeze_chunks` then announces it as
`CHUNK`³ boxes, `CHUNKS_PER_FRAME` per frame (14 frames for a 36 m region), and each chunk's event
carries the flips inside its box (doc 12, "The freeze (as built)"). A flip is true of the store only
until the next write. Any write in that window is announced before the chunks still waiting, so
subscribers apply the freeze's flips after the later write's.

- **TerrainSupport** recovers from a stale solid flip: it registers a cell that is air now, and the
  same event's box scan drops it. This is why the scan's "tracked cell gone air" branch stays. It
  only partly recovers from a stale air flip. A later write refilled the cell X and was announced
  first, so X is tracked with its real material; the late air flip then removes X's record. The scan
  re-registers X only if X has an air neighbour, and then as `Stone`. An interior X stays untracked,
  and an exposed one takes the wrong material. (From the code, `terrain_support.gd`
  `_on_matter_changed` then `_scan_box`; no test reproduces it yet.)
- **PartIndex** does not recover. A stale air flip releases a cell a newer part owns.
- **DetachmentScout** checks solidity before it seeds, so a stale flip costs one wasted check. The
  scout waits only for `active_count() == 0`, not `is_idle()`, so its own thaw can run inside the
  window.

Before this chunk, the freeze carried no flips at all. PartIndex never heard it, which was worse.

## Fix options (the call is Robert's)
1. **Announce every flip at the write.** Put all the flips on the first chunk's event, or on a
   flips-only event with an empty box. Timing is then exact. Each chunk event no longer means "a
   box and the flips inside it", and the DC render's box union would take in an empty box.
2. **Flush before any later announcement.** `TerrainSdfChangedEvent.announce` would first emit any
   freeze chunks still pending, so events arrive in write order. That is a global ordering hook on
   the event class. When a write lands mid-freeze, the rest of the freeze's scan work falls into one
   frame.
3. **Drop the chunking.** `DcWorldPreview` already combines a frame's edit boxes into one
   asynchronous `edit_world`, so chunking now only bounds TerrainSupport's per-frame box scan. That
   bound may not need the delay. Measure a 36 m freeze's scan in one frame first.
