# Edit & Movement Lifecycles (explain-like-I'm-five)

Two things happen over and over in this game: the player **changes the world** (digs, builds)
and the player **moves through it**. This doc traces both, start to finish, in plain language —
what actually happens between "player does a thing" and "the screen shows it." It's the mental
model the [incremental-LOD-splice work](roadmap/design/13-incremental-lod-splice.md) builds on.

## The cast (in plain terms)

- **The generator** — a *recipe* for the untouched world. Give it any point in space and it
  tells you "rock" or "air." It's just math; it stores nothing. The whole infinite landscape is
  this recipe until someone edits it.
- **The EditStore** — a *coloring book over the recipe*. The recipe is the printed picture; the
  EditStore holds only the spots where the player colored over it with crayon. Ask it about a
  point: if the player edited there, it returns the crayon; otherwise it falls through to the
  recipe. It stores **only what changed**, so an untouched world costs nothing.
- **The mesh** — the actual *triangles you see*. The generator and EditStore describe the world
  as numbers; the mesh turns those numbers into a surface you can look at. Building it is the
  expensive part.
- **The clipmap** — *detail that follows you like a spotlight*. Fine triangles right around the
  player, coarser triangles farther out, coarsest on the horizon. It re-centers on you as you
  move, so you always have crisp ground underfoot and cheap ground in the distance.
- **Workers** — *background helpers*. Heavy jobs (turning numbers into triangles) run on a worker
  thread so the game stays smooth. The main thread hands off the job and keeps running; later it
  picks up the finished triangles.
- **The bus** — a *town crier*. When something changes, whoever caused it shouts one message
  ("the terrain changed in this box!") and everyone who cares (the renderer, collision, physics)
  hears it without being wired directly together.

---

## Lifecycle 1 — The player edits (digs / builds)

You click. Here's the whole journey from click to "I can see the hole."

1. **Aim.** The game traces a line from the camera into the world and finds the point you're
   pointing at (a sphere-trace through the field, so it's accurate down to a quarter-metre).
2. **Make an action.** The current tool turns that hit point into an **Action** object — "dig a
   sphere here," "place this beam here." The Action first **asks permission** (`validate()`):
   would this bury the player? float in mid-air? If the rules say no, it refuses and nothing
   happens. (We *refuse*, we don't half-do.)
3. **Color the coloring book.** If allowed, the Action **stamps the EditStore** — it writes the
   new shape (and material) into that sparse crayon-over-recipe structure. This is the moment the
   world's *data* actually changes. Building a part isn't a separate kind of thing; it's just
   crayon shaped like a beam.
4. **Shout it.** The Action tells the town crier: "terrain changed, in *this* box." It doesn't
   call the renderer or physics directly — it just announces.
5. **Three listeners react** to that one shout:
   - **The renderer** (the part we're improving) queues a **splice**: re-mesh a small box around
     the edit and swap those triangles into what's on screen. More below.
   - **Collision** re-cooks a small patch of "solid you can stand on" near where you're standing,
     so you don't fall through your own edit.
   - **Structural physics** wakes up and checks: did you just dig the support out from under
     something? Should anything fall now?
6. **The splice, step by step** (the renderer's reaction):
   - The edit's box goes into a short **queue**.
   - On a later frame, a **worker** picks it up: it reads the field (generator + your crayon)
     around the box and turns it into a small patch of triangles.
   - When the worker finishes, the **main thread swaps** the old triangles in that box for the new
     patch — pure list surgery, fast — and uploads the result. *Now you see the hole.* (That's the
     blue tick in the perf graph: "a new mesh just landed.")
7. **Why it can feel slow.** Steps 6's worker job is the heavy bit. If the box is big, or if the
   renderer has to fall back to rebuilding *everything* instead of just the box, the gap between
   your click and the blue tick stretches. That gap — and shrinking it — is the whole point of
   the incremental-LOD-splice work.

**One-line version:** click → check the rules → color the coloring book → shout → a worker
re-meshes just the changed box → swap it onto the screen.

---

## Lifecycle 2 — The player moves (walks / flies)

You hold W. Here's what keeps the world correct as you go.

1. **Every physics tick**, the player code does the boring, reliable stuff: gravity pulls you
   down, WASD pushes you around, the mouse turns your head, jumps launch you. (Until the world
   has finished loading at startup, this is *switched off* — no falling through ground that
   hasn't grown in yet. A "world is ready" shout flips it on.)
2. **The spotlight follows.** Remember the clipmap — fine detail centered on you. As you walk,
   that center needs to keep up with you.
3. **Re-center when you've drifted enough.** The renderer watches how far you've moved from where
   the detail is currently centered. Once you've wandered past a threshold (about 8 metres), it
   **rebuilds the clipmap** centered on your new spot — on a worker, so you don't stutter — and
   swaps in the fresh mesh. Small movements cost nothing; you only pay when you've actually gone
   somewhere.
4. **Collision tags along.** A small patch of "stand-on-able solid" is kept cooked right under
   you and scrolls along as you move, so the ground is always physically there even though the
   pretty triangles are managed separately.
5. **Detail is distance-based.** Closer = finer, farther = coarser, decided by how big a triangle
   would look on screen. Move toward a hill and its detail sharpens; move away and it coarsens.

**One-line version:** move → when you've drifted far enough, rebuild the follow-the-player detail
spotlight (and keep a little patch of collision cooked under your feet).

---

## Why these two share a future

Today, **moving** rebuilds the whole spotlight (expensive, but rare — only when you've traveled),
and **editing** *tries* to patch just the changed box but often gives up and does that same whole
rebuild. The plan ([doc 13](roadmap/design/13-incremental-lod-splice.md)) is to make **both**
work the same cheap way: only ever re-mesh the small region that actually changed — whether it
changed because you *edited* it or because you *moved* and its detail level shifted. Same
machinery, no full rebuilds. This doc is the "before" picture; that's the "after."
