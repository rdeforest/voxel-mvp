# Tech Ladders, Worked Through Fire

*Drafted by Claude from a design conversation with Robert, 2026-09-13. The
design decisions are his; the prose is not. Geology needs a specialist's
review — see "Open questions."*

> **What this chapter is for.** Fire is the first capability the player earns,
> and working it out end to end produced a pattern that should govern every
> other capability: the **tech ladder**. The ladder is described in §4; §§1–3
> are the worked example that produced it.
>
> Cross-references: [`../vision/05-design-pillars.md`](../vision/05-design-pillars.md)
> pillars 2 (epistemic progression), 4 (threat-gating), 8 (realism license) and
> 9 (surprise in the world, not the controls);
> [`../vision/04-volcano-story.md`](../vision/04-volcano-story.md) for the
> generation grammar this leans on; [`09-world-setting.md`](09-world-setting.md).

---

## 1. The geology constrains the design, and that's the point

The island is a dormant volcano whose history *is* the generation grammar.
That means materials aren't placed for game-design convenience — they're placed
where the geology puts them, and the design works with that.

The payoff: **"go over there to get that" stops being arbitrary.** It's not a
gate, it's a fact about the world, and a player who learns the grammar can
predict where things are before finding them. That is pillar 2 made physical.

Three findings, from working out what fire needs:

### There is no flint on this island

Flint is biogenic silica formed in marine chalk and limestone — sponge spicules
and diatoms concentrated over geological time. A young volcanic island has no
chalk. **Do not put flint in this game, and do not use the word.**

### But chalcedony and agate belong there, and do the same job

Basalt flows are full of gas vesicles, and silica-rich groundwater fills them
with chalcedony, agate and zeolites. Iceland, Oregon and Brazil all produce
agate exactly this way.

So: **agate and chalcedony nodules weathering out of the older basalt flows**,
concentrated where erosion has been cutting longest — the ravines, the stream
gravels, the beach shingle. Same Mohs-7 silica, same sparking behaviour, same
knappability. The mechanic survives; only the noun changes.

### Obsidian needs the volcano to have an evolved late phase

**This is a correction to earlier notes**, which had obsidian readily available.
Obsidian is rhyolitic — high-silica, viscous magma. A shield volcano is
basaltic by definition. Abundant obsidian on a basalt shield is the kind of
thing a geologist notices immediately.

The fix improves the world rather than costing anything: **give the volcano a
late-stage differentiated phase.** Ocean island volcanoes commonly evolve
toward trachyte and rhyolite as they age, producing small domes and short flows
on the flanks of an otherwise basaltic edifice. Precedents to verify: Ascension
Island, Tenerife.

Design consequences, all good:

- Obsidian becomes **a place**, not a scatter — one or two glassy domes with a
  distinct silhouette, colour and sound.
- Sharp-tool tech gets a natural mid-game gate that isn't a permission check.
- The volcano's history gains another readable chapter, which the
  system-thinking player can infer from the rock before being told.

### Pyrite comes free with the hydrothermal zones

Dormant volcanoes have altered zones around old vents where sulfides
precipitate. Pyrite there is unremarkable geology, and §3 needs it.

---

## 2. The correction that reshaped the fire design

**Striking two rocks together does not make fire.** Rock on rock produces cold
chips. A spark is a burning particle of *metal*, shaved off and oxidising —
which means either steel, or naturally occurring iron pyrite. Ötzi carried
pyrite and flint; that is the genuine prehistoric percussion method.

So flint-and-steel cannot be the player's first fire without handing them
steel, which inverts the whole progression. Percussion is the *endpoint*, not
the entry. Friction comes first.

---

## 3. The fire ladder

Five rungs. **The method never gets better; the player's knowledge does.**
There is no fire-making stat and there never will be.

### Rung 1 — Fire plough

A grooved hardwood base, a stick driven hard along the groove. This is the
Polynesian method and the thematically correct first fire for a tropical
volcanic island.

*Costs:* real time, real effort, high failure rate, needs genuinely dry
material.
*Buys:* first fire from nothing but wood. The threat-gating clock (night,
sleep) starts here — pillar 4.

### Rung 2 — Hand drill

Palm-rolled spindle on a hearth board. Iconic, and brutally demanding in
reality — specific wood pairings, blistered hands.

*Costs:* the highest skill floor on the ladder.
*Buys:* portability. No prepared base needed, just the right two woods.

Rungs 1 and 2 are siblings rather than strict sequence; either can be
discovered first.

### Rung 3 — Bow drill

**The first reliable fire, and the best-designed rung.** It requires cordage —
which the player already discovers when tying a vine to a bent branch to make a
bow.

*Costs:* cordage, plus a socket to bear down with.
*Buys:* reliability, and the click of recognition. One insight (cordage), two
payoffs (bow, bow drill). The player feels clever rather than issued a recipe.
This is the recipe philosophy from pillar 9 working exactly as intended.

### Rung 4 — Pyrite and agate

Percussion at last. Requires having found the hydrothermal zone (pyrite) and
the old flows or gravels (agate).

*Costs:* travel and geological understanding.
*Buys:* fire in your pocket. Seconds instead of minutes. This is the rung that
makes the hydrothermal zones worth walking to — see §1.

### Rung 5 — Steel striker

Available once smelting is. By this point it reads as a luxury rather than as
the baseline, which is the correct emotional order.

*Costs:* the whole metallurgy chain.
*Buys:* effectively free fire, and a small permanent object the player made.

---

## 4. The pattern this establishes

Every capability in the game should be built this way. Stated as a template:

**A tech ladder is a sequence of methods for one outcome, where each rung is
unlocked by an insight rather than a permission, and no rung improves a
number.**

The rules that make it work:

1. **The outcome is constant; the cost falls.** Fire is fire at every rung.
   What changes is time, reliability and portability — things the player feels,
   not things a stat tracks.

2. **Each rung is gated by understanding or by geography, never by fiat.**
   "You can't do that yet" is forbidden. "You haven't realised how yet" and
   "the material for that is over there" are the only two gates.

3. **At least one rung should reuse an insight from another ladder.** Cordage
   serving both the bow and the bow drill is the model. These crossings are
   what make the tech tree feel like a world rather than a menu.

4. **The world's materials come first; the ladder is fitted to them.** Not the
   reverse. If a rung needs a material the geology won't supply, the rung is
   wrong — or the geology gains a defensible new chapter, as in §1.

5. **Lower rungs never become obsolete or unavailable.** A player who lost
   their striker can still plough. Nothing is taken away.

6. **The failure state must be legible.** See below — this one is load-bearing
   enough to be its own section.

---

## 5. Failure legibility (both of us arrived at this independently)

Real friction fire has a brutal skill floor and a great deal of *silent*
failure. Silent failure is fatal here, and not for realism reasons.

A player who tries the fire plough five times and gets nothing will conclude
**they are missing an ingredient**, go looking for a recipe they don't need,
and quit the ladder. The game will have taught them the opposite of the truth:
that persistence is pointless and the answer is elsewhere.

So every failed attempt must communicate two things:

- **What was wrong** — wood too green, tinder damp, speed insufficient, groove
  too shallow. Diegetically: smoke colour, sound, the char that forms and dies.
- **That the approach is correct** — visible progress toward the threshold.
  Scorch accumulating. Dust darkening. The ember almost catching.

The player should be able to tell "I am doing the right thing badly" from "I am
doing the wrong thing" without a single line of text. That distinction is the
whole difference between a demanding mechanic and an opaque one.

This is refuse-don't-deform applied to a *skill* rather than to geometry, and
it's pillar 9's "all the surprise lives in the world, none in the controls."

**This requirement generalises to every ladder.** Any rung that can fail must
show its work.

---

## 6. Realism licences spent here

Per pillar 8, each one recorded with its reason:

- **Compressed timescales.** A real fire plough is minutes of hard labour by an
  experienced hand. Ours is shorter. Reason: the *lesson* is that it's hard and
  improvable, and that lands well before realistic duration does.
- **Forgiving material tolerances.** Real wood pairings are narrower than ours
  will be. Reason: the interesting failure is "damp / green / too slow," not
  "you picked the wrong one of forty species."

Neither licence is extended to *outcomes*. Wet tinder does not light.

---

## 7. Open questions

- **Geology review.** The evolved-late-phase argument, the Ascension and
  Tenerife precedents, and the agate-in-vesicles claim all want checking by
  someone with the training. Cecilia (geology, UCSC) is the candidate.
- **Where the late-stage domes sit** on the island, and what they look like
  from a distance. This is worldgen grammar and belongs in
  [`09-world-setting.md`](09-world-setting.md) once decided.
- **Whether rungs 1 and 2 are both needed**, or whether the fire plough alone
  carries the early game.
- **The memory-video for fire** (see the FMV discussion): hands and a grooved
  log, no face. Which rung gets the video, and whether later rungs get their
  own.
- **How the ladder is surfaced.** The player should be able to *consider* a
  known rung and see that better ones exist without being told what they are.
  Interaction with [`17-consider-and-hypothetical-mode.md`](17-consider-and-hypothetical-mode.md)
  is unspecified.
