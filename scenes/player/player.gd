extends CharacterBody3D

var _movement:   PlayerMovement
var _camera_rig: CameraRig

# Edit modes
var edit_modes:            Array[EditMode] = []
var edit_mode_index:       int             = 0

var wireframe_enabled  := false
var _build_rotation:   Vector3i = Vector3i.ZERO  # 0-3 steps of 90° per axis (X, Y, Z)

var _key_actions:          Dictionary
var _mouse_button_actions: Dictionary

# Node references
@onready var head:         Node3D              = $Head
@onready var camera:       Camera3D            = $Head/Camera3D
@onready var mode_label:   Label               = $HUD/BoxContainer/ModeLabel
@onready var edit_preview: MeshInstance3D      = $EditPreview
@onready var integrity:    StructuralIntegrity = get_parent().get_node("StructuralIntegrity")
@onready var terrain:      VoxelLodTerrain     = get_parent().get_node("VoxelLodTerrain")

# Terrain editing
const EDIT_RADIUS   = 3.0
const EDIT_STRENGTH = 5.0
const EDIT_REACH    = 20.0

const SPHERE_RADIAL_SEGMENTS = 16
const SPHERE_RINGS           =  8

var _parts: Array[Part] = [
    preload("res://assets/parts/board/board.tres"),
    preload("res://assets/parts/plank/plank.tres"),
    preload("res://assets/parts/stud/stud.tres"),
    preload("res://assets/parts/beam/beam.tres"),
]
var _part_index:    int             = 0
var _build_meshes:  Array[BoxMesh]  = []

var _materials:      Array[StringName] = [&"Wood", &"Stone", &"Metal", &"Dirt", &"Sand"]
var _material_index: int               = 0

@onready var raycast: RayCast3D = $Head/RayCast3D


func _ready() -> void:
    _movement   = PlayerMovement.new(self)
    _camera_rig = CameraRig.new(self, $Head)
    # Capture the mouse cursor for FPS controls
    Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

    # shared resources for terrain edit previews
    var sphere             := SphereMesh.new()
    sphere.radius           = EDIT_RADIUS
    sphere.height           = EDIT_RADIUS * 2.0
    sphere.radial_segments  = SPHERE_RADIAL_SEGMENTS
    sphere.rings            = SPHERE_RINGS

    var plane := PlaneMesh.new()
    plane.size             = Vector2(EDIT_RADIUS * 2.0, EDIT_RADIUS * 2.0)

    var dig_mat     := _make_preview_material(Color(1.0, 0.2, 0.2, 0.3))
    var fill_mat    := _make_preview_material(Color(0.2, 0.4, 1.0, 0.3))
    var flatten_mat := _make_preview_material(Color(1.0, 0.9, 0.2, 0.4))
    var build_mat   := _make_preview_material(Color(1.0, 1.0, 0.5, 0.4))

    for p in _parts:
        var box := BoxMesh.new()
        box.size = p.dimensions
        _build_meshes.append(box)

    edit_modes = [
        EditMode.new()                                            \
            .named("Dig")                                         \
            .on_make_action(_make_dig_action)                     \
            .preview_mesh(    func(_hp, _hn): return sphere)      \
            .preview_material(func(_hp, _hn): return dig_mat)     \
            .preview_position(func( hp,  hn): return hp - hn * (EDIT_RADIUS * 0.5)),

        EditMode.new()                                            \
            .named("Fill")                                        \
            .on_make_action(_make_fill_action)                    \
            .preview_mesh(    func(_hp, _hn): return sphere)      \
            .preview_material(func(_hp, _hn): return fill_mat)    \
            .preview_position(func( hp,  hn): return hp + hn * (EDIT_RADIUS * 0.5)),

        EditMode.new()                                            \
            .named("Flatten")                                     \
            .on_make_action(_make_flatten_action)                 \
            .preview_mesh(    func(_hp, _hn): return plane)       \
            .preview_material(func(_hp, _hn): return flatten_mat) \
            .preview_position(func( hp, _hn): return hp)          \
            .preview_basis(   func(_hp,  hn):
                var n := _get_flatten_normal()
                if n == Vector3.ZERO: n = hn
                if n.is_equal_approx(Vector3.UP):   return Basis.IDENTITY
                if n.is_equal_approx(Vector3.DOWN): return Basis(Vector3.RIGHT, Vector3.DOWN, Vector3.FORWARD)
                var up      := n
                var right   := up.cross(Vector3.UP).normalized()
                var forward := right.cross(up).normalized()
                return Basis(right, up, forward)),

        EditMode.new()                                                                  \
            .named("Build")                                                             \
            .on_make_action(_make_construction_action)                                  \
            .preview_mesh(    func(_hp, _hn): return _build_meshes[_part_index])        \
            .preview_material(func(_hp, _hn): return build_mat)                         \
            .preview_position(_build_preview_position)                                  \
            .preview_basis(   func(_hp, _hn): return _build_rotation_basis()),

        EditMode.new()                                          \
            .named("Remove")                                    \
            .on_make_action(_make_removal_action)               \
            .preview_mesh(    func(_hp, _hn): return null)      \
            .preview_material(func(_hp, _hn): return null)      \
            .preview_position(func( hp, _hn): return hp),
    ]

    edit_preview.player = self
    raycast.target_position = Vector3(0, 0, -EDIT_REACH) # negative Z is forward
    _key_actions          = {
        KEY_TAB:          _cycle_edit_mode,
        KEY_Q:            _quit_game,
        KEY_F:            _toggle_wireframe,
        KEY_V:            _toggle_debug_visuals,
        KEY_M:            _cycle_material,
        KEY_R:            _rotate_build_y,
        KEY_T:            _rotate_build_x,
        KEY_Y:            _rotate_build_z,
        KEY_BRACKETLEFT:  _prev_part,
        KEY_BRACKETRIGHT: _next_part,
    }
    _update_mode_label()

    _mouse_button_actions = {
        MOUSE_BUTTON_LEFT: _try_edit_terrain,
    }

func _make_preview_material(color: Color) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()

    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.albedo_color = color
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.cull_mode    = BaseMaterial3D.CULL_DISABLED

    return mat

func current_mode() -> EditMode:
    return edit_modes[edit_mode_index]

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        _on_key_pressed(event)
    elif event is InputEventMouseMotion:
        _on_mouse_motion(event)
    elif event is InputEventMouseButton:
        _on_mouse_button_pressed(event)

func _cycle_edit_mode():
    edit_mode_index = (edit_mode_index + 1) % edit_modes.size()
    _update_mode_label()

func _prev_part() -> void:
    _part_index = (_part_index - 1 + _parts.size()) % _parts.size()
    _update_mode_label()

func _next_part() -> void:
    _part_index = (_part_index + 1) % _parts.size()
    _update_mode_label()

func _cycle_material() -> void:
    _material_index = (_material_index + 1) % _materials.size()
    _update_mode_label()

func _toggle_debug_visuals() -> void:
    integrity.set_debug_visuals_enabled(not integrity.debug_visuals_enabled)

func _update_mode_label() -> void:
    var mode := current_mode()
    if mode.mode_name == "Build":
        mode_label.text = "%s: %s (%s)" % [mode.mode_name, _part_name(_parts[_part_index]), _materials[_material_index]]
    else:
        mode_label.text = mode.mode_name

func _part_name(part: Part) -> String:
    return part.resource_path.get_file().get_basename()

func _on_mouse_motion(event: InputEventMouseMotion) -> void:
    _camera_rig.handle_mouse_motion(event)

func _on_key_pressed(event: InputEventKey) -> void:
    if event.is_action_pressed("ui_cancel"):
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
        return

    if _key_actions.has(event.keycode):
        _key_actions[event.keycode].call()

func _toggle_wireframe():
    wireframe_enabled = not wireframe_enabled
    get_viewport().debug_draw = (
        Viewport.DEBUG_DRAW_WIREFRAME
        if wireframe_enabled
        else Viewport.DEBUG_DRAW_DISABLED
    )

func _on_mouse_button_pressed(event: InputEventMouseButton) -> void:
    if event.pressed:
        if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
            if _mouse_button_actions.has(event.button_index):
                _mouse_button_actions[event.button_index].call()
                return
        else:
            Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _quit_game():
    get_tree().quit()

func _process(_delta: float) -> void:
    var hovered: Node3D = null
    if raycast.is_colliding():
        var collider := raycast.get_collider() as Node3D
        if collider != null and integrity.has_part(collider):
            hovered = collider
    integrity.set_hovered_part(hovered)

func _physics_process(delta: float) -> void:
    _movement.tick(delta)


func _try_edit_terrain() -> void:
    if not raycast.is_colliding():
        return
    var hit_pos    := raycast.get_collision_point()
    var hit_normal := raycast.get_collision_normal()
    var action: Action = current_mode().make_action.call(hit_pos, hit_normal)
    if action == null:
        return
    if action.validate():
        action.execute()
    # else: refused. Feedback mechanism comes later.


# --- Action factories (the "targeting" layer for each mode) ---

func _make_dig_action(hit_pos: Vector3, hit_normal: Vector3) -> Action:
    var center := hit_pos - hit_normal * (EDIT_RADIUS * 0.5)
    return DigAction.new(center, EDIT_RADIUS, terrain, integrity)

func _make_fill_action(hit_pos: Vector3, hit_normal: Vector3) -> Action:
    var center := hit_pos + hit_normal * (EDIT_RADIUS * 0.5)
    return FillAction.new(center, EDIT_RADIUS, terrain, integrity, self)

func _make_flatten_action(hit_pos: Vector3, hit_normal: Vector3) -> Action:
    var flatten_normal := _get_flatten_normal()
    if flatten_normal == Vector3.ZERO:
        flatten_normal = hit_normal
    var center := hit_pos - hit_normal * (EDIT_RADIUS * 0.5)
    return FlattenAction.new(center, hit_pos, flatten_normal, EDIT_RADIUS, terrain, self, integrity)


func _get_flatten_normal() -> Vector3:
    if Input.is_key_pressed(KEY_SHIFT):
        # Horizontal: always flatten level
        return Vector3.UP

    if Input.is_key_pressed(KEY_CTRL):
        # Vertical: wall facing the direction you're looking
        # Get the camera's forward direction, flattened to horizontal
        var forward := camera.global_transform.basis.z
        forward.y = 0.0
        return forward.normalized()

    # Default: use the surface normal
    return Vector3.ZERO  # sentinel meaning "use hit normal"


func _rotate_build_y() -> void:
    _build_rotation.y = (_build_rotation.y + 1) % 4

func _rotate_build_x() -> void:
    _build_rotation.x = (_build_rotation.x + 1) % 4

func _rotate_build_z() -> void:
    _build_rotation.z = (_build_rotation.z + 1) % 4

func _build_rotation_basis() -> Basis:
    var b := Basis.IDENTITY
    b = b.rotated(Vector3.RIGHT,   _build_rotation.x * PI * 0.5)
    b = b.rotated(Vector3.UP,      _build_rotation.y * PI * 0.5)
    b = b.rotated(Vector3.FORWARD, _build_rotation.z * PI * 0.5)
    return b

# Preview is a centered BoxMesh on a MeshInstance3D — the rotated mesh's
# Y centroid is at the MeshInstance3D's global_position.y. Lift it so the
# rotated bottom face lands at the hit point.
func _build_preview_position(hp: Vector3, _hn: Vector3) -> Vector3:
    var part      := _parts[_part_index]
    var rot_basis := _build_rotation_basis()
    var aabb      := AABB(-part.dimensions * 0.5, part.dimensions)
    var rotated   := Transform3D(rot_basis, Vector3.ZERO) * aabb
    return Vector3(roundi(hp.x), hp.y + rotated.size.y * 0.5, roundi(hp.z))

func _make_removal_action(_hit_pos: Vector3, _hit_normal: Vector3) -> Action:
    var collider := raycast.get_collider()
    if collider == null or not integrity.has_part(collider):
        return null
    return RemovalAction.new(collider, integrity)

func _make_construction_action(hit_pos: Vector3, _hit_normal: Vector3) -> Action:
    var placement_pos := Vector3(roundi(hit_pos.x), floor(hit_pos.y), roundi(hit_pos.z))
    var anchor        := Vector3i(roundi(hit_pos.x), floori(hit_pos.y), roundi(hit_pos.z))
    return ConstructionAction.new(_parts[_part_index], placement_pos, anchor, _build_rotation, _materials[_material_index], terrain, integrity, self)
