# Accessibility

What the game's accessibility commitments are, independent of when they ship.
The manifesto supersedes this chapter; if they disagree, the manifesto wins.

Accessibility is a first-class design constraint here, not a late polish pass.
It is the mechanism half of pillar 10
([`../vision/05-design-pillars.md`](../vision/05-design-pillars.md)); this
chapter records *how* the commitments are met. Two principles drive
everything below.

## Principle 1: no sense is load-bearing alone

**No game-critical information may reach the player through only one sense.**
Music and sound effects are wanted — but they can *never* be the only clue
about anything.

- **Mood is doubled into color.** When music shifts the mood, the **color
  palette shifts with it.** A player who can't hear the score still reads the
  tonal change off the screen. (This also serves pillar 6: the mood is
  conveyed diegetically, through the world's look, not a label.)
- **Visible sounds.** A toggle — represented by the symbol sequence **ear →
  → eye** ("turn sounds into sight") — adds a visual effect for every
  game-critical sound. Worked examples:
  - a grumbling stomach → a visible hunger cue;
  - twigs snapping under heavy wildlife → a visible disturbance in the
    direction of the approach;
  - nearby running water → a visible flow cue.
  The audio still plays; the visible-sounds layer is *additive*, so hearing
  players lose nothing and non-hearing players miss nothing load-bearing.

The symmetric obligation (no clue *only* visual) follows from the same
principle and should be honored as the systems are built — e.g. a structural
warning is both a creak and a visible strain cue.

## Principle 2: no reflexes are ever required

**Nothing in the game may require fast reaction time.** Difficulty comes from
comprehension and engineering (pillars 2 + 4), never from twitch.

- **Pause time without pausing interaction.** The player can stop the game
  clock and *still* think, plan, and describe actions. This is not a dead
  pause menu — it is hypothetical mode (see
  [`17-consider-and-hypothetical-mode.md`](17-consider-and-hypothetical-mode.md))
  running against a frozen world.
- **Plans execute instantaneously in game time.** The collapse case is the
  model: cues warn that a structure is failing → the player pauses → plans the
  brace/support in hypothetical mode → triggers execution, which lands at once
  in game time. A structure is never lost because the player couldn't move
  fast enough; only because they didn't work out *what* to do. This is the
  accessibility guarantee that makes pillar 4's threat-gating fair to
  everyone.

## Settings

There is a settings menu — one of the shell-level screens pillar 6 permits
text on. It carries at least **controls**, **graphics**, and
**accessibility** sections. The accessibility section is where visible-sounds,
mood-palette coupling, pause behavior, and rebinding live. Settings UI follows
the same symbol-first, minimal-text discipline as the rest of the game
wherever a symbol can carry the meaning (the ear→→eye glyph is the model).

## Relationship to the pillars

- **Pillar 6 (minimal text; diegetic UI)** — accessibility *pushes the same
  direction*: doubling mood into palette and sounds into sight is more
  diegetic information, not more overlay text.
- **Pillar 9 (least surprise)** — pause-and-plan removes the last hidden
  surprise: being punished for slow reaction. The only surprises left are the
  fun ones.
- **Pillar 5 (no manipulation)** — refusing twitch-pressure is of a piece with
  refusing engagement-hooking; both decline to exploit the player's nervous
  system.

## Open questions

- **Colorblind-safe mood palettes.** Mood→palette can't lean on hue alone, or
  it reintroduces a single-channel dependency for colorblind players. Mood
  shifts need a value/contrast component too.
- **Visible-sound vocabulary.** A consistent visual grammar for "sound from
  direction X / of kind Y" without it becoming a HUD. Shares DNA with the
  job-queue and concept-library visual-language problems.
- **Pause and a future multiplayer game.** A stop-the-clock pause is trivial
  single-player and hard once peers share a clock — noted, and deferred to the
  successor game (see [`05-network-architecture.md`](05-network-architecture.md)),
  which is where networking lives at all.
