extends CharacterBody3D

var _movement:          PlayerMovement
var _camera_rig:        CameraRig
var build_state:        BuildState
var action_factories:   ActionFactories
var edit_modes_catalog: EditModeCatalog
var _grid_overlay:      Node3D

var edit_mode_index: int  = 0
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


func _ready() -> void:
    _movement          = PlayerMovement.new(self)
    _camera_rig        = CameraRig.new(self, $Head)
    build_state        = BuildState.new()
    action_factories   = ActionFactories.new(self, terrain, integrity, camera, raycast, build_state)
    edit_modes_catalog = EditModeCatalog.new(action_factories, build_state)
    build_state.changed.connect(_update_mode_label)

    _grid_overlay = preload("res://scenes/player/voxel_grid_overlay.gd").new()
    _grid_overlay.raycast = raycast
    get_parent().add_child.call_deferred(_grid_overlay)

    Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

    edit_preview.player     = self
    raycast.target_position = Vector3(0, 0, -EDIT_REACH)

    _key_actions = {
        KEY_TAB:          _cycle_edit_mode,
        KEY_Q:            _quit_game,
        KEY_F:            _toggle_wireframe,
        KEY_V:            _toggle_debug_visuals,
        KEY_M:            build_state.cycle_material,
        KEY_R:            build_state.rotate_y,
        KEY_T:            build_state.rotate_x,
        KEY_Y:            build_state.rotate_z,
        KEY_BRACKETLEFT:  build_state.prev_part,
        KEY_BRACKETRIGHT: build_state.next_part,
        KEY_G:            _toggle_grid_overlay,
        KEY_F5:           _save_game,
        KEY_F9:           _load_game,
    }

    _mouse_button_actions = {
        MOUSE_BUTTON_LEFT: _try_edit_terrain,
    }

    _update_mode_label()


func current_mode() -> EditMode:
    return edit_modes_catalog.modes[edit_mode_index]


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
    if _mouse_button_actions.has(event.button_index):
        _mouse_button_actions[event.button_index].call()


# --- Per-frame ---

func _process(_delta: float) -> void:
    var hovered: Node3D = null
    if raycast.is_colliding():
        var collider := raycast.get_collider() as Node3D
        if collider != null and integrity.has_part(collider):
            hovered = collider
    integrity.set_hovered_part(hovered)

func _physics_process(delta: float) -> void:
    _movement.tick(delta)


# --- Edit dispatch ---

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


# --- Mode UI ---

func _cycle_edit_mode() -> void:
    edit_mode_index = (edit_mode_index + 1) % edit_modes_catalog.modes.size()
    _update_mode_label()

func _update_mode_label() -> void:
    var mode := current_mode()
    if mode.mode_name == "Build":
        mode_label.text = "%s: %s (%s)" % [mode.mode_name, build_state.part_name(), build_state.current_material()]
    else:
        mode_label.text = mode.mode_name

func _toggle_debug_visuals() -> void:
    integrity.set_debug_visuals_enabled(not integrity.debug_visuals_enabled)

func _toggle_grid_overlay() -> void:
    _grid_overlay.toggle()

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
        print("Cannot save: world still settling.")
        return
    var err := WorldSnapshot.save(SavePaths.SNAPSHOT_FILE, get_parent())
    print("Saved." if err == OK else "Save failed: %s" % err)

func _load_game() -> void:
    if not SavePaths.snapshot_exists():
        return
    get_tree().reload_current_scene()
