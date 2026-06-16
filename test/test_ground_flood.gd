extends GutTest

# GroundFlood: the connectivity test behind the detachment trigger. A solid column that reaches
# Bedrock floods GROUNDED (and cheaply — it dives straight down); a floating block with no bedrock
# beneath drains DETACHED; an over-cap component reports OVERFLOW.

const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337
const CX := 100.0
const CZ := 100.0


func _store() -> EditStore:
    var s0 := EditStore.terrain_surface(CX, CZ, BASE, AMP, PERIOD, OCTAVES, SEED)
    var es := EditStore.new()
    es.setup(Vector3(CX - 256.0, s0 - 256.0, CZ - 256.0), 512.0, BASE, AMP, PERIOD, OCTAVES, SEED)
    return es

func _surface() -> int:
    return int(EditStore.terrain_surface(CX, CZ, BASE, AMP, PERIOD, OCTAVES, SEED))


func _run(flood: GroundFlood) -> int:
    for _i in 100000:
        if flood.step(500) != GroundFlood.RUNNING:
            break
    return flood.state


func test_ground_terrain_floods_grounded() -> void:
    # A seed_cell in the solid mountain, a few metres down, must reach Bedrock (deep) -> GROUNDED.
    var es := _store()
    var top := _surface()
    var seed_cell := Vector3i(int(CX), top - 4, int(CZ))
    var flood := GroundFlood.new()
    flood.start([seed_cell], es, 5000)
    assert_eq(_run(flood), GroundFlood.GROUNDED, "solid terrain reaches bedrock and is grounded")


func test_floating_block_floods_detached() -> void:
    # A solid block stamped high in the air (no bedrock anywhere beneath within itself) drains
    # without reaching ground -> DETACHED.
    var es := _store()
    var top := _surface()
    var by := top + 60   # well above the surface, in air
    es.stamp_box(Vector3(CX, float(by), CZ), Vector3(5, 5, 5), 0, MaterialPalette.index_of(&"Stone"), 1.0)
    var seed_cell := Vector3i(int(CX), by, int(CZ))
    assert_lt(es.sample(Vector3(seed_cell) + Vector3(0.5, 0.5, 0.5)), 0.0, "the floating block seed_cell is solid")
    var flood := GroundFlood.new()
    flood.start([seed_cell], es, 5000)
    assert_eq(_run(flood), GroundFlood.DETACHED, "a floating block has no ground beneath -> detached")
    assert_gt(flood.visited.size(), 50, "it flooded the whole block (~4^3 solid cells) before draining")


func test_oversize_component_reports_overflow() -> void:
    # The same grounded mountain, but with a tiny cap, must report OVERFLOW before it finds bedrock
    # (the cap guards against free-falling an enormous chunk).
    var es := _store()
    var top := _surface()
    var seed_cell := Vector3i(int(CX), top - 4, int(CZ))
    var flood := GroundFlood.new()
    flood.start([seed_cell], es, 3)   # cap of 3 cells — overflow before the ~50 m dive completes
    assert_eq(_run(flood), GroundFlood.OVERFLOW, "an over-cap flood reports OVERFLOW")
