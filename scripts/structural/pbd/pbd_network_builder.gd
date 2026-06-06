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
# Per-material strength/mass is a Phase-7 concern; defaults for now.

const DEFAULT_MASS       := 1.0
const DEFAULT_COMPLIANCE := 1.0e-7      # near-rigid
const DEFAULT_TENSION    := 200.0       # axial force limit
const DEFAULT_COMPRESSION := 200.0

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
        var mass := 0.0 if pinned else DEFAULT_MASS
        var world := (Vector3(cell) + Vector3.ONE * 0.5) * cell_size
        node_of_cell[cell] = sim.add_node(world, mass)
        cell_of_node.append(cell)

    for cell in cells:
        var a: int = node_of_cell[cell]
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
                    sim.add_member(a, b, DEFAULT_COMPLIANCE, DEFAULT_TENSION, DEFAULT_COMPRESSION)

    return { "sim": sim, "node_of_cell": node_of_cell, "cell_of_node": cell_of_node }


static func _anchored(cell: Vector3i, is_natural_terrain: Callable) -> bool:
    for off in FACE6:
        if is_natural_terrain.call(cell + off):
            return true
    return false
