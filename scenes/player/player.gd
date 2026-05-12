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

# Node references
@onready var head:         Node3D              = $Head
@onready var camera:       Camera3D            = $Head/Camera3D
@onready var mode_label:   Label               = $HUD/CenterContainer/ModeLabel
@onready var edit_preview: MeshInstance3D      = $EditPreview
@onready var integrity:    StructuralIntegrity = get_parent().get_node("StructuralIntegrity")

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
            .on_execute(_edit_dig)                                \
            .preview_mesh(    func(_hp, _hn): return sphere)      \
            .preview_material(func(_hp, _hn): return dig_mat)     \
            .preview_position(func( hp,  hn): return hp - hn * (EDIT_RADIUS * 0.5)),

        EditMode.new()                                            \
            .named("Fill")                                        \
            .on_execute(_edit_fill)                               \
            .preview_mesh(    func(_hp, _hn): return sphere)      \
            .preview_material(func(_hp, _hn): return fill_mat)    \
            .preview_position(func( hp,  hn): return hp + hn * (EDIT_RADIUS * 0.5)),

        EditMode.new()                                            \
            .named("Flatten")                                     \
            .on_execute(_edit_flatten)                            \
            .preview_mesh(    func(_hp, _hn): return plane)       \
            .preview_material(func(_hp, _hn): return flatten_mat) \
            .preview_position(func( hp, _hn): return hp),
    ]

    edit_preview.player = self
    raycast.target_position = Vector3(0, 0, -EDIT_REACH) # negative Z is forward

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
    # Change edit mode
    if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
        edit_mode_index = (edit_mode_index + 1) % edit_modes.size()
        mode_label.text = edit_modes[edit_mode_index].mode_name

    # Mouse look
    if event is InputEventMouseMotion:
        # Rotate body left/right
        rotate_y(-event.relative.x * MOUSE_SENSITIVITY)

        # Rotate head up/down, clamped so you can't backflip
        head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
        head.rotation.x = clampf(head.rotation.x, -PI / 2.0, PI / 2.0)

    # Press Escape to free the mouse (useful for debugging)
    if event.is_action_pressed("ui_cancel"):
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

    if event is InputEventKey and event.pressed and event.keycode == KEY_F:
        wireframe_enabled = not wireframe_enabled
        get_viewport().debug_draw = (
            Viewport.DEBUG_DRAW_WIREFRAME
            if wireframe_enabled
            else Viewport.DEBUG_DRAW_DISABLED
        )

    if event is InputEventMouseButton and event.pressed:
        # Terrain editing with mouse buttons
        if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
            if event.button_index == MOUSE_BUTTON_LEFT:
                _try_edit_terrain()
                return
        else:
            # Click to recapture mouse
            Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

    if event is InputEventKey and event.pressed and event.keycode == KEY_Q:
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
    var hit_pos := raycast.get_collision_point()
    var hit_normal := raycast.get_collision_normal()
    current_mode().execute.call(hit_pos, hit_normal)


func _get_voxel_tool() -> VoxelTool:
    var terrain := get_parent().get_node("VoxelLodTerrain") as VoxelLodTerrain

    if terrain == null:
        return null

    var vt := terrain.get_voxel_tool()
    vt.channel = VoxelBuffer.CHANNEL_SDF

    return vt


func _edit_dig(hit_pos: Vector3, hit_normal: Vector3) -> void:
    var voxel_tool := _get_voxel_tool()
    if voxel_tool == null:
        return

    var center := hit_pos - hit_normal * (EDIT_RADIUS * 0.5)

    voxel_tool.mode = VoxelTool.MODE_REMOVE
    voxel_tool.do_sphere(center, EDIT_RADIUS)

    var origin     := center - Vector3.ONE *  EDIT_RADIUS
    var dimensions :=          Vector3.ONE * (EDIT_RADIUS * 2)

    # Notify integrity manager of removed voxels
    VoxelUtils.for_each_in_bounding_box(
        origin,
        dimensions,
        func(pos: Vector3i):
            if VoxelUtils.is_in_sphere(Vector3(pos), center, EDIT_RADIUS):
                integrity.remove_voxel(pos)
    )


func _edit_fill(hit_pos: Vector3, hit_normal: Vector3) -> void:
    var voxel_tool := _get_voxel_tool()
    if voxel_tool == null:
        return

    var center := hit_pos + hit_normal * (EDIT_RADIUS * 0.5)

    voxel_tool.mode = VoxelTool.MODE_ADD
    voxel_tool.do_sphere(center, EDIT_RADIUS)

    var origin     := center - Vector3.ONE *  EDIT_RADIUS
    var dimensions :=          Vector3.ONE * (EDIT_RADIUS * 2)

    # Notify integrity manager of placed voxels
    VoxelUtils.for_each_in_bounding_box(
        origin,
        dimensions,
        func(pos: Vector3i) -> void:
            if Vector3(pos).distance_to(center) <= EDIT_RADIUS:
                integrity.register_voxel(pos, Materials.STONE)
    )

    _push_player_above_terrain(voxel_tool)


func _edit_flatten(hit_pos: Vector3, hit_normal: Vector3) -> void:
    var voxel_tool := _get_voxel_tool()
    if voxel_tool == null:
        return

    # Determine which normal to flatten against
    var flatten_normal := _get_flatten_normal()
    if flatten_normal == Vector3.ZERO:
        flatten_normal = hit_normal

    var center     := hit_pos - hit_normal * (EDIT_RADIUS * 0.5)

    var origin     := center - Vector3.ONE *  EDIT_RADIUS
    var dimensions :=          Vector3.ONE * (EDIT_RADIUS * 2)

    VoxelUtils.for_each_in_bounding_box(
        origin,
        dimensions,
        func(pos: Vector3i) -> void:
            var plane_dist: float = flatten_normal.dot(Vector3(pos) - hit_pos)

            voxel_tool.set_voxel_f(pos, plane_dist)
    )

    _push_player_above_terrain(voxel_tool)


func _push_player_above_terrain(voxel_tool: VoxelTool) -> void:
    var feet_pos := global_position
    var sdf := voxel_tool.get_voxel_f(Vector3i(
        roundi(feet_pos.x),
        roundi(feet_pos.y),
        roundi(feet_pos.z)
    ))

    # Negative SDF means we're inside terrain
    if sdf >= 0.0:
        return

    # March upward until we find air
    for i in range(1, 20):
        var check_pos := Vector3i(
            roundi(feet_pos.x),
            roundi(feet_pos.y + float(i)),
            roundi(feet_pos.z)
        )
        var check_sdf := voxel_tool.get_voxel_f(check_pos)

        if check_sdf >= VoxelConstants.SDF_SOLID_THRESHOLD:
            global_position.y = feet_pos.y + float(i) + VoxelConstants.VOXEL_SIZE
            return

    # If we somehow can't find air in 20 voxels, just pop up a lot
    global_position.y += 30.0

func _get_flatten_normal() -> Vector3:
    if Input.is_key_pressed(KEY_SHIFT):
        # Horizontal: always flatten level
        return Vector3.UP

    if Input.is_key_pressed(KEY_CTRL):
        # Vertical: wall facing the direction you're looking
        # Get the camera's forward direction, flattened to horizontal
        var forward := -camera.global_transform.basis.z
        forward.y = 0.0
        return forward.normalized()

    # Default: use the surface normal
    return Vector3.ZERO  # sentinel meaning "use hit normal"
