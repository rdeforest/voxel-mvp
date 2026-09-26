extends SceneTree

# Characterizes FillVoxel / EmptyVoxel on the game's own field and render
# (docs/bugs/single-voxel-edits-unexpected.md, Characterization): an EditStore set up exactly as
# EditStoreManager does, aimed with TerrainRaymarch the way player.gd aims, targeted with
# ActionFactories' cell formulas, executed through the real actions, and meshed before/after with
# DCOctreeMesher.mesh_world as DcWorldPreview calls it. Writes one TSV row per edit step, and a
# refusal census over a wider sample (validate() only, no meshing) to <out>.census.tsv.
#
#   godot --path . --headless -s res://scripts/dev/probe_single_voxel.gd -- out.tsv [per_class [census]]
#   godot --path . --headless -s res://scripts/dev/probe_single_voxel.gd -- check out.occupancy.tsv [per_class]
#
# `check` validates the occupancy measure itself (single_voxel_occupancy.gd).
#
# The work lives in scripts loaded after the first frame: the actions name the
# VoxelEventBusSingleton autoload, which a -s main script can't see at its own compile time.

const PER_CLASS := 8          # meshed targets per terrain class
const CENSUS    := 3000       # targets in the validate()-only refusal census


func _initialize() -> void:
    _run.call_deferred()


func _run() -> void:
    await process_frame
    var args  := Array(OS.get_cmdline_user_args())
    var check: bool = args.size() > 0 and args[0] == "check"
    if check:
        args.pop_front()
    var out_path  := str(args[0]) if args.size() > 0 else ""
    var per_class := int(args[1]) if args.size() > 1 else PER_CLASS
    var census    := int(args[2]) if args.size() > 2 else CENSUS
    var targets: RefCounted = load("res://scripts/dev/single_voxel_targets.gd").new(per_class)
    if check:
        load("res://scripts/dev/single_voxel_occupancy.gd").new(targets).run(out_path)
    else:
        load("res://scripts/dev/single_voxel_probe.gd").new(targets, census).run(out_path)
    quit()
