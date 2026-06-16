# Distant shadow shimmer when panning (CSM)

**Status:** Deferred to polish. Cosmetic.

## Symptom
Far-terrain shadows shift/shimmer when the camera pans.

## Cause
Cascaded shadow maps (CSM) — the distant cascade re-samples as the view moves, so shadow texels crawl. A
standard CSM artifact, not a terrain/mesher issue.

## Fix
Shadow-pass polish: stabilize the cascades (snap the light frustum to texel increments), tune cascade
splits/distances, or limit far-shadow detail. v0.2 art/polish pass.

## References
[[distant-shadow-shimmer]] (memory).
