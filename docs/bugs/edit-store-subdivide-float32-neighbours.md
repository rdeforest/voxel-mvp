# A write nudges samples just outside its region when it subdivides a coarser leaf

*Filed by Claude (agent), overnight 2026-09-26, from a measurement made while closing Track G2
(`71236e1`, `EditStore.write_region_flips`).*

**Status:** Open. Severity low (latent). No sign flip has been seen.

## Symptom
`write_region` subdivides edited leaves that are coarser than the write cell and straddle the
region. The children outside the region get their corners re-stored at float32, which moves
samples outside the measured set by up to about 1.2e-7. As a result, neither the measured flips
(the old GDScript measurement or the new C++ one) nor `changed` strictly covers everything a write
touched, and a write that changes nothing inside its region still reports `changed = true`.

## Why it's latent
1.2e-7 can flip a cell only when that cell's centre is already within 1.2e-7 of zero. None was
seen in the G2 measurements. A flip it missed would be a cell that changes solidity with no event.

## Options
- Make `_subdivide` leave untouched children bit-exact, so a write outside its region is a strict no-op.
- Or measure each subdivided leaf's full footprint, not just the region.

The first removes the cause. The second only reports it.
