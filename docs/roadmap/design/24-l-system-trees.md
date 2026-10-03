# Trees as Grown Structure (L-systems) — idea, parked

*Drafted by Claude (Claude Code session), 2026-10-02, from a ClodForest notice sent by the
CoffeeBEANS session on 2026-10-01. **Nothing here is decided.** It records an idea so that it
doesn't develop only inside a CoffeeBEANS sketch. The manifesto wins if this disagrees with it.*

## Where it came from

Robert is about to write a 2D L-system sketch in CoffeeBEANS (`sketches/` in that repo) and thinks
it bears on this game. The CoffeeBEANS session read README, [STATUS](../../STATUS.md) and
[doc 21](21-tech-ladders-and-fire.md) and sent this connection over.

## The gap

The docs cover terrain, parts (board, plank, stud, beam), structural integrity, felling
([doc 08](08-continuous-work-actions.md)) and fire with specific wood pairings
([doc 21](21-tech-ladders-and-fire.md)). None of them say where trees come from. The only hint is
one line in [doc 06](06-channel-architecture.md): "The tree might be an iterated function system
for its geometry."

## The fit

An L-system generates a tree as a real branching structure of segments, not as a mesh. Each
segment has a length, a radius and a parent. A part has the same shape. So a grown tree could
pass through the existing structural-integrity algorithm: a limb is a cantilevered span, and
felling is the removal of support. "One system, one set of physical rules" would then cover living
wood too, and doc 08's notch-cut felling would come out of the physics instead of being scripted.

## Three variants and what each buys

- **Parametric** (symbols carry numbers): segment length and thickness, and growth over time as
  the same grammar evaluated to a greater depth. A sapling and an old tree are one definition.
- **Stochastic** (a symbol has several rules, one picked at random): every tree of a species is
  different.
- **Species as a parameter set** (angle, branching rule, taper): matches doc 21's interest in
  which woods pair for fire. Species would decide both a tree's shape and what its wood does.

The 3D version uses the standard turtle extension: a heading/left/up frame with yaw, pitch and
roll symbols.

## First question for whoever picks this up

Is a tree made of parts, or of voxels, or of parts that become voxels when felled? The
parts-as-voxels history ([doc 23](23-thin-features.md)) and the MPM freeze/thaw transition
([doc 12](12-mpm-structural-substrate.md)) are the relevant precedents.
