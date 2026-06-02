# Answered Questions

Questions that came up during planning and have committed answers.
Kept here so they don't have to be re-relitigated.

## Should we track Godot master or stable?

**Track stable.** Zylann publishes pre-built godot_voxel binaries for
each Godot stable branch — there are builds for 4.3, 4.4, 4.4.1, 4.5,
and 4.6. He also now offers experimental GDExtension builds (plugin
format, no engine recompile needed). Godot's stable releases come
every 3–6 months and maintain backward compatibility within the 4.x
series.

Tracking master would mean compiling both Godot and godot_voxel from
source on every update, dealing with API breakage, and debugging
issues that might be Godot's fault vs. the module's. For an MVP where
the goal is validating the idea, that's pure friction. Pin to Godot
4.6 stable + the matching godot_voxel release.

## Can the Ryzen 9 7900X iGPU serve as a low-end performance target?

**No — it's far too weak.** The 7900X's integrated graphics is 2 CUs
of RDNA 2 (128 shaders). AMD designed it as a display adapter for
troubleshooting and basic desktop use, not gaming. In benchmarks it
struggles to hit 17–23 FPS in modern games at 1080p low settings. It
sits roughly in GT 1030 territory.

A GTX 1660 has 1,408 CUDA cores and 6GB of dedicated VRAM — it's
roughly 10–15× more powerful. The 7900X iGPU would be testing "can
this run at all?" not "is this performant?"

**Better options for a low-end target:**
- A spare older GPU (even a GTX 1050 Ti), plugged into a test rig.
- A used GTX 1060 6GB or RX 580 ($40–60) representing the Steam
  Hardware Survey's low-end floor reasonably well.
- Godot's Forward+ renderer quality settings to simulate lower-end
  GPUs on the 5090 and extrapolate.
- A $150–200 used mini PC with an AMD APU (Ryzen 5 5600G or 7600 with
  real iGPUs of 6–8 CUs).

For v0.0 validation, don't worry about this at all. Test on the 5090
and optimize later.

## Are voxels the right primitive?

**Voxels are right for the hardest part of the problem** (continuous
terrain, no loading screens, real modification, caves as first-class
spaces) **and adequate for the rest via a hybrid approach.**

Alternatives surveyed:

- **Tetrahedral / unstructured meshes:** Physically accurate, supports
  arbitrary topology. Tooling is decades behind dense voxel engines;
  no shippable game uses these.
- **CSG trees:** Lossless and semantically rich, but pathological
  after thousands of edits. Prototyping tool, not a shipping
  representation.
- **Sparse voxel octrees / OpenVDB-style structures:** Where
  godot_voxel will probably go long-term for planet-scale work.
  Dynamic editing is harder than dense chunks; tooling is research-
  grade.
- **B-rep (CAD-style):** Perfect for buildings, catastrophic for
  terrain.
- **Hybrid (voxels for terrain, mesh for construction):** What this
  project actually does today. Terrain is voxels with SDF; player-
  placed prefab pieces are traditional rigid bodies with collision
  meshes; the structural integrity system is the connective tissue
  that lets them speak the same language ("how supported is this
  thing, regardless of what kind of thing it is").

The instinct to worry about "what if a voxel is two types of cell?"
is a category error. The voxel stores *what the matter is*. Whether
that matter is *part of a building* or *part of a load-bearing
structure* is a role, not a property — and roles live in sidecar
indexes maintained by their owning systems. This is the same pattern
as ECS.

## Are we picking a perfect hammer?

The DC-QEF transition addresses this directly. The current hybrid
(voxel terrain + mesh parts) is a *transitional* answer. The long-term
answer is one representation (field-based), one mesher (DC-QEF), one
set of rules. See [the geometry design chapter](../design/03-dc-qef-geometry.md).

## Is the DC-QEF rework a Hytale-style rewrite?

**No.** Hytale rewrote the entire engine. The DC-QEF transition
replaces one layer (meshing, ~15–20% of what godot_voxel does for us)
while keeping storage, streaming, LOD, and engine glue. The migration
is bounded, scope-isolated, and has a clear test (does it produce
correct meshes for the same SDF as the current Transvoxel mesher).

The Hytale lesson is "don't rewrite to satisfy hypothetical future
requirements." The DC-QEF transition satisfies a *current* requirement
(off-grid surfaces) that no amount of cleverness with Transvoxel can
address.
