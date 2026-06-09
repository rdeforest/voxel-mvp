# docs/roadmap — Index

The planning corpus, split into four sections. Each entry notes *why the
doc or section exists*, not what it contains. On a first visit, read the
sections in order; on a return visit, jump to the chapter you need.

The manifesto at [`../MANIFESTO.md`](../MANIFESTO.md) supersedes anything
here. If a chapter and the manifesto disagree, the manifesto wins.

## Sections

- [`vision/`](vision/00_INDEX.md) — answers *why this project exists*; read
  before any decision that feels architectural.
- [`design/`](design/00_INDEX.md) — the non-implementation specs: *what the
  answer is*, independent of when it ships.
- [`implementation/`](implementation/00_INDEX.md) — the temporal axis:
  phases, versions, and the work-order tying designs to delivery.
- [`reference/`](reference/00_INDEX.md) — lookup material: tables,
  answered questions, and other non-narrative facts.

## How the sections relate

| Question                                | Section        |
|-----------------------------------------|----------------|
| Why are we doing this?                  | Vision         |
| What is the answer (when we get there)? | Design         |
| When and in what order does it happen?  | Implementation |
| Where do I look up a fact?              | Reference      |

A single concern often spans sections: when something has both a permanent
shape and a one-shot migration, the permanent shape lives in `design/` and
the migration lives in `implementation/`. When a design chapter ships, its
mechanism rationale moves into [`../architecture.md`](../architecture.md)
and its decisions are added to
[`design/02-architectural-commitments.md`](design/02-architectural-commitments.md);
the chapter itself is then deleted or condensed.
