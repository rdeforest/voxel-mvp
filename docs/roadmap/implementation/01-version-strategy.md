# Version Strategy

Each version answers one question. Versions are nominal labels —
v0.5 falls chronologically between v0.1 and v0.2 because it's
"halfway to 1.0", not "between 0.2 and 0.9."

**Scope boundary: this game is single-player.** Networking and multiplayer
are *not* part of this project at any version — they are the **successor
game** (the one after this one). The decentralized network design is captured
now only so its groundwork (`grid_id` in payloads, the deferred action-journal
model) isn't lost; see [`../design/05-network-architecture.md`](../design/05-network-architecture.md).
Every version below is a single-player milestone.

| Version | Question it answers                          | Maps to phases                                              |
|---------|----------------------------------------------|-------------------------------------------------------------|
| 0.0     | Is this as good of an idea as I think it is? | Phases 0, 2, 5 (fast path)                                  |
| 0.1     | Can I make it fun/performant?                | Phases 1, 3, 4, 5.5, plus honest-destruction + construction |
| 0.5     | Playtester drop                              | Linux/macOS binaries + brief onboarding                     |
| 0.2     | Can I make it pretty?                        | Art pass, shader work, audio, vehicles, channels            |
| 0.9     | Can I make it into a real product?           | Survival, combat, locomotives (single-player)               |
| 1.0     | Will people pay to get it from Steam?        | Open-source + Steam cloud-save extras                       |
| 1.1     | Can I make it run on Windows?                | Cross-platform builds via cloud CI                          |
| 1.x     | Wild dreams                                  | Planet-scale, sailing                                       |

## v0.0 — Status: complete

The thesis defense. Walking around a procedural voxel world, real
terrain modification, building that integrates seamlessly with terrain,
unified structural integrity, cave reinforcement. No biomes, no
resources, no inventory, no enemies. **Answered: yes, this is as good
an idea as I thought.** See [`done/`](done/00_INDEX.md) for the
chronological record.

## v0.1 — Status: in progress

Filling in the gameplay loop on top of the v0.0 foundation. Phase 5.5
(architectural maturation) is interleaved with phases 1, 3, 4. The
manifesto's anti-Enterprise stance is especially relevant here — v0.1
is where the temptation to ship phases small and call them "done" is
highest. **Each phase should defend the thesis at its own scale, not
just check a box.**

## v0.5 — Playtester drop

A release milestone between v0.1 (gameplay-feature-complete, programmer
art) and v0.2 (art pass). Gets feedback *before* sinking art-pass time
into things playtesters would want changed.

## v0.2 — Art pass + vehicles + channels

Visual polish. Also where the first multi-grid vehicle ships (cart or
rowboat) and where the first non-SDF channel ships (probably
temperature). Both gated behind v0.1's gameplay loop landing.

## v0.9 — Real product

Survival subsystems. Combat. AI. Locomotives. The pieces that turn the
tech demo into a game people would play for forty hours — **single-player.**
Multiplayer is explicitly *not* here: it forces the network-architecture work,
which belongs to the successor game (see the scope boundary above). v0.9 is
"a real product you play alone," not "an MMO."

## v1.0 — Steam release

Open-source release of the game code, Steam keeps the value-added
features (cloud saves, achievements, matchmaking). Tutorial, content
depth, Linux+macOS QA.

## v1.1 — Windows

Only if Linux/macOS sales demonstrate demand. Cross-compilation via
GitHub Actions Windows runners.

## v1.x — Wild dreams

Planet-scale world, sailing, vessel-vs-vessel combat. The "what if
this whole thing actually works" frontier.

## What about the DC-QEF transition?

The DC-QEF migration is *not* a version. It's a transition that
happens *during* a version (most likely v0.2) and changes what's
possible in subsequent versions. See
[`14-dc-qef-transition.md`](done/14-dc-qef-transition.md) for the work plan.

The transition replaces godot_voxel's meshing layer — keeping its
storage, streaming, and LOD. It is *not* the kind of rewrite that
killed Hytale.
