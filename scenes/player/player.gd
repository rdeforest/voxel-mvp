extends CharacterBody3D

# Movement
const SPEED             = 8.0
const JUMP_VELOCITY     = 6.0
const MOUSE_SENSITIVITY = 0.002

# Gravity (use Godot's built-in project gravity)
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Edit modes
var edit_modes := [
	{"name": "Dig",     "execute": _edit_dig},
	{"name": "Fill",    "execute": _edit_fill},
	{"name": "Flatten", "execute": _edit_flatten},
]
var edit_mode_index: int = 0

# Node references
@onready var head:       Node3D   = $Head
@onready var camera:     Camera3D = $Head/Camera3D
@onready var mode_label: Label    = $HUD/CenterContainer/ModeLabel

func _ready() -> void:
	# Capture the mouse cursor for FPS controls
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	# Change edit mode
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		edit_mode_index = (edit_mode_index + 1) % edit_modes.size()
		mode_label.text = edit_modes[edit_mode_index].name

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
				_try_edit_terrain()
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

func _try_edit_terrain() -> void:
	if not raycast.is_colliding():
		return

	var hit_pos := raycast.get_collision_point()
	var hit_normal := raycast.get_collision_normal()

	edit_modes[edit_mode_index].execute.call(hit_pos, hit_normal)

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

func _edit_fill(hit_pos: Vector3, hit_normal: Vector3) -> void:
	var voxel_tool := _get_voxel_tool()
	if voxel_tool == null:
		return
	var center := hit_pos + hit_normal * (EDIT_RADIUS * 0.5)
	voxel_tool.mode = VoxelTool.MODE_ADD
	voxel_tool.do_sphere(center, EDIT_RADIUS)

func _edit_flatten(hit_pos: Vector3, hit_normal: Vector3) -> void:
	var terrain := get_parent().get_node("VoxelLodTerrain") as VoxelLodTerrain
	if terrain == null:
		return

	var voxel_tool := terrain.get_voxel_tool()
	voxel_tool.channel = VoxelBuffer.CHANNEL_SDF

	# The flatten plane is defined by the hit point and hit normal.
	# We want to remove everything above the plane (in the normal direction)
	# within a radius, leaving a flat surface.

	# We'll iterate over voxels in a box around the hit point and set SDF
	# values based on their distance from the plane.
	var radius_int := int(EDIT_RADIUS) + 1
	var center := Vector3i(
		roundi(hit_pos.x),
		roundi(hit_pos.y),
		roundi(hit_pos.z)
	)

	for x in range(-radius_int, radius_int + 1):
		for y in range(-radius_int, radius_int + 1):
			for z in range(-radius_int, radius_int + 1):
				var pos := center + Vector3i(x, y, z)
				var pos_f := Vector3(pos)

				# Distance from this voxel to the hit point
				var dist_from_center := pos_f.distance_to(hit_pos)
				if dist_from_center > EDIT_RADIUS:
					continue

				# Signed distance from the plane:
				# positive = above the surface (should be air)
				# negative = below the surface (should be solid)
				var plane_dist: float = hit_normal.dot(pos_f - hit_pos)

				# Only modify voxels above the plane (remove them)
				if plane_dist > 0.0:
					voxel_tool.set_voxel_f(pos, plane_dist		)
