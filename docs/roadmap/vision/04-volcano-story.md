# Story, Setting & Mood

> Narrative-design foundation. This document defines the fiction, the world, and the
> emotional throughline. It is deliberately *vision*-tier: it constrains design without
> dictating implementation. Where a fiction implies a system (e.g. threat-gating), the
> system lives in its own design chapter; this doc owns the *why*.

---

## 1. The Core Conceit: It Is All a Dream

The player is dreaming. Or comatose. The game never commits, and the refusal to commit
is load-bearing — see §7.

The dream is not a narrative gimmick bolted onto a survival game. It is the single
metaphor everything else derives from, and it does three distinct jobs:

**It excuses the unreal.** Death is not permanent. A few minutes of smelting yields more
metal than physics would allow. The world runs on dream-logic, not conservation of mass.

**It justifies the look.** A watercolor-*implied* style — soft edges, colors bleeding
across boundaries, paper-grain texture, blooms where wet meets wet — reads as *memory* or
*reverie* rather than as a rendered simulation. This is an ally of the field-based geometry
direction (DC-QEF): smudged, dissolving surfaces are easier to sell than crisp photoreal
edges. The art style and the meshing technology want the same thing — surfaces that soften
at the corner.

**It earns the ending.** "You wake up" is only satisfying inside a frame that was honestly
a dream from the first moment. See §7.

### The Aesthetic Tension That Defines the Game

The *systems* are rigorously honest: structural integrity refuses to fudge, terrain
operations refuse rather than deform (the project's core "refuse-don't-deform" principle).
The *world's economy* is dreamlike and generous: abundance flows from the ground.

That contrast **is** the aesthetic. The floor beneath you is utterly solid and
consequential; the larder is infinite. A dream where the ground is real and the gifts are
free. Hold this tension deliberately — it is the difference between this game and a
cheat-mode survival sandbox.

---

## 2. The Setting: One Volcano Explains Everything

A single dormant shield volcano. Peak at the center, shoreline a rough circle ~5km out.
The whole island is one object with a history, and that history is the procedural
generation grammar. Everything follows from one rule — the same pattern the codebase
favors.

### The Volcano's History as Generation Grammar

- **Lava tubes** (the empty caves) radiate from old vents. They have direction and logic:
  they trend downslope, branch, and occasionally collapse into skylights. The underground
  is navigable by grammar, not noise.
- **Stratification** layers the material: older basalt deep, newer flows above, ash beds,
  occasional harder intrusions. The "relative material strength" system gets a natural map
  — the player learns to *read* the rock.
- **Erosion since dormancy** carves ravines, deposits beaches, makes soil. The shore is
  young sediment; the peak is bare old stone.
- **Obsidian** is the volcano's gift: readily available, it eases the early tool path
  (knife, axe) and provides the first dark mirror (§5).

The radial symmetry quietly previews the long-term planet-scale spherical ambition. An
island is a small sphere's worth of "everything radiates from a center." The cosmology is
being rehearsed at island scale.

### The Crater Lake: The Heart of the Metaphor

At the peak sits a crater lake. It is the literal high point and the emotional center.

**The volcano is the thing that put the player under.** The water hides the truth about
what that was. This is not stated; it is structure the attentive player feels.

The lake is the game's deepest mega-project, in the Dwarf Fortress tradition. Draining it,
or finding a way to dive it, is the act of confronting what the dream is hiding. The
mechanical ambition (a vast engineering undertaking) and the emotional payload (looking at
the wound) are the *same action*. This coincidence is the most important design fact in the
document — protect it.

What lies beneath: see §6.

### Flora & Fauna

Tropical. Dangerous creatures are small and grounded — lizards, snakes, spiders, flying
insects. No large predators. The threat is intimate and creeping, not cinematic. (And see
§4: nothing is dangerous until the player can engage it.)

---

## 3. Tech Level & Crafting: The Hand, Not the Machine

No technology washes ashore. No firearms, no compasses, no maps, no found artifacts, no
inherited knowledge-as-loot. **Everything the player makes, they make from the island and
their hands. Discovery *is* progression.**

Tools stay primitive and purposeful: knapped stone and obsidian, bone, sinew, fire-hardened
wood, plant-fiber cordage. Bow, knife, snare, deadfall, fish trap. The pleasure is the
*chain* — fiber → cordage → bowstring — which the action-as-data model represents naturally.

### Remember, Don't Tutorialize

The dreamer **remembers how things work but must find the materials.** This keeps friction
low and reinforces the dream's "I somehow just know" quality while still gating progress on
the world.

Concretely, this is a **prerequisite DAG with a hint-timer overlay** — a data structure, not
a branching tutorial:

- The player combines valid inputs (a vine and a bendy branch) → the bow is made
  *immediately*. The dream remembers along with them. No menu, no recipe unlock screen.
- The player lingers without progress → escalating hints begin to surface (diegetically
  where possible — a memory-flash, a glance, a half-remembered gesture).
- **The dependency graph is the tutorial.** There is no separate tutorial system.

Example sub-graph:

- *Bow* depends on: a flexible branch + cordage + the ability to *tie* cord to the branch
  ends.
- *Arrow* depends on: a shaft + the ability to *hone a point*.
- *Wooden parts* depend on: felling a tree, which depends on **either** mechanical-advantage
  tree-snapping **or** an axe.
- *Axe* is eased by readily available **obsidian** — so the obsidian route shortcuts the
  whole woodworking branch. Geology shapes the tech tree.

This is the "data structures over conditionals" principle applied to narrative
progression. Build the graph; the gameplay falls out of it.

---

## 4. Threat-Gating: Danger as the Price of Understanding

The world is safe until the player comprehends it, and comprehension is what makes it
dangerous. This inverts the survival-genre default (front-loaded danger) deliberately.

Thematically: *ignorance is bliss; to understand a thing is to become vulnerable to it.*
Eden, and the fruit of knowledge. Very dream-like.

**The unifying fiction: the dream simulates only what you are equipped to engage with.**
Reality unspools in step with competence. The world is built lazily, on demand — which is
*exactly* the engineering philosophy of the codebase (the simplest thing that works,
elaborated only when a real second use-case appears). The game's metaphysics and the
architecture are the same idea.

### The Design Hazard, and the Rule That Avoids It

If learning a solution is what *creates* the problem, players can feel punished for
progressing ("why make a campfire if it summons the night?").

**Rule: the reward must precede or accompany the threat. The player must love the thing
before its shadow arrives.**

| Capability unlocked | Reward arrives first | Threat then unspools |
|---|---|---|
| **Fire** | light, warmth, cooking, comfort | night & the need for sleep |
| **Food prep** | the delight of the first cooked meal | hunger |
| **Water prep** | safe drink | thirst |
| **Hunting tools** | the lizard was always there, sunning, harmless | now it can fight back — predator & prey unlock together |
| **Clothing** *(optional, maybe never)* | the comfort of being clothed | exposure — the last comfort to erode |

Night is atmosphere the player was made ready for, not a punishment. The first meal is a
gift; only afterward does the body begin to want.

---

## 5. The Mirror: Identity as a Discovery

The player begins faceless and bodiless — a pure first-person consciousness. You do not
have a body until the dream gives you one, which is also a quiet coma/dream resonance.

Self-image is *earned* by finding still water and looking down. This unlocks appearance
customization, third-person camera, and the ability to look down and see one's own
chest and feet.

### The Progression of Self-Recognition

A small arc, each tier both a crafting achievement and a deepening of selfhood:

1. **Still water** (a tide pool, the crater lake) — a wavering reflection. Basic
   customization; third-person unlocked.
2. **Polished obsidian** — the volcano's own gift of a first clear glimpse of yourself.
   Thematically perfect: the island hands you your face. Finer customization.
3. **Polished metal** — a clearer image still.
4. **Poured-glass mirror** (tin sheet with a lip, molten glass poured across it) — the
   masterwork, the sharpest self-view. Dream-logic covers any metallurgical hand-waving;
   do not over-engineer the realism.

### The Wounds You Cannot Remove

When the player customizes their face and body, there are **marks they cannot edit away.**
They represent the wounds that put them under.

This is never explained. It is a quiet, recurring dissonance — the one thing about yourself
the dream will not let you change. The player who later drains the crater lake (§6) may find
the wounds echoed in what lies beneath. Let them connect it themselves.

---

## 6. The Place That Should Not Exist

Beneath the crater lake — reachable only by the mega-project of draining or diving — is a
place that violates the island's entire grammar.

An **apartment.** Windows looking out on a city. *How am I seeing a city when I am inside a
volcano, underwater?*

The cognitive dissonance is the entire point. The system-minded player — the one who has
internalized that *everything* on this island follows from the volcano's history — breaks
against this precisely *because* everything else has been so consistent. The contradiction
only lands because the world earned the player's trust first.

Design notes for the apartment:

- Make the first glimpse **unexplained and unexplainable.** Do not narrate it. Do not gate
  it behind a codex entry. The windows, the city, the impossibility — felt, not told.
- Make it subtly **the player's own.** A lived-in layout, objects that almost resolve into
  meaning, the unremovable wounds (§5) echoed somewhere — a cracked window matching a scar.
  Nothing stated. Just felt.
- It is the bottom of the metaphor: the volcano is the trauma, the water is the repression,
  the apartment is the life on the other side of the wound.

---

## 7. Endings: For Those Who Like Games That End

Two layers, serving two different players.

### Achievement Tiers — the Completionist's Ending

Discovery (places, recipes, parts, tools), accomplishment (preserved-food stockpiles,
height/depth reached, count of things made, variety of things made, largest stable
structure built), and easter eggs.

These suit the "save file as replayable action history" model (the Quake `.dem` approach):
every achievement is *provable* from the action log, and the path to it could in principle
be reconstructed. The structural-integrity system is itself a rich achievement source
(tallest stable tower, deepest stable delve, largest spanning structure).

### Waking Up — the Narrative Ending

Reference points: Iain Banks' *The Bridge* (the coma-dream as a psyche working through
trauma; waking as ambiguous, earned reintegration) and *Dear Esther* (landscape as the
externalized interior of a grieving mind; story emerging from environment, never stated).

**Both point the same way: the ending is discovered, not triggered.** It is found by the
player who goes looking for the seams of the dream. It is something the player *does*, not
something they *learn*.

This property also solves the spoiler problem (§ below): if waking is an *act* (notice the
seam, drain the lake, stand in the apartment) rather than an *information reveal*, then
knowing "it's a coma dream" cannot steal the experience — exactly as *Dear Esther* remains
potent while fully spoiled everywhere.

**Dream-seams** the player can find — the world's hidden contradictions:

- **Writing is impossible.** Text will not hold still; letters rearrange; a page cannot be
  read the same way twice. A classic dream-tell.
- Clocks that disagree with themselves; the sun's position not matching elapsed time.
- A carving or book whose words change when you look away.
- The crater lake reflecting a face that is not quite the one you customized.
- **Sailing past the shore only to arrive back at it** — the radial/spherical geometry
  makes this literal and cheap to implement.
- A place that defies the volcano's own logic — the apartment (§6) is the deepest of these.

The act of waking should require *noticing*. The player who treats the island as a system
and finds its one impossible contradiction is rewarded with the truth. That player is, not
coincidentally, the kind of person this game is made for.

### On Coma Realism

Do not over-research it. Real waking from a coma is slow, medical, and undramatic — it would
deflate the fiction. The Banks/Esther tradition does something *mythic* with the idea of the
coma, not the neurology. Stay there.

### The Refusal to Resolve

Was it a dream, a coma, a death, a between-place? **Do not answer.** Leave it genuinely
ambiguous. The refusal to resolve is the most honest ending available — *refuse, don't
deform*, applied to meaning itself. The project's core principle, turned inward on the
story.

---

## Open Questions

- **Ending awareness on first playthrough vs. deep-secret layer.** Leaning toward: cannot be
  kept secret (the internet exists), but spoilers are made not to *matter* by keeping the
  ending an *act* rather than a *reveal* (see §7). Whether to also make the seams loud or
  subtle on a first playthrough is still open.
- **What happens after waking.** Undecided. Both reference works have an *after*. Options
  range from a hard cut-to-black to a brief, wordless frame on the other side. Deferred.
- **How explicitly the apartment connects to the wounds.** The instinct is "barely, and
  never stated." Exact dosage TBD in art/level design.

---

## Why This Holds Together

The dream is not a skin over a survival game. It is the spine:

- The **honest systems vs. generous world** tension is the aesthetic (§1).
- The **one volcano** is the generative rule, mirroring the codebase's "everything follows
  from one principle" (§2).
- The **crafting DAG** is data-over-conditionals applied to narrative (§3).
- **Lazy threat-gating** is "simplest thing that works, elaborated on demand" applied to
  metaphysics (§4).
- The **crater-lake mega-project** makes the largest engineering act and the deepest
  emotional act the same gesture (§2, §6).
- The **refusal to resolve** the ending is *refuse-don't-deform* applied to meaning (§7).

The game's philosophy and its engineering are, at every level, the same idea.
