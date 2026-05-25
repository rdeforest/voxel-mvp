class_name Materials
extends Resource

# Material data driven by .tres resource files in assets/materials/. Each
# material's properties (decay, albedo, etc.) live in its .tres file; this
# class is the thin loader plus singleton accessors for ergonomics. Adding
# a new material is a file copy in assets/materials/ and a getter here.
#
# Why .tres and not JSON: editor-discoverable, Godot-native, no parse step
# at startup. Anyone who wants JSON can export from .tres trivially.

@export var name:            String = ""
@export var decay:           float  = 0.0
@export var max_support:     float  = 1.0
@export var albedo:          Color  = Color(0.5, 0.5, 0.5)
@export var angle_of_repose: float  = -1.0  # degrees, -1 for rigid materials
@export var failure_mode:    String = "fracture"  # "crumble", "fracture", "snap", "bend"


# --- Singleton accessors ---
#
# Static vars initialise lazily on first access to the class. Using load()
# rather than preload() avoids a parse-time circular reference: the .tres
# files reference this script, so preload at script scope would try to
# resolve them while this script is still being parsed. load() defers to
# runtime, by which time the script is fully defined and the .tres can
# bind to it cleanly.

static var TERRAIN: Materials = load("res://assets/materials/terrain.tres") as Materials
static var DIRT:    Materials = load("res://assets/materials/dirt.tres")    as Materials
static var SAND:    Materials = load("res://assets/materials/sand.tres")    as Materials
static var STONE:   Materials = load("res://assets/materials/stone.tres")   as Materials
static var WOOD:    Materials = load("res://assets/materials/wood.tres")    as Materials
static var METAL:   Materials = load("res://assets/materials/metal.tres")   as Materials

static var _by_name: Dictionary = {}


# Resolve a material by its `name` field (StringName for cheap comparison at
# call sites). Falls back to STONE if the name is unknown — matches the old
# behaviour and keeps callers from having to null-check.
static func from_name(n: StringName) -> Materials:
    if _by_name.is_empty():
        _by_name = {
            &"Terrain": TERRAIN,
            &"Dirt":    DIRT,
            &"Sand":    SAND,
            &"Stone":   STONE,
            &"Wood":    WOOD,
            &"Metal":   METAL,
        }
    return _by_name.get(n, STONE)
