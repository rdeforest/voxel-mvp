# docs/roadmap/vision/handoff — Index

This directory exists to get *name, First* out of Robert's head and into a
form someone else could build from. It holds the measure for that, the
current priority, and the methods we use. Each file entry notes *why the doc
exists*, not what it contains.

## The measure: could Claude finish the project without Robert?

Recorded 2026-09-30. Prompted by Anthropic's write-up of a two-week
performance sprint run by Claude
([How we made claude.ai 3x faster](https://claude.dev/blog/how-we-made-claude-ai-faster/)).
Two things from it matter here:

- The team's standing instructions ended with: the ultimate goal is for
  Claude to become as autonomous as possible, but that isn't yet possible.
- Their central lesson: once Claude can measure something, it can improve
  it. The highest-leverage human work was finding more things to measure.

Applied to this project, the question becomes *how much of name, First is
captured, and how much is still floating around in Robert's head?* The
working measure, deliberately not objective:

> **Could Claude finish the project without Robert?**

As of 2026-09-30 the answer is a solid *no*. Optimizing toward *yes* is a
way to raise the project's velocity: every gap closed is a decision no
session has to stop and ask about, and a decision no session can quietly get
wrong.

What the sprint team kept for themselves even at full speed: **ambition**
(pushing past the targets), **taste** (ruling on anything a user would
perceive), and **direction** (which hill to climb, when to stop). "Without
Robert" doesn't mean those vanish. It means they are written down well enough
that a session can apply them the way Robert would, and can tell when a call
is genuinely new and needs him.

A rough way to read progress: when a session hits a question, how often is
the answer already in the docs?

## Ask or decide? Lean toward asking (set 2026-09-30)

While we're still figuring this out, sessions should **ask rather than
decide** whenever the docs don't clearly cover a call. The questions are the
instrument: they measure how well Robert's answers are landing. Robert's side
of the bargain is to answer at the right level, balancing general and
specific, and to separate orthogonal considerations so his answers can be
combined to settle new questions without asking again. Fewer questions over
time means that's working; a session that stops asking by guessing defeats
the measure.

## Current priority (set 2026-09-30)

**Be able to say what the game is.** This is the biggest gap Claude found in
the docs, and the same one Cecilia named when Robert visited her and Jamin.
The docs are strong on refusals (the pillars, doc 06's rejection test) and
on architecture, and thin on positive content: what an hour of play looks
like, what's on the island, what the player makes. It stays top priority for
at least two **project days**.

A project day is about six hours of Robert and Claude working on the project
together, not a calendar day.

## Methods

The ways we close the gap, roughly in order of how directly they answer
"what is the game?"

- **Story cards.** One sentence a player might tell a friend after playing,
  the way Tarn and Zach Adams define Dwarf Fortress features (500+ cards for
  DF). Robert writes; Claude sharpens (split, merge, prompt when stalled) and
  doesn't write cards of its own. Cards are GitHub issues labeled
  `story card`. A few minutes a day. Prompt: [`story-card-prompt.md`](story-card-prompt.md).
- **Demo role-play.** Robert describes the game; Claude plays the player and
  says what it wants to try; Robert says what happens. Features that come up
  get collected, then trimmed to a set that can be judged for viability.
  Started 2026-09-28 with the demo opening (tropical beach, dormant volcano,
  sand that behaves by moisture). It produces both story cards and scope
  decisions. See [`demo-role-play.md`](demo-role-play.md).
- **Named clarification sessions.** A standing routine: on a day Robert has
  the energy, he opens a session and we work on whatever most needs
  correction or clarification. See [`sessions.md`](sessions.md).
- **Agent workflow for implementation.** An author, two adversarial critics,
  and a fixer. The concrete roster in use (from `docs/STATUS.md`): an Opus
  author, an Opus correctness reviewer and a Sonnet completeness reviewer, a
  Fable tiebreak on disputes, and an Opus fixer who commits only on green
  GUT, plus an integration review after merges. It has caught real
  cross-track bugs. This doesn't define the game, but it's why
  implementation can run without Robert once the game is defined, which is
  what makes the other methods pay off.
- **Contradiction register.** Where docs disagree with each other or with
  newer decisions:
  [`../../reference/12-known-contradictions.md`](../../reference/12-known-contradictions.md).

## Files

- [`story-card-prompt.md`](story-card-prompt.md) — the prompt to paste at the
  start of a story-card session, so every session runs the same way.
- [`demo-role-play.md`](demo-role-play.md) — the role-play format and what
  it has produced so far, so the next round picks up where the last stopped.
- [`sessions.md`](sessions.md) — the named-session routine, so Robert can
  start one with a single sentence and any Claude knows what to do.
