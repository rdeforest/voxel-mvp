# The Elevator Pitch (Long Form)

The short version lives at
[`../vision/01-elevator-pitch.md`](../vision/01-elevator-pitch.md).
This is the version with the architectural argument spelled out, for
when someone wants the case rather than just the hook.

---

Valheim chose a heightmap engine in 2018 and has spent 7+ years
working around its limitations: loading screens for caves, floating
buildings, fake terrain modification, no overhangs. This project
proves that a voxel engine — built today with modern tools and AI-
assisted development — delivers the same core gameplay without those
compromises.

Your house grows out of the mountain. Your mine connects to a natural
cave. Dig too wide and the ceiling warns you before it collapses.
Reinforce it with pillars and keep going. The world is one continuous
space, governed by one set of physical rules.

The architectural bet is older than this project: Miguel Cepero
(VoxelFarm) demonstrated all the core ideas on his Procedural World
blog over a decade ago. Smooth field-based geometry with sharp
features where the field has creases. Adaptive octree sampling.
Imprinting brushes that throw away their source identity. A mesh
extraction step that lives entirely separate from physics. Cepero's
engine ended up pivoting to GIS and architecture markets because the
game industry didn't fund voxel-first development.

Meanwhile Enshrouded shipped voxel survival and immediately punted on
persistence (modifications outside your base reset). Deep Rock
Galactic nailed the feel of voxel destruction but isn't persistent.
Teardown nailed structural physics but isn't open-world. Hytale burned
$100M and ten years rewriting an engine that already worked. Nobody
has shipped a persistent open-world survival game on voxel-first
principles with unified structural integrity for terrain and
construction.

That's the gap this project fills. Solo developer, modern AI tooling,
no investors, no schedule, no commercial pressure to compromise on the
architecture. Open-source release of the game code when v1.0 ships;
Steam handles distribution and value-added features (cloud saves,
matchmaking) only.

The thesis was defended at v0.0: you can dig a tunnel, build a house
into the hillside, watch the cave ceiling warn you before it collapses,
and reinforce it with pillars. v0.1 adds biomes, resources, crafting,
and proves the gameplay loop. v0.2 is the visual identity pass and the
DC-QEF transition that collapses the part/terrain dichotomy
permanently. v0.9 ships multiplayer (decentralized op-log replication
in the style of Willow/Earthstar), combat, and the locomotive demo
that puts the field-based representation through its paces. v1.0 ships
on Steam.

The pace is set by attention, not deadlines.
