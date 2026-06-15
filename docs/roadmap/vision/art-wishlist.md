# Art Wishlist

A running list of art assets we'd want. Maintained as something to hand to
artists who ask "what could I help with?" — *not* a commitment to ship all
of it, and not in priority order within a category.

## Project conventions

- **License**: CC0 or compatible permissive (CC-BY at the strictest). The
  game code will be open-source eventually; assets should match.
- **Style**: stylized realism in the Valheim/Enshrouded family — soft
  Transvoxel terrain, hand-painted-feeling textures, low-to-mid-poly
  models. *Not* Minecraft-blocky despite being voxel-based.
- **Coordinate scale**: world units are metres; one voxel = 1m. Models
  sized accordingly.
- **Texture authoring**: PBR-friendly (albedo + roughness at minimum,
  normal/AO if practical). Single-material per asset where possible to
  keep draw calls cheap.
- **Animation budget**: real-time on a GTX 1660-class GPU. Vertex
  displacement is OK for grass and similar; skeletal animation is
  reserved for characters.

---

## HUD icons (highest near-term value)

The tool/activity UI is currently text-only. Icons would dramatically
improve readability. Each icon should read at ~32×32px and ~64×64px.

### Tool icons (3)
- **None** — observe/walk-around. Eye, hand, or footprint.
- **Landscape** — shovel, trowel, or pickaxe + flat hand combo.
- **Construction** — hammer, square, or wrench.

### Landscape activity icons (7)
- **Dig** — pickaxe / hole.
- **Fill** — pile of dirt / dome shape.
- **Flatten** — flat trowel / level.
- **Raise** — upward arrow over terrain.
- **Lower** — downward arrow over terrain.
- **FillVoxel** — single block being placed.
- **EmptyVoxel** — single block being removed.

### Construction activity icons (2)
- **Build** — hammer or wrench.
- **Remove** — hammer with red X / "minus."

### Material icons (5)
- **Wood** — grain pattern.
- **Stone** — rough surface.
- **Metal** — polished/reflective surface.
- **Dirt** — granular brown.
- **Sand** — granular tan.

### Part icons (4)
Should communicate cross-section shape and proportion.
- **Board** — wide thin plank from side, end-grain visible.
- **Plank** — narrower than board, similar otherwise.
- **Stud** — square cross-section, ~2m long.
- **Beam** — thick square cross-section, longer than stud.

(Will grow as more parts are added.)

---

## Terrain textures

The terrain currently uses a procedural shader (slope-based grass/dirt
with wind animation). Real textures would replace the flat colours.

- **Grass** — short-bladed, top-down-ish, tileable. Subtle colour
  variation. Animation handled by the shader; the texture itself doesn't
  need frames.
- **Dirt** — packed earth, slightly damp-looking, tileable.
- **Stone / cliff** — rough rock, tileable, works well on near-vertical
  surfaces (since dirt fades to it at >30° slopes).
- **Sand** — beach/dune sand, tileable. (Not used in any biome yet,
  reserved for v0.1 biome work.)
- **Snow** — for future cold biomes.

Each ideally with an accompanying normal map.

---

## Part models

Parts are currently procedural box meshes. Hand-modelled parts with
visible material character would be a huge visual upgrade.

- **Wooden parts** (board, plank, stud, beam): visible grain, end-cut
  surfaces, slight bevelled edges. Single mesh per part, textured.
- **Stone parts**: chiselled or rough-hewn faces. Future.
- **Metal parts**: forged or riveted. Future.
- **Joinery hints**: optional — small detail like a peg, notch, or
  mortise at the cell-aligned faces. Reads as "this is a real piece of
  craft, not a primitive."

---

## VFX

Particle systems and shaders for the "this feels alive" moments.

- **Dig dust** — short-lived puff of soil-coloured particles at dig
  point.
- **Fill spray** — small cascade of material falling into place.
- **Flatten chips** — small chips/dust along the cut plane.
- **Strain crumble** — slow trickle of dust from cells under strain,
  ramping up as collapse nears.
- **Collapse burst** — large dust cloud at the moment a region breaks
  loose.
- **Part-break splinters** (future) — wood splinters / stone chips when
  a part is destroyed.
- **Wind leaves** (future) — for trees / vegetation.

---

## Sound (related — though "audio art" usually has its own person)

Not strictly visual art but goes alongside.

- **Footsteps** — variants per material (grass, dirt, stone, sand,
  wood-on-part). Short loop or one-shot per step.
- **Tool sounds** — dig, fill, flatten, build, remove. Distinct so the
  player learns by ear.
- **Ambient** — wind, distant birdcall by biome.
- **Structural** — creaks of straining parts, a low rumble before
  collapse, the actual collapse impact.

---

## Sky / environment

- **Skybox or improved procedural sky** — the current
  `ProceduralSkyMaterial` is fine but generic. A painted-ish skydome
  with weather variants would help atmosphere.
- **Sun / moon discs** — when the day/night cycle is enabled.
- **Cloud shader** — slow-moving, volumetric-cheap.
- **Atmosphere fog** — distance and altitude-banded.

---

## Player avatar (later)

- **First-person hands** — visible at the bottom of the screen during
  edit. Animated grip per tool.
- **Full body** (much later, for multiplayer / third-person) — humanoid
  rig, walk/run/jump/swing animations.

---

## UI surfaces (later)

- **Crosshair** — currently absent or default. Subtle, mode-aware (e.g.
  different reticle for Landscape vs Construction).
- **Menu / pause screen** — main menu, settings.
- **Save / load UI** — slot picker for save management beyond F5/F9.

---

## World decoration (v0.1 biomes onward)

When biomes land, we'll want scatterable props:

- **Trees** — at least two silhouettes per biome (sapling + adult).
  Eventually: choppable, with directional fall.
- **Rocks** — boulders and rubble for scatter. Distinct from terrain
  voxels (they're scene props, not SDF).
- **Grass tufts / bushes** — vegetation density.
- **Mushrooms / small plants** — visual richness.
- **Water shader** — sea, rivers; reflections, shoreline foam.
