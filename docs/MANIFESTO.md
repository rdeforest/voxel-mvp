# Manifesto

> Read this first. If something later in the docs contradicts what's here,
> what's here wins.

This document exists because vision drift is the most expensive failure mode
this project can suffer. The architecture is unusual, the schedule is
nonexistent, and almost every well-meaning instinct from professional
software development pushes in the wrong direction. The manifesto's job is
to make those wrong directions explicit so they can be recognized in the
moment, before another phase quietly gets "tightened up to ship faster."

---

## The thesis, in one paragraph

The voxel-versus-heightmap argument has been won at the level of *demos* —
VoxelFarm, Teardown, Deep Rock Galactic, Enshrouded have all shipped
proof points. What hasn't been built is a **persistent open-world survival
game on voxel-first principles** where terrain and construction are the
same kind of data, structural integrity governs both, caves are first-class
spaces, and nothing resets. The project's bet is that **a field-based
representation meshed with Dual Contouring + QEF** (Miguel Cepero's
approach, demonstrated over a decade ago and still not in shipping games)
is the right substrate, and that a solo developer with modern AI tooling
can deliver the proof faster than a team can.

---

## Infinite programming resources

The deeper thesis, stated as a question: **what kind of game do I get when I'm
willing to devote infinite programming resources to it?** Design choices here are
made *as if programming effort were unlimited* — because for the purpose of
deciding what is *right*, it is. There is no schedule, no budget, no team to
coordinate. The only finite resource is attention, and attention is spent getting
things *right*, not getting them *done*.

This is what makes the project more ambitious than anything before it, Dwarf
Fortress included. Toady is brilliant, but the question he answered was "what can
one person sustain over decades?" The question here is "what becomes possible if
you refuse every limitation that comes from resource scarcity — *what if we had no
limitations at all?*"

### No half-measures

Breaking a change into small, reversible parts is good engineering — keep doing
it. **Settling for a lesser solution when a no-compromise solution is available is
not.** These are different things; do not confuse them. Small steps toward the
right end are correct. A smaller *end* is not.

The only legitimate trade-offs are **hardware limits** — looks versus performance
on real silicon. Those are physics. A trade-off justified by "this is more
programming work," "the simpler version is good enough," "let's keep it opt-in,"
or "we can revisit it later" is illegitimate: it is the Enterprise trap wearing a
humble face. When two solutions both work and one is a compromise, the compromise
is wrong even if it is smaller, faster to write, or more familiar.

When Claude Code proposes "as-is," "good enough for now," "accept the slower
path," or "defer the hard part," that is the habit, not the thesis — override it.
(It has already happened: a 3-second GDScript mesh proposed as "smooth enough,
it's off-thread" when a C++ port made it 44ms; the DC render layer proposed as
"keep it opt-in" when making it the default render was the actual goal. Both were
corrected by Robert. Catch them before he has to.)

---

## What this project is NOT

These are the anti-goals. When in doubt, the project is *more* unlike each
of these than you think.

- **Not a commercial endeavor.** There is no revenue target, no runway, no
  investor expectation. v1.0 may eventually ship on Steam as open-source
  with cloud-save extras, but that is a distribution decision, not a
  business plan. "Will this scale" and "is this monetizable" are not
  inputs to any architectural decision.

- **Not on a schedule.** There are no deadlines. Time estimates only
  matter if they run into decades. Phases are work descriptions, not
  delivery commitments. "This should ship by X" is not a sentence that
  applies here. Pace is set by attention and energy, not by a calendar.

- **Not Minecraft, not Valheim with better graphics, not an MMO.** It
  borrows verbs from Valheim because they're good verbs, and inspiration
  from Teardown's physics and DRG's destruction feel because those are
  best-in-class. The point is not to make a better version of an existing
  game; it's to prove the architectural thesis. Resemblance is incidental.

- **Not a tech demo dressed up as a game.** The thesis includes that this
  has to be *fun* (the v0.1 question), and eventually *real* (the v0.9
  question). But scope creep toward "real game" before the thesis is
  defended at each stage is exactly how this dies.

- **Not Enterprise software.** This deserves its own section.

---

## The Enterprise trap

Most of the well-trained instincts both Robert and Claude Code bring to
this project come from Enterprise software, where the right answers are:

- Reduce scope to ship sooner.
- Defer hard problems behind well-defined interfaces.
- Prefer the boring, proven solution.
- Optimize for predictable delivery.
- Treat ambitious technical bets as risk to be mitigated.

**These are the wrong instincts here.** Scope reduction has already
happened to this project at least once where neither of us caught it in
the moment — a phase got tightened up to ship faster, and the work that
came out the door was smaller than the work the thesis needed. Enterprise
experience said "always a good idea." It was not a good idea.

The corrected instincts for *this* project:

- **The hard problem IS the project.** If a phase's scope is being reduced
  to get something shipping, ask whether what's being cut is the part that
  proved the thesis. If yes, the right move is to take longer, not ship
  smaller.
- **Boring solutions are how you get Valheim's heightmap.** Cepero's
  field-based DC-QEF approach is *more* ambitious than what godot_voxel
  ships, and that ambition is the point. The project exists *because*
  nobody else has done it.
- **Predictable delivery is irrelevant.** Nobody is waiting on this. There
  is no quarter, no demo day, no stakeholder.
- **"Risk" is a finance term.** Architectural bets that look risky in an
  Enterprise context are the project's entire reason for existing.

When Claude Code (or future-Robert) suggests scope reductions, defers a
hard problem, or proposes a "simpler" path, the question to ask is:
**does this serve the thesis, or does it serve a habit?** If it's a habit,
override it.

---

## The non-negotiables

Stated as assertions, not paragraphs. If a proposed change violates one
of these, the change is wrong.

1. **Terrain and construction are the same kind of data.** Anything that
   reintroduces a part/terrain dichotomy is regression.
2. **No loading screens.** Caves, underground spaces, dungeons — same
   continuous volume as the surface.
3. **Modifications persist everywhere, forever.** No "outside your base
   area resets" Enshrouded compromise.
4. **Operations fail honest.** When an op can't cleanly do the intended
   thing, it produces truthful geometry — even if that means opening a
   void — rather than faking a result. Heightmap engines fake; voxel
   engines tell the truth.
5. **The same physical rules apply to everything.** Structural integrity
   governs terrain, parts, vehicles, and anything else made of matter,
   with the same algorithm and the same visual language.
6. **Hardware keeps improving.** Don't over-optimize for 2025 hardware.
   The 100 km² world at 5mm detail is ~1.5 TB as a surface octree, on
   2026 NVMe. The exabyte/terabyte ratio that storage compression buys is
   the project premise, vindicated by hardware year over year.
7. **The grid is a multi-channel spatial database, not a renderable
   surface.** SDF is one channel. Material is another. Temperature,
   pressure, momentum can be more — possibly at different resolutions.
   Roles and identities ("this is a wall belonging to player X's house")
   live in sidecar indexes, not in the voxel data itself.

---

## What "losing sight of the vision" looks like

Specific failure modes, named so they can be caught in the moment:

- **Cube thinking.** Treating a voxel as a cube of matter rather than a
  sample of a field. The cube is the most common case of a primitive
  that defines a closed space; it is not the primitive itself. The
  rock in Cepero's blog was never one voxel — it was a contoured
  isosurface threaded through a neighborhood of samples. Anytime
  reasoning starts with "one voxel is..." or "the voxel at position
  (x,y,z) is solid," check whether cube thinking has crept in.

- **Part/terrain dichotomy.** Treating placed objects and natural terrain
  as fundamentally different things requiring different systems. The
  current shipped code has a remnant of this (separate part-support and
  terrain-support algorithms) for good engineering reasons, but the
  *long-term* direction is one field, one representation, one mesher.
  Anytime a new feature is being designed as "parts do this, terrain
  does that," ask if the unified answer is being skipped because it's
  harder.

- **Faking surfaces.** Adding code that makes the world look right when
  the underlying data doesn't support it. The horizontal-flatten-fakes-a-
  floor bug is the canonical example. If you find yourself writing a
  workaround that lies about geometry, stop and fix the data instead.

- **Scope reduction to ship faster.** Already happened once. The
  characteristic move: "let's defer X to v0.next so we can land this
  sooner." Sometimes legitimate (X is genuinely later-phase work that
  drifted forward). Often Enterprise habit (X is the hard part of the
  phase and dropping it makes the phase trivial). Ask which.

- **Optimizing for hardware that doesn't matter.** Performance work
  targeting machines below GTX 1660-class is not the project's job. The
  premise is that hardware keeps improving; the architecture should be
  *correct*, not *fast on a 2020 laptop*.

- **Treating Claude Code's output as authoritative.** Claude Code is a
  productivity accelerant tuned by training data heavy in Enterprise
  patterns. It will sometimes suggest scope reductions, type-narrow
  ambitious interfaces, or propose architectural retreats that sound
  reasonable. When it does, the question is not "is this advice sound
  in general?" but "does it serve the thesis?" Often the answer is no.

- **Drifting toward "real game" features before the thesis is defended
  at each stage.** Survival mechanics, combat, AI, inventory polish —
  these are v0.9 work. If they start landing in v0.1 because "the game
  needs them," the thesis is not being defended; it's being papered
  over.

---

## The Hytale lesson, in one line

**Ship the working thing.**

The full case study lives in `roadmap/vision/hytale-case-study.md`. The
one-line version is enough for most decisions: if there is a working
implementation and someone proposes rewriting it, the burden of proof is
on the proposal, not on the existing code.

---

## How to use this document

- Read it before starting a new phase.
- Re-read it when Claude Code proposes a scope change.
- Re-read it when a session has been going for hours and a "let's just"
  is forming.
- Cite specific sections by name in commit messages or design docs when
  a decision is downstream of the manifesto (e.g. "rejecting the
  type-narrowed API per manifesto Enterprise trap").

If updating *this* document takes more than half an hour, the update is
probably wrong — the manifesto should be stable. The roadmap is where
plans churn.
