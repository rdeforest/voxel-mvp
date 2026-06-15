# Architecture: Mechanism Rationale

This doc captures the *why* behind subtle mechanism choices in the structural
integrity and collapse detection systems — the kind of rationale that used to
live as paragraph comments inline in the code.

What lives where:

| Doc                                                | Scope                                       |
|----------------------------------------------------|---------------------------------------------|
| `CLAUDE.md`                                        | Where code lives, how to use it             |
| `roadmap.md` → Architectural Commitments           | Design-level decisions worth not relitigating |
| `docs/roadmap/design/architecture.md` (this file)  | Mechanism rationale: how the gears mesh     |

If a piece of reasoning fits in one of the first two, it should live there.
This doc is for everything else — invariants, asymmetries, sequence
decisions, and "you might want to do X, here's why we didn't" notes.

---

## Structural Integrity

### Two parallel support systems

Terrain voxels (`voxel_data`) and placed Parts (`part_registry`) run
different propagation algorithms.

- **Terrain:** worklist fixpoint over a dirty queue. BFS-order because
  support changes ripple outward from their origin; budget-bounded per
  frame so a large change stretches across multiple frames rather than
  hitching the main thread.
- **Parts:** sort-bottom-up by `placement_y`, then one pass. Cheap
  because parts only depend on parts strictly below themselves — no
  fixpoint needed. Recomputed fresh every frame.

The two systems share `_cell_to_part` so terrain propagation can see
parts as supporters and vice versa.

### Natural terrain = untracked AND bedrock

A solid SDF cell is "natural terrain" — and therefore an unconditional
FULL_SUPPORT source — only if **both**:

1. It's not in `voxel_data` (untracked).
2. Its column has no registered cell below it (bedrock-by-column-definition).

Without the bedrock check, a cell directly below a cave would claim
FULL_SUPPORT just because its SDF is negative. Suspended mass isn't
bedrock no matter how solid it looks locally.

### Lazy expansion: where the cascade stops

When propagation reaches an untracked-solid non-bedrock neighbour, it
gets lazy-registered with material STONE so the algorithm can compute
its actual support. Lazy registration is gated on the current cell's
support being above `FALL_THRESHOLD` — cells already at zero won't seed
a chain worth extending.

The cascade depth is therefore bounded by the material's decay budget
(~20 cells for STONE). The chain terminates naturally where support
reaches zero, which is also where the values stop being meaningful.

### Per-cell stack of parts

`_cell_to_part: Dictionary[Vector3i, Array[Node3D]]` is a stack, not a
single value, because multiple thin parts can share one voxel cell
(0.15m beam on top of a 0.012m board, both inside a 1m³ cell). The
array is ordered by `placement_y`; `_direct_part_supporter` walks the
stack to find the part with the highest `placement_y` below a query.

### In-limbo semantics

A part is `in_limbo` when any of its support dependencies — a supporter
Part still in-limbo, or a terrain voxel still dirty — hasn't settled.
Strain accumulation pauses while in-limbo so a transient zero during
propagation doesn't start a 3-second countdown that would have resolved
before expiry.

Without this, every dig near a part triggers spurious collapse timers.

### Tall part support

Multi-cell-Y parts (a beam rotated onto its end) only check support
from the bottom row of footprint cells. Upper rows are part of the
part's own body, not supported surfaces.

### Strain feedback on emission, not albedo

`_apply_part_visual` puts the strain color on the material's
`emission`, not `albedo_color`. This keeps the part's natural surface
colour (and, later, its texture) visible underneath the strain glow.
Replacing albedo would erase the material identity.

---

## Collapse Detection

### Lifecycle

A voxel becomes a *fall candidate* when its support decays to (effectively)
zero. The detector flood-fills connected components of fall candidates,
then files each as a *pending collapse* with a strain countdown
(`VoxelConstants.STRAIN_DURATION_SEC`).

During the strain window, one of three things happens:

1. The player adds support and `voxel_support_increased` fires for a
   voxel in the component → rewind the timer (see *Strain rewind*).
2. The component recovers enough that no voxel is still a fall
   candidate → cancel the pending collapse, return its voxels to
   ordinary tracked status.
3. The timer expires while still falling → materialize a falling
   `RigidBody3D` and carve the cells out of the SDF.

This is the cave-reinforcement loop: the structure creaks, the player
scrambles, the structure is either saved or lost.

### Strain accumulates against `delta`, not wall-clock

`pc.strained += delta` deliberately does NOT use
`Time.get_ticks_msec()`. Wall-clock time keeps running while the game
is paused, which would expire strain windows during a pause.
Accumulating `delta` inside `_physics_process` is automatically:

- **Pause-correct:** physics processing stops when the tree is paused.
- **Frame-hitch-correct:** `delta` is the true step length.

### Seed-conservative, expand-permissive

There are two predicates for "is this a fall candidate?":

- **`_can_seed_collapse`:** requires `not dirty`. We won't *start* a
  flood from a voxel whose support is still settling — it might be on
  its way back up.
- **`_is_fall_candidate`:** permissive. A voxel whose support is at or
  below the threshold belongs to the unsupported component whether or
  not propagation has fully settled its value.

The asymmetry matters. The earlier code used a single strict predicate;
that artificially split components mid-cascade — a large structure
would flood only its already-settled part, strand its still-settling
(often most-unsupported) voxels, and those would never pulse or fall.
Optimistically flooding a dirty voxel that later recovers is safe: the
strain window is the grace period, and
`_component_still_falling` re-checks every voxel through the permissive
predicate each tick.

### Strain rewind, not reset

When `voxel_support_increased` fires on a voxel in a pending collapse:

    pc.strained = minf(pc.strained, STRAIN_DURATION - STRAIN_RESET)

The `min()` means adding support can only ever *help* — it never
advances strain on a component that was already fresher than the reset
floor. Concretely with a 3.0s window and 2.7s reset: a component that
has strained 2.5s rewinds to 0.3s (2.7s remaining). One that has only
strained 0.1s is left alone (already has 2.9s remaining).

### The `voxel_support_increased` signal

Fired synchronously from inside the propagation loop whenever a voxel's
recalculated support is meaningfully higher than its previous value.
`CollapseDetector._on_voxel_support_increased` is the handler — and the
only thing that triggers a strain rewind.

Synchronous is intentional: rewinding strain mid-propagation is fine,
and a queued handler would have to remember which voxels rewound this
frame.

### Materialization

When a pending collapse expires:

1. Compute the component's centroid (in world coordinates, voxel-centered).
2. Greedy-merge the voxel set into axis-aligned boxes.
3. Build a `RigidBody3D` at the centroid, one collider + mesh per box,
   `can_sleep = false` so it doesn't fall asleep mid-air.
4. Carve the cells out of the SDF.

Carving dirties tracked neighbours; their recomputation will
lazy-register any newly-exposed untracked solids, propagating into the
fresh cave wall.

### Greedy box merge

Scan voxels in stable (y, z, x) order. For each unconsumed start cell,
grow in +X as far as possible, then +Z requiring the full X-strip,
then +Y requiring the full X×Z slab. Mark consumed; emit box; continue.

Not optimal, but produces a small number of boxes for slab-shaped
masses (which is what most collapses produce: a ceiling chunk falls
flat). Deterministic because of the stable sort.

### Known limit: flood detection lag

`_resume_unfinished_floods` advances each pending flood by one
`DETECTION_BUDGET` slice per `step()`, and `step()` only runs on frames
where the propagation dirty queue is empty. A connected component
larger than `DETECTION_BUDGET` therefore takes multiple settled frames
to fully detect. A continuous stream of edits that keeps the dirty
queue busy can starve phase-1 entirely.

Not a correctness bug — detection just lags. Fix path: budget profiling
to find a realistic worst-case component size, then either lift the
budget or advance multiple floods per `step()`. Deferred until there
are real numbers to tune against.

---

## Cross-references

- **CLAUDE.md → Architecture** — where each script lives, public API
  surface for the player.
- **roadmap.md → Architectural Commitments** — design-level
  commitments worth not re-litigating (Action-as-data, refuse-don't-
  deform, FIFO queue choice, etc.).
- **roadmap.md → Phase 5** — the v0.0 thesis claim and the cave-
  integrity demo this whole subsystem exists to support.
