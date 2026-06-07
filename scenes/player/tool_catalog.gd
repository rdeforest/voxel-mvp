class_name ToolCatalog
extends RefCounted

# Four top-level tools, each holding a list of activity EditModes:
#   None         — probe-only
#   Landscape    — Dig, Fill, Flatten, Raise, Lower, FillVoxel, EmptyVoxel
#   Construction — Build, Remove
#   Assembly     — Add Snap, Remove Snap (edit a placed part's snap points)

var tools: Array[Tool] = []


func _init(action_factories: ActionFactories, build_state: BuildState, csg_state: CsgState) -> void:
    tools = _build_catalog(action_factories, build_state, csg_state)


# Lambdas below close over the local `af`, `bs`, `cs` and mesh/material vars
# rather than over `self`. Capturing self would create a cycle that
# prevents the RefCounted catalog from freeing when the player exits.
func _build_catalog(af: ActionFactories, bs: BuildState, cs: CsgState) -> Array[Tool]:
    var build_mat := _make_preview_material(Color(1.0, 1.0, 0.5, 0.4))
    var csg_add   := _make_preview_material(Color(0.4, 1.0, 0.5, 0.35))   # green  — union
    var csg_sub   := _make_preview_material(Color(1.0, 0.4, 0.35, 0.35))  # red    — difference
    var csg_mat   := func(): return csg_add if cs.op == CsgState.Op.ADD else csg_sub

    var none_activities: Array[EditMode] = [
        EditMode.new()                                            \
            .named("Probe")                                       \
            .on_make_action(af.make_probe)                        \
            .preview_mesh(    func(_hp, _hn): return null)        \
            .preview_material(func(_hp, _hn): return null)        \
            .preview_position(func( hp, _hn): return hp)          \
            .placement_offset(true)                               \
            .keep_offset(true),
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
            .preview_position(func( hp, _hn): return _ghost_mesh_position(af.build_placement_pos(hp), bs))   \
            .preview_basis(   func(_hp, _hn): return bs.rotation_basis())                                    \
            .air_placement(   true)                                                                          \
            .placement_offset(true),

        EditMode.new()                                          \
            .named("Remove")                                    \
            .on_make_action(af.make_removal)                    \
            .preview_mesh(    func(_hp, _hn): return null)      \
            .preview_material(func(_hp, _hn): return null)      \
            .preview_position(func( hp, _hn): return hp),
    ]

    var assembly_activities: Array[EditMode] = [
        EditMode.new()                                         \
            .named("Add Snap")                                 \
            .on_make_action(af.make_add_snap)                  \
            .preview_mesh(    func(_hp, _hn): return null)     \
            .preview_material(func(_hp, _hn): return null)     \
            .preview_position(func( hp, _hn): return hp),

        EditMode.new()                                         \
            .named("Remove Snap")                              \
            .on_make_action(af.make_remove_snap)               \
            .preview_mesh(    func(_hp, _hn): return null)     \
            .preview_material(func(_hp, _hn): return null)     \
            .preview_position(func( hp, _hn): return hp),
    ]

    var csg_activities: Array[EditMode] = [
        _csg_mode("Box",      CsgSdf.Shape.BOX,      af, cs, csg_mat),
        _csg_mode("Cylinder", CsgSdf.Shape.CYLINDER, af, cs, csg_mat),
        _csg_mode("Sphere",   CsgSdf.Shape.SPHERE,   af, cs, csg_mat),
    ]

    return [
        Tool.new("None",         none_activities),
        Tool.new("Landscape",    landscape_activities),
        Tool.new("Construction", construction_activities),
        Tool.new("Assembly",     assembly_activities),
        Tool.new("CSG",          csg_activities),
    ]


# One CSG activity. The ghost is the live primitive mesh at the placement point,
# rotated by the CSG basis, tinted by op (green add / red subtract), with an
# arrow marking the axis the resize wheel currently grows. CSG only stamps onto a
# real surface hit: aiming at nothing shows an inert (greyed) ghost floated at 2x
# the shape's largest dimension (so it doesn't fill the screen) and a click is a
# no-op (act_on_air false).
static func _csg_mode(p_name: String, shape: int, af: ActionFactories, cs: CsgState, csg_mat: Callable) -> EditMode:
    return EditMode.new()                                            \
        .named(p_name)                                               \
        .shape(shape)                                                \
        .on_make_action(af.make_csg)                                 \
        .preview_mesh(    func(_hp, _hn): return cs.current_mesh())  \
        .preview_material(func(_hp, _hn): return csg_mat.call())     \
        .preview_position(func( hp, _hn): return af.csg_placement_pos(hp))  \
        .preview_basis(   func(_hp, _hn): return cs.rotation_basis())       \
        .axis_arrow(      func():         return cs.axis_dir())             \
        .air_placement(   true)                                            \
        .act_on_air(      false)                                           \
        .air_distance(    func(): return 2.0 * cs.bounding_extent())       \
        .placement_offset(true)


static func _make_preview_material(color: Color) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.albedo_color = color
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
    return mat


# Centered BoxMesh preview: the rotated mesh's Y centroid sits at the
# MeshInstance3D's global_position.y. Lift it so the rotated bottom face lands at
# placement_pos.y. placement_pos is already the snapped free-placement target.
static func _ghost_mesh_position(placement_pos: Vector3, bs: BuildState) -> Vector3:
    var part      := bs.current_part()
    var rot_basis := bs.rotation_basis()
    var aabb      := AABB(-part.dimensions * 0.5, part.dimensions)
    var rotated   := Transform3D(rot_basis, Vector3.ZERO) * aabb
    return Vector3(placement_pos.x, placement_pos.y + rotated.size.y * 0.5, placement_pos.z)
