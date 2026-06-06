extends CharacterBody3D

var _movement:         PlayerMovement
var _camera_rig:       CameraRig
var build_state:       BuildState
var action_factories:  ActionFactories
var tool_catalog:      ToolCatalog
var _grid_overlay:     Node3D
var _preview_renderer: Node3D
var _snap_overlay:     Node3D

var tool_index:        int       = 0
var _activity_indices: Array[int] = []   # remembered per tool

var wireframe_enabled := false

var _key_actions:          Dictionary
var _mouse_button_actions: Dictionary

@onready var head:         Node3D              = $Head
@onready var camera:       Camera3D            = $Head/Camera3D
@onready var mode_label:   Label               = $HUD/BoxContainer/ModeLabel
@onready var edit_preview: MeshInstance3D      = $EditPreview
@onready var integrity:    StructuralIntegrity = get_parent().get_node("StructuralIntegrity")
@onready var terrain:      VoxelLodTerrain     = get_parent().get_node("VoxelLodTerrain")
@onready var raycast:      RayCast3D           = $Head/RayCast3D

const EDIT_REACH := 20.0

# When an air-placement activity (Build) aims at nothing within reach, float the
# target this far along the camera ray so parts can be placed over empty space.
const AIR_PLACE_DISTANCE := 4.0

# Free-placement chord (Build only): hold Shift + (W|A|E), scroll wheel.
const WHEEL_STEP := 0.05


func _ready() -> void:
    _movement         = PlayerMovement.new(self, camera)
    _camera_rig       = CameraRig.new(self, $Head)
    build_state       = BuildState.new()
    action_factories  = ActionFactories.new(self, terrain, integrity, camera, raycast, build_state)
    tool_catalog      = ToolCatalog.new(action_factories, build_state)
    _activity_indices.resize(tool_catalog.tools.size())   # all zero
    build_state.changed.connect(_update_mode_label)

    _grid_overlay = preload("res://scenes/player/voxel_grid_overlay.gd").new()
    _grid_overlay.raycast = raycast
    get_parent().add_child.call_deferred(_grid_overlay)

    _preview_renderer = preload("res://scenes/player/voxel_preview_renderer.gd").new()
    _preview_renderer.player = self
    get_parent().add_child.call_deferred(_preview_renderer)

    _snap_overlay = preload("res://scenes/player/snap_point_overlay.gd").new()
    _snap_overlay.player = self
    get_parent().add_child.call_deferred(_snap_overlay)

    _wire_debug_raycast.call_deferred()

    Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

    edit_preview.player     = self
    raycast.target_position = Vector3(0, 0, -EDIT_REACH)

    _key_actions = {
        KEY_TAB:          _cycle_tool,
        KEY_Q:            _quit_game,
        KEY_F:            _toggle_wireframe,
        KEY_X:            _toggle_fly,
        KEY_V:            _toggle_debug_visuals,
        KEY_M:            build_state.cycle_material,
        KEY_R:            build_state.rotate_y,
        KEY_T:            build_state.rotate_x,
        KEY_Y:            build_state.rotate_z,
        KEY_BRACKETLEFT:  build_state.prev_part,
        KEY_BRACKETRIGHT: build_state.next_part,
        KEY_G:            _toggle_grid_overlay,
        KEY_H:            _toggle_obscured_stress,
        KEY_F5:           _save_game,
        KEY_F9:           _load_game,
        KEY_1:            _select_activity.bind(0),
        KEY_2:            _select_activity.bind(1),
        KEY_3:            _select_activity.bind(2),
        KEY_4:            _select_activity.bind(3),
        KEY_5:            _select_activity.bind(4),
        KEY_6:            _select_activity.bind(5),
        KEY_7:            _select_activity.bind(6),
        KEY_8:            _select_activity.bind(7),
        KEY_9:            _select_activity.bind(8),
    }

    _mouse_button_actions = {
        MOUSE_BUTTON_LEFT: _try_edit_terrain,
    }

    _update_mode_label()


# Deferred because StructuralIntegrity constructs its `debug` and
# `part_support` components in *its* _ready, after Player._ready.
func _wire_debug_raycast() -> void:
    integrity.debug.raycast        = raycast
    integrity.part_support.raycast = raycast


func current_tool() -> Tool:
    return tool_catalog.tools[tool_index]

func current_activity() -> EditMode:
    var t := current_tool()
    if t.activities.is_empty():
        return null
    return t.activities[_activity_indices[tool_index]]


# --- Input dispatch ---

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        _on_key_pressed(event)
    elif event is InputEventMouseMotion:
        _camera_rig.handle_mouse_motion(event)
    elif event is InputEventMouseButton:
        _on_mouse_button_pressed(event)

func _on_key_pressed(event: InputEventKey) -> void:
    if event.is_action_pressed("ui_cancel"):
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
        return
    if _key_actions.has(event.keycode):
        _key_actions[event.keycode].call()

func _on_mouse_button_pressed(event: InputEventMouseButton) -> void:
    if not event.pressed:
        return
    if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
        Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
        return
    if _handle_placement_wheel(event):
        return
    if _mouse_button_actions.has(event.button_index):
        _mouse_button_actions[event.button_index].call()

# Returns true if the event was consumed as a placement-adjust wheel tick.
func _handle_placement_wheel(event: InputEventMouseButton) -> bool:
    var is_wheel_up   := event.button_index == MOUSE_BUTTON_WHEEL_UP
    var is_wheel_down := event.button_index == MOUSE_BUTTON_WHEEL_DOWN
    if not (is_wheel_up or is_wheel_down):
        return false
    if not Input.is_key_pressed(KEY_SHIFT):
        return false
    var activity := current_activity()
    if activity == null or not activity.uses_placement_offset:
        return false
    var axis := _placement_chord_axis()
    if axis == Vector3.ZERO:
        return false
    var step := WHEEL_STEP if is_wheel_up else -WHEEL_STEP
    build_state.adjust_offset(axis * step)
    return true

func _placement_chord_axis() -> Vector3:
    var cam_basis := camera.global_transform.basis
    if Input.is_key_pressed(KEY_W):   return -cam_basis.z
    if Input.is_key_pressed(KEY_A):   return -cam_basis.x
    if Input.is_key_pressed(KEY_E):   return  cam_basis.y
    return Vector3.ZERO


# --- Per-frame ---

func _physics_process(delta: float) -> void:
    _movement.tick(delta)


# --- Edit dispatch ---

func _try_edit_terrain() -> void:
    var activity := current_activity()
    if activity == null:
        return
    var aim := current_target()
    if aim == null:
        return
    var action: Action = activity.make_action.call(aim.position, aim.normal)
    if action == null:
        return
    if action.validate():
        action.execute()
        if not activity.keep_offset_on_action:
            build_state.reset_offset()


# The world point the current activity should act on this frame, or null when
# there's nothing to act on. Real surface hits win; otherwise air-placement
# activities (Build) fall back to a fixed distance along the camera ray so parts
# can be positioned over empty space (then snapped / offset into place).
func current_target() -> Aim:
    if raycast.is_colliding():
        return Aim.new(raycast.get_collision_point(), raycast.get_collision_normal(), true)
    var activity := current_activity()
    if activity != null and activity.allows_air_placement:
        var forward := -camera.global_transform.basis.z
        return Aim.new(camera.global_position + forward * AIR_PLACE_DISTANCE, Vector3.UP, false)
    return null


# --- Tool / activity UI ---

func _cycle_tool() -> void:
    tool_index = (tool_index + 1) % tool_catalog.tools.size()
    build_state.reset_offset()
    _update_mode_label()

func _select_activity(idx: int) -> void:
    var t := current_tool()
    if idx < 0 or idx >= t.activities.size():
        return
    _activity_indices[tool_index] = idx
    build_state.reset_offset()
    _update_mode_label()

func _update_mode_label() -> void:
    var lines: Array[String] = []
    var t        := current_tool()
    var activity := current_activity()
    if activity != null and activity.mode_name == "Build":
        lines.append("Material: %s" % build_state.current_material())
        lines.append("Part:     %s" % build_state.part_name())
    if activity != null:
        lines.append("Activity: %s" % activity.mode_name)
    lines.append("Tool:     %s" % t.name)
    if _movement != null and _movement.fly_enabled:
        lines.append("Fly:      ON")
    mode_label.text = "\n".join(lines)


# --- Other toggles ---

func _toggle_debug_visuals() -> void:
    integrity.set_debug_visuals_enabled(not integrity.debug_visuals_enabled)

func _toggle_grid_overlay() -> void:
    _grid_overlay.toggle()

func _toggle_obscured_stress() -> void:
    integrity.debug.toggle_obscured()

func _toggle_fly() -> void:
    _movement.fly_enabled = not _movement.fly_enabled
    _update_mode_label()

func _toggle_wireframe() -> void:
    wireframe_enabled = not wireframe_enabled
    get_viewport().debug_draw = (
        Viewport.DEBUG_DRAW_WIREFRAME
        if wireframe_enabled
        else Viewport.DEBUG_DRAW_DISABLED
    )

func _quit_game() -> void:
    TerrainPersistence.flush(terrain)
    get_tree().quit()


# --- Save/load ---

func _save_game() -> void:
    if not integrity.is_quiescent():
        Toast.failure("Can't save — world still settling.")
        return
    TerrainPersistence.flush(terrain)
    var err := WorldSnapshot.save(SavePaths.SNAPSHOT_FILE, get_parent())
    if err == OK:
        Toast.success("Saved.")
    else:
        push_error("Save failed: %s" % error_string(err))
        Toast.failure("Save failed: %s" % error_string(err))

func _load_game() -> void:
    if not SavePaths.snapshot_exists():
        return
    get_tree().reload_current_scene()
