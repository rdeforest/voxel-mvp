class_name DigAction
extends Action

# Not a PlayerSafeAction on purpose: players expect to dig under themselves, and directives will
# replace this verb (docs/bugs/closed/dig-action-no-validate-no-safety.md).

enum Shape { SPHERE }

var position:  Vector3
var radius:    float
var shape:     int  # Shape enum

var store:     EditStore

var _stamp_cache: SdfLattice = null


func _init(
    p_position: Vector3,
    p_radius:   float,
    p_ctx:      ActionContext,
    p_shape:    int = Shape.SPHERE,
) -> void:
    position = p_position
    radius   = p_radius
    shape    = p_shape
    store    = p_ctx.store
    source   = p_ctx.source


func to_step() -> Dictionary:
    return {
        "position": StepFields.encode_vec3(position),
        "radius":   radius,
        "shape":    StepFields.enum_name(Shape, shape),
    }

static func from_step(f: StepFields, ctx: ActionContext) -> Action:
    return DigAction.new(f.vec3("position"), f.number("radius"), ctx, f.enum_value("shape", Shape))


func validate() -> bool:
    if store == null:
        return false
    return not _stamp().flips(store).is_empty()   # a carve that flips no cell: the ghost's refusal

func preview() -> ActionPreview:
    var p := ActionPreview.new()
    if store == null:
        p.refused = true
        return p
    _stamp().flips(store).add_to(p)
    p.refused = p.is_empty()
    return p

func execute() -> void:
    if store == null:
        push_error("DigAction.execute(): no store")
        return

    # Write the very field the preview read; the event carries the cells whose sample point the
    # write actually flipped, measured across it. A carve repaints nothing.
    var lattice := _stamp()
    var flips   := lattice.write(store, lattice.materials(store, -1, true))

    # Box one cell wider than the dig sphere so the boundary-cell scan in
    # TerrainSupport sees newly-exposed neighbours just outside the sphere.
    var scan := AABB(position - Vector3.ONE * (radius + 1.0), Vector3.ONE * ((radius + 1.0) * 2.0))
    TerrainSdfChangedEvent.announce(source, scan, flips)


# The field execute() writes — validate, preview and events all read this brush. Stamped once, so
# the cache is a snapshot of the store: safe only because every caller builds a fresh action and
# runs validate/preview/execute with no other write in between (player.gd, the preview renderer).
func _stamp() -> SdfLattice:
    if _stamp_cache == null:
        _stamp_cache = SdfLattice.sphere_stamp(store, position, radius,
            VoxelConstants.STORE_OP_SUBTRACT, VoxelConstants.RENDER_BASE_CELL)
    return _stamp_cache
