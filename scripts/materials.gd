class_name Materials

var name:            String
var decay:           float
var max_support:     float
var albedo:          Color
var angle_of_repose: float  # degrees, -1 for rigid materials
var failure_mode:    String # "crumble", "fracture", "snap", "bend"

func _init(
    p_name:        String,
    p_decay:       float,
    p_max_support: float,
    p_albedo:      Color  = Color(0.5, 0.5, 0.5),
    p_angle:       float  = -1.0,
    p_failure:     String = "fracture",
) -> void:
    name            = p_name
    decay           = p_decay
    max_support     = p_max_support
    albedo          = p_albedo
    angle_of_repose = p_angle
    failure_mode    = p_failure

# --- Singleton instances ---

static var TERRAIN := Materials.new("Terrain", 0.0,  1.0, Color(0.45, 0.30, 0.18))
static var DIRT    := Materials.new("Dirt",    0.20, 1.0, Color(0.40, 0.26, 0.16), 35.0, "crumble")
static var SAND    := Materials.new("Sand",    0.25, 1.0, Color(0.85, 0.75, 0.55), 30.0, "crumble")
static var STONE   := Materials.new("Stone",   0.05, 1.0, Color(0.55, 0.55, 0.55), 90.0, "fracture")
static var WOOD    := Materials.new("Wood",    0.10, 1.0, Color(0.51, 0.32, 0.20), -1.0, "snap")
static var METAL   := Materials.new("Metal",   0.03, 1.0, Color(0.65, 0.65, 0.70), -1.0, "bend")

static var _by_name: Dictionary = {}

static func from_name(n: StringName) -> Materials:
    if _by_name.is_empty():
        _by_name = {
            &"Terrain": TERRAIN, &"Dirt": DIRT,  &"Sand":  SAND,
            &"Stone":   STONE,   &"Wood": WOOD,   &"Metal": METAL,
        }
    return _by_name.get(n, STONE)
