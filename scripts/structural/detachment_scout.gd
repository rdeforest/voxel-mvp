class_name DetachmentScout
extends Node

# The loss-of-support trigger (replaces the removed scalar-support cascade). When a terrain edit
# might have cut something loose, it floods the affected solid component down toward Bedrock
# (GroundFlood): a component that drains without reaching ground is DETACHED and gets thawed into
# MPM (it falls). Non-blocking — one flood at a time, a budget of cells per physics frame.
#
# Cascade safety (why the scalar trigger died): the scout only considers edits made while MPM is
# IDLE, and pauses resolving while material is in flight. MPM's own thaw/freeze edits fire while it
# has active particles, so they're ignored; once a detached chunk has fallen and frozen, the world
# is reconsidered fresh. So detachment proceeds in settled waves, never a runaway feedback loop.

const BUDGET := 400          # flood cells stepped per physics frame
const MAX_DETACH := 700      # a component larger than this is treated as grounded — too big to free-
                             # fall, and MpmStructure.MAX_PARTICLES caps near here anyway (future: split)
const MAX_SCAN := 12000      # skip seed-gathering for absurdly large edit boxes (not a dig)

var _store: EditStore
var _integrity: StructuralIntegrity
var _pending := {}           # candidate seed cells still to resolve (Vector3i -> true)
var _flood: GroundFlood
var _active := false


func setup(store: EditStore, integrity: StructuralIntegrity) -> void:
    _store = store
    _integrity = integrity
    VoxelEventBusSingleton.subscribe(TerrainSdfChangedEvent.CHANNEL, _on_edit)
    VoxelEventBusSingleton.subscribe(WorldReadyEvent.CHANNEL, _on_world_ready)


func _on_world_ready(_event: VoxelEvent) -> void:
    _active = true


# Only react to edits made while MPM is idle — that excludes MPM's own thaw/freeze (which fire with
# particles in flight) and so breaks the cascade. Gather the edit's exposed solid cells as seeds.
func _on_edit(event: TerrainSdfChangedEvent) -> void:
    if not _active:
        return
    if _integrity.mpm == null or _integrity.mpm.active_count() > 0:
        return
    _gather_seeds(event)


# Seeds = solid, non-bedrock cells with an air neighbour in (a 1-cell dilation of) the edit box —
# the freshly-exposed surface, where support may have been cut.
func _gather_seeds(event: TerrainSdfChangedEvent) -> void:
    var lo := Vector3i(event.box_origin.floor()) - Vector3i.ONE
    var hi := Vector3i((event.box_origin + event.box_size).ceil()) + Vector3i.ONE
    var span := hi - lo + Vector3i.ONE
    if span.x * span.y * span.z > MAX_SCAN:
        return
    for z in range(lo.z, hi.z + 1):
        for y in range(lo.y, hi.y + 1):
            for x in range(lo.x, hi.x + 1):
                var c := Vector3i(x, y, z)
                if _is_solid(c) and not _is_bedrock(c) and _has_air_neighbor(c):
                    _pending[c] = true


func _physics_process(_delta: float) -> void:
    if not _active:
        return
    if _flood != null:
        if _flood.step(BUDGET) == GroundFlood.RUNNING:
            return
        _finish(_flood)
        _flood = null
    # Let in-flight material settle (and freeze) before resolving more detachment — the next wave
    # is judged against the post-fall world, not the mid-fall one.
    if _integrity.mpm != null and _integrity.mpm.active_count() > 0:
        return
    _start_next()


func _finish(flood: GroundFlood) -> void:
    for cell in flood.visited:
        _pending.erase(cell)
    if flood.state == GroundFlood.DETACHED and not flood.visited.is_empty():
        _integrity.mpm.thaw_cells(flood.visited.keys())


func _start_next() -> void:
    while not _pending.is_empty():
        var seed_cell: Vector3i = _pending.keys()[0]
        if not _is_solid(seed_cell) or _is_bedrock(seed_cell):
            _pending.erase(seed_cell)   # carved/thawed away since it was queued, or it's ground itself
            continue
        _flood = GroundFlood.new()
        _flood.start([seed_cell], _store, MAX_DETACH)
        return


func _is_solid(cell: Vector3i) -> bool:
    return TerrainProbe.is_solid(_store, cell)

func _is_bedrock(cell: Vector3i) -> bool:
    return TerrainProbe.is_bedrock(_store, cell)

func _has_air_neighbor(cell: Vector3i) -> bool:
    for n in GroundFlood.NEIGHBORS:
        if not _is_solid(cell + n):
            return true
    return false
