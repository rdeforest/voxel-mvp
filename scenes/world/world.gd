extends Node3D

@onready var _integrity: StructuralIntegrity = $StructuralIntegrity
@onready var _player:    CharacterBody3D     = $Player

var _inval_overlay: Node3D
var _world_preview: DcWorldPreview
var _dc_collision: DCCollisionManager
var _awake_overlay: AwakeOverlay
var _mpm_structure: MpmStructure
var _detachment_scout: DetachmentScout
var _edit_store: EditStoreManager
var _saved: SavedWorld
var _part_index: PartIndex
var _console: ConsoleCommands
var _instruments: InstrumentCommands
var _recording: RecordingCommands
var _debug_server: DebugServer

# World-ready gate: gameplay + physics systems start inactive and resume on a
# WorldReadyEvent. With the store-backed field resident from frame one there's nothing to
# wait for, so this fires on the first _process frame (see _process).
var _world_ready := false


func _enter_tree() -> void:
    SavePaths.ensure_dir()

func _ready() -> void:
    # The EditStore is the authoritative terrain (SDF + material). Build it, restore the save,
    # then hand it to everything that reads or writes terrain: render, collision, the
    # structural tracking, and (lazily, via edit_store_ref) the player's actions.
    _part_index = PartIndex.new()   # identity sidecar; subscribes to part_placed / terrain_sdf_changed
    _edit_store = EditStoreManager.new()
    _edit_store.setup()
    _restore_save()
    _integrity.set_store(_edit_store.store)               # solidity checks + falling-body classification
    _inval_overlay = preload("res://scenes/player/invalidation_overlay.gd").new()
    add_child(_inval_overlay)
    _world_preview = DcWorldPreview.new()
    add_child(_world_preview)
    _world_preview.setup(_player, _edit_store.store)       # doc 16/17: world-fixed incremental octree
    _world_preview.set_diagnostic_overlay(_inval_overlay)  # `dcinval` highlights its off-target LOD triangles
    _world_preview.set_enabled(true)                       # THE terrain render (doc 17 P3); `dcworld` toggles it
    _player.world_preview = _world_preview                 # key I toggles its incremental-edit path (doc 20 E)
    Perf.set_shown(true)                                   # perf overlay on by default during co-dev; `perf` toggles it
    if OS.is_debug_build():                                # localhost telemetry/command endpoint (never shipped)
        _debug_server = DebugServer.new()
        add_child(_debug_server)
        _debug_server.setup(_world_preview)
    # Body-driven JIT terrain collision from our DC mesher, sourced from the EditStore
    # (generator + edits) — godot_voxel collision is off (world.tscn generate_collisions
    # = false), so this is the only terrain body.
    _dc_collision = DCCollisionManager.new()
    add_child(_dc_collision)
    _dc_collision.setup(_edit_store.store, _player)
    _awake_overlay = AwakeOverlay.new()
    add_child(_awake_overlay)
    _awake_overlay.setup(self)
    _wire_structural_sims()
    _wire_console()
    # Pull the OS window forward and take keyboard focus on launch, so an F5 from
    # the editor doesn't leave keystrokes landing in the script. Deferred so the
    # window is mapped before we ask. Under focus-follows-mouse the WM still hands
    # focus back to whatever the pointer is over, so this only sticks if the game
    # spawns under the cursor.
    _grab_os_focus.call_deferred()

# PB-MPM (doc 12) is the structural substrate. (PBD was removed — increment C — once MPM became
# the default; the old mass-spring sim, VoxelChunkBody debris, and the falling-body classifier are
# gone.)
func _wire_structural_sims() -> void:
    _mpm_structure = MpmStructure.new()
    _mpm_structure.name = "MpmStructure"
    add_child(_mpm_structure)
    _mpm_structure.setup(_edit_store.store)
    _integrity.mpm = _mpm_structure

    # The loss-of-support trigger: floods edits toward bedrock and thaws detached chunks into MPM.
    _detachment_scout = DetachmentScout.new()
    _detachment_scout.name = "DetachmentScout"
    add_child(_detachment_scout)
    _detachment_scout.setup(_edit_store.store, _integrity)

func _wire_console() -> void:
    _console = ConsoleCommands.new()
    _console.host          = self
    _console.inval_overlay = _inval_overlay
    _console.world_preview = _world_preview
    _console.integrity         = _integrity
    _console.player            = _player
    _console.awake_overlay     = _awake_overlay
    _console.edit_store        = _edit_store
    _console.part_index        = _part_index
    _console.register_all()
    _instruments = InstrumentCommands.new()
    _instruments.host       = self
    _instruments.edit_store = _edit_store
    _instruments.integrity  = _integrity
    _instruments.player     = _player
    _instruments.register_all()
    _recording = RecordingCommands.new()
    _recording.name = "RecordingCommands"
    add_child(_recording)
    _recording.setup(_console, _instruments)
    _player.examine_toggle_requested.connect(_console.examine.bind(""))   # Ctrl+E = `examine`

func _grab_os_focus() -> void:
    DisplayServer.window_move_to_foreground()
    get_window().grab_focus()

# A `reset` reload skips the save and may overwrite it; otherwise a save this build can't read
# is left on disk untouched, and the player is told why the world started fresh. The slot read is
# the one a console `load <name>` asked for, else the default; F5 always saves the default.
func _restore_save() -> void:
    var resetting := WorldSnapshot.reset_pending
    var slot      := SaveSlot.take_pending_load()
    WorldSnapshot.reset_pending = false
    if resetting:
        _saved = SavedWorld.new(SaveSlot.snapshot_path(SaveSlot.DEFAULT), SaveSlot.editstore_path(SaveSlot.DEFAULT))
        return

    _saved = SaveSlot.read(SaveSlot.DEFAULT)
    var loading := _saved if slot == SaveSlot.DEFAULT else SaveSlot.read(slot)
    var named   := "" if slot == SaveSlot.DEFAULT else " \"%s\"" % slot
    if loading.load_into(self, _edit_store):
        Toast.success("Loaded save%s." % named)
    elif not loading.refusal.is_empty():
        push_error("Save%s not loaded: %s" % [named, loading.refusal])
        Toast.failure("Save%s not loaded: %s. %s" % [named, loading.refusal, _kept_note(slot)])

# A refused pair stays on disk. The default slot's then blocks F5; F5 never writes a named one.
static func _kept_note(slot: String) -> String:
    if slot == SaveSlot.DEFAULT:
        return "Files kept; F5 won't overwrite them (console `reset` starts over)."
    return "Its files are kept; F5 saves to the default slot, not over them."

# Both halves of the save, into the default slot (F5) or a named one (console `save <name>`). ""
# on success, otherwise the reason it didn't save.
func save_game(slot := SaveSlot.DEFAULT) -> String:
    return _saved.save(self, _edit_store) if slot == SaveSlot.DEFAULT else SaveSlot.save(slot, self, _edit_store)

# Why the save on disk wasn't loaded and won't be overwritten; "" when there's no such save.
func save_refusal() -> String:
    return _saved.refusal

# The authoritative terrain store. Actions resolve it lazily through here (they're built in
# the player's _ready, before this world's _ready creates the store).
func edit_store_ref() -> EditStore:
    return _edit_store.store

# Part identity, which the save carries beside the field (WorldSnapshot).
func part_index() -> PartIndex:
    return _part_index

func _exit_tree() -> void:
    # Drop our console commands before this world is freed (scene reload / quit)
    # so LimboConsole never holds a callable bound to a freed object.
    if _console != null:
        _console.unregister_all()
    if _instruments != null:
        _instruments.unregister_all()


func _process(_delta: float) -> void:
    # The EditStore + analytic generator are resident from frame one — there's no streaming
    # to wait for (the old godot_voxel gate is gone). Fire world_ready on the first frame, so
    # gravity/edits/structural sim start against a field that's already trustworthy.
    if _world_ready:
        return
    _world_ready = true
    VoxelEventBusSingleton.emit(WorldReadyEvent.CHANNEL, WorldReadyEvent.new())
