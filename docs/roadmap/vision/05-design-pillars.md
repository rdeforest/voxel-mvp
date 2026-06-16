# Design Pillars

The player-facing "why." Where [`../design/01-principles.md`](../design/01-principles.md)
states the *architectural* thesis (voxel over heightmap, field over cube),
this chapter states the *experience* commitments — what playing the game
must feel like and what it must never do. The manifesto supersedes this
chapter; if they disagree, the manifesto wins.

These pillars are the cross-check for any proposed feature, the same way the
architectural principles are. The recurring theme underneath all of them:
**respect the player.** Most of the genre's bad habits — non-interactive set
dressing, arbitrary inventory caps, grind-as-content, jump scares,
dehumanized enemies, gotcha controls and trick puzzles — are the same
failure: treating the player as something to be managed, frightened,
tricked, or retained rather than trusted. Each pillar below is a refusal of
that.

Each pillar is stated as *what it forbids* and *what it buys you*, because a
pillar that only inspires can't be used to reject a feature.

## 1. The player owns the world

**Two faces of one rule.** Everything that exists was made by world
generation or by a player — there is no third category of authored,
non-interactive set dressing. And the converse: not having seen a thing
doesn't mean it can't exist; players can build most of what they can
imagine.

- *Forbids:* story props you can't touch, scenery bins of fake supplies,
  decorative corpses, any "look but don't interact" object.
- *Buys you:* no bespoke non-interactive assets to build (less art work, not
  more), and a world whose consistency the player can trust — which is what
  makes the one deliberate impossibility (the apartment under the lake) land.

**The completeness half** (everything visible is real) is a cheap worldgen/
asset discipline. **The generativity half** (you can build what you imagine)
is an unbounded systems-depth commitment and is the one that can eat the
project — see the voxel-substrate / coded-behavior rule below, which is how
generativity stays affordable.

### Sub-rule: voxels for truth of matter, coded behavior for truth of function

A functional machine (block-and-tackle, winch, waterwheel, locomotive) is
**voxel-represented and voxel-destructible** — when destroyed it returns to
voxel data — but while functional its *operation is programmed to be
reliable rather than emergent*, wherever emergence would produce unpleasant
surprises (a rope jumping off its pulley from rounding error at sub-metre
precision).

- *Forbids:* both over-simulating the machine (vision creep) and faking the
  machine as a non-voxel scene prop (thesis erosion). The Enterprise trap
  lives at both edges.
- *Buys you:* arbitrarily complex player-built machines that *just work*,
  without committing to general rigid-body rope physics.

This is "refuse-don't-deform" applied to simulation fidelity: the machine
may *lie* about being made of voxels in order to never lie to the player
about how it behaves.

## 2. All progression is external or epistemic

There is **no character capability growth.** No strength, stamina, or skill
stats; nothing the player does makes the avatar's raw capabilities larger.
The world changes, the player's *knowledge* grows, and structures
accumulate — but the character is constant. Fatigue and the need to sleep
are constant constraints, not trainable stats.

- *Forbids:* exercise-to-raise-stamina, use-to-level skills, gear-score,
  strength-from-body-size, any number that goes up because you repeated an
  action.
- *Buys you:* all progression is forced into comprehension, world-state, and
  the *player's own* skill. Learning, building, and understanding *are* the
  advancement. This is the same move as "no tech washes ashore."

**Consequence to accept:** this kills the standard difficulty curve (enemies
get harder / you get stronger). Difficulty must come from threat-gating
(pillar 4) and from the inherent difficulty of bigger builds and deeper
questions. The late game has to be *interesting*, not *numerically tense* —
which puts the weight on the mystery/ending layer. The bill comes due there;
that's acceptable.

## 3. Limits are physical, never arbitrary

Constraints exist, but every constraint must have an in-world physical
reason. The model case is **inventory as a craftable, discoverable arc**:
bare hands → containers (backpack, bucket, basket) unlock capacity *and*
introduce exhaustion from overwork → the pack is defined by weight, volume,
and length → iterating on pack design unlocks a 2D-tetris organization toy →
further refinement makes it 3D tetris.

- *Forbids:* "15 sticks, 3 skulls" per-item-class caps, weightless infinite
  pockets, any limit whose only justification is balance.
- *Buys you:* limits the player can *reason about and engineer against*, and
  a system (inventory) that is itself content rather than a fixed UI.

**The tetris must be opt-in.** Auto-pack ("stow") is the default; manual
tetris is a toy for players who enjoy optimization. Otherwise this pillar
fights pillar 5 every time someone picks up a log.

The skill of packing lives in the *player*, not in a Packing stat — which is
why this pillar and pillar 2 reinforce rather than contradict each other.

## 4. Threat-gating: the reward precedes the threat

The world is safe until the player comprehends it; comprehension is what
unspools danger. But the **rule that keeps this from feeling like
punishment**: the player must love the thing before its shadow arrives.

| Capability | Reward arrives first | Threat then unspools |
|---|---|---|
| Fire | light, warmth, cooking, comfort | night & the need to sleep |
| Food prep | the first cooked meal | hunger |
| Water prep | safe drink | thirst |
| Hunting tools | the lizard was harmless scenery | now it can fight back |
| Clothing *(optional)* | the comfort of being clothed | exposure |

- *Forbids:* front-loaded danger the player scrambles against; making a
  campfire "summon" the night as a penalty for progressing.
- *Buys you:* a difficulty source that doesn't need stat-inflation (paying
  pillar 2's bill), and a world that "simulates only what you're equipped to
  engage with" — lazy elaboration on demand, the same philosophy as the
  codebase.

## 5. No manipulation the player would resent if they noticed it

The game does not poke the lizard brain. **No cheap scares** — when horror
eventually arrives it is earned through the player's investment in something
that is then put at risk, never extracted by reflex. **No engagement-
hooking, no grind-for-grind, no time-wasting.** The game does not try to
maximize playtime or "retention"; people play because they like learning,
exploring, building, and collaborating.

- *Forbids:* jump scares, daily-login pressure, artificial click-repetition
  (making 30 arrows one click at a time), any dark-pattern dependency loop.
- *Buys you:* a trust relationship with the player, and a clear mandate for
  QoL — repetitive tasks are *queued* (Dwarf-Fortress job model) and, when
  nothing requires delaying them, complete as fast as is reasonable.

Two structural consequences:

- **Horror is late-game by construction.** You can't threaten what the
  player doesn't care about, so dread lives where investment lives — near
  the dream/coma layer.
- **The job queue needs a visual language** (open problem below), because
  the DF model is legible *because* it's textual and this game is committed
  to minimal text.

## 6. Minimal text; diegetic UI

The full game shows **as little on-screen text as reasonably possible**, and
**no in-world HUD until the player presses the meta key** (ESC or rebind).
The aim is a game that needs no translation beyond shell-level words
("settings," "profile," "multiplayer"). Information reaches the player
through the world — an animal's posture, a straining creak, a half-built
object on the bench — not through overlays.

- *Forbids:* persistent HUD, floating quest text, tutorial popups, a job
  queue rendered as a text list.
- *Buys you:* immersion and near-zero localization burden — but it raises
  real unsolved design problems (below), which are the cost of the pillar,
  not reasons to abandon it.

**Honest exceptions exist** and should not be omitted out of purism: the
character-customization screen's missing-legs explanation (pillar 1 of that
chapter) is text that *must* be present, because silence there would be
misread. Minimal is the rule; zero is not the rule.

## 7. Comprehension over conquest

There is **no game-sanctioned violence against any humanoid Other** —
extraterrestrial, mutant, outlaw, anyone. Non-violence is always available
as the answer. The only "enemies" are small fauna, gated behind the player's
own tools (pillar 4). If a future project ever depicts human conflict, the
model is *Far Cry 2* — violence shown as cost and futility, indicting it
rather than offering it as the satisfying verb — not this game.

- *Forbids:* dehumanized kill-fodder, the "they're monsters so it's fine"
  excuse, any design where the Other is the obstacle to overcome by force.
- *Buys you:* a game whose politics *are its design* rather than a message
  bolted on. The thesis (comprehension over conquest; the player owns the
  world; the Other is never the answer) is the game, not a soapbox inside
  it. This needs no defense beyond "this is what the game is about" — a
  player who wants conquest-of-the-Other has abundant options elsewhere.

## 8. The dream is the realism license, spent deliberately

The dream/coma frame is a *finite budget* of permitted unrealism, not a
blanket excuse. Where realism would serve nothing the player enjoys, the
dream pays for the shortcut — and each expenditure is **written down with
its reason**, so future work doesn't "fix" an intentional choice.

- *Examples already on the books:* a few minutes of smelting yielding
  unrealistic metal; death's impermanence; the glider's invisible slow-climb
  thrust (no thermal-riding skill required, because that isn't fun). The
  belief-domain machinery for abilities like this lives in
  [`../design/14-consensus-reality.md`](../design/14-consensus-reality.md).
- *Forbids:* using "it's a dream" to wave away inconsistency the player
  *would* find unsatisfying, or to justify dishonest systems (the systems
  stay rigorous — see the honest-failure principle).
- *Buys you:* permission to choose fun over simulation at specific,
  documented points, while the ground underfoot stays utterly real. The
  tension — honest systems, generous dreamlike world — *is* the aesthetic.

## 9. Least surprise in the controls; all surprise in the world

The mapping from input to action must never surprise the player; everything
the *world* yields to experimentation should. **Two halves of one rule:** the
verbs are predictable, the consequences are discoverable. A player should be
able to guess what a key, button, or controller input will do before pressing
it — and should always be rewarded, never punished, for poking at the world
to find out what it's made of.

**Examine, interact, and consider are universal and always safe.** Every
thing in the game answers three always-available verbs:

- **Examine** — gather more information about a thing without committing to
  any other action or taking any risk. *Not* "poke the bear with a stick to
  see if it's sleeping" — examine never acts *on* its target. It's the safe
  probe: posture, material, state, and (crucially) recipe clues.
- **Interact** — the default action, which is *also* always safe to try. The
  default may *change* as the player's relationship to the object changes (a
  wary animal vs. a tamed one), but whatever the current default is, it is
  never a trap.
- **Consider / think** — enter *hypothetical mode* about the examined thing:
  describe changes and relationships, name combinations into a reusable
  concept library, and request recipe hints by considering things together —
  all without committing to anything. This is the verb that makes the other
  two surprise-free: you can always preview an outcome (as a ghost) before it
  happens. The full mechanic — ghosts-plus-naming as the visual language, the
  concept library, the hint system — is
  [`../design/17-consider-and-hypothetical-mode.md`](../design/17-consider-and-hypothetical-mode.md).

- *Forbids:* context-sensitive controls that do something destructive you
  didn't expect; an "interact" that sometimes attacks; an examine with side
  effects; challenge design built on tricks, hidden gotchas, or memorized
  sequences — no sliding-block puzzles, no "press the unmarked button or die."
- *Buys you:* a player who explores fearlessly, because experimentation is
  *always* safe and *usually* rewarded. All of the game's surprise is
  reinvested into discovery instead of spent punishing the curious.

**Challenges are comprehension, not tricks.** Because everything is
procedural, emergent, or both, there are no authored gotcha puzzles. The
puzzle is *figuring out how the world works*, and the answers always make
sense in hindsight. Recipes are the model: **stick + string = bow** is a
puzzle only until you see it, and then it's obvious. Examining the materials
yields the clues; the reward is the click of recognition, never the relief of
having guessed an arbitrary password. (Authoring every recipe by hand is the
cost — and, like the player's discovery, it's meant to be a pleasure rather
than a chore.)

This is pillar 5 (no manipulation) turned toward the *challenge* layer and
pillar 2 (epistemic progression) turned toward the *discovery* layer: the
difficulty lives in understanding, the controls stay honest, and the only
surprises left are the fun ones.

## 10. Accessibility is structural, not a polish pass

Accessibility is a design constraint from the start, not a feature bolted on
near ship. Two absolutes, each a refusal to make the player's body the
difficulty:

- **No sense is load-bearing alone.** No game-critical information reaches the
  player through only one sense. Music and sound effects are wanted, but they
  can *never* be the only clue: when the score shifts the mood, the **color
  palette shifts with it**, and a **visible-sounds** toggle (the symbol
  sequence *ear → → eye*) renders a visual cue for every game-critical
  sound — a grumbling stomach, twigs snapping under heavy wildlife, nearby
  running water.
- **No reflexes are ever required.** Nothing demands fast reaction time. The
  player can **pause time without pausing interaction** — freeze the clock,
  plan the fix in hypothetical mode (pillar 9's *consider*), then trigger
  execution, which lands *instantaneously in game time*. A collapsing
  structure is lost only by not knowing what to do, never by not moving fast
  enough.

- *Forbids:* audio-only alerts, mood conveyed by sound alone, twitch-gated
  saves, any failure that hinges on reaction speed, "accessibility options"
  deferred to a someday backlog.
- *Buys you:* the difficulty stays where pillars 2 and 4 put it — in
  comprehension and engineering — and the game is fair to a strictly wider set
  of players at no cost to anyone. The mechanisms (visible sounds,
  mood↔palette coupling, pause-and-plan, the settings menu) live in
  [`../design/18-accessibility.md`](../design/18-accessibility.md).

This pillar *pushes the same direction as* pillar 6: doubling mood into
palette and sound into sight is more diegetic information, not more overlay
text.

## Open problems these pillars create

Stated here so they aren't rediscovered from scratch:

- **A visual language for the job queue** (pillars 5 + 6). Candidate:
  diegetic work-in-progress objects — a queued meal is a half-assembled meal
  on the counter with a progress shimmer; the backlog is literally the
  lineup of unfinished things, no list, no text. Most aligned with pillar 1.
  Load-bearing for the anti-tedium goal; prototype early.
- **A visual language for the input→action mapping** (pillars 6 + 9).
  *Resolved in principle:* the answer is the tool-preview **ghosts** plus
  letting the player **name things**, plus the **consider** verb that lets
  them preview any action's ghost before committing — see
  [`../design/17-consider-and-hypothetical-mode.md`](../design/17-consider-and-hypothetical-mode.md).
  Still open: how the cue reads across keyboard, mouse, *and* controller, and
  how it shows an object's default interaction changing with the player's
  relationship to it.
- **"See it → interact with it" vs. distance** (pillar 1). The principle
  means *interaction is never gated by fiat*, not *every visible pixel is in
  reach*. The telescope/binoculars feature deliberately lets players see
  what they can't yet reach — so state the rule as "nothing visible is fake
  or off-limits by permission; reach is a physical question." The telescope
  turns the see/reach gap into content, not frustration.
- **Opt-in vs. mandatory inventory tetris** (pillars 3 + 5). Resolved in
  principle (opt-in, auto-pack default) but the UX of offering both without
  clutter is unbuilt.
- **Where the difficulty curve comes from** (pillars 2 + 4). With no stat
  growth, late-game interest must come from build complexity and the mystery
  layer. Needs the ending/mystery design to actually carry that weight.
