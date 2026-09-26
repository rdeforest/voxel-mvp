extends RefCounted

# Only the player-safety test is asked (endangered_by of make_dig's brush), not DigAction.validate,
# so the reach is not mixed with the empty-carve refusal. Reports the edge of the contiguous
# endangered run from the feet and the farthest endangered step, which differ if the run has gaps.

const COLUMNS: Array[Vector2] = [Vector2(100, 100), Vector2(300, -200), Vector2(-150, 420)]
const STEPS                   := 80
const STEP                    := 0.1


static func _surface(x: float, z: float) -> float:
    return EditStore.terrain_surface(x, z, EditStoreManager.BASE, EditStoreManager.AMP,
        EditStoreManager.PERIOD, EditStoreManager.OCTAVES, EditStoreManager.SEED)


static func _endangers(guard: PlayerSafeAction, store: EditStore, hit: Vector3) -> bool:
    var brush := SdfLattice.sphere_stamp(store, hit - Vector3.UP * 1.5, 3.0,
        VoxelConstants.STORE_OP_SUBTRACT, VoxelConstants.RENDER_BASE_CELL)
    return guard.endangered_by(brush, store)


static func run(root: Node) -> void:
    var manager := EditStoreManager.new()
    manager.setup()
    var body := CharacterBody3D.new()
    root.add_child(body)
    var guard := PlayerSafeAction.new()
    guard.player = body

    for col in COLUMNS:
        body.global_position = Vector3(col.x + 0.5, _surface(col.x + 0.5, col.y + 0.5) + 1.5, col.y + 0.5)
        var run_edge := -1.0
        var farthest := -1.0
        var in_run   := true

        for i in STEPS:
            var hit := Vector3(col.x + 0.5 + float(i) * STEP, 0.0, col.y + 0.5)
            hit.y = _surface(hit.x, hit.z)
            var endangered := _endangers(guard, manager.store, hit)
            if endangered:
                farthest = float(i) * STEP
            in_run = in_run and endangered
            if in_run:
                run_edge = float(i) * STEP

        print("column %s: endangered run to %.1f m, farthest endangered %.1f m" % [col, run_edge, farthest])
