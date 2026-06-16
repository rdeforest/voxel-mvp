# DC: crease normals not stored — sharp edges shade soft

**Status:** Deferred, conditional (doc 14 Bite E storage half). Low priority — fine on terrain + fat parts.

## Symptom
Sharp edges on edits/built structures shade with a soft bevel instead of a crisp crease.

## Cause
The C++ mesher uses field-gradient normals (one averaged normal per vertex). The crease-aware normal
*splitting* (regroup a vertex's faces by angle, split at a crease) is done in the GDScript prototype
(`MeshNormals`) but not in the C++ path; and godot_voxel stores scalar SDF only, so crisp creases need
point+normal at crossings stored or recomputed.

## Fix
Port crease-normal splitting to the C++ mesher; store/recompute Hermite (point+normal) at crossings.
Revisit when the art pass needs crisp edges (it's a v0.2 art-pass concern). Pairs with the low-poly art
lever idea (coarse terrain reads better with line art).

## References
doc 14 "Bite E"; `CLAUDE.md` Architecture #7 NOTE.
