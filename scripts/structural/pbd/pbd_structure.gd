class_name PbdStructure
extends Node3D

# Live PBD over the REAL tracked structural set: derives a spring network from the
# current tracked voxels (TerrainSupport.voxel_data) + placed parts
# (PartSupport.part_registry), with anchors from TerrainSupport.is_natural_terrain,
# runs the solver, and renders member stress in-world. Rebuilds on any structural
# edit (bus). Phase 2: VIZ-ONLY / non-authoritative — it does not carve or collapse
# anything; the existing structural system stays in charge. Toggle: `pbdlive`.
#
# A stable structure shows as a stress-coloured wireframe hugging the terrain; an
# over-extended one visibly droops/falls (predicting where the real system — once
# PBD is authoritative in a later phase — will let it go).

var _integrity: StructuralIntegrity
var _solver := PbdSolver.new()
var _net: PbdNetwork
var _im: ImmediateMesh
var _mesh: MeshInstance3D
var _enabled := false
var _dirty := true


func setup(integrity: StructuralIntegrity) -> void:
    _integrity = integrity
    _im = ImmediateMesh.new()
    _mesh = MeshInstance3D.new()
    _mesh.mesh = _im
    _mesh.material_override = PbdRenderer.make_material()
    _mesh.visible = false
    add_child(_mesh)
    for channel in [
            TerrainSdfChangedEvent.CHANNEL, VoxelAddedEvent.CHANNEL, VoxelRemovedEvent.CHANNEL,
            PartAddedEvent.CHANNEL, PartRemovedEvent.CHANNEL]:
        VoxelEventBusSingleton.subscribe(channel, _on_structural_change)


func set_enabled(on: bool) -> void:
    _enabled = on
    _mesh.visible = on
    if on:
        _dirty = true
    else:
        _im.clear_surfaces()


func is_enabled() -> bool:
    return _enabled


func _on_structural_change(_event: VoxelEvent) -> void:
    _dirty = true


func _physics_process(delta: float) -> void:
    if not _enabled:
        return
    if _dirty:
        _rebuild()
        _dirty = false
    if _net != null:
        _solver.step(_net, delta)
        PbdRenderer.draw(_net, _im)


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
    _net = PbdNetworkBuilder.build(cells, is_natural)["network"]
