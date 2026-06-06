class_name PbdStructure
extends Node3D

# Live PBD over the REAL tracked structural set: derives a spring network (PbdSim,
# C++) from the current tracked voxels (TerrainSupport.voxel_data) + placed parts
# (PartSupport.part_registry), with anchors from TerrainSupport.is_natural_terrain,
# steps the solver each physics tick, and renders member stress in-world (once per
# rendered frame). Rebuilds on any structural edit (bus). AUTHORITATIVE while enabled
# (enabled by default at world startup): when a member breaks and a component comes
# loose, terrain cells are carved out of the SDF + handed to FallingBodyFactory and
# detached parts drop whole; the old PartSupport strain/collapse stands down via
# StructuralIntegrity.part_collapse_enabled (terrain has no old system left).
# `pbdlive` toggles it; the `V` key toggles the stress-line overlay. Reports its
# per-tick cost to the Perf overlay.

const GRID_ID := 0

var _integrity: StructuralIntegrity
var _sim: PbdSim
var _cell_of_node: Array = []      # node index -> Vector3i cell (collapse handoff)
var _node_of_cell: Dictionary = {} # Vector3i cell -> node index (probe lookup)
var _mesh: ArrayMesh
var _mi: MeshInstance3D
var _enabled := false
var _viz_visible := true            # V key toggles the stress-line overlay
var _dirty := true
var _headless := false              # no display → skip rendering (dummy renderer chokes on it)
var _unanchored := false            # built a non-empty network with no anchors (terrain not streamed yet)
var _retry_timer := 0.0
var _active := false                # inactive until WorldReadyEvent — don't sim a half-loaded world

const ANCHOR_RETRY_SEC := 0.3       # while unanchored, re-derive this often until terrain loads


func setup(integrity: StructuralIntegrity) -> void:
    _integrity = integrity
    _headless = DisplayServer.get_name() == "headless"
    _mesh = ArrayMesh.new()
    _mi = MeshInstance3D.new()
    _mi.mesh = _mesh
    _mi.material_override = PbdRenderer.make_material()
    _mi.visible = false
    add_child(_mi)
    for channel in [
            TerrainSdfChangedEvent.CHANNEL, VoxelAddedEvent.CHANNEL, VoxelRemovedEvent.CHANNEL,
            PartAddedEvent.CHANNEL, PartRemovedEvent.CHANNEL]:
        VoxelEventBusSingleton.subscribe(channel, _on_structural_change)
    VoxelEventBusSingleton.subscribe(WorldReadyEvent.CHANNEL, _on_world_ready)


func set_enabled(on: bool) -> void:
    _enabled = on
    _mi.visible = on and _viz_visible
    # Take collapse authority while on (the old PartSupport strain/collapse stands
    # down so two systems don't both act); hand it back when off.
    if is_instance_valid(_integrity):
        _integrity.part_collapse_enabled = not on
    if on:
        _dirty = true
    else:
        _mesh.clear_surfaces()


func is_enabled() -> bool:
    return _enabled


# Show/hide the stress-line overlay without disabling the sim (the V key).
func toggle_viz() -> void:
    _viz_visible = not _viz_visible
    _mi.visible = _enabled and _viz_visible


# Settled = nothing is going to move on its own (gates save / quiescence). A
# disabled PBD doesn't gate (the old system handles quiescence then).
func is_settled() -> bool:
    if not _enabled:
        return true
    return not _dirty and (_sim == null or _sim.awake_count() == 0)


# Force the network to rest right now (for the `settle` save-unblock command):
# fold in any pending rebuild, then sleep every node where it stands.
func force_settle() -> void:
    if not _enabled:
        return
    if _dirty:
        _rebuild()
        _dirty = false
    if _sim != null:
        _sim.sleep_all()


# Diagnostic snapshot of a cell's place in the live network (for the Probe tool).
# "anchored" is the answer to "why isn't this falling?": a cell still connected to
# any pinned anchor is held by definition, however stressed its members look.
func probe(cell: Vector3i) -> Dictionary:
    var out := {"enabled": _enabled}
    if not _enabled or _sim == null:
        return out
    if not _node_of_cell.has(cell):
        out["in_network"] = false
        return out
    var node: int = _node_of_cell[cell]
    var detached := false
    for comp in _sim.get_detached_components():
        if node in comp:
            detached = true
            break
    var members: Array = []
    var peak_ratio := 0.0
    var peak_damage := 0.0
    for k in _sim.member_count():
        if _sim.member_broken(k):
            continue
        if _sim.member_a(k) != node and _sim.member_b(k) != node:
            continue
        var f: float = _sim.member_force(k)
        var limit: float = _sim.member_tension(k) if f >= 0.0 else _sim.member_compression(k)
        var ratio := absf(f) / maxf(limit, 0.001)
        var dmg: float = _sim.member_damage(k)
        peak_ratio = maxf(peak_ratio, ratio)
        peak_damage = maxf(peak_damage, dmg)
        members.append({"force": f, "limit": limit, "ratio": ratio, "damage": dmg})
    out["in_network"] = true
    out["node"] = node
    out["pinned"] = _sim.is_pinned(node)
    out["sleeping"] = _sim.is_sleeping(node)
    out["anchored"] = not detached
    out["members"] = members
    out["peak_ratio"] = peak_ratio
    out["peak_damage"] = peak_damage
    return out


func _on_structural_change(_event: VoxelEvent) -> void:
    _dirty = true

func _on_world_ready(_event: VoxelEvent) -> void:
    _active = true
    _dirty = true   # build now that the terrain SDF (and thus anchors) exists


func _physics_process(delta: float) -> void:
    if not _enabled or not _active:
        return
    var t0 := Time.get_ticks_usec()
    if _dirty:
        _rebuild()
        _dirty = false
    if _sim != null:
        if _unanchored:
            # Don't step a network with no anchors — it would free-fall through the
            # world. On load this means the terrain SDF hasn't streamed in yet, so
            # re-derive periodically until anchor detection finds ground.
            _retry_timer += delta
            if _retry_timer >= ANCHOR_RETRY_SEC:
                _retry_timer = 0.0
                _dirty = true
        else:
            _sim.step(delta)
            if _sim.broke_last_step():
                _handle_detachment()
    Perf.report("PBD (%d nodes)" % (_sim.node_count() if _sim != null else 0), (Time.get_ticks_usec() - t0) / 1000.0)


# A member broke; any component that's now anchorless is falling. Terrain cells get
# carved + handed to the falling-body pipeline; any Part with a detached cell drops
# whole (a part is an atomic Node3D — it can't half-fall). Then rebuild.
func _handle_detachment() -> void:
    var ts := _integrity.terrain_support
    var ps := _integrity.part_support
    var detached_parts := {}   # Node3D -> true (dedup; a part spans many cells)
    var collapsed := false
    for comp in _sim.get_detached_components():
        var cells: Array[Vector3i] = []
        for idx in comp:
            var cell: Vector3i = _cell_of_node[idx]
            if ts.voxel_data.has(cell):
                cells.append(cell)
            else:
                for part in ps.parts_at_cell(cell):
                    detached_parts[part] = true
        if not cells.is_empty():
            _collapse(cells)
            collapsed = true
    for part in detached_parts:
        ps.collapse_part(part)
        collapsed = true
    # Rebuild NOW, not next tick: _collapse erased the terrain cells from voxel_data
    # and collapse_part dropped the parts from the registry (both synchronous), so the
    # detached nodes vanish from the network this frame instead of free-falling as
    # stale green lines for a frame (250ms at 4fps). The freshly-built sim won't
    # report broke_last_step until a real break, so this can't re-enter.
    if collapsed:
        _rebuild()


# Spawn a falling body for the detached terrain cells, carve them to air, and emit
# the primitive events so the rest of the world reacts.
func _collapse(cells: Array[Vector3i]) -> void:
    var body := FallingBodyFactory.from_voxels(cells)
    get_parent().add_child(body)
    VoxelEventBusSingleton.emit(RegionCollapsingEvent.CHANNEL, RegionCollapsingEvent.new(GRID_ID, cells))
    var vt: VoxelTool = _integrity.terrain_support.terrain.get_voxel_tool()
    vt.channel = VoxelBuffer.CHANNEL_SDF
    vt.mode = VoxelTool.MODE_REMOVE
    var lo := Vector3(cells[0])
    var hi := lo + Vector3.ONE
    for v in cells:
        vt.set_voxel_f(v, VoxelConstants.SDF_AIR)
        VoxelEventBusSingleton.emit(VoxelRemovedEvent.CHANNEL, VoxelRemovedEvent.new(GRID_ID, v))
        lo = lo.min(Vector3(v))
        hi = hi.max(Vector3(v) + Vector3.ONE)
    VoxelEventBusSingleton.emit(TerrainSdfChangedEvent.CHANNEL, TerrainSdfChangedEvent.new(GRID_ID, lo, hi - lo))


func _process(_dt: float) -> void:
    if _headless:
        return   # no RenderingServer to draw into (and the dummy one crashes on it)
    if _enabled and _viz_visible and _sim != null:
        PbdRenderer.draw(_sim, _mesh)


func _rebuild() -> void:
    var ts := _integrity.terrain_support
    var ps := _integrity.part_support
    var cells := {}
    for cell in ts.voxel_data:
        cells[cell] = ts.voxel_data[cell].material
    for node in ps.part_registry:
        var data: PartData = ps.part_registry[node]
        for c in data.cells:
            cells[c] = data.material
    var is_natural := func(c: Vector3i) -> bool: return ts.is_natural_terrain(c)
    var r := PbdNetworkBuilder.build(cells, is_natural)
    _sim = r["sim"]
    _cell_of_node = r["cell_of_node"]
    _node_of_cell = r["node_of_cell"]
    # A non-empty network with no anchors can't be a real settled structure (one
    # never goes quiescent, so it can't have been saved) — it's the terrain SDF not
    # yet streamed in. Hold off stepping until anchors appear. See _physics_process.
    _unanchored = _sim.node_count() > 0 and int(r["anchor_count"]) == 0
