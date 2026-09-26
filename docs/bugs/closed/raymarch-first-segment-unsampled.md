# `TerrainRaymarch` leaves the first `[0, step)` segment unsampled

**Status:** **CLOSED — not a bug** (2026-09-26). Split out of `misc-low-severity` (item 3) to close it.
The header comment that invited the report was reworded. A test pins the verdict.

*Closing note drafted by Claude (agent), 2026-09-26 overnight session. Robert has not reviewed it.*

## The report (code review 2026-06-22)

`TerrainRaymarch.surface` starts its march at `t = step`, so the report said a thin solid sliver
within `step` (0.2 m) of the camera is stepped over. That seemed to contradict the header's
"a sub-metre feature is never stepped over".

## Why it's not a bug

The first segment is sampled like every other one, at both ends. Its near end is `t = 0`, the
origin, which `surface` tests first (and returns a miss if the origin is solid). Its far end is
`t = step`. A segment `[k*step, (k+1)*step]` anywhere else on the ray has the same two samples. So a
sliver thinner than `step` can be missed on any segment, and the first one is not special.
Solid at least `step` thick along the ray always contains a sample, including within the first step.

The real inaccuracy was the header: "a sub-metre feature is never stepped over" holds only for
features at least `step` thick. The header now says that (`scripts/terrain_raymarch.gd`).
`test_surface_within_the_first_step_is_hit` (`test/test_terrain_raymarch.gd`) aims from half a step
above the terrain and hits it inside the first segment. It passes on the old code too. It pins the
verdict; it doesn't test a fix.
