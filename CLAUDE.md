# CLAUDE.md

Guidance for Claude Code and other agents working in this repository.

This file is **routing and operating instructions only**. It deliberately does
not restate content another doc owns — when it disagrees with the doc it points
at, the doc wins.

## Read these first, in this order

1. **`docs/MANIFESTO.md`** — the vision authority. If anything anywhere
   contradicts it, the manifesto wins. Read it before proposing anything
   architectural.
2. **`docs/CODE-MAP.md`** — where the code lives and what the conventions are.
   Read the sections relevant to your task before editing.
3. **`docs/STATUS.md`** — the current resumption brief. Where we are, what's
   next, what's paused and why.
4. **`docs/BUILD.md`** — build, run, test, and the editor-clobber protocol.
   **Read the clobber section before touching `.tscn` files or `.godot/`.**

Also useful: `docs/roadmap.md` (version strategy and the immovable
architectural commitments), `docs/roadmap/design/architecture.md` (mechanism
rationale), `docs/bugs/00_INDEX.md` (open defects),
`docs/roadmap/vision/06-what-the-game-is.md` (what the game is for a player).

## The one stance to internalize

The manifesto states it in full; this is the operational summary, because it
inverts habits you will otherwise apply by reflex.

**Infinite programming resources. No half-measures.** Design choices are made
as if programming effort were unlimited. The only legitimate trade-offs are
hardware limits — looks versus performance on real silicon. "This is more
work," "the simpler version is good enough," "let's keep it opt-in," and "we
can revisit it later" are not legitimate reasons to choose a lesser solution.

This inverts the usual "prefer the boring, minimal solution" instinct **for
architecture and scope**. Minimalism still applies to code *expression* — small
diffs, no needless complexity. It does not apply to ambition.

Breaking a change into small reversible steps is good engineering. Settling for
a smaller *end* is not. These are different things.

When you are about to propose "as-is," "opt-in," "defer the hard part," or
"accept the slower path": that's the Enterprise habit, not the thesis.
Override it, and say out loud that you nearly didn't.

This has already gone wrong twice, both caught by Robert rather than by the
agent: a 3-second GDScript mesh proposed as "smooth enough, it's off-thread"
when a C++ port made it 44 ms; and the DC render layer proposed as "keep it
opt-in" when making it the default render was the actual goal. Catch these
before he has to.

## Working agreements

- **Tests gate everything.** Run GUT before and after a change set. Report the
  counts. A change that moves the pass count without explanation is not done.

- **Diagnose before fixing.** Instrument first when the cause isn't known.
  Guessing at a perf fix without a measurement is not acceptable here.

- **Refuse-don't-deform applies to you too.** If a request can't be satisfied
  cleanly, say so rather than producing something that looks right.

- **Don't scope-reduce a phase to close it.** If the hard part of a phase is
  being cut, that's the phase.

- **Update `docs/STATUS.md` after a session** — rewrite the Resumption Brief,
  don't append to it. If the update takes more than ten minutes, the doc's
  shape is wrong, not the session.

- **Attribute authored prose.** Docs drafted by an agent carry a line saying
  so. Robert's repo, Robert's voice by default; anything else gets labelled.

- **Vendor addons, don't submodule them.** See `docs/CODE-MAP.md`.
