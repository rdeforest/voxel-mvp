# Network Architecture: Decentralized, Op-Log Replicated World

*The spec. For the one-shot transition / build sequence, see
[`../implementation/15-network-transition.md`](../implementation/15-network-transition.md).*

> Far-horizon work (v0.9+ territory). Does NOT block single-player
> development. Captured now so the reasoning isn't lost. The v0.1
> persistence already carries `grid_id` in payloads and deferred an
> action-journal/replay model — both of which this design builds on.

## The goal (in Robert's words)

Entirely decentralized. If I fire up the game, my friend connects to my
world, I log off — my friend continues without me. When I reconnect, I
get all their updates. No node is *the* server; any peer can be offline
arbitrarily long and rejoin.

## The reframe that makes it tractable

This is **not** a peer-to-peer *game* in the usual sense (lockstep sims,
host migration, rollback). It's a **distributed replicated datastore
that happens to be a world.** The canonical references are the **local-
first / CRDT / Git merge** lineage — specifically the **Earthstar /
Willow** protocol family. The local-first playbook applies to a voxel
field; the hard problems are already named.

## Core model: the world is a LOG, not a state

Stop thinking "current state we synchronize"; think "**a history of
edits each peer accumulates.**" This is the Git mental model almost
exactly:

- Each peer has a full local replica (or working subset).
- Edits are commits — content-addressed, parent-linked, **signed by
  author**.
- "Connecting to your world" = fetch your commit DAG, replay/merge
  onto theirs.
- "Log off, reconnect" = each side committed independently; on
  reconnect exchange the commits the other lacks and merge.
  (= `git pull` after both committed offline.)

Decentralization requirement is satisfied at the **data layer**, not
the netcode layer.

## Why CRDTs — and why the voxel field makes this EASIER than chat

CRDTs (Conflict-free Replicated Data Types) merge concurrent edits
deterministically with no coordinator; every replica that has seen the
same set of edits converges regardless of order (commutativity). That
commutativity is what lets two offline peers reconcile without a
referee.

The lucky part: **our world is spatial and grid-indexed**, which
sidesteps the hardest CRDT problem (ordered sequences, à la
collaborative text — "where does this inserted char go"). Our edits are
keyed to **positions in space** (octree cells / field samples at
coordinates). Edits to *different* cells don't conflict — they both
apply. Spatial locality means the overwhelming majority of concurrent
edits are non-overlapping and merge trivially. The conflict surface is
tiny vs. text.

Data model wants to be: **a map from cell-coordinate → field value, as
a CRDT map**, where each cell's value is a register resolving concurrent
writes. The world is a giant key-value CRDT keyed by spatial coordinate.

## Replication unit: OPERATIONS, not values **[DECISION TAKEN]**

**Op-based replication**: store **"imprint this log-shape at this
position at this time"** — the *brush stroke* (cf. Cepero's imprinting
model, see [the geometry chapter](03-dc-qef-geometry.md) §4) — as the
replicated unit, NOT "cell X = solid."

- Operations preserve **intent** on merge: the whole log appears or
  doesn't, rather than fragmenting into half-doorway/half-wall (the
  failure mode of naive per-cell last-writer-wins).
- Op-based CRDTs need a **deterministic replay order** because SDF ops
  don't perfectly commute (imprint-then-carve ≠ carve-then-imprint
  where they overlap). The logical clock provides that order. LWW is
  the tiebreaker for genuinely concurrent same-cell ops.

Conflict policy is **not a major concern** because game networks are
**invite-only** — players handle conflicts out-of-game (socially).
There's no in-game conflict resolution.

## Time: logical clocks, never wall-clock

Wall-clock timestamps can't order edits across machines (drift; "later"
is meaningless after offline periods). Use:
- **Lamport timestamps** — a counter advancing past any seen timestamp;
  total order consistent with causality. Good for the replay order.
- **Vector clocks / version vectors** — per-peer counters that detect
  *true concurrency* ("these edits had no knowledge of each other") vs.
  causal order. This directly answers the reconnection question:
  compare version vectors, exchange exactly the missing edits —
  efficient delta sync, no resending the whole world.

This is precisely the **Willow** model (range-based set reconciliation
of exactly-the-missing-pieces over spatial/path keys) — the closest
existing thing to what we want. **Read Willow before building this
part.**

(Note the parallel with shipped code: `architecture.md` already
documents why collapse strain accumulates against `delta`, not
`Time.get_ticks_msec()` — wall-clock is the wrong clock there too. Same
instinct, different layer.)

## Identity, trust, membership **[DECISIONS TAKEN]**

Internet-style: **public-key identity.** Each peer has a keypair; each
edit is signed. "Your world" = the world rooted at your public key,
with write access granted to others. Gives tamper-evidence,
authorization, content-addressed signed log (≈ Secure Scuttlebutt /
Earthstar author model).

Decisions:
- **Start simple:** out-of-band identity exchange to confirm an
  invitee, then **treat all peers identically.** Once invited, Alice
  can destroy everything — recovery is: restore from a **template/
  snapshot captured before inviting her.** Fine-grained per-region
  controls are a *future* want and **do not depend on decisions made
  now.**
- **Abuse: take it outside.** Anyone can detach from the network. A
  group can **force-detach** one person by all agreeing to join a new
  network and not telling them. Adults, who knew each other in
  advance, hashing it out IRL. Not a problem this game is meant to
  solve.
- **Invites require unanimous approval of existing members.** Only the
  **sponsor** must identify the invitee (out-of-band); others with
  questions go to the sponsor. **Why unanimity, in data-structure
  terms:** membership = "whose logs do I merge?" If invites are
  unanimous, every peer's merge set is identical → everyone converges.
  If NOT unanimous, the network **silently forks** (Alice+Bob see
  Bob's barn, Carol doesn't, neither is "wrong"). The authorized-key
  set is *shared state* and needs the same agreement discipline as any
  other shared state. Sponsor delegates *trust* (identity check), not
  *consent* (the group's agreement).

> **Seed planted:** the membership set is itself edits — "I, key X,
> vouch for key Y," signed. Membership is just another op-log. "Force-
> detach by all rejoining a new network" = fork the membership log
> without one key. The social abuse-handling is already expressible in
> the same primitive.

## Deferred / kicked down the road **[DECISION TAKEN]**

- **Storage growth / compaction.** If every peer keeps the full log
  forever, replicas grow unbounded; a long-lived world becomes a huge
  first-join sync. Git solves with shallow clones + gc/squash; we'll
  want **checkpoint/compaction** (snapshot merged field state, fetch
  "snapshot + recent ops"). Designing decentralized compaction (whose
  snapshot is canonical?) is non-trivial. **Explicitly deferred — safe
  to kick down the road for now.**

## The deepest tension: physics is NOT a CRDT **[DIRECTION TAKEN]**

Static geometry edits merge beautifully (CRDT). But the **substrate
physics** (temperature, pressure, momentum — the steam locomotive
plume) is a *running, path-dependent simulation*. Two peers simulating
the same region offline **diverge** in ways no per-cell merge can
reconcile. Geometry is a CRDT; a live sim is not.

Resolutions considered:
- Treat simulation state as **derived, re-computable from geometry +
  initial conditions** → discard and recompute on merge; OR
- **Designated regional authority for active simulation**, while
  *geometry* stays fully decentralized.

**Direction taken: a designated regional authority for physics
simulation.** (Geometry remains the decentralized CRDT/op-log; only the
live sim has an authority per region.) Details TBD — this is the thing
to think hardest about before it bites. (Compare the shipped two-system
split in `architecture.md`: terrain propagation vs. part propagation
already run different algorithms over shared state — precedent for
"different layers, different consistency models.")

## Sync cost context

For perspective on feasibility (memory budget detail in the geometry
chapter): a 100 km² world stored as a surface octree is ~1.5 TB total.

**Implication for sync:** first-join transfers a working subset +
relevant op-history, not the whole TB — another reason the Willow-style
"exchange only the missing range" model matters. The resident set is
players × view radius (a few GB); the rest streams as needed.
