class_name DetachmentScout
extends Node

# The loss-of-support trigger (replaces the removed scalar-support cascade). When a terrain edit
# might have cut something loose, it floods the affected solid component down toward Bedrock
# (GroundFlood): a component that drains without reaching ground is DETACHED and gets thawed into
# MPM (it falls). Non-blocking — one flood at a time, a budget of cells per physics frame.
#
# Cascade safety (why the scalar trigger died): the scout never re-floods what its own work was
# meant to remove, and it resolves only a settled world. Neither rule is a timing guess.
#   - Edits are told apart by source. For its own SCOUT thaw it seeds only from the collateral: the
#     measured flips outside the component it thawed. The thaw's carve is solved to keep every
#     unplanned cell on its side, so there should be none; the seeding stays because the flips are
#     measured, not assumed. The thawed component itself is never re-seeded, and a refused thaw writes
#     and announces nothing, so neither can loop.
#   - MPM freeze events are ignored entirely, flips and all. That is a known hole: the freeze's 1 m
#     rewrite can empty a cell and leave a neighbour unsupported. Seeding from its flips was measured
#     to loop: a pile frozen onto geometry the collider holds but GroundFlood reads as air floods
#     DETACHED, thaws, and freezes again (https://github.com/rdeforest/voxel-mvp/issues/20).
#   - It pauses resolving while MPM has material in flight, so the next wave is judged against the
#     post-fall world. Edits by anyone else during flight are queued, not dropped.
# So detachment proceeds in settled waves, never a runaway feedback loop.

const BUDGET := 400          # flood cells stepped per physics frame
const MAX_DETACH := 700      # a component larger than this is treated as grounded — too big to free-
                             # fall, and MpmStructure.MAX_PARTICLES caps near here anyway (future: split)
const MAX_SCAN := 12000      # skip seed-gathering for absurdly large edit boxes (not a dig)

var _store: EditStore
var _integrity: StructuralIntegrity
var _pending := {}           # candidate seed cells still to resolve (Vector3i -> true)
var _flood: GroundFlood
var _active := false
var _thawing := {}           # the component whose thaw is being announced (emit is synchronous)


# Registers with `integrity`, whose quiescence gate must wait for this scout's pending work.
func setup(store: EditStore, integrity: StructuralIntegrity) -> void:
    _store = store
    _integrity = integrity
    _integrity.scout = self
    VoxelEventBusSingleton.subscribe(TerrainSdfChangedEvent.CHANNEL, _on_edit)
    VoxelEventBusSingleton.subscribe(WorldReadyEvent.CHANNEL, _on_world_ready)


func _on_world_ready(_event: VoxelEvent) -> void:
    _active = true


# Without MPM there is nothing to thaw a detached piece into. See the header for the sources.
func _on_edit(event: TerrainSdfChangedEvent) -> void:
    if not _active or _integrity.mpm == null:
        return

    if event.source == EditSource.Kind.MPM:
        return

    if event.source == EditSource.Kind.SCOUT:
        _seed_collateral(event.flips)
        return

    _gather_seeds(event)


# Seeds from the cells the scout's own thaw flipped outside the component it thawed: the solid
# neighbours of a cell that went air (where support may have been cut) and a cell that went solid
# (a sliver the rewrite may have left floating).
func _seed_collateral(flips: CellFlips) -> void:
    for cell in flips.air:
        if _thawing.has(cell):
            continue

        for n in GroundFlood.NEIGHBORS:
            _seed(cell + n)

    for cell in flips.solid:
        _seed(cell)


func _seed(cell: Vector3i) -> void:
    if not _thawing.has(cell) and _is_solid(cell) and not _is_bedrock(cell):
        _pending[cell] = true


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
    tick()


# One physics frame of work. The frame is the unit of the flood budget, so a replay steps the scout
# on its own clock by calling this (test/support/scenario.gd), never on wall-clock time.
func tick() -> void:
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


# No flood running and no seed waiting: every edit it has heard is resolved. The save and recording
# gate (StructuralIntegrity.is_quiescent) waits for this, because pending seeds aren't saved.
func is_idle() -> bool:
    return _flood == null and _pending.is_empty()


func _finish(flood: GroundFlood) -> void:
    for cell in flood.visited:
        _pending.erase(cell)
    if flood.state == GroundFlood.DETACHED and not flood.visited.is_empty():
        _thawing = flood.visited
        _integrity.mpm.thaw_cells(flood.visited.keys(), EditSource.Kind.SCOUT)
        _thawing = {}


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
