class_name StepRegistry

# The step vocabulary: which op name stands for which Action class. A step is
# {"op": <name>} plus the action's to_step() fields; rebuilding one calls that class's
# from_step() with an ActionContext, so the replay's context (its store, player stand-in and
# source) is the rebuilt action's. docs/roadmap/design/22-scenario-languages.md, Format 2.


static func ops() -> Dictionary:
    return {
        "dig":         DigAction,
        "fill":        FillAction,
        "flatten":     FlattenAction,
        "raise":       RaiseAction,
        "lower":       LowerAction,
        "fill_voxel":  FillVoxelAction,
        "empty_voxel": EmptyVoxelAction,
        "csg":         CsgAction,
        "build":       ConstructionAction,
        "probe":       ProbeAction,
    }


# The step for `action`; {} (and an error) for an action class with no op.
static func step_of(action: Action) -> Dictionary:
    var op: Variant = ops().find_key(action.get_script())
    if op == null:
        push_error("StepRegistry: %s has no step op" % action.get_script().get_global_name())
        return {}
    var step := action.to_step()
    step["op"] = op
    return step


# The action `fields`' step describes, built in `ctx`; null, with fields.error saying why, if the
# step names no op, lacks or mistypes a field, has one the op doesn't, or no longer matches
# what it recorded (a part file whose size changed).
static func action_of(fields: StepFields, ctx: ActionContext) -> Action:
    var op     := fields.text("op")
    var op_cls: Variant = ops().get(op)
    if op_cls == null:
        fields.fail("op: \"%s\" is not one of %s" % [op, ops().keys()])
        return null
    var action: Action = op_cls.from_step(fields, ctx)
    fields.check_all_read()
    return action if fields.error == "" else null
