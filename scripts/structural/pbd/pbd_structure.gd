class_name PbdStructure
extends Node3D

# Live PBD over the REAL tracked structural set: derives a spring network (PbdSim,
# C++) from the current tracked voxels (TerrainSupport.voxel_data) + placed parts
# (PartSupport.part_registry), with anchors from TerrainSupport.is_natural_terrain,
# steps the solver each physics tick, and renders member stress in-world (once per
# rendered frame). Rebuilds on any structural edit (bus). Phase 2: VIZ-ONLY /
# non-authoritative — it does not carve or collapse; the existing system stays in
# charge. Toggle: `pbdlive`. Reports its per-tick cost to the Perf overlay.

var _integrity: StructuralIntegrity
var _sim: PbdSim
var _mesh: ArrayMesh
var _mi: MeshInstance3D
var _enabled := false
var _dirty := true


func setup(integrity: StructuralIntegrity) -> void:
    _integrity = integrity
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


func set_enabled(on: bool) -> void:
    _enabled = on
    _mi.visible = on
    if on:
        _dirty = true
    else:
        _mesh.clear_surfaces()


func is_enabled() -> bool:
    return _enabled


func _on_structural_change(_event: VoxelEvent) -> void:
    _dirty = true


func _physics_process(delta: float) -> void:
    if not _enabled:
        return
    var t0 := Time.get_ticks_usec()
    if _dirty:
        _rebuild()
        _dirty = false
    if _sim != null:
        _sim.step(delta)
    Perf.report("PBD (%d nodes)" % (_sim.node_count() if _sim != null else 0), (Time.get_ticks_usec() - t0) / 1000.0)


func _process(_dt: float) -> void:
    if _enabled and _sim != null:
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
    _sim = PbdNetworkBuilder.build(cells, is_natural)["sim"]
