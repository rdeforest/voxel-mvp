extends CharacterBody3D

var _movement:         PlayerMovement
var _camera_rig:       CameraRig
var build_state:       BuildState
var csg_state:         CsgState
var action_factories:  ActionFactories
var tool_catalog:      ToolCatalog
var _grid_overlay:     Node3D
var _preview_renderer: Node3D
var _help_overlay:     HelpOverlay
var _probe_hud:        CanvasLayer

var tool_index:        int       = 0
var _activity_indices: Array[int] = []   # remembered per tool

var wireframe_enabled := false

# Inactive until the world finishes loading (WorldReadyEvent): no gravity/movement
# (so we don't fall through ground that hasn't grown yet) and no edits. Look still
# works. Set true on the event.
var _active := false

var _key_actions:          Dictionary
var _mouse_button_actions: Dictionary

@onready var head:         Node3D              = $Head
@onready var camera:       Camera3D            = $Head/Camera3D
@onready var mode_label:   Label               = $HUD/BoxContainer/ModeLabel
@onready var edit_preview: MeshInstance3D      = $EditPreview
@onready var integrity:    StructuralIntegrity = get_parent().get_node("StructuralIntegrity")
@onready var raycast:      RayCast3D           = $Head/RayCast3D

const EDIT_REACH := 30.0

# When an air-placement activity (Build) aims at nothing within reach, float the
# target this far along the camera ray so parts can be placed over empty space.
# A mode can override the distance via EditMode.get_air_distance (CSG floats its
# ghost at 2x its largest dimension so a big shape doesn't fill the screen).
const AIR_PLACE_DISTANCE := 4.0

# Free-placement chord (Build only): hold Shift + (W|A|E), scroll wheel.
const WHEEL_STEP := 0.05


func _ready() -> void:
    _movement         = PlayerMovement.new(self, camera)
    _camera_rig       = CameraRig.new(self, $Head)
    build_state       = BuildState.new()
    csg_state         = CsgState.new()
    action_factories  = ActionFactories.new(self, integrity, camera, build_state, csg_state)
    tool_catalog      = ToolCatalog.new(action_factories, build_state, csg_state)
    _activity_indices.resize(tool_catalog.tools.size())   # all zero
    build_state.changed.connect(_update_mode_label)
    csg_state.changed.connect(_update_mode_label)

    _create_overlays()

    VoxelEventBusSingleton.subscribe(WorldReadyEvent.CHANNEL, _on_world_ready)

    Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

    edit_preview.player     = self
    raycast.target_position = Vector3(0, 0, -EDIT_REACH)

    _build_input_map()

    _sync_csg_shape()
    _update_mode_label()


func _create_overlays() -> void:
    _grid_overlay = preload("res://scenes/player/voxel_grid_overlay.gd").new()
    _grid_overlay.raycast = raycast
    get_parent().add_child.call_deferred(_grid_overlay)

    _preview_renderer = preload("res://scenes/player/voxel_preview_renderer.gd").new()
    _preview_renderer.player = self
    get_parent().add_child.call_deferred(_preview_renderer)

    _help_overlay = HelpOverlay.new()
    add_child(_help_overlay)

    _probe_hud = preload("res://scenes/player/probe_hud.gd").new()
    _probe_hud.player = self
    add_child(_probe_hud)


func _build_input_map() -> void:
    _key_actions = {
        KEY_TAB:          _cycle_tool,
        KEY_Q:            _quit_game,
        KEY_F:            _toggle_wireframe,
        KEY_X:            _toggle_fly,
        KEY_V:            _toggle_stress_viz,
        KEY_M:            _route_edit.bind(&"cycle_material"),
        KEY_R:            _route_edit.bind(&"rotate_y"),
        KEY_T:            _route_edit.bind(&"rotate_x"),
        KEY_Y:            _route_edit.bind(&"rotate_z"),
        KEY_C:            _route_csg.bind(&"cycle_axis"),
        KEY_B:            _route_csg.bind(&"toggle_op"),
        KEY_BRACKETLEFT:  build_state.prev_part,
        KEY_BRACKETRIGHT: build_state.next_part,
        KEY_G:            _toggle_grid_overlay,
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
    # `?` toggles the keybinding chart. Match the resolved character (layout-
    # agnostic), with Shift+/ as a fallback if unicode isn't populated.
    if event.unicode == 0x3F or (event.keycode == KEY_SLASH and event.shift_pressed):
        _help_overlay.toggle()
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
    if _handle_csg_resize_wheel(event):
        return
    if _mouse_button_actions.has(event.button_index):
        _mouse_button_actions[event.button_index].call()

# Bare scroll-wheel (no Shift) grows/shrinks the active CSG axis. Shift+wheel is
# claimed first by _handle_placement_wheel for the placement offset, so the two
# don't collide.
func _handle_csg_resize_wheel(event: InputEventMouseButton) -> bool:
    if current_tool().name != "CSG" or Input.is_key_pressed(KEY_SHIFT):
        return false
    if event.button_index == MOUSE_BUTTON_WHEEL_UP:
        csg_state.grow(1.0)
        return true
    if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
        csg_state.grow(-1.0)
        return true
    return false

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
    if not _active:
        return
    _movement.tick(delta)

func _on_world_ready(_event: VoxelEvent) -> void:
    _active = true


# --- Edit dispatch ---

func _try_edit_terrain() -> void:
    if not _active:
        return
    var activity := current_activity()
    if activity == null:
        return
    var aim := current_target()
    if aim == null:
        return
    if not aim.hit and not activity.acts_on_air:
        return   # air target with no surface, and this mode won't act on air (CSG) — no-op
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
        var dist := AIR_PLACE_DISTANCE
        if activity.get_air_distance.is_valid():
            dist = maxf(AIR_PLACE_DISTANCE, activity.get_air_distance.call())
        return Aim.new(camera.global_position + forward * dist, Vector3.UP, false)
    return null


# --- Tool / activity UI ---

func _cycle_tool() -> void:
    tool_index = (tool_index + 1) % tool_catalog.tools.size()
    build_state.reset_offset()
    _sync_csg_shape()
    _update_mode_label()

func _select_activity(idx: int) -> void:
    var t := current_tool()
    if idx < 0 or idx >= t.activities.size():
        return
    _activity_indices[tool_index] = idx
    build_state.reset_offset()
    _sync_csg_shape()
    _update_mode_label()


# --- Editing-state routing (Construction uses BuildState, CSG uses CsgState) ---

func _uses_csg() -> bool:
    return current_tool().name == "CSG"

# The editing state for the active tool. BuildState (parts) and CsgState (primitives)
# expose the same edit-verb interface (cycle_material, rotate_x/y/z), so an edit input
# routes to whichever is active instead of branching the same way in every handler.
func _active_edit_state() -> Object:
    return csg_state if _uses_csg() else build_state

func _route_edit(verb: StringName) -> void:
    _active_edit_state().call(verb)

# CSG-only verbs (no part-building equivalent): a no-op outside the CSG tool.
func _route_csg(verb: StringName) -> void:
    if _uses_csg():
        csg_state.call(verb)

# Keep the CSG state's active shape in step with the selected activity, so the
# ghost, resize, and stamp all act on the shape the activity names.
func _sync_csg_shape() -> void:
    var a := current_activity()
    if a != null and a.csg_shape >= 0:
        csg_state.set_shape(a.csg_shape)

func _update_mode_label() -> void:
    var lines: Array[String] = []
    var t        := current_tool()
    var activity := current_activity()
    if activity != null:
        if activity.get_hud_lines.is_valid():
            lines.append_array(activity.get_hud_lines.call())
        lines.append("Activity: %s" % activity.mode_name)
    lines.append("Tool:     %s" % t.name)
    if _movement != null and _movement.fly_enabled:
        lines.append("Fly:      ON")
    mode_label.text = "\n".join(lines)


# --- Other toggles ---

func _toggle_stress_viz() -> void:
    if integrity.pbd != null:
        integrity.pbd.toggle_viz()

func _toggle_grid_overlay() -> void:
    _grid_overlay.toggle()

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
    get_tree().quit()


# --- Save/load ---

func _save_game() -> void:
    if not integrity.is_quiescent():
        Toast.failure("Can't save — world still settling.")
        return
    var world := get_parent()
    var err := WorldSnapshot.save(SavePaths.SNAPSHOT_FILE, world)
    if err == OK:
        world.save_edit_store()   # S4: persist terrain edits via the EditStore blob
        Toast.success("Saved.")
    else:
        push_error("Save failed: %s" % error_string(err))
        Toast.failure("Save failed: %s" % error_string(err))

func _load_game() -> void:
    if not SavePaths.snapshot_exists():
        return
    get_tree().reload_current_scene()
