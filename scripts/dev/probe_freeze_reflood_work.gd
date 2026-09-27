extends RefCounted

# Each case: build the edit that starts a fall, then run frame by frame until the world is at rest
# or FRAME_CAP passes. A loop shows as scout thaws that keep coming (and no rest).

const Scenario  := preload("res://test/support/scenario.gd")
const MatterLog := preload("res://test/support/matter_log.gd")

const FRAME_CAP := 20000
const FAR       := Vector3(4000.5, 400.0, 4000.5)   # the player, out of every edit's way
const VERDICTS  := {GroundFlood.GROUNDED: "grounded", GroundFlood.DETACHED: "detached", GroundFlood.OVERFLOW: "overflow"}


static func run(root: Node) -> void:
    _case(root, "fence beam falls", func(s: Scenario) -> void:
        var foot := Vector3(100.5, -45.0, 100.5)
        s.csg(CsgBoxShape.new(Vector3(1.6, 12.0, 1.6)), Transform3D(Basis(), foot + Vector3.UP * 4.0),
            CsgState.Op.ADD, &"Stone")
        s.build(preload("res://assets/parts/beam/beam.tres"), foot + Vector3.UP * 10.0, Vector3.ZERO, &"Wood")
        s.settle()
        s.lower(foot + Vector3.UP * 5.0, 3.0))

    for at in [Vector2(100.5, 100.5), Vector2(0.5, 0.5), Vector2(-40.5, 60.5), Vector2(150.5, -80.5)]:
        _case(root, "voxel dropped at %s" % at, func(s: Scenario) -> void:
            s.fill_voxel(Vector3i(int(at.x), _top(at) + 12, int(at.y)), &"Wood"))
        _case(root, "r1.5 ball dropped at %s" % at, func(s: Scenario) -> void:
            s.fill(Vector3(at.x, float(_top(at)) + 10.0, at.y), 1.5, &"Stone"))
        _case(root, "r3 thaw at %s" % at, func(s: Scenario) -> void:
            s.thaw(Vector3(at.x, float(_top(at)) - 3.0, at.y), 3.0))


    _case(root, "six balls stacked at (100.5, 100.5)", func(s: Scenario) -> void:
        for i in 6:
            s.fill(Vector3(100.5 + 0.3 * i, float(_top(Vector2(100.5, 100.5))) + 10.0, 100.5), 1.2, &"Stone")
            s.settle())

    # A 1 m post on the cell grid: its cell centres sample SDF 0, which is not solid, yet the collider
    # holds particles on it. A pile frozen on top floods as DETACHED.
    _case(root, "voxel dropped on a 1 m grid post", func(s: Scenario) -> void:
        var t := _top(Vector2(100.5, 100.5))

        s.csg(CsgBoxShape.new(Vector3(1, 12, 1)), Transform3D(Basis(), Vector3(100.5, t + 2.0, 100.5)),
            CsgState.Op.ADD, &"Stone")
        s.settle()
        s.fill_voxel(Vector3i(100, t + 14, 100), &"Wood"))

    _case(root, "16 voxels scattered over slopes", func(s: Scenario) -> void:
        for i in 16:
            var at := Vector2(-150.5 + 20.0 * (i % 4), -150.5 + 20.0 * (i / 4))
            s.fill_voxel(Vector3i(int(at.x), _top(at) + 6, int(at.y)), &"Wood"))


static func _top(at: Vector2) -> int:
    return int(EditStore.terrain_surface(at.x, at.y, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED))


static func _case(root: Node, label: String, start: Callable) -> void:
    var s := Scenario.new()
    root.add_child(s)
    s.start_fresh()
    s.player_at(FAR)
    var log := MatterLog.new()
    start.call(s)

    var tally := {"floods": 0, "freezes": 0, "scout_thaws": 0}
    var prev: GroundFlood = null
    var rest := -1
    for f in FRAME_CAP:
        s._tick()
        var now: GroundFlood = s.scout._flood
        if now != prev:
            if now != null:
                tally.floods += 1
            if prev != null:
                var verdict: String = VERDICTS.get(prev.state, "running")
                tally[verdict] = tally.get(verdict, 0) + 1
            prev = now
        if s.integrity.is_quiescent():
            rest = f
            break

    for e in log.events:
        if e.source == EditSource.Kind.MPM:
            tally.freezes += 1
        elif e.source == EditSource.Kind.SCOUT:
            tally.scout_thaws += 1
    print("%-32s rest at %6d  %s  error '%s'" % [label, rest, tally, s.error])
    s.free()
