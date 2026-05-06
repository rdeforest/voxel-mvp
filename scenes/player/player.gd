extends CharacterBody3D

# Movement
const SPEED             = 8.0
const JUMP_VELOCITY     = 6.0
const MOUSE_SENSITIVITY = 0.002

# Gravity (use Godot's built-in project gravity)
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Node references
@onready var head:   Node3D   = $Head
@onready var camera: Camera3D = $Head/Camera3D

func _ready() -> void:
	# Capture the mouse cursor for FPS controls
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
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

	# Click to recapture mouse
	if event is InputEventMouseButton and event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Terrain editing with mouse buttons
	if event is InputEventMouseButton and event.pressed:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_try_edit_terrain(0)  # Dig 
				return
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_try_edit_terrain(1)  # Fill
				return
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		
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
	
# Terrain editing
const EDIT_RADIUS   = 3.0
const EDIT_STRENGTH = 5.0
@onready var raycast: RayCast3D = $Head/RayCast3D

func _try_edit_terrain(mode: int) -> void:
	if not raycast.is_colliding():
		return

	var hit_pos := raycast.get_collision_point()
	var hit_normal := raycast.get_collision_normal()

	# Get the VoxelLodTerrain node — adjust path if your scene tree differs
	var terrain := get_parent().get_node("VoxelLodTerrain") as VoxelLodTerrain
	if terrain == null:
		return

	var voxel_tool := terrain.get_voxel_tool()
	voxel_tool.channel = VoxelBuffer.CHANNEL_SDF

	# Offset position slightly along normal for better results
	var edit_center: Vector3
	if mode == 0:  # Remove (dig)
		edit_center = hit_pos - hit_normal * (EDIT_RADIUS * 0.5)
	else:  # Add (fill)
		edit_center = hit_pos + hit_normal * (EDIT_RADIUS * 0.5)

	voxel_tool.mode = VoxelTool.MODE_REMOVE if mode == 0 else VoxelTool.MODE_ADD
	voxel_tool.do_sphere(edit_center, EDIT_RADIUS)
