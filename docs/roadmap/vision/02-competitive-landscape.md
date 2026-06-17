# Competitive Landscape

What exists in adjacent space, where each project compromised, and where
this one fits.

## Enshrouded (Keen Games, Early Access January 2024)

The closest competitor to this project's vision. Keen Games built a
proprietary voxel engine for a survival-action RPG set in a voxel-based
continent. The building and terraforming are genuinely impressive —
players can carve stairs into cliffs, dig underground bases, and shape
terrain with fine-grained control.

**What they got right:**
- Proved the market wants voxel-based survival with real terrain modification
- Building system that feels artistic and precise, not just functional
- Voxel-based world that looks realistic, not blocky
- Solid commercial success in early access

**Where they compromised:**
- Terrain modifications outside your base area reset to their original
  state. This is the single biggest player complaint. The stated reason
  is save data management — a solved problem that Minecraft handled 15
  years ago with chunk diffs. A terabyte of SSD costs $150. This decision
  sacrifices immersion for engineering convenience.
- No structural integrity system. You can build floating structures in
  midair. This removes the engineering-puzzle aspect of construction
  entirely.
- Loading screens still exist for certain transitions.
- No cave reinforcement mechanics — caves are static geometry.

**Our direct advantages over Enshrouded:**
1. Persistent terrain modification everywhere, not just near your base
2. Unified structural integrity for terrain AND structures
3. Cave reinforcement as a gameplay mechanic
4. Continuous work actions instead of click-spam
5. Material physics (angle of repose, structural properties)

## Deep Rock Galactic (Ghost Ship Games, 2020)

Not a survival game, but the gold standard for "terrain destruction that
feels good." Fully destructible procedurally generated cave systems where
digging is a core traversal and combat mechanic. Sold over 8 million
copies. Proves that voxel terrain deformation can be performant,
satisfying, and central to a game loop.

**What to learn:** The *feel* of their terrain destruction — the sound
design, particle effects, and immediate visual feedback when you drill
through rock. Study their chunk meshing performance. Their terrain is
ephemeral (per-mission), so they never had to solve persistence, but
their real-time deformation is best-in-class.

## Teardown (Tuxedo Labs, 2022)

The gold standard for voxel structural simulation. Every object in the
world is made of voxels with physical properties. Structures collapse
realistically when supports are removed. Not a survival game — it's a
heist/puzzle game — but its physics engine is proof that structural
integrity simulation at game-scale is achievable and fun.

**What to learn:** Their structural simulation algorithm. When you remove
voxels, connected components are evaluated and unsupported sections
become physics objects. This is exactly the behavior we want for cave
ceilings and unsupported building sections. Their fracture mechanics —
breaking along computed failure surfaces rather than voxel boundaries —
are the model for Phase 5.5c.

## Hytale (Hypixel Studios, Early Access January 2026)

A cautionary tale more than a competitor. See
[`03-hytale-case-study.md`](03-hytale-case-study.md) for the full study.
Blocky Minecraft-style voxels with excellent world generation and modding
tools. After $100M and 10 years of development, it shipped on a four-
year-old legacy build after the "improved" engine was abandoned. Its
world generation system is worth studying; its development history is
worth studying harder.

## VoxelFarm (Engine/Middleware)

Not a game but an engine — the most technically ambitious voxel terrain
system in existence. Miguel Cepero's work. Smooth SDF terrain with
real-time editing, LOD, and procedural generation, all using field-based
DC-QEF representation. Originally targeted games but has pivoted to
architecture, simulation, and GIS products. This pivot likely reflects
the game industry's reluctance to fund voxel-first game development
despite the technology being ready.

**This is the project the current roadmap aspires to follow.** Cepero
demonstrated all the core ideas in his public Procedural World blog over
a decade ago. The DC-QEF spec in
[`../design/03-dc-qef-geometry.md`](../design/03-dc-qef-geometry.md) is
essentially "do what Miguel already showed how to do, in our own
clean-room implementation."

**The gap VoxelFarm's pivot reveals:** The tech exists. The market
demand exists (see Enshrouded's sales, DRG's 8M copies). What's missing
is someone willing to build a game on voxel-first principles without
either (a) compromising on persistence and physics (Enshrouded) or
(b) drowning in scope creep (Hytale). That's the gap this project fills.

## Alientrap (Unannounced, In Development ~2025)

The studio behind Apotheon and Capsized is building an unannounced
multiplayer survival game described as "Astroneer-like setting, Teardown
voxel physics, in a Valheim-like online multiplayer survival game." Tech
demos show voxel physics with gravity and connected-object simulation.
Worth monitoring — this is the closest anyone has come to announcing a
project in this exact design space. Their Astroneer-like sci-fi setting
means minimal thematic overlap with our iron-age direction.

## Spiritfarer (Thunder Lotus Games, 2020) — tonal inspiration, not a tech competitor

The entries above are voxel/physics competitors — adjacent in *technology*.
Spiritfarer is adjacent in *tone*, and on no other axis: a hand-drawn
management-adventure about ferrying the dead to their final passage, built
on gentleness rather than conflict. It shares none of this project's terrain,
voxel, or structural-integrity concerns, and that is the point of listing it
separately.

**What to learn:** the proof that a game can be wholly engaging without a
single hostile verb. Spiritfarer is the lived example of several pillars at
once — *comprehension over conquest* (no game-sanctioned violence), *no
manipulation the player would resent*, the *dream/death layer* the late game
spends its weight on, and the hand-drawn, watercolor-adjacent art direction.
Where Teardown and DRG show how destruction should *feel*, Spiritfarer shows
the emotional register the rest of the experience should sit in — that care,
loss, and letting-go can carry a game that never asks the player to fight.

## The competitive summary

Nobody has shipped a persistent open-world survival game with:
- Real volumetric terrain that never resets
- Unified structural integrity for terrain and construction
- Cave reinforcement as gameplay
- Seamless underground-to-surface continuity (no loading screens)

Enshrouded came closest and punted on persistence and physics. Deep Rock
nailed the feel but isn't persistent. Teardown nailed the physics but
isn't open-world survival. VoxelFarm proved the tech but never shipped
a game. The intersection of all four is unoccupied.
