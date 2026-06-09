class_name DcSubstratePreview
extends MeshInstance3D

# Phase B diagnostic: render the store-over-generator substrate so it can be eyeballed
# against the live clipmap render. Builds a SparseVoxelOctree from the analytic
# TerrainField (fine near the player, graded coarser out), meshes it (DC, world-fixed,
# NO camera input -> view-independent by construction), and shows the result tinted
# cyan, overlaid on the existing terrain.
#
# One-shot per `dcgen` toggle (rebuilds at the player's current position) — no movement
# tracking or worker thread yet. The threaded, edit-aware re-meshing manager that
# actually replaces the clipmap is the next bite; this proves the field -> octree ->
# mesh path works in the live world first.

# Terrain params — mirror tools/build_terrain_graph.gd until the generator's home is
# decided (editor graph vs C++-single-source). TerrainField matches the graph's noise.
const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337

const ROOT_SIZE := 256.0   # world cube spanning the preview, centred on the player
const NEAR_LEAF := 1.0     # finest leaf at the focus
const BAND      := 24.0    # leaf size doubles every BAND metres from the focus

var _follow: Node3D


func setup(follow: Node3D) -> void:
    _follow = follow
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.25, 0.85, 1.0)
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
    mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
    material_override = mat
    visible = false


# Build the octree at the player's current position and show its mesh. Returns the
# triangle count so the caller can report it (0 = the cube held no surface).
func rebuild() -> int:
    if _follow == null:
        return 0
    var focus  := _follow.global_position
    var origin := focus - Vector3.ONE * (ROOT_SIZE * 0.5)
    var octree := SparseVoxelOctree.new()
    octree.setup(origin, ROOT_SIZE)
    octree.imprint_terrain_graded(focus, NEAR_LEAF, BAND, BASE, AMP, PERIOD, OCTAVES, SEED)
    var arrays := octree.mesh()
    var m := ArrayMesh.new()
    var tris := 0
    var idx := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
    if idx.size() > 0:
        m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        @warning_ignore("integer_division")
        tris = idx.size() / 3
    mesh = m
    global_position = Vector3.ZERO   # octree mesh vertices are already world-space
    visible = true
    return tris


func clear() -> void:
    visible = false
    mesh = null
