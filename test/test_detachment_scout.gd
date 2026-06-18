extends GutTest

# DetachmentScout: the loss-of-support trigger. On a terrain edit it floods the exposed solid
# toward bedrock; a detached component is thawed into MPM. Two cases: a floating block (no ground
# beneath) gets thawed; grounded terrain is left alone. Also pins the cascade guard: an edit that
# arrives while MPM has material in flight is ignored.

const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337
const CX := 100.0
const CZ := 100.0


func _surface() -> int:
    return int(EditStore.terrain_surface(CX, CZ, BASE, AMP, PERIOD, OCTAVES, SEED))

# A live store + MpmStructure + StructuralIntegrity + scout, all wired and world-ready.
func _rig() -> Dictionary:
    var s0 := _surface()
    var es := EditStore.new()
    es.setup(Vector3(CX - 256.0, s0 - 256.0, CZ - 256.0), 512.0, BASE, AMP, PERIOD, OCTAVES, SEED)

    var si: StructuralIntegrity = autofree(StructuralIntegrity.new())
    add_child(si)
    si.set_store(es)

    var ms: MpmStructure = autofree(MpmStructure.new())
    add_child(ms)
    ms.setup(es)
    si.mpm = ms

    var scout: DetachmentScout = autofree(DetachmentScout.new())
    add_child(scout)
    scout.setup(es, si)

    VoxelEventBusSingleton.emit(WorldReadyEvent.CHANNEL, WorldReadyEvent.new())   # arms _active
    return {"store": es, "mpm": ms, "scout": scout}


func _emit_edit(store: EditStore, lo: Vector3, size: Vector3) -> void:
    VoxelEventBusSingleton.emit(TerrainSdfChangedEvent.CHANNEL,
        TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, lo, size))


func _drive(scout: DetachmentScout, frames: int) -> void:
    for _i in frames:
        scout._physics_process(1.0 / 60.0)


func test_floating_block_is_detached_and_thawed() -> void:
    var rig := _rig()
    var es: EditStore = rig.store
    var ms: MpmStructure = rig.mpm
    var by := _surface() + 60
    es.stamp_box(Vector3(CX, float(by), CZ), Vector3(5, 5, 5), 0, MaterialPalette.index_of(&"Stone"), 1.0)

    _emit_edit(es, Vector3(CX - 4, float(by) - 4, CZ - 4), Vector3(8, 8, 8))
    assert_eq(ms.active_count(), 0, "no particles before the scout runs")
    _drive(rig.scout, 200)
    assert_gt(ms.active_count(), 0, "the floating block was detached and thawed into MPM")


func test_grounded_terrain_is_left_alone() -> void:
    var rig := _rig()
    var es: EditStore = rig.store
    var ms: MpmStructure = rig.mpm
    var top := _surface()
    # Edit box over solid mountain that connects down to bedrock — nothing should thaw.
    _emit_edit(es, Vector3(CX - 4, float(top) - 8, CZ - 4), Vector3(8, 8, 8))
    _drive(rig.scout, 400)
    assert_eq(ms.active_count(), 0, "grounded terrain reaches bedrock — nothing detaches")


func test_edit_while_mpm_active_is_ignored() -> void:
    var rig := _rig()
    var es: EditStore = rig.store
    var ms: MpmStructure = rig.mpm
    var by := _surface() + 60
    # Put MPM material in flight first (thaw a separate floating block), so the scout is in its
    # "settling" window when the next edit arrives.
    es.stamp_box(Vector3(CX + 40, float(by), CZ), Vector3(5, 5, 5), 0, MaterialPalette.index_of(&"Stone"), 1.0)
    ms.thaw_sphere(Vector3(CX + 40, float(by), CZ), 3.0)
    assert_gt(ms.active_count(), 0, "material is in flight")
    var before := ms.active_count()

    es.stamp_box(Vector3(CX, float(by), CZ), Vector3(5, 5, 5), 0, MaterialPalette.index_of(&"Stone"), 1.0)
    _emit_edit(es, Vector3(CX - 4, float(by) - 4, CZ - 4), Vector3(8, 8, 8))
    rig.scout._physics_process(1.0 / 60.0)   # one tick: the in-flight guard should hold
    assert_eq(ms.active_count(), before, "an edit during MPM flight is ignored (no new thaw) — cascade guard")
