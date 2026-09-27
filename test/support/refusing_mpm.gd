extends MpmStructure

# An MpmStructure whose carve solve refuses every plan, as EditStore.predict_carve does when no field
# empties the plan and keeps every other cell on its side. No plan a thaw makes on the game's field
# has been found that the real solve refuses (docs/roadmap/design/12-mpm-structural-substrate.md,
# "The thaw carve"), so the refusal path is reached by standing one in. Counts the solves asked for.
# (Drafted by Claude, overnight 2026-09-27.)

var solves := 0


func _solve_carve(planned: Array[Vector3i]) -> Dictionary:
    solves += 1
    return {"conflict": planned.slice(0, 2), "proven": true, "pinned": false, "margin": 4, "sweeps": 256}
