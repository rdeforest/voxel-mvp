class_name MpmStructure
extends Node3D

# World MPM structural manager (PB-MPM) — the doc-12 thaw → simulate → freeze loop on REAL
# terrain, the replacement for PbdStructure. Loose material is MPM particles; the static terrain
# (the EditStore SDF) is the collider. Cells thaw into particles (carved from the store, so a
# hole appears and the DC mesher re-meshes), fall/deform/settle against the terrain, then freeze
# back into the store when at rest (rasterised to SDF + material). Active particles render as a
# MultiMesh of cubes. Standalone for now (driven by `mpmthaw`); the support-loss auto-trigger and
# retiring PBD come next.

const PARTICLE_SIZE := 0.45
const RHO := 400.0
const GRID_DIM := 48           # re-centred on the material each step (no domain walls)
const SETTLE_DISP := 0.01      # max displacement/step below which the material counts as settled
const SETTLE_FRAMES := 30      # consecutive settled frames before freezing back
const FREEZE_RADIUS := 0.6     # particle-skinning radius for the freeze rasterisation
const MAX_PARTICLES := 6000    # hard cap — beyond this a step costs too much (a runaway-thaw guard)
const CHUNK := 12              # freeze region is re-meshed in CHUNK³ boxes (keeps each edit small)
const CHUNKS_PER_FRAME := 2    # bounded work/frame — the closest chunks re-mesh first
const SINGLE_EMIT_MAX := 24    # a settled clump this small re-meshes in ONE watertight box (no chunk seams)

var _sim: MpmSim
var _store: EditStore
var _mm: MultiMesh
var _settled_frames := 0
var _material_index := 1        # Stone — the material the frozen-back terrain takes
var _pending_chunks: Array = [] # freeze re-mesh boxes still to emit (closest-to-camera first)


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

    _mm = MultiMesh.new()
    _mm.transform_format = MultiMesh.TRANSFORM_3D
    var box := BoxMesh.new()
    box.size = Vector3.ONE * PARTICLE_SIZE
    _mm.mesh = box
    var mmi := MultiMeshInstance3D.new()
    mmi.multimesh = _mm
    mmi.material_override = _make_material()
    add_child(mmi)


# Thaw the solid terrain cells within `radius` of `center` (the `mpmthaw` console path).
func thaw_sphere(center: Vector3, radius: float, material_index := 1) -> int:
    var r2 := radius * radius
    var lo := Vector3i((center - Vector3.ONE * radius).floor())
    var hi := Vector3i((center + Vector3.ONE * radius).ceil())
    var cells: Array[Vector3i] = []
    for z in range(lo.z, hi.z + 1):
        for y in range(lo.y, hi.y + 1):
            for x in range(lo.x, hi.x + 1):
                var cell := Vector3i(x, y, z)
                if (Vector3(cell) + Vector3(0.5, 0.5, 0.5)).distance_squared_to(center) <= r2:
                    cells.append(cell)
    return thaw_cells(cells, material_index)


# Thaw a set of (presumed solid) terrain cells into MPM particles: carve each from the store (a
# hole opens, DC re-meshes), seed 8 particles per cell. Air cells are skipped. Returns the count
# thawed. This is what the loss-of-support auto-trigger feeds.
func thaw_cells(cells: Array, material_index := 1) -> int:
    _material_index = material_index
    var p_vol := 0.125
    var p_mass := RHO * p_vol
    var work: Array = []
    var box_lo := Vector3(INF, INF, INF)
    var box_hi := Vector3(-INF, -INF, -INF)
    for cell in cells:
        if _sim.particle_count() >= MAX_PARTICLES:
            break # runaway-thaw guard: leave the rest as terrain rather than choke
        if _store.sample(Vector3(cell) + Vector3(0.5, 0.5, 0.5)) >= VoxelConstants.SDF_SOLID_THRESHOLD:
            continue # already air
        for ox in [0.25, 0.75]:
            for oy in [0.25, 0.75]:
                for oz in [0.25, 0.75]:
                    _sim.add_particle(Vector3(cell) + Vector3(ox, oy, oz), p_mass, p_vol)
        work.append([cell, VoxelConstants.SDF_AIR])
        VoxelEventBusSingleton.emit(VoxelRemovedEvent.CHANNEL, VoxelRemovedEvent.new(VoxelConstants.GRID_ID, cell))
        box_lo = box_lo.min(Vector3(cell))
        box_hi = box_hi.max(Vector3(cell) + Vector3.ONE)
    if work.is_empty():
        return 0
    StoreWrite.cells(_store, work, func(_e): return -1) # carve to air
    VoxelEventBusSingleton.emit(TerrainSdfChangedEvent.CHANNEL, TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, box_lo, box_hi - box_lo))
    _settled_frames = 0
    _mm.instance_count = _sim.particle_count()
    return work.size()


func active_count() -> int:
    return _sim.particle_count() if _sim != null else 0


# Drop all active material (no freeze-back). Called when leaving MPM mode so a large in-flight
# set stops being stepped.
func reset() -> void:
    if _sim != null:
        _sim.clear()
    _settled_frames = 0
    _pending_chunks.clear()
    if _mm != null:
        _mm.instance_count = 0


func _physics_process(delta: float) -> void:
    tick(delta)


# Step the active material and freeze it back into the terrain once it has settled. Split out so
# the loop is headless-testable without the scene-tree physics callback.
func tick(delta: float) -> void:
    _emit_pending_chunks()
    if _sim == null or _sim.particle_count() == 0:
        return
    _sim.step(delta)
    if _sim.max_displacement() < SETTLE_DISP:
        _settled_frames += 1
        if _settled_frames >= SETTLE_FRAMES:
            _freeze()
    else:
        _settled_frames = 0


# Re-mesh the frozen region a few bounded boxes per frame, closest to the camera first, so each
# terrain_sdf_changed stays small (no main-thread freeze) and the nearby change shows promptly.
func _emit_pending_chunks() -> void:
    var n := 0
    while not _pending_chunks.is_empty() and n < CHUNKS_PER_FRAME:
        var box: Vector3 = _pending_chunks.pop_front()
        VoxelEventBusSingleton.emit(TerrainSdfChangedEvent.CHANNEL,
            TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, box, Vector3.ONE * float(CHUNK)))
        n += 1


# Rasterise the settled particles back into the store as terrain (fast, bin-hashed), then queue
# the region for chunked re-meshing (closest first), and drop the particles.
func _freeze() -> void:
    var region: Dictionary = _sim.rasterize_to_store(_store, 1.0, FREEZE_RADIUS, _material_index)
    if not region.is_empty():
        var origin: Vector3 = region["origin"]
        var dim: int = region["dim"]
        if dim <= SINGLE_EMIT_MAX:
            # Small settled clump → one box, meshed in a single splice (watertight, no chunk seams).
            VoxelEventBusSingleton.emit(TerrainSdfChangedEvent.CHANNEL,
                TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, origin, Vector3.ONE * float(dim)))
        else:
            _queue_freeze_chunks(origin, dim)
    _sim.clear()
    _settled_frames = 0
    if _mm != null:
        _mm.instance_count = 0


# Split the rasterised region into CHUNK³ boxes and sort them nearest-camera-first.
func _queue_freeze_chunks(origin: Vector3, dim: int) -> void:
    var vp := get_viewport()
    var cam := vp.get_camera_3d() if vp != null else null
    var eye := cam.global_position if cam != null else origin
    var boxes: Array = []
    var cx := 0
    while cx < dim:
        var cy := 0
        while cy < dim:
            var cz := 0
            while cz < dim:
                boxes.append(origin + Vector3(cx, cy, cz))
                cz += CHUNK
            cy += CHUNK
        cx += CHUNK
    boxes.sort_custom(func(a, b):
        return eye.distance_squared_to(a + Vector3.ONE * (CHUNK * 0.5)) < eye.distance_squared_to(b + Vector3.ONE * (CHUNK * 0.5)))
    _pending_chunks = boxes


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
