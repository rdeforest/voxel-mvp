# Consensus Reality (excuse-driven magic)

*The design spec for the game's "magic": unrealistic abilities default **on**, and stay
on until the player does something that only makes sense if they believe the ability
**shouldn't** work — at which point reality switches to honest physics for that domain.
The player re-enables the ability by building an in-world artifact their brain accepts as
a license to cheat again. This is a deliberate, diegetic break from the rest of the
engine's honest-physics rigor: it is the world telling the player it is a dream.*

## TL;DR

The headline abilities — **double-jump** and **gliding** (no fall damage) — are not three
independent flags. They are instances of one rule:

> An ability is a **belief**. You can do it until you prove you know you can't. You can do
> it again once you give your brain an excuse.

So the data model is a small set of **belief domains**, each a tiny state machine that
gates one or more abilities. Add a new magic ability by adding a row, not a subsystem.

This chapter fixes the *shape* of that system. It deliberately **defers** one decision:
how the "you proved you know better" transition (the *disillusionment trigger*) fires —
explicit crafted artifacts vs. inferred intent. That waits on the damage model, which does
not exist yet (fall damage is deferred in `STATUS.md` to v0.1+).

## Why this exists (the thesis tension, on purpose)

The rest of the engine is aggressively *honest*: refuse-don't-deform, PBD→MPM continuum
physics, no procedural shortcuts in the render path. This mechanic is aggressively
*dishonest* — physics gated by what the player believes. That is not a contradiction of the
manifesto; it is a separate, intentional layer. The magic is **diegetic**: each ability is
a *tell* that the world is a dream, and the dream's logic is consistent even though it isn't
physical. Robert's framing: "you can do things as soon as you try, until you do something
that shows you know it *shouldn't* work, then you re-enable things by making excuses your
brain will accept."

Design consequence: **magic mode must read as a different register from the structural
sim.** If glide or double-jump looks like the physics misbehaving, the conceit fails — it
feels like a bug, not a dream. Visible/audible/diegetic distinction is load-bearing, not
polish.

## The model: belief domains

A **belief domain** owns a state and gates a set of abilities. The headline example:

```
domain: "falling"
  state NAIVE   (default)   → fall damage OFF; glide ON; double-jump ON
       │
       │  disillusion: player demonstrates they know heights are dangerous
       ▼
  state HONEST              → fall damage ON; glide OFF; double-jump OFF
       │
       │  excuse(squirrel_suit)   → glide ON  (still in HONEST: damage stays on)
       │  excuse(double_jump_boots)→ double-jump ON
       ▼
  (HONEST + accumulated excuses): honest gravity, but re-licensed cheats
```

Key properties:

- **Default-on.** A fresh world starts NAIVE in every domain. The player is quietly
  omnipotent; reality is something they *opt into*, not something they unlock. This inverts
  the usual progression (you normally *gain* powers) and is the compelling core.
- **Disillusionment is one-way for the base belief.** Once you "know" heights are
  dangerous, you don't un-know it by deleting the bridge. Fall damage stays on. What you
  *can* do is buy specific exceptions back.
- **Excuses are per-ability, not per-domain.** Crafting double-jump boots re-enables
  double-jump without re-disabling fall damage. Each excuse is an artifact whose existence
  (owned/equipped — TBD) flips one ability back on within an otherwise-honest domain.
- **Excuses are diegetic license, not stat items.** The squirrel suit's job is to make your
  brain accept gliding; whether it confers any numeric bonus is secondary.

Abilities are therefore a **derived** state: `ability_enabled = domain.allows(ability)`,
computed from the domain's state plus which excuse-artifacts exist. The movement code reads
that boolean; it does not own the belief logic.

## The headline abilities

| Ability | Domain | NAIVE | HONEST | Excuse to restore |
|---|---|---|---|---|
| Double-jump | falling | on | off | double-jump boots |
| Glide (no fall damage) | falling | on | off | flying-squirrel suit |
| Fall damage | falling | *off* | *on* | — (this IS the honest state) |

"Glide" here is doing double duty in Robert's description — gliding *and* "won't take
falling damage." Cleanest reading: in NAIVE there's simply no fall damage at all, and glide
is a movement affordance on top. In HONEST, fall damage is real; the squirrel suit is what
lets you glide (and thereby avoid the damage) again. Mechanically, glide = clamp descent to
a gentle terminal velocity while a key is held; double-jump = an air-jump counter reset on
landing. Both live in `scenes/player/movement.gd` and are independent of the MPM work.

## OPEN DECISION — the disillusionment trigger (deferred)

How does the game decide the player "knows heights are dangerous"? Two candidates, recorded
so they aren't rediscovered:

1. **Explicit artifacts only.** Crafting/placing climbing safety gear (rope, harness,
   piton) is the trigger. Robust, legible, zero false positives — but loses the "your brain
   noticed on its own" subtlety that is the whole charm.

2. **Inferred intent, *always announced*.** Infer from behavior — built a high bridge, made
   safety gear, anything "that would only be necessary if falling hurt" — and surface a
   diegetic line at the moment reality flips ("You suddenly remember that heights are
   dangerous."). The announcement is what makes inference *fun* instead of confusing: the
   player gets to recognize their own brain's logic.

The hazard with (2) is false positives: someone builds a tall bridge for looks, fall damage
silently switches on, their glide stops working, and it reads as a bug. The announcement
mitigates but does not eliminate this. Whichever we pick, **the flip must never be silent.**

**Decision: deferred** until the damage model exists. Until then the gating half has nothing
to gate against, so the trigger choice is premature. The NAIVE-side abilities (double-jump,
glide) can ship and be enjoyed before any of this lands.

## What can ship now vs. what's blocked

- **Now, cheap, no dependencies:** double-jump + glide, default-on, in `movement.gd`. They
  deliver the dream-tell immediately and touch nothing in the MPM/substrate pivot.
- **Blocked on the damage model:** the HONEST state, the disillusionment trigger, and the
  excuse-artifact loop. Fall damage is itself deferred (`STATUS.md`, v0.1+ "Falling
  damage"); the belief system is the layer that sits on top of it once it exists.

## Open questions parked here

- **Excuse ownership model:** owned-in-inventory vs. equipped vs. once-crafted-always-on.
  No inventory/equip system exists yet.
- **Persistence:** belief state is per-world and must survive save/load (WorldSnapshot). It
  is small (an enum + a set of excuse ids per domain).
- **Other domains:** the framework should make a second magic ability trivial. Candidates
  to pressure-test the abstraction: water-walking until you "notice" and fall through;
  unlimited reach until you measure a distance. Don't build these; use them as a sanity
  check that the domain model isn't overfit to falling.
- **Multiplayer:** belief is per-player, but it gates *physics the player experiences*, not
  world state — so it lives client-side over the op-log world
  ([`05-network-architecture.md`](05-network-architecture.md)). Recorded, not designed.
