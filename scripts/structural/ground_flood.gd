class_name GroundFlood
extends RefCounted

# Flood connected solid terrain from seed cells, BIASED DOWNWARD, to decide whether the component
# is GROUNDED (a path reaches Bedrock) or DETACHED (the frontier drains without bedrock, under the
# size cap). Non-blocking: step(budget) advances a bounded number of cells per call, so a big flood
# spreads across frames. Shared by the detachment trigger (DetachmentScout) and the floodviz overlay.
#
# The down-bias makes a grounded component cheap: it dives straight toward bedrock (~50 m below the
# surface) and returns GROUNDED on the first bedrock cell, long before visiting the whole mountain.
# Only a genuinely floating chunk floods its (bounded) self in full.

enum { RUNNING, GROUNDED, DETACHED, OVERFLOW }

const NEIGHBORS := [
    Vector3i(0, -1, 0),                                   # down first — the bedrock-ward bias
    Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
    Vector3i(0, 0, 1), Vector3i(0, 0, -1),
    Vector3i(0, 1, 0),
]

var visited := {}            # Vector3i -> true: the connected component reached so far
var state := RUNNING

var _store: EditStore
var _frontier: Array[Vector3i] = []
var _max_cells := 700


# Seed the flood from `seeds` (solid cells). `max_cells` bounds a DETACHED component — beyond it the
# flood reports OVERFLOW (treated as grounded; a chunk that large shouldn't free-fall).
func start(seeds: Array, store: EditStore, max_cells: int) -> void:
    _store = store
    _max_cells = max_cells
    _frontier = []
    visited = {}
    state = RUNNING
    for s in seeds:
        if not visited.has(s) and _is_solid(s):
            visited[s] = true
            _frontier.append(s)
    if _frontier.is_empty():
        state = DETACHED   # no solid seed — nothing to flood (caller treats empty as "nothing to do")


# Advance up to `budget` cells. Returns the (possibly updated) state.
func step(budget: int) -> int:
    if state != RUNNING:
        return state
    var done := 0
    while not _frontier.is_empty() and done < budget:
        if visited.size() > _max_cells:
            state = OVERFLOW
            return state
        var cell: Vector3i = _frontier.pop_front()
        done += 1
        if _is_bedrock(cell):
            state = GROUNDED   # reached ground — the component is supported
            return state
        for n in NEIGHBORS:
            var nb: Vector3i = cell + n
            if visited.has(nb) or not _is_solid(nb):
                continue
            visited[nb] = true
            if n.y < 0:
                _frontier.push_front(nb)   # dive down first
            else:
                _frontier.push_back(nb)
    if _frontier.is_empty():
        state = DETACHED       # drained without bedrock — the component is floating
    return state


func _is_solid(cell: Vector3i) -> bool:
    return _store.sample(Vector3(cell) + Vector3(0.5, 0.5, 0.5)) < VoxelConstants.SDF_SOLID_THRESHOLD

func _is_bedrock(cell: Vector3i) -> bool:
    return _store.material_at(Vector3(cell) + Vector3(0.5, 0.5, 0.5)) == MaterialPalette.BEDROCK
