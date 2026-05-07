class_name Materials

var name:            String
var decay:           float
var max_support:     float
var angle_of_repose: float  # degrees, -1 for rigid materials
var failure_mode:    String # "crumble", "fracture", "snap", "bend"

func _init(
    p_name:        String,
    p_decay:       float,
    p_max_support: float,
    p_angle:       float = -1.0,
    p_failure:     String = "fracture",
) -> void:
    name            = p_name
    decay           = p_decay
    max_support     = p_max_support
    angle_of_repose = p_angle
    failure_mode    = p_failure

# --- Singleton instances ---

static var TERRAIN := Materials.new("Terrain", 0.0,  1.0)
static var DIRT    := Materials.new("Dirt",    0.20, 1.0, 35.0,  "crumble")
static var SAND    := Materials.new("Sand",    0.25, 1.0, 30.0,  "crumble")
static var STONE   := Materials.new("Stone",   0.05, 1.0, 90.0,  "fracture")
static var WOOD    := Materials.new("Wood",    0.10, 1.0, -1.0,  "snap")
static var METAL   := Materials.new("Metal",   0.03, 1.0, -1.0,  "bend")
