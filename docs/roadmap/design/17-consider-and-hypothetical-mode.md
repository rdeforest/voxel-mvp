# Consider & Hypothetical Mode

What the third universal interaction is, independent of when it ships. The
manifesto supersedes this chapter; if they disagree, the manifesto wins.

This chapter resolves the open problem pillar 9 created (a visual language
for the input→action mapping — see
[`../vision/05-design-pillars.md`](../vision/05-design-pillars.md)). The
answer is the same diegetic ghosts already used for tool previews, plus
giving the player the power to **name things**, plus a third verb that turns
naming into thinking.

## The third verb

Everything answers three always-available, always-safe inputs:

- **Examine** — gather information without acting on the target (pillar 9).
- **Interact** — the safe default action (pillar 9).
- **Consider / think** — enter *hypothetical mode* about the thing being
  examined: a space for describing changes, relationships, and actions
  **without committing to any of them.**

Consider is the bridge between the minimal-text commitment (pillar 6) and the
least-surprise commitment (pillar 9). The player never has to memorize what an
input does, because they can *consider* first and watch the ghost of the
outcome before anything happens.

## The visual language: ghosts + naming

The mapping from input to action is conveyed two ways, no on-screen key
labels required:

- **Ghosts.** The same translucent preview the build/dig/fill tools already
  render (`VoxelPreviewRenderer`, the part-mesh ghost) generalizes to *every*
  considered action. To consider an action is to see its ghost — the exact
  cells, objects, or relationships it would change — before deciding.
- **Naming.** The player can attach names to things and to relationships
  between things. A named thing is a thing the player understands; the act of
  naming is the act of comprehension (pillar 2). Names are the player's own
  words, which is why this stays compatible with near-zero localization
  (pillar 6) — the game ships no nouns the player didn't choose.

## Hypothetical mode

Considering puts the player in a non-committing sandbox over the real world:

- Describe a change and see its ghost; nothing mutates until execution is
  triggered.
- Name a combination of items to record it. **Naming a hypothetical
  combination adds it to the player's concept library** — the personal store
  of understood combinations.

### Composing a prediction: consider, then interact

The player *builds* a hypothetical by composing the verbs. **Consider** one
thing, then **interact** with another, and the game shows what would *likely*
happen if that interaction were real — without doing it. Worked example:

1. Examine a bucket you made and **consider** it. Time pauses.
2. Cast the cursor to a nearby stream and **interact**.
3. The game plays a **ghost** of the likely outcome — the player walking to
   the water's edge and filling the bucket. Nothing actually changed: the
   bucket is still empty, the clock still paused.

The prediction is "what is *likely* to happen," not a promise — see the open
questions on uncertain and multi-outcome interactions.

### The sentence: symbols the player names

After the ghost, the interaction is shown as a row of symbols — for the bucket
fill, **🖐 hand · bucket · → · stream** (agent · instrument · action ·
target). Each symbol is a slot the player can **fill in with their own text.**
Naming the slots buys two things:

- **Search.** Having typed "bucket" and "stream," the player can later find
  those things by those words — the concept library becomes queryable in the
  player's *own* language.
- **Future sentences.** Once named, later predicted interactions render as
  *sentences* built from the player's words ("fill bucket from stream")
  instead of anonymous glyphs.

The game ships **no nouns**; the player writes the language. This is exactly
why a naming system is compatible with minimal text and near-zero localization
(pillar 6) — the only words on screen are ones the player chose to put there.

This unifies the two halves of the visual language above: the **ghost** shows
*what* would happen; the **nameable sentence** is *how the player records and
recalls it.* A named action-sentence is the action-shaped sibling of a named
build in the concept library below — both live in the same player-authored
store.

## The concept library: naming makes builds repeatable

The concept library is how a player turns a one-off arrangement into a
**repeatable structure.** Once a combination of parts/voxels is named, that
name *is* a build recipe the player can place again, the same way they place a
single part today. This is the player-facing path from "I figured out this
arrangement once" to "I can stamp this whenever I want" — emergent
schematics, authored by the player rather than by us.

This reinforces pillar 2 (progression is epistemic): a bigger concept library
is *literally* the player knowing more, with no capability stat anywhere.

## The hint system: consider weird combinations

Considering two things *together* yields hints — the game's diegetic,
spoiler-free nudge toward recipes the player hasn't discovered. The clues
make sense in hindsight (pillar 9's "stick + string = bow" rule); consider is
how the player asks for them:

| Consider together | Hints toward |
|---|---|
| wood + sun | making fire |
| stone + sun | making shelter |
| wood + stone | making tools |

The combination doesn't have to be a literal recipe — considering *the sun*
with *wood* is a deliberately "weird" pairing whose only purpose is to surface
the fire hint. This keeps discovery in the player's hands: the hint is
requested by curiosity, never pushed by a quest marker (pillar 5). Examining
the individual materials already yields recipe clues; considering them
together sharpens those clues into a direction.

This is the same "the dreamer remembers how things work but must find the
materials" texture as the volcano frame
([`../vision/04-volcano-story.md`](../vision/04-volcano-story.md) §"remembers
how things work") — the hint is the dream half-remembering, not a tutorial.

Authoring every recipe and every sensible hint pairing by hand is the cost.
Per pillar 9, that authoring is meant to be as much a pleasure for us as the
discovery is for the player.

## Pause-and-plan (the collapse case)

Consider also carries an accessibility load, in concert with
[`18-accessibility.md`](18-accessibility.md): hypothetical mode is where a
player **plans under a paused clock.** When visual + audio cues warn that a
structure is about to collapse, the player can pause time, lay out the fix in
hypothetical mode (which supports to add, where to brace), and then trigger
execution — which happens *instantaneously in game time.* Failing to support
a structure is therefore never a question of reacting fast enough; it is only
ever a question of understanding what to do. See pillar 10 and the
accessibility chapter for the no-reflexes commitment this serves.

## Open questions

- **Granularity of naming.** Can the player name a single voxel relationship,
  or only assemblies? Where's the line between an examined *thing* and a named
  *relationship*? And when the player names a sentence slot ("bucket"), does
  that name bind to *this* instance, to the item *type*, or to every
  bucket-shaped thing — i.e. how does one naming generalize?
- **Predicting uncertain or multi-outcome interactions.** The ghost shows what
  is *likely*, but some interactions have more than one plausible result or a
  genuinely probabilistic one. Show only the most likely outcome, a fan of
  alternatives, or a confidence cue? It must stay surprise-free (pillar 9)
  without pretending the world is more deterministic than it is.
- **Concept-library UI without clutter** (pillars 5 + 6). The library is
  player-authored content; presenting it for re-placement without a text list
  is the same unsolved problem as the job-queue visual language.
- **Hint reach.** How many "weird combination" pairings get hand-authored, and
  how does the game signal that a considered pair has *no* hint without
  feeling like a dead end?
- **How consider reads on a controller** vs. keyboard/mouse — it must be one
  obvious input on each (pillar 9).
