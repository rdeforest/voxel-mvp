extends SceneTree

# Builds the procedural terrain as a VoxelGeneratorGraph and saves it to a .tres you can
# open in the editor's graph view and tinker with. Run headless:
#   bin/godot --path . --headless -s res://tools/build_terrain_graph.gd
#
# THE FORMULA (plain text — the graph just wires these up):
#
#   mnt     = FastNoise2D(x, z)         # a bumpy height map in roughly [-1 .. 1]
#   surface = BASE + AMP * mnt          # ground height at (x,z)
#   OUTPUT_SDF = y - surface            # SDF: <0 below ground = solid, >0 above = air
#
# Shape only — no caves (solid all the way down, physics-stable). Terrain MATERIAL (rock
# on the heights, grass/dirt below) lives in terrain.gdshader by altitude+slope, not here:
# it works at every LOD and is live-tunable via the `set` console command. The per-voxel
# material channel is reserved for authored CSG stamps.
#
# THE KNOBS (edit, rerun this script, or change them live in the graph editor):
#   BASE      valley/ground baseline height (m)
#   AMP       mountain relief (m) — how far peaks rise above the baseline
#   PERIOD    mountain width (m) — bigger = broader, smoother mountains
#   OCTAVES   roughness — more octaves = more fine detail (and more mesh cracks); fewer = smoother
#   FRACTAL   RIDGED = sharp peaks/ridgelines; FBM = rounded rolling hills

const OUT_PATH := "res://assets/generators/terrain.tres"

const BASE      := 30.0
const AMP       := 140.0
const PERIOD    := 1000.0
const OCTAVES   := 2


func _mountain_noise() -> ZN_FastNoiseLite:
    var n := ZN_FastNoiseLite.new()
    n.noise_type = ZN_FastNoiseLite.TYPE_OPEN_SIMPLEX_2
    n.fractal_type = ZN_FastNoiseLite.FRACTAL_RIDGED     # FRACTAL_FBM for rolling hills instead
    n.seed = 1337
    n.period = PERIOD
    n.fractal_octaves = OCTAVES
    return n


func _initialize() -> void:
    var gen := VoxelGeneratorGraph.new()
    # Single texture id per voxel (8-bit CHANNEL_INDICES), matching our material model.
    # The default Mixel4 splat mode demands a 16-bit indices channel and warns otherwise.
    gen.texture_mode = VoxelGeneratorGraph.TEXTURE_MODE_SINGLE
    var g := gen.get_main_function()
    var T := VoxelGraphFunction

    var y_in   := g.create_node(T.NODE_INPUT_Y,       Vector2(0,   0))

    var mnt    := g.create_node(T.NODE_FAST_NOISE_2D, Vector2(0, 160))   # auto-connects x, z
    g.set_node_param(mnt, 0, _mountain_noise())
    var mntamp := g.create_node(T.NODE_MULTIPLY,      Vector2(240, 160))
    g.add_connection(mnt, 0, mntamp, 0)
    g.set_node_default_input(mntamp, 1, AMP)
    var surf   := g.create_node(T.NODE_ADD,           Vector2(480, 160))
    g.add_connection(mntamp, 0, surf, 0)
    g.set_node_default_input(surf, 1, BASE)

    var density := g.create_node(T.NODE_SUBTRACT,     Vector2(720, 60))  # y - surface
    g.add_connection(y_in, 0, density, 0)
    g.add_connection(surf, 0, density, 1)
    var out_sdf := g.create_node(T.NODE_OUTPUT_SDF,   Vector2(960, 60))
    g.add_connection(density, 0, out_sdf, 0)

    var result: Dictionary = gen.compile()
    if not result.get("success", false):
        printerr("graph compile failed: ", result)
        quit(1)
        return
    var err := ResourceSaver.save(gen, OUT_PATH)
    if err != OK:
        printerr("save failed: ", err)
        quit(1)
        return
    print("terrain graph saved to ", OUT_PATH, "  (compiled OK)")
    quit()
