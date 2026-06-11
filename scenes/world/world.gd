extends Node3D

@onready var _integrity: StructuralIntegrity = $StructuralIntegrity
@onready var _player:    CharacterBody3D     = $Player

var _dc_manager: DCTerrainManager
var _substrate_preview: DcSubstratePreview
var _dc_collision: DCCollisionManager
var _awake_overlay: AwakeOverlay
var _pbd_structure: PbdStructure
var _edit_store: EditStoreManager
var _part_index: PartIndex
var _console: ConsoleCommands

# World-ready gate: gameplay + physics systems start inactive and resume on a
# WorldReadyEvent. With the store-backed field resident from frame one there's nothing to
# wait for, so this fires on the first _process frame (see _process).
var _world_ready := false


func _enter_tree() -> void:
    SavePaths.ensure_dir()

func _ready() -> void:
    var resetting := WorldSnapshot.reset_pending
    WorldSnapshot.reset_pending = false
    if not resetting and SavePaths.snapshot_exists():
        if WorldSnapshot.load_into(SavePaths.SNAPSHOT_FILE, self):
            Toast.success("Loaded save.")
    # The EditStore is the authoritative terrain (SDF + material). Build it, restore any saved
    # edits, then hand it to everything that reads or writes terrain: render, collision, the
    # structural tracking, and (lazily, via edit_store_ref) the player's actions.
    _part_index = PartIndex.new()   # identity sidecar; subscribes to part_placed / voxel_removed
    _edit_store = EditStoreManager.new()
    _edit_store.setup()
    if not resetting and SavePaths.editstore_exists():
        _edit_store.load_from(SavePaths.EDITSTORE_FILE)   # S4: restore persisted terrain edits into the store
    _integrity.set_store(_edit_store.store)               # solidity checks + falling-body classification
    _dc_manager = DCTerrainManager.new()
    add_child(_dc_manager)
    _dc_manager.setup(_player, _edit_store.store)   # render sources SDF + material from the store
    _dc_manager.start_default()   # DC is the terrain render
    _substrate_preview = DcSubstratePreview.new()
    add_child(_substrate_preview)
    _substrate_preview.setup(_player, _edit_store.store)   # Phase B S3: render imprints generator + edits from the store (dcgen)
    # Body-driven JIT terrain collision from our DC mesher, sourced from the EditStore
    # (generator + edits) — godot_voxel collision is off (world.tscn generate_collisions
    # = false), so this is the only terrain body.
    _dc_collision = DCCollisionManager.new()
    add_child(_dc_collision)
    _dc_collision.setup(_edit_store.store, _player)
    _awake_overlay = AwakeOverlay.new()
    add_child(_awake_overlay)
    _awake_overlay.setup(self)
    _pbd_structure = PbdStructure.new()
    _pbd_structure.name = "PbdStructure"   # ActionFactories resolves the probe target by this name
    add_child(_pbd_structure)
    _pbd_structure.setup(_integrity)
    _integrity.pbd = _pbd_structure
    _pbd_structure.set_enabled(true)   # PBD is authoritative; the old collapse systems stand down
    _wire_console()
    # Pull the OS window forward and take keyboard focus on launch, so an F5 from
    # the editor doesn't leave keystrokes landing in the script. Deferred so the
    # window is mapped before we ask. Under focus-follows-mouse the WM still hands
    # focus back to whatever the pointer is over, so this only sticks if the game
    # spawns under the cursor.
    _grab_os_focus.call_deferred()

func _wire_console() -> void:
    _console = ConsoleCommands.new()
    _console.host              = self
    _console.dc_manager        = _dc_manager
    _console.substrate_preview = _substrate_preview
    _console.pbd_structure     = _pbd_structure
    _console.integrity         = _integrity
    _console.player            = _player
    _console.awake_overlay     = _awake_overlay
    _console.edit_store        = _edit_store
    _console.part_index        = _part_index
    _console.register_all()

func _grab_os_focus() -> void:
    DisplayServer.window_move_to_foreground()
    get_window().grab_focus()

# Persist the EditStore blob (terrain SDF). Called by the player's F5 save alongside the
# WorldSnapshot (parts/player/tunables). S4: replaces the godot_voxel stream's save.
func save_edit_store() -> void:
    if _edit_store != null:
        _edit_store.save_to(SavePaths.EDITSTORE_FILE)

# The authoritative terrain store. Actions resolve it lazily through here (they're built in
# the player's _ready, before this world's _ready creates the store).
func edit_store_ref() -> EditStore:
    return _edit_store.store

func _exit_tree() -> void:
    # Drop our console commands before this world is freed (scene reload / quit)
    # so LimboConsole never holds a callable bound to a freed object.
    if _console != null:
        _console.unregister_all()


func _process(_delta: float) -> void:
    # The EditStore + analytic generator are resident from frame one — there's no streaming
    # to wait for (the old godot_voxel gate is gone). Fire world_ready on the first frame, so
    # gravity/edits/PBD start against a field that's already trustworthy.
    if _world_ready:
        return
    _world_ready = true
    VoxelEventBusSingleton.emit(WorldReadyEvent.CHANNEL, WorldReadyEvent.new())
