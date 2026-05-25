class_name ToolCatalog
extends RefCounted

# Three top-level tools, each holding a list of activity EditModes:
#   None         — probe-only
#   Landscape    — Dig, Fill, Flatten, Raise, Lower, FillVoxel, EmptyVoxel
#   Construction — Build, Remove

var tools: Array[Tool] = []


func _init(action_factories: ActionFactories, build_state: BuildState) -> void:
    tools = _build_catalog(action_factories, build_state)


# Lambdas below close over the local `af`, `bs` and mesh/material vars
# rather than over `self`. Capturing self would create a cycle that
# prevents the RefCounted catalog from freeing when the player exits.
func _build_catalog(af: ActionFactories, bs: BuildState) -> Array[Tool]:
    var build_mat := _make_preview_material(Color(1.0, 1.0, 0.5, 0.4))

    var none_activities: Array[EditMode] = [
        EditMode.new()                                            \
            .named("Probe")                                       \
            .on_make_action(af.make_probe)                        \
            .preview_mesh(    func(_hp, _hn): return null)        \
            .preview_material(func(_hp, _hn): return null)        \
            .preview_position(func( hp, _hn): return hp),
    ]

    var landscape_activities: Array[EditMode] = [
        EditMode.new()                                            \
            .named("Dig")                                         \
            .on_make_action(af.make_dig)                          \
            .preview_mesh(    func(_hp, _hn): return null)        \
            .preview_material(func(_hp, _hn): return null)        \
            .preview_position(func( hp, _hn): return hp),

        EditMode.new()                                            \
            .named("Fill")                                        \
            .on_make_action(af.make_fill)                         \
            .preview_mesh(    func(_hp, _hn): return null)        \
            .preview_material(func(_hp, _hn): return null)        \
            .preview_position(func( hp, _hn): return hp),

        EditMode.new()                                            \
            .named("Flatten")                                     \
            .on_make_action(af.make_flatten)                      \
            .preview_mesh(    func(_hp, _hn): return null)        \
            .preview_material(func(_hp, _hn): return null)        \
            .preview_position(func( hp, _hn): return hp),

        EditMode.new()                                            \
            .named("Raise")                                       \
            .on_make_action(af.make_raise)                        \
            .preview_mesh(    func(_hp, _hn): return null)        \
            .preview_material(func(_hp, _hn): return null)        \
            .preview_position(func( hp, _hn): return hp),

        EditMode.new()                                            \
            .named("Lower")                                       \
            .on_make_action(af.make_lower)                        \
            .preview_mesh(    func(_hp, _hn): return null)        \
            .preview_material(func(_hp, _hn): return null)        \
            .preview_position(func( hp, _hn): return hp),

        EditMode.new()                                            \
            .named("FillVoxel")                                   \
            .on_make_action(af.make_fill_voxel)                   \
            .preview_mesh(    func(_hp, _hn): return null)        \
            .preview_material(func(_hp, _hn): return null)        \
            .preview_position(func( hp, _hn): return hp),

        EditMode.new()                                            \
            .named("EmptyVoxel")                                  \
            .on_make_action(af.make_empty_voxel)                  \
            .preview_mesh(    func(_hp, _hn): return null)        \
            .preview_material(func(_hp, _hn): return null)        \
            .preview_position(func( hp, _hn): return hp),
    ]

    var construction_activities: Array[EditMode] = [
        EditMode.new()                                                                          \
            .named("Build")                                                                     \
            .on_make_action(af.make_construction)                                               \
            .preview_mesh(    func(_hp, _hn): return bs.current_mesh())                         \
            .preview_material(func(_hp, _hn): return build_mat)                                 \
            .preview_position(func( hp, _hn): return _compute_build_preview_position(hp, bs))   \
            .preview_basis(   func(_hp, _hn): return bs.rotation_basis()),

        EditMode.new()                                          \
            .named("Remove")                                    \
            .on_make_action(af.make_removal)                    \
            .preview_mesh(    func(_hp, _hn): return null)      \
            .preview_material(func(_hp, _hn): return null)      \
            .preview_position(func( hp, _hn): return hp),
    ]

    return [
        Tool.new("None",         none_activities),
        Tool.new("Landscape",    landscape_activities),
        Tool.new("Construction", construction_activities),
    ]


static func _make_preview_material(color: Color) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.albedo_color = color
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
    return mat


# Centered BoxMesh preview: the rotated mesh's Y centroid sits at the
# MeshInstance3D's global_position.y. Lift it so the rotated bottom face
# lands at hit_pos + placement_offset (free placement; no cell snap).
static func _compute_build_preview_position(hp: Vector3, bs: BuildState) -> Vector3:
    var part      := bs.current_part()
    var rot_basis := bs.rotation_basis()
    var aabb      := AABB(-part.dimensions * 0.5, part.dimensions)
    var rotated   := Transform3D(rot_basis, Vector3.ZERO) * aabb
    var base      := hp + bs.placement_offset
    return Vector3(base.x, base.y + rotated.size.y * 0.5, base.z)
