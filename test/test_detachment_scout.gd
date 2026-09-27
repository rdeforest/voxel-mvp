extends GutTest

# DetachmentScout: the loss-of-support trigger. On a terrain edit it floods the exposed solid
# toward bedrock; a detached component is thawed into MPM. Two cases: a floating block (no ground
# beneath) gets thawed; grounded terrain is left alone. Also pins the cascade guard, by the source
# each event carries: the scout seeds from its own thaw only where that thaw flipped cells outside
# the component it thawed, ignores MPM's freezes, and resolves an edit made while material is in
# flight only once it has settled.

const MatterLog := preload("res://test/support/matter_log.gd")


# A thaw whose carve can't empty its plan but still rewrites the field there, as
# docs/bugs/mpm-thaw-carve-leaves-planned-cells.md describes: every corner inside the plan (all 8
# of its cells planned) is pushed further solid. Nothing leaves the store and no cell flips, MPM
# stays idle, and the write still changes samples, so it is announced. Pushing a corner an
# unplanned cell shares would grow the piece instead, which is collateral the scout rightly
# re-checks. Counts the thaws the scout asks for.
class StubbornMpm:
    extends MpmStructure

    var thaws := 0

    func _carve_corners(planned: Dictionary) -> Array[LatticeEdit]:
        thaws += 1
        var work: Array[LatticeEdit] = []
        var seen := {}
        for cell: Vector3i in planned:
            for k in 8:
                var corner := cell + Vector3i(CubeGeometry.corner(k))
                if seen.has(corner) or not _inside(corner, planned):
                    continue

                seen[corner] = true
                work.append(LatticeEdit.new(corner, _store.sample(Vector3(corner)) - 0.05))
        return work

    func _inside(corner: Vector3i, planned: Dictionary) -> bool:
        for k in 8:
            if not planned.has(corner - Vector3i(CubeGeometry.corner(k))):
                return false
        return true

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
func _rig(ms: MpmStructure = MpmStructure.new()) -> Dictionary:
    var s0 := _surface()
    var es := EditStore.new()
    es.setup(Vector3(CX - 256.0, s0 - 256.0, CZ - 256.0), 512.0, BASE, AMP, PERIOD, OCTAVES, SEED)
    return _wire(es, ms)


func _wire(es: EditStore, ms: MpmStructure) -> Dictionary:
    var si: StructuralIntegrity = autofree(StructuralIntegrity.new())
    add_child(si)
    si.set_store(es)

    autofree(ms)
    add_child(ms)
    ms.setup(es)
    si.mpm = ms

    var scout: DetachmentScout = autofree(DetachmentScout.new())
    add_child(scout)
    scout.setup(es, si)

    VoxelEventBusSingleton.emit(WorldReadyEvent.CHANNEL, WorldReadyEvent.new())   # arms _active
    return {"store": es, "mpm": ms, "scout": scout}


func _emit_edit(lo: Vector3, size: Vector3, source := EditSource.Kind.PLAYER) -> void:
    TerrainSdfChangedEvent.announce(source, AABB(lo, size), CellFlips.new())


func _stone_block(es: EditStore, centre: Vector3) -> void:
    es.stamp_box(centre, Vector3(5, 5, 5), 0, MaterialPalette.index_of(&"Stone"), 1.0)


func _drive(scout: DetachmentScout, frames: int) -> void:
    for _i in frames:
        scout._physics_process(1.0 / 60.0)


func test_floating_block_is_detached_and_thawed() -> void:
    var rig := _rig()
    var es: EditStore = rig.store
    var ms: MpmStructure = rig.mpm
    var by := _surface() + 60
    es.stamp_box(Vector3(CX, float(by), CZ), Vector3(5, 5, 5), 0, MaterialPalette.index_of(&"Stone"), 1.0)

    _emit_edit(Vector3(CX - 4, float(by) - 4, CZ - 4), Vector3(8, 8, 8))
    assert_eq(ms.active_count(), 0, "no particles before the scout runs")
    _drive(rig.scout, 200)
    assert_gt(ms.active_count(), 0, "the floating block was detached and thawed into MPM")


func test_grounded_terrain_is_left_alone() -> void:
    var rig := _rig()
    var es: EditStore = rig.store
    var ms: MpmStructure = rig.mpm
    var top := _surface()
    # Edit box over solid mountain that connects down to bedrock — nothing should thaw.
    _emit_edit(Vector3(CX - 4, float(top) - 8, CZ - 4), Vector3(8, 8, 8))
    _drive(rig.scout, 400)
    assert_eq(ms.active_count(), 0, "grounded terrain reaches bedrock — nothing detaches")


func test_edit_during_mpm_flight_waits_for_the_material_to_settle() -> void:
    var rig := _rig()
    var es: EditStore = rig.store
    var ms: MpmStructure = rig.mpm
    var by := _surface() + 60
    # Put MPM material in flight first (thaw a separate floating block), so the scout is in its
    # "settling" window when the next edit arrives.
    _stone_block(es, Vector3(CX + 40, float(by), CZ))
    ms.thaw_sphere(Vector3(CX + 40, float(by), CZ), 3.0, EditSource.Kind.INSTRUMENT)
    assert_gt(ms.active_count(), 0, "material is in flight")
    var before := ms.active_count()

    _stone_block(es, Vector3(CX, float(by), CZ))
    _emit_edit(Vector3(CX - 4, float(by) - 4, CZ - 4), Vector3(8, 8, 8))
    _drive(rig.scout, 1)
    assert_eq(ms.active_count(), before, "nothing new thaws while material is in flight")

    _settle(ms)
    _drive(rig.scout, 200)
    assert_gt(ms.active_count(), 0, "the edit was kept, and once the world settled its block detached")


func test_scout_and_mpm_edits_do_not_seed_from_their_box() -> void:
    var rig := _rig()
    var top := _surface()
    var box := AABB(Vector3(CX - 4, float(top) - 4, CZ - 4), Vector3(8, 8, 8))
    for source: EditSource.Kind in EditSource.Kind.values():
        rig.scout._pending.clear()
        _emit_edit(box.position, box.size, source)
        var ignored := source in [EditSource.Kind.SCOUT, EditSource.Kind.MPM]
        assert_eq(rig.scout._pending.is_empty(), ignored,
            "%s edits %s" % [EditSource.Kind.keys()[source], "seed nothing" if ignored else "seed the scout"])


# The B4 loop (7e6c225): a detachment thaw that empties nothing leaves MPM idle but still
# announces its rewrite. Judged by timing (MPM idle = not MPM's edit) the scout re-seeded onto the
# same piece and thawed it again, forever; judged by source it hears its own thaw and moves on.
func test_a_thaw_that_empties_nothing_does_not_make_the_scout_reflood() -> void:
    var stubborn := StubbornMpm.new()
    var rig      := _rig(stubborn)
    var matter   := MatterLog.new()
    var by       := _surface() + 60
    _stone_block(rig.store, Vector3(CX, float(by), CZ))

    _emit_edit(Vector3(CX - 4, float(by) - 4, CZ - 4), Vector3(8, 8, 8))
    _drive(rig.scout, 400)

    assert_eq(stubborn.thaws, 1, "the floating block was detached once and not re-flooded")
    assert_eq(stubborn.active_count(), 0, "precondition: the thaw emptied nothing, so MPM stayed idle")
    var own := matter.events.filter(func(e: TerrainSdfChangedEvent) -> bool: return e.source == EditSource.Kind.SCOUT)
    assert_eq(own.size(), 1, "precondition: the thaw's rewrite was announced, credited to the scout")
    assert_true(own[0].flips.is_empty(), "precondition: and it flipped no cell")


# Provenance: test_mpm_structure's test_thaw_events_are_the_measured_flips. On the game's field
# at this spot, rewriting the thaw's box flips a cell outside its plan to air. The flood proved
# only the planned component detached, so that collateral cell's solid neighbours may have lost
# support: the scout seeds from exactly them, and never from the component it thawed.
func test_the_scouts_own_thaw_seeds_from_its_collateral_flips() -> void:
    var manager := EditStoreManager.new()
    manager.setup()
    var rig    := _wire(manager.store, MpmStructure.new())
    var matter := MatterLog.new()
    var top    := EditStore.terrain_surface(15.0, -16.0, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)

    var flood := GroundFlood.new()
    flood.state = GroundFlood.DETACHED
    for cell in VoxelUtils.cells_in_sphere(Vector3(15.5, top, -15.5), 1.4):
        if TerrainProbe.is_solid(manager.store, cell):
            flood.visited[cell] = true

    rig.scout._finish(flood)

    var collateral := matter.air.filter(func(c: Vector3i) -> bool: return not flood.visited.has(c))
    assert_eq(matter.sources(), [EditSource.Kind.SCOUT] as Array[EditSource.Kind], "precondition: one scout thaw")
    assert_false(collateral.is_empty(), "precondition: the thaw flipped a cell outside its plan to air")
    assert_eq(matter.solid.size(), 0, "precondition: it flipped nothing to solid")

    var expected := {}
    for cell: Vector3i in collateral:
        for n: Vector3i in GroundFlood.NEIGHBORS:
            var c: Vector3i = cell + n
            if not flood.visited.has(c) and TerrainProbe.is_solid(manager.store, c) \
                    and not TerrainProbe.is_bedrock(manager.store, c):
                expected[c] = true

    assert_false(expected.is_empty(), "precondition: the collateral cell had solid neighbours")
    assert_eq(_sorted(rig.scout._pending.keys()), _sorted(expected.keys()),
        "the scout seeds the collateral cells' solid neighbours, and nothing it thawed")


func _sorted(cells: Array) -> Array:
    var out := cells.duplicate()
    out.sort()
    return out


func _settle(ms: MpmStructure) -> void:
    for _i in 1500:
        ms.tick(1.0 / 60.0)
        if ms.active_count() == 0:
            return
    fail_test("the in-flight material never settled and froze")


# Robert's fence on a hill, as the systems stand: a beam rests on a pillar of ground; a Lower sinks
# the pillar's middle away, so the beam and the pillar's top are left hanging. The Lower's event
# carries its source and flips like any write, the scout floods from it, and the hanging piece is
# detached into MPM (it falls); its PartIndex record goes with the cells the thaw empties.
func test_terraforming_away_a_parts_support_detaches_it() -> void:
    var rig   := _rig()
    var es: EditStore    = rig.store
    var ms: MpmStructure = rig.mpm
    var index := PartIndex.new()
    var ctx   := ActionContext.new(es, null, null)
    var foot  := Vector3(CX + 0.5, float(_surface()), CZ + 0.5)
    CsgAction.new(CsgBoxShape.new(Vector3(1.6, 12.0, 1.6)), Transform3D(Basis(), foot + Vector3.UP * 4.0),
        CsgState.Op.ADD, &"Stone", ctx).execute()
    var beam := ConstructionAction.new(preload("res://assets/parts/beam/beam.tres"), foot + Vector3.UP * 10.0,
        Vector3.ZERO, &"Wood", ctx)
    assert_true(beam.validate(), "the beam rests on the pillar")
    beam.execute()
    _drive(rig.scout, 200)
    assert_eq(ms.active_count(), 0, "precondition: the beam is supported, nothing detaches")
    assert_eq(index.count(), 1, "precondition: the beam is recorded")

    var lower := LowerAction.new(foot + Vector3.UP * 5.0, 3.0, ctx)
    assert_true(lower.validate(), "the lower writes")
    lower.execute()
    assert_eq(index.count(), 1, "precondition: the lower cut the pillar, not the beam")
    _drive(rig.scout, 200)

    assert_gt(ms.active_count(), 0, "the hanging beam was detached and thawed into MPM")
    assert_eq(index.count(), 0, "and its record went with the cells the thaw emptied")
