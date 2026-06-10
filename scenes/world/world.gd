extends Node3D

@onready var _terrain:   VoxelLodTerrain     = $VoxelLodTerrain
@onready var _integrity: StructuralIntegrity = $StructuralIntegrity
@onready var _player:    CharacterBody3D     = $Player

var _dc_manager: DCTerrainManager
var _substrate_preview: DcSubstratePreview
var _dc_collision: DCCollisionManager
var _awake_overlay: AwakeOverlay
var _pbd_structure: PbdStructure
var _edit_store: EditStoreManager
var _console: ConsoleCommands

# World-ready gate: gameplay + physics systems start inactive and resume on a
# WorldReadyEvent, so nothing acts on a half-streamed world. We poll the terrain
# (is_area_editable around the player) rather than pausing it — pausing the
# terrain would stall the very streaming we're waiting on. A timeout backstops a
# bad probe so the game can never freeze forever.
var _world_ready := false
var _ready_wait := 0.0
const READY_PROBE_RADIUS := 8.0      # cells around the player that must be loaded
const WORLD_READY_TIMEOUT := 10.0    # seconds; fire anyway past this


func _enter_tree() -> void:
    SavePaths.ensure_dir()
    # Keep generated data blocks resident (default off) so our region reads hit
    # cached data instead of re-running the noise generator every time. Set before
    # the terrain starts generating (parent _enter_tree runs before the child's).
    $VoxelLodTerrain.cache_generated_blocks = true
    # Our DCCollisionManager owns terrain collision now — disable godot_voxel's
    # per-block collision. Set in code, not world.tscn: the Godot editor re-saves
    # the scene and silently reverts .tscn edits made externally (it ate this once).
    $VoxelLodTerrain.generate_collisions = false
    # Per-voxel material: assign a format with an 8-bit INDICES channel. The
    # default format stores indices at 16-bit packed-mixel4 (default 0x3210, the
    # 4-material splat encoding) which has no clean single-id zero; 8-bit gives one
    # material id per voxel with 0 = "natural" (slope-shaded). Set before the
    # terrain enters the tree (parent _enter_tree runs first) so the channel is
    # allocated, streamed, and SQLite-persisted. Existing pre-material saves use a
    # different format and must be reset (`reset`) — accepted when this landed.
    var fmt := VoxelFormat.new()
    fmt.set_channel_depth(VoxelBuffer.CHANNEL_INDICES, VoxelBuffer.DEPTH_8_BIT)
    $VoxelLodTerrain.format = fmt
    # If a reset is pending, detach the SQLite stream BEFORE the terrain
    # node enters the tree, so it never reads modified blocks from disk.
    # _enter_tree runs parent-first, so we get here before $VoxelLodTerrain
    # has run its own _enter_tree.
    if WorldSnapshot.reset_pending:
        $VoxelLodTerrain.stream = null

func _ready() -> void:
    var resetting := WorldSnapshot.reset_pending
    WorldSnapshot.reset_pending = false
    if not resetting and SavePaths.snapshot_exists():
        if WorldSnapshot.load_into(SavePaths.SNAPSHOT_FILE, self):
            Toast.success("Loaded save.")
    _dc_manager = DCTerrainManager.new()
    add_child(_dc_manager)
    _dc_manager.setup(_terrain, _player)
    _dc_manager.start_default()   # DC is the default terrain render; dcmanager/dcsolo override
    _edit_store = EditStoreManager.new()
    _edit_store.setup(_terrain)                    # Phase B S2: dual-write edits into our EditStore (shadow)
    _substrate_preview = DcSubstratePreview.new()
    add_child(_substrate_preview)
    _substrate_preview.setup(_player, _edit_store.store)   # Phase B S3: render imprints generator + edits from the store (dcgen)
    # Body-driven JIT terrain collision from our DC mesher; godot_voxel collision is
    # off (world.tscn generate_collisions = false), so this is the only terrain body.
    _dc_collision = DCCollisionManager.new()
    add_child(_dc_collision)
    _dc_collision.setup(_terrain, _player)
    _awake_overlay = AwakeOverlay.new()
    add_child(_awake_overlay)
    _awake_overlay.setup(self)
    _pbd_structure = PbdStructure.new()
    _pbd_structure.name = "PbdStructure"   # ActionFactories resolves the probe target by this name
    add_child(_pbd_structure)
    _pbd_structure.setup(_integrity)
    _integrity.pbd = _pbd_structure
    _pbd_structure.set_enabled(true)   # PBD is authoritative; the old collapse systems stand down
    _console = ConsoleCommands.new()
    _console.host              = self
    _console.terrain           = _terrain
    _console.dc_manager        = _dc_manager
    _console.substrate_preview = _substrate_preview
    _console.pbd_structure     = _pbd_structure
    _console.integrity         = _integrity
    _console.player            = _player
    _console.awake_overlay     = _awake_overlay
    _console.edit_store        = _edit_store
    _console.register_all()
    # Pull the OS window forward and take keyboard focus on launch, so an F5 from
    # the editor doesn't leave keystrokes landing in the script. Deferred so the
    # window is mapped before we ask. Under focus-follows-mouse the WM still hands
    # focus back to whatever the pointer is over, so this only sticks if the game
    # spawns under the cursor.
    _grab_os_focus.call_deferred()

func _grab_os_focus() -> void:
    DisplayServer.window_move_to_foreground()
    get_window().grab_focus()

func _exit_tree() -> void:
    # Drop our console commands before this world is freed (scene reload / quit)
    # so LimboConsole never holds a callable bound to a freed object.
    if _console != null:
        _console.unregister_all()


func _process(delta: float) -> void:
    if _world_ready:
        return
    _ready_wait += delta
    var timed_out := _ready_wait >= WORLD_READY_TIMEOUT
    if not _terrain_loaded_around_player() and not timed_out:
        return
    _world_ready = true
    if timed_out:
        push_warning("world_ready fired on timeout — terrain may not be fully streamed")
    VoxelEventBusSingleton.emit(WorldReadyEvent.CHANNEL, WorldReadyEvent.new())

# True once the terrain DATA (not just mesh) around the player has streamed in —
# the point at which gravity, edits, and PBD anchoring can trust the SDF.
func _terrain_loaded_around_player() -> bool:
    if _player == null or _terrain == null:
        return false
    var vt := _terrain.get_voxel_tool()
    var origin := _player.global_position - Vector3.ONE * READY_PROBE_RADIUS
    return vt.is_area_editable(AABB(origin, Vector3.ONE * (READY_PROBE_RADIUS * 2.0)))
