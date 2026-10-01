# Known Contradictions

Places where two docs disagree, or a doc disagrees with a decision Robert has
made since it was written. A session that hits one of these should not pick a
side on its own: follow the "Current best reading" if one is given, otherwise
ask Robert. When an item is resolved, fix the docs involved and delete the
item here (git keeps the history).

Opened 2026-09-30 by Claude, from a read of the roadmap during the
story-cards / autonomy session. Affected docs carry a one-line banner
pointing here.

---

## C1. Commercial, and on a schedule?

- **Status (2026-09-30):** the manifesto now says this is an open question.
  The decision waits on defining the game, then feasibility estimates, then
  Robert's call on whether it's his first commercial project. What remains
  here is the v1.0 doc, which still says "not a commercial endeavor";
  rewrite it once the decision is made.
- **The docs say:** the manifesto's anti-goals ("Not a commercial endeavor",
  "Not on a schedule", "no demo day") and the v1.0 doc
  (`implementation/planned/12-v1_0-steam-release.md`).
- **Robert said (chat, September 2026):** the project is now commercial and
  on a schedule: by the next relevant Steam Fest, or not as the first
  product. Separately, still undecided (deliberately deferred) whether
  *name, First* is the first self-supporting commercial game at all.
- **Why it matters:** the manifesto wins over everything, so every session
  currently inherits "no schedule" while the real constraint is a Fest date.
- **Current best reading:** the manifesto's open-question stance.

## C2. Enemies, bosses, dungeons

- **The docs say:** v0.9 (`implementation/planned/11-v0_9-survival-product.md`)
  plans enemy AI and combat (FEAT066, outdoor and dungeon enemies), boss
  encounters as progression gates (FEAT067), procedural dungeons (FEAT068),
  and material fatigue justified by "mobs hammering on structures" (FEAT071).
- **Against:** pillar 7 (no violence against any humanoid Other; the only
  "enemies" are small fauna), pillar 4 (threat-gating), pillar 2 (no stat
  curve, so bosses-as-gates have nothing to gate), volcano story §2 (no large
  predators), and the 2026-09-28 creature decisions (wildlife follows habitat;
  creatures react to the world but don't reshape it).
- **Current best reading:** the pillars and the 09-28 decisions win; v0.9's
  combat section predates them. Caves stay (non-negotiable #2), but as lava
  tubes from the volcano's grammar, not dungeons with enemies.

## C3. Matchmaking

- **The docs say:** the version table's v1.0 row and FEAT076 list Steam
  matchmaking.
- **Against:** doc 06 ("no matchmaking of any kind ever ships"), and the
  scope boundary that makes this project single-player.
- **Current best reading:** no matchmaking. Steam extras are cloud saves and
  achievements.

## C4. Workbench radius

- **The docs say:** FEAT075, "build only near workbench" (Valheim mechanic,
  marked tentative).
- **Against:** pillar 3 (limits are physical, never arbitrary).
- **Current best reading:** out, unless someone finds a physical reason for it.

## C5. Survival loop stats

- **The docs say:** FEAT065 lists health, stamina, hunger, food buffs, comfort.
- **Against (possibly):** pillar 2 (no capability growth; fatigue is a
  constant constraint) and pillar 4 (hunger arrives only after the first
  cooked meal). Temporary food buffs may or may not count as capability
  growth.
- **Current best reading:** needs Robert on food buffs; the rest should be
  re-specified as threat-gated constraints rather than meters.

## C6. World setting

- **The docs say:** `design/09-world-setting.md`, "iron-age, distinctly not
  Norse", a placeholder.
- **Against:** `vision/04-volcano-story.md`, which settled the setting: one
  dormant volcano island, a dream, primitive tools from the island.
- **Current best reading:** the volcano story wins; doc 09 is superseded and
  should be deleted or replaced with a pointer.

## C7. DC-QEF transition and the storage layer

- **The docs say:** `implementation/01-version-strategy.md` calls the DC-QEF
  transition future work ("most likely v0.2") that keeps godot_voxel's
  storage, streaming and LOD.
- **Actually:** the transition shipped (its plan is in `done/`), and the
  EditStore (design 11) replaced godot_voxel as the data layer. Since
  2026-09-27 the EditStore is itself a cache; truth is generator functions
  plus the op log.
- **Current best reading:** the code and the 09-27 decisions; the version
  strategy section is stale.

## C8. The stale-docs list from 2026-09-27

Carried over from the ClodForest handoff so it lives in the repo:

1. ~~Manifesto opening paragraph~~ (fixed 2026-09-30, with non-negotiable #1).
2. Doc 23 (thin features) should record the 09-27 decisions: part meshes
   ship, appearance follows history, the field is a cache, simulation results
   are written back as exact shapes to the op log, physics is co-simulated
   sub-solvers.
3. Doc 03: "no separate part data type", §4 discarding shape identity, and
   "The field is the world" are superseded.
4. Anything calling EditStore "the only terrain store" should say cache.
5. Doc 23's history says sub-metre was on until 09-13; evidence suggests it
   was turned off ~06-22 during crack debugging and swept into `59ac2f4` on
   09-13. Confirm from session logs.
6. Any design doc describing coupled ecosystems, emergent predator/prey
   dynamics, or creature lifecycle detail should be checked against the
   09-28 creature decisions (see C2). Not yet swept.

---

## Not contradictions: open questions

Recorded so nobody mistakes a proposal for a decision.

- **Is the game materials-centered?** Proposed by Claude on 2026-09-28, not
  adopted by Robert. Open; the story-card deck is meant to answer it.
- **A name for the line between demo scope and the ultimate vision.**
  "The Fest line" was suggested; not chosen.
- **The demo's physics hero moment** (the trailer clip), which decides which
  solver pieces must exist by the Fest.
