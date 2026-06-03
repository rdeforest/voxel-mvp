class_name SdfField
extends RefCounted

# Pluggable field source for the DC meshers, chosen per run. `value` is the
# signed distance at a world point; `gradient` is the (unit) surface normal
# there. SdfAnalytic calls an SDF directly (exact gradients); SdfBaked reads
# pre-sampled grid data (finite-diff gradients), mirroring the engine's stored-
# scalar path. Meshers depend only on this interface.

func value(_p: Vector3) -> float:
    push_error("SdfField.value() not implemented")
    return 0.0

func gradient(_p: Vector3) -> Vector3:
    push_error("SdfField.gradient() not implemented")
    return Vector3.UP
