# Network Transition

*The one-shot migration plan. The permanent spec is at
[`../design/05-network-architecture.md`](../design/05-network-architecture.md).
When this work lands, this chapter becomes history.*

## When this happens

v0.9, gated by the multiplayer commitment (FEAT064).

There is no urgency on the network architecture; single-player work
through v0.5/v0.2 doesn't need any of it. But the seeds are already
planted in v0.1: every event payload carries `grid_id`, and the
deferred action-journal/replay model from v0.1 is the same primitive
the network layer needs.

## Why this is a separate chapter from the design doc

The design doc says what the answer is. This doc says how the
transition happens — what to build, in what order, with what success
criteria for each step. The design doc is forward-looking permanently;
this doc expires when the work lands.

## Granular, scope-isolated bites

Each can be picked up cold without holding the rest in your head.

- [ ] **Read Willow's range-based set reconciliation** spec. Pure
  learning, no code. The reconnection-delta-sync mechanism we'd adapt.
- [ ] **Op record format.** Define a signed brush-stroke op: author
  key, Lamport stamp, brush shape ref, position, rotation, add/
  subtract. Serialization only. (Aligns with the deferred v0.1 action-
  journal/replay model.)
- [ ] **Local op-log + replay.** Single-peer: append ops, replay
  deterministically into the field. No networking yet. Success =
  replay reproduces the world. (This is also the v0.0.1 replay
  harness that
  [`code-cleanup-plan.md`](../../code-cleanup-plan.md) step #4 was
  waiting on.)
- [ ] **Version-vector bookkeeping.** Track per-peer counters; given
  two vectors, compute the missing-op delta. Unit-testable offline
  with fake peers.
- [ ] **Two-peer sync over a socket.** Exchange deltas, merge,
  converge. The first actually-distributed milestone.
- [ ] **Membership op-log.** "Key X vouches for key Y," unanimity
  check, fork semantics. Depends on op format + identity keys.
- [ ] **Regional physics authority (design first, code later).** How a
  live sim coexists with the CRDT geometry; recompute-vs-authority
  boundary. This is the deepest open question; needs more thought
  before code.

## When this lands

- Mechanism rationale graduates into `../../architecture.md`.
- Decisions added to
  [`../design/02-architectural-commitments.md`](../design/02-architectural-commitments.md).
- This chapter becomes a historical record.
