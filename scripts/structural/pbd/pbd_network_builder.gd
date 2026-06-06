class_name PbdNetworkBuilder
extends RefCounted

# Derives a PbdNetwork from the tracked structural set (edited/suspended voxels +
# placed-part cells). One particle per tracked cell (cell-centre); members connect
# each cell to its tracked neighbours in the 26-neighbourhood (face + edge + body
# diagonals) so the lattice is cross-braced and rigid until members break. A cell
# face-adjacent to NATURAL terrain (solid but not in the tracked set) is a pinned
# anchor — that covers both "held from below" (ground) and "pulled from above"
# (a cell hanging off overhead terrain), so suspension is emergent.
#
# Pure: takes the tracked set + an is_natural_terrain predicate, returns the network
# plus node↔cell maps. No scene/terrain access here, so it's headless-testable.
# Node mass = material density; each member takes the WEAKEST LINK of its two
# endpoints (min limits, softest compliance, shortest fatigue τ).

# A neutral Materials carries the @export defaults (density 1, tension/compression
# 200, compliance 1e-7, fatigue 1.25s) — the substitute when a cell has no material
# (only in headless tests; real cells always carry one).
static var _FALLBACK: Materials = Materials.new()

static func _mat(m: Materials) -> Materials:
    return m if m != null else _FALLBACK

const FACE6 := [
    Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
    Vector3i(0, 1, 0), Vector3i(0, -1, 0),
    Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


# cells: Dictionary[Vector3i, Materials] (material may be null for now).
# is_natural_terrain: Callable(Vector3i) -> bool.
# Returns { sim: PbdSim, node_of_cell: Dictionary, cell_of_node: Array[Vector3i] }.
static func build(cells: Dictionary, is_natural_terrain: Callable, cell_size := 1.0) -> Dictionary:
    var sim := PbdSim.new()
    var node_of_cell := {}
    var cell_of_node: Array[Vector3i] = []

    for cell in cells:
        var pinned := _anchored(cell, is_natural_terrain)
        var mass := 0.0 if pinned else _mat(cells[cell]).density
        var world := (Vector3(cell) + Vector3.ONE * 0.5) * cell_size
        node_of_cell[cell] = sim.add_node(world, mass)
        cell_of_node.append(cell)

    for cell in cells:
        var a: int = node_of_cell[cell]
        var ma := _mat(cells[cell])
        for dz in [-1, 0, 1]:
            for dy in [-1, 0, 1]:
                for dx in [-1, 0, 1]:
                    if dx == 0 and dy == 0 and dz == 0:
                        continue
                    var nb: Vector3i = cell + Vector3i(dx, dy, dz)
                    if not node_of_cell.has(nb):
                        continue
                    var b: int = node_of_cell[nb]
                    if a >= b:
                        continue   # each unordered pair once
                    var mb := _mat(cells[nb])
                    sim.add_member(a, b,
                        maxf(ma.compliance,      mb.compliance),       # softest gives
                        minf(ma.tension,         mb.tension),          # weakest link
                        minf(ma.compression,     mb.compression),
                        minf(ma.fatigue_seconds, mb.fatigue_seconds))  # most brittle

    return { "sim": sim, "node_of_cell": node_of_cell, "cell_of_node": cell_of_node }


static func _anchored(cell: Vector3i, is_natural_terrain: Callable) -> bool:
    for off in FACE6:
        if is_natural_terrain.call(cell + off):
            return true
    return false
