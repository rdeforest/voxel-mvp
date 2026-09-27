class_name MpmStructure
extends Node3D

# World MPM structural manager (PB-MPM) — the doc-12 thaw → simulate → freeze
# loop on REAL terrain, the structural substrate (it replaced the old mass-spring
# sim). Loose material is MPM particles; the static terrain (the EditStore SDF) is
# the collider. Cells thaw into particles (carved from the store, so a hole appears
# and the DC mesher re-meshes), fall/deform/settle against the terrain, then freeze
# back into the store when at rest (rasterised to SDF + material). Active particles
# render as a MultiMesh of cubes. Manual thaw (`mpmthaw`) plus the loss-of-support
# auto-trigger (DetachmentScout); the auto-trigger's flood-to-ground is being hardened.

const DEBUG_CUBE_SIZE  := 0.45
const RHO              := 400.0
const GRID_DIM         := 48     # re-centred on the material each step (no domain walls)
const SETTLE_DISP      := 0.01   # max displacement/step below which the material counts as settled
const SETTLE_FRAMES    := 30     # consecutive settled frames before freezing back
const FREEZE_RADIUS    := 0.6    # particle-skinning radius for the freeze rasterisation
const MAX_PARTICLES    := 6000   # hard cap — beyond this a step costs too much (a runaway-thaw guard)
const CHUNK            := 12     # freeze region is re-meshed in CHUNK³ boxes (keeps each edit small)
const CHUNKS_PER_FRAME := 2      # bounded work/frame
const SINGLE_EMIT_MAX  := 24     # a settled clump this small re-meshes in ONE watertight box (no chunk seams)

const _UNIT_CUBE: Array[Vector3i] = [
    Vector3i(0, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(0, 1, 1),
    Vector3i(1, 0, 0), Vector3i(1, 0, 1), Vector3i(1, 1, 0), Vector3i(1, 1, 1),
]

var _sim:   MpmSim
var _store: EditStore
var _mm:    MultiMesh

var _settled_frames := 0
var _material_index := 1        # Stone — the material the frozen-back terrain takes
var _pending_chunks: Array = [] # freeze re-mesh boxes still to emit, bottom layer first


func setup(store: EditStore) -> void:
    _store = store

    _sim = MpmSim.new()
    _sim.configure(Vector3.ZERO, GRID_DIM, 1.0, Vector3(0, -9.8, 0), -1.0e9)
    _sim.set_iterations(4)
    _sim.set_elastic(1.0, 0.5)
    _sim.set_contact_friction(0.35)   # so it grips terrain instead of sliding forever (SSX)
    _sim.set_damping(0.03)            # bleed energy so it actually comes to rest
    _sim.set_recenter(true)
    _sim.set_sdf_collider(store)

    var box := BoxMesh.new()
    box.size = Vector3.ONE * DEBUG_CUBE_SIZE

    _mm = MultiMesh.new()
    _mm.transform_format = MultiMesh.TRANSFORM_3D
    _mm.mesh = box

    var mmi := MultiMeshInstance3D.new()
    mmi.multimesh = _mm
    mmi.material_override = _make_material()

    add_child(mmi)


# Thaw the solid terrain cells within `radius` of `center` (the `mpmthaw` console path).
func thaw_sphere(center: Vector3, radius: float, source: EditSource.Kind, material_index := 1) -> int:
    return thaw_cells(VoxelUtils.cells_in_sphere(center, radius), source, material_index)


# Thaw a set of (presumed solid) terrain cells into MPM particles: carve them from the store (a
# hole opens, DC re-meshes) and seed 8 particles per cell the carve actually turned to air. Air
# cells are skipped. Returns the count thawed. This is what the loss-of-support auto-trigger feeds;
# the carve's event is credited to `source` (SCOUT for a detachment, INSTRUMENT for `mpmthaw`).
#
# The planned cells are only the carve's input. A planned cell can survive it (every corner it has
# is shared with kept solid, so none may clear), and rewriting the box re-encodes the field there,
# which can flip cells the plan never named. So the event and the particles both follow the flips
# measured across the write, as VoxelImprint.apply does: matter leaves the store exactly where it
# enters the sim.
func thaw_cells(cells: Array, source: EditSource.Kind, material_index := 1) -> int:
    _material_index = material_index   # freeze fallback only; each particle carries its own material

    var work := _carve_corners(_plan_thaw(cells))

    if work.is_empty():
        return 0

    var lat   := StoreWrite.lattice(_store, work)
    var flips := StoreWrite.write(_store, lat, work)

    _seed_particles(flips)
    _settled_frames = 0
    _mm.instance_count = _sim.particle_count()

    # A rewrite that changed nothing needs no re-mesh and has no flips to report.
    if flips.changed:
        TerrainSdfChangedEvent.announce(source, lat.region(), flips)

    return flips.air.size()


# The solid cells to carve (centre sampled solid), capped so the planned cells' particles fit
# under MAX_PARTICLES: past the cap the rest stays terrain rather than choke the sim.
func _plan_thaw(cells: Array) -> Dictionary:
    var planned := {}
    var budget  := (MAX_PARTICLES - _sim.particle_count()) / 8

    for cell in cells:
        if planned.size() >= budget:
            break

        if TerrainProbe.is_solid(_store, cell):
            planned[cell] = true

    return planned


# Eight particles in each cell the carve emptied, of what the cell was made of.
func _seed_particles(carved: CellFlips) -> void:
    var p_vol  := 0.125
    var p_mass := RHO * p_vol

    for i in carved.air.size():
        var cell := carved.air[i]
        for ox in [0.25, 0.75]:
            for oy in [0.25, 0.75]:
                for oz in [0.25, 0.75]:
                    _sim.add_particle(Vector3(cell) + Vector3(ox, oy, oz), p_mass, p_vol, carved.air_materials[i])


# Carving a corner-sampled SDF cleanly. StoreWrite sets the value at the grid CORNER it's handed,
# so the old per-cell `[cell, AIR]` raised only each cell's base (min) corner — the +X/+Y/+Z face
# corners of the boundary cells stayed solid, leaving every thawed cell a 1..7/8-solid shell.
# Instead: raise a grid corner to air UNLESS a kept-solid cell still needs it — a corner clears iff
# none of its 8 surrounding cells is solid-and-not-thawed. Interior corners (all neighbours thawed)
# clear; corners against the kept terrain stay, so the carve leaves a clean wall, not a crust.
func _carve_corners(planned: Dictionary) -> Array[LatticeEdit]:
    var corner_work: Array[LatticeEdit] = []
    var seen := {}
    var kept := {}   # unplanned cell -> kept solid; each is probed once, not once per corner

    for cell: Vector3i in planned:
        for offset in _UNIT_CUBE:
            var corner := cell + offset

            if seen.has(corner):
                continue

            seen[corner] = true

            if _corner_clears(corner, planned, kept):
                corner_work.append(LatticeEdit.new(corner, VoxelConstants.SDF_AIR))

    return corner_work


# The 8 cells touching grid corner C have base corners C-{0,1}³. The corner can go air unless one
# of them is kept solid (not thawed, and its centre samples solid).
func _corner_clears(corner: Vector3i, planned: Dictionary, kept: Dictionary) -> bool:
    for offset in _UNIT_CUBE:
        var nc := corner - offset

        if planned.has(nc):
            continue

        if not kept.has(nc):
            kept[nc] = TerrainProbe.is_solid(_store, nc)

        if kept[nc]:
            return false   # a kept-solid neighbour needs this corner

    return true


func active_count() -> int:
    return _sim.particle_count() if _sim != null else 0


# No material in flight and no frozen region still waiting to be announced.
func is_idle() -> bool:
    return active_count() == 0 and _pending_chunks.is_empty()


func _physics_process(delta: float) -> void:
    tick(delta)


# Step the active material and freeze it back into the terrain once it has settled. Split out so
# the loop is headless-testable without the scene-tree physics callback.
func tick(delta: float) -> void:
    _emit_pending_chunks()

    if _sim and _sim.particle_count():
        _sim.step(delta)

        if _sim.max_displacement() < SETTLE_DISP:
            _settled_frames += 1

            if _settled_frames >= SETTLE_FRAMES:
                _freeze()
        else:
            _settled_frames = 0


# Announce the frozen region a few bounded boxes per frame, so each terrain_sdf_changed (a re-mesh
# and a structural re-scan) stays small: no main-thread freeze.
func _emit_pending_chunks() -> void:
    var n := 0

    while not _pending_chunks.is_empty() and n < CHUNKS_PER_FRAME:
        var box: Vector3 = _pending_chunks.pop_front()

        _announce_freeze(AABB(box, Vector3.ONE * float(CHUNK)))

        n += 1


# Rasterise the settled particles back into the store as terrain (fast, bin-hashed), then queue
# the region for chunked announcement, and drop the particles.
func _freeze() -> void:
    var region: Dictionary = _sim.rasterize_to_store(_store, 1.0, FREEZE_RADIUS, _material_index)

    if not region.is_empty():
        var origin: Vector3 = region["origin"]
        var dim:    int     = region["dim"]

        if dim <= SINGLE_EMIT_MAX:
            # Small settled clump → one box, meshed in a single splice (watertight, no chunk seams).
            _announce_freeze(AABB(origin, Vector3.ONE * float(dim)))
        else:
            _queue_freeze_chunks(origin, dim)

    _sim.clear()
    _settled_frames = 0

    if _mm:
        _mm.instance_count = 0


# MpmSim.rasterize_to_store writes without measuring, so a freeze reports its box with no flips:
# subscribers learn of its cells only by re-scanning the box
# (docs/bugs/mpm-freeze-flips-unmeasured.md).
func _announce_freeze(box: AABB) -> void:
    TerrainSdfChangedEvent.announce(EditSource.Kind.MPM, box, CellFlips.new())


# Split the rasterised region into CHUNK³ boxes, in an order fixed by position: bottom layer first,
# then z, then x. Structural subscribers hear the freeze in this order, so it must be part of the
# world, not of where the camera happens to be; any fixed order would do, and bottom-up puts a pile's
# footing before what rests on it. Appended, so a freeze landing while an earlier one is still being
# announced doesn't drop the rest of the earlier one.
func _queue_freeze_chunks(origin: Vector3, dim: int) -> void:
    for cy in range(0, dim, CHUNK):
        for cz in range(0, dim, CHUNK):
            for cx in range(0, dim, CHUNK):
                _pending_chunks.append(origin + Vector3(cx, cy, cz))


func _process(_dt: float) -> void:
    if _sim == null:
        return

    for i in _sim.particle_count():
        _mm.set_instance_transform(i, Transform3D(Basis(), _sim.get_position(i)))


static func _make_material() -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()

    mat.albedo_color = Color(0.5, 0.45, 0.4)
    mat.roughness = 0.95

    return mat
