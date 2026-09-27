extends GutTest

# DetachmentScout: the loss-of-support trigger. On a terrain edit it floods the exposed solid
# toward bedrock; a detached component is thawed into MPM. Two cases: a floating block (no ground
# beneath) gets thawed; grounded terrain is left alone. Also pins the cascade guard, by the source
# each event carries: the scout seeds from its own thaw only where that thaw flipped cells outside
# the component it thawed, ignores MPM's freezes (flips and all), and resolves an edit made while
# material is in flight only once it has settled.

const MatterLog := preload("res://test/support/matter_log.gd")
const Scenario  := preload("res://test/support/scenario.gd")


const RefusingMpm := preload("res://test/support/refusing_mpm.gd")

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
    return {"store": es, "mpm": ms, "scout": scout, "integrity": si}


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


# (Drafted by Claude, overnight 2026-09-27.) Pending seeds aren't saved, so a save (or a recording's
# start) taken while the scout still has an edit to resolve would drop a detachment for good: the
# gate waits for the scout as it waits for support and MPM.
func test_the_save_gate_waits_for_the_scouts_pending_work() -> void:
    var rig := _rig()
    var si: StructuralIntegrity = rig.integrity
    var top := _surface()
    _emit_edit(Vector3(CX - 4, float(top) - 8, CZ - 4), Vector3(8, 8, 8))
    assert_true(si.force_quiescent(), "precondition: support settles")
    assert_false(rig.scout._pending.is_empty(), "precondition: the edit left seeds to resolve")

    assert_false(si.is_quiescent(), "not quiescent while the scout has seeds pending")
    _drive(rig.scout, 1)
    assert_not_null(rig.scout._flood, "precondition: a flood is now in flight")
    assert_false(si.is_quiescent(), "nor while its flood is in flight")

    _drive(rig.scout, 400)
    assert_true(si.force_quiescent(), "support settles")
    assert_eq(rig.mpm.active_count(), 0, "precondition: grounded terrain, nothing detached")
    assert_true(si.is_quiescent(), "quiescent once the scout has resolved everything")


# (Drafted by Claude, overnight 2026-09-27.) A seed no flood will ever visit, because its cell went
# air before the scout reached it, must still leave the queue, or it would hold the save gate shut.
func test_a_seed_that_went_air_does_not_hold_the_gate() -> void:
    var rig := _rig()
    var sky := Vector3i(int(CX), _surface() + 60, int(CZ))
    assert_false(TerrainProbe.is_solid(rig.store, sky), "precondition: the seed cell is air")
    rig.scout._pending[sky] = true

    _drive(rig.scout, 1)
    assert_true(rig.scout.is_idle(), "the air seed is dropped without a flood")


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


# A detachment whose thaw is refused leaves the piece in place, still detached. The scout must not
# re-flood it and ask again every frame: the refused thaw writes and announces nothing, and the flood
# that found the piece consumed its seeds. (The B4 loop, 7e6c225, was the same shape with a thaw
# that emptied nothing but still announced its rewrite.)
func test_a_refused_thaw_is_not_retried() -> void:
    var refusing = RefusingMpm.new()
    var rig      := _rig(refusing)
    var matter   := MatterLog.new()
    var by       := _surface() + 60
    _stone_block(rig.store, Vector3(CX, float(by), CZ))

    _emit_edit(Vector3(CX - 4, float(by) - 4, CZ - 4), Vector3(8, 8, 8))
    _drive(rig.scout, 400)

    assert_eq(refusing.solves, 1, "the floating block was detached once and not re-flooded")
    assert_push_error("refused", "the refusal is logged")
    assert_true(rig.scout.is_idle(), "the scout has nothing left to resolve")
    assert_eq(rig.scout._thawing, {}, "the refused thaw's component isn't held as its collateral filter")
    assert_eq(refusing.active_count(), 0, "nothing entered the sim")
    assert_eq(matter.events.filter(func(e: TerrainSdfChangedEvent) -> bool: return e.source == EditSource.Kind.SCOUT),
        [], "nothing was announced for the refused thaw")
    assert_true(TerrainProbe.is_solid(rig.store, Vector3i(int(CX), by, int(CZ))), "the block is still there")


# Provenance: the since-closed bug mpm-thaw-carve-leaves-planned-cells. At this spot (test_mpm_structure pins
# it), re-encoding the thaw's box alone flips a cell outside its plan to air: collateral the scout
# had to re-check under the corner carve. The solved carve keeps every unplanned cell on its side, so the scout's own thaw leaves
# nothing to seed.
func test_the_scouts_own_thaw_leaves_no_collateral_at_a_stray_flip_spot() -> void:
    var manager := EditStoreManager.new()
    manager.setup()
    var rig    := _wire(manager.store, MpmStructure.new())
    var matter := MatterLog.new()
    var flood  := _detached_ball(manager.store)

    rig.scout._finish(flood)

    assert_eq(matter.sources(), [EditSource.Kind.SCOUT] as Array[EditSource.Kind], "precondition: one scout thaw")
    assert_eq(_sorted(matter.air), _sorted(flood.visited.keys()), "it emptied exactly the component")
    assert_eq(matter.solid.size(), 0, "and flipped nothing to solid")
    assert_true(rig.scout._pending.is_empty(), "so there is no collateral to seed")


# The seeding itself, for a SCOUT thaw whose measured flips do reach outside the component (the solve
# is read back within float32 rounding where finer leaves sit in the box): the collateral cells' solid
# neighbours are seeded, and nothing in the component.
func test_the_scout_seeds_from_its_own_thaws_collateral_flips() -> void:
    var manager := EditStoreManager.new()
    manager.setup()
    var rig   := _wire(manager.store, MpmStructure.new())
    var flood := _detached_ball(manager.store)
    var inside: Vector3i = flood.visited.keys()[0]
    var outside := inside + Vector3i(0, -3, 0)
    assert_false(flood.visited.has(outside), "precondition: the collateral cell is outside the component")

    var flips := CellFlips.new()
    flips.air = [inside, outside] as Array[Vector3i]
    rig.scout._thawing = flood.visited
    TerrainSdfChangedEvent.announce(EditSource.Kind.SCOUT, AABB(Vector3(inside), Vector3.ONE * 4.0), flips)
    rig.scout._thawing = {}

    var expected := {}
    for n: Vector3i in GroundFlood.NEIGHBORS:
        var c: Vector3i = outside + n
        if not flood.visited.has(c) and TerrainProbe.is_solid(manager.store, c) \
                and not TerrainProbe.is_bedrock(manager.store, c):
            expected[c] = true

    assert_false(expected.is_empty(), "precondition: the collateral cell has solid neighbours")
    assert_eq(_sorted(rig.scout._pending.keys()), _sorted(expected.keys()),
        "the scout seeds the collateral cell's solid neighbours, and nothing it thawed")


# (Drafted by Claude, overnight 2026-09-27.) A freeze is ignored even when it carries measured
# flips, both a cell it emptied and one it made solid (https://github.com/rdeforest/voxel-mvp/issues/20).
func test_a_freezes_flips_seed_nothing() -> void:
    var rig     := _rig()
    var top     := _surface()
    var emptied := Vector3i(int(CX), top - 6, int(CZ))
    var made    := emptied + Vector3i(4, 0, 0)
    var flips   := CellFlips.new()
    flips.air   = [emptied] as Array[Vector3i]
    flips.solid = [made] as Array[Vector3i]
    assert_true(TerrainProbe.is_solid(rig.store, made), "precondition: the made cell reads solid")

    TerrainSdfChangedEvent.announce(EditSource.Kind.MPM, AABB(Vector3(emptied) - Vector3.ONE * 8.0, Vector3.ONE * 16.0), flips)

    assert_true(rig.scout._pending.is_empty(), "the freeze seeds nothing")


# (Drafted by Claude, overnight 2026-09-27.) The loop seeding from freezes would start: a 1 m post on
# the cell grid reads air at every cell centre (SDF 0 is not solid), but the collider holds particles
# on it. A voxel dropped on it is thawed once, falls, and freezes on the post; a scout that flooded
# that pile would find it DETACHED and thaw it again, once per cell down the post.
func test_a_pile_frozen_on_a_post_the_flood_cannot_see_is_not_thawed_again() -> void:
    var s   := Scenario.new()
    var top := _surface()
    add_child(s)
    assert_true(s.start_fresh(), "precondition: the scenario started")
    s.player_at(Vector3(4000.5, 400.0, 4000.5))
    s.csg(CsgBoxShape.new(Vector3(1, 12, 1)), Transform3D(Basis(), Vector3(CX + 0.5, top + 2.0, CZ + 0.5)),
        CsgState.Op.ADD, &"Stone")
    s.settle()
    assert_false(TerrainProbe.is_solid(s.edit_store_ref(), Vector3i(int(CX), top + 6, int(CZ))),
        "precondition: the post's cells read air")
    var matter := MatterLog.new()

    s.fill_voxel(Vector3i(int(CX), top + 14, int(CZ)), &"Wood")
    s.settle()

    assert_eq(s.error, "", "the world came to rest")
    assert_eq(matter.sources().count(EditSource.Kind.MPM), 1, "the voxel froze once")
    assert_eq(matter.sources().count(EditSource.Kind.SCOUT), 1, "and was thawed once")
    s.free()


func _detached_ball(store: EditStore) -> GroundFlood:
    var top := EditStore.terrain_surface(-20.0, 14.0, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)
    var flood := GroundFlood.new()
    flood.state = GroundFlood.DETACHED
    for cell in VoxelUtils.cells_in_sphere(Vector3(-19.5, top, 14.5), 1.4):
        if TerrainProbe.is_solid(store, cell):
            flood.visited[cell] = true
    return flood


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
