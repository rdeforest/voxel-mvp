# Performance Budget

Target: 60fps on GTX 1660-class hardware (16.7ms frame time).

| System                | Budget | Strategy                                                |
|-----------------------|--------|---------------------------------------------------------|
| Voxel meshing         | 8ms    | godot_voxel threading; tune chunk distance              |
| Structural integrity  | 2ms    | Compute on modification, not per-frame; cache results   |
| Scattering            | 4ms    | MultiMeshInstance3D, frustum culling, LOD               |
| Physics               | 4ms    | Simplified colliders, sleep distant bodies              |
| AI                    | 2ms    | Max 20 active enemies, simple state machines            |
| Rendering             | 12ms   | Forward+, limited shadows, no volumetric fog            |
| Game logic            | 2ms    | Event-driven crafting/inventory                         |

Note that the sum exceeds 16.7ms — this is *budget*, not *reservation*.
Most systems don't burn their budget every frame. The table is for
identifying which system is over-spending when frame time slips, not
for static reservation.

The principle from the manifesto applies: **hardware keeps improving.**
This budget targets the GTX 1660 because that's the Steam Hardware
Survey's low-end floor. Optimizing for hardware below that is not the
project's job.

The FEAT043 (budget-consumption telemetry) work in Phase 5.5h is what
turns this table from aspirational into verifiable.
