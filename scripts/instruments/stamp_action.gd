class_name StampAction
extends CsgAction

# Instrument (doc 22, the instrument layer): a CSG primitive stamped by typed numbers. The same
# write as the CSG tool's (VoxelImprint, with its body freeze), without the player-safety refusal;
# InstrumentCommands rescues the player instead (danger_of on written_field()). Its step has the
# csg step's fields under its own op, so a replay knows it bypassed safety.

# Past this many metres on any axis of the stamp's lattice box the write is refused: its lattice
# is dim^3 floats plus a byte each, twice over (prediction, then write), and 256 m is ~0.3 GB.
const MAX_SPAN := 256.0


static func from_step(f: StepFields, ctx: ActionContext) -> Action:
    var csg: CsgAction = CsgAction.from_step(f, ctx)
    return StampAction.new(csg.shape, csg.xform, csg.op, csg.material_name, ctx)


# Why the stamp won't run; "" when it will.
func refusal() -> String:
    if store == null:
        return "no store"
    if shape == null:
        return "no shape"
    for d in shape.sdf_dims():
        if not (is_finite(d) and d > 0.0):
            return "dimensions must be positive numbers, got %s" % shape.sdf_dims()
    if not (xform.basis.is_finite() and xform.origin.is_finite()):
        return "position and rotation must be finite numbers"
    var span := _world_box().size
    if span[span.max_axis_index()] > MAX_SPAN:
        return "the stamp spans %s m; %d m per axis is the most one write takes" % [span, int(MAX_SPAN)]
    if not MaterialPalette.NAMES.has(material_name):
        return "\"%s\" is not a material" % material_name
    _ensure_work()
    if not _writes:
        return "the stamp changes nothing"
    return ""


func validate() -> bool:
    return refusal() == ""


# The field execute() writes, built against the store before it runs.
func written_field() -> SdfLattice:
    _ensure_work()
    return _lattice
