extends CharacterBody3D

# Movement
const SPEED             = 8.0
const JUMP_VELOCITY     = 9.0
const MOUSE_SENSITIVITY = 0.002

# Gravity (use Godot's built-in project gravity)
var gravity:               float           = ProjectSettings.get_setting("physics/3d/default_gravity")

# Edit modes
var edit_modes:            Array[EditMode] = []
var edit_mode_index:       int             = 0

var wireframe_enabled := false

var _named_actions:        Dictionary
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

@onready var raycast: RayCast3D = $Head/RayCast3D


func _ready() -> void:
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
            .preview_position(func( hp, _hn): return hp),
    ]

    edit_preview.player = self
    raycast.target_position = Vector3(0, 0, -EDIT_REACH) # negative Z is forward
    _key_actions          = {
        KEY_TAB: _cycle_edit_mode,
        KEY_Q:   _quit_game,
        KEY_F:   _toggle_wireframe,
    }

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
    mode_label.text = edit_modes[edit_mode_index].mode_name

func _on_mouse_motion(event: InputEventMouseMotion) -> void:
    rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
    head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
    head.rotation.x = clampf(head.rotation.x, -PI * 0.5, PI * 0.5)

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

func _physics_process(delta: float) -> void:
    # Gravity
    if not is_on_floor():
        velocity.y -= gravity * delta

    # Jump
    if Input.is_action_just_pressed("ui_accept") and is_on_floor():
        velocity.y = JUMP_VELOCITY

    # Movement direction relative to where we're facing
    var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

    if direction:
        velocity.x = direction.x * SPEED
        velocity.z = direction.z * SPEED
    else:
        velocity.x = move_toward(velocity.x, 0, SPEED)
        velocity.z = move_toward(velocity.z, 0, SPEED)

    move_and_slide()


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
    return FlattenAction.new(center, hit_pos, flatten_normal, EDIT_RADIUS, terrain, self)


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
