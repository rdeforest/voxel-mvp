# EditStore: a loaded blob's inherited corners aren't checked against their source

*Filed by Claude (agent) on 2026-09-27 (overnight Track F, chunk F2), from a reviewer's question on
`EditStore.leaf_info` and a code read.*

**Status:** Open, latent. Severity low: no code writes such a blob; it takes a corrupt or hand-made
save.

## Symptom
An INHERITED_FIELD leaf keeps its own float32 corners (`_subdivide` stores
`_held_corner(source, ...)`), and two paths read the leaf differently:
- `sample()` (so the mesher and the probe's corner lines) and the dry run recompute from the
  FIELD_SOURCE's trilerp.
- `stamp` combines against the stored `n.corners`, and `leaf_info` reports them.

In memory the two always agree: a FIELD_SOURCE is internal, so nothing rewrites its corners after the
children are made. A loaded blob is not held to that. `_read_node` checks only that each corner is
finite, and `_link_sources` relinks `source` without comparing the stored inherited corners with
`_held_corner`. A blob where they differ loads, then renders one field and stamps against another.
The probe would show it (its corner lines read the source, `leaf_info` the stored corners), nothing
else would.

## Where
`edit_store_serialize.cpp`: `_read_node`, `_link_sources`.

## Fix
In `_link_sources` (or a pass after it), refuse a blob whose INHERITED leaf's corner `j` isn't
exactly `float(trilerp(source.corners, ...))` at that corner, the same rule `_subdivide` uses.
Needs the source's corners from the blob's node list (the check runs before the nodes are
committed).
