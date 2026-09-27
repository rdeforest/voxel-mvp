class_name TerrainSdfChangedEvent
extends VoxelEvent

# The matter-changed event: the one event every write to the store emits, once per write. It says
# who wrote (source), which box was rewritten (the re-mesh / re-scan region), and which cells the
# write flipped between solid and air, measured across it (flips). The name predates matter as the
# umbrella term; scripts/dc subscribes to it by name, so the rename waits for that code's owner.
#
# The dispatch footprint is every cell of the box, not just the flipped ones, so a per-cell
# subscriber (something resting on the ground) hears a change that moved the surface under it
# without flipping a cell. docs/roadmap/design/04-event-bus.md.

const CHANNEL := &"terrain_sdf_changed"

var source:     EditSource.Kind
var box_origin: Vector3
var box_size:   Vector3
var flips:      CellFlips


func _init(p_grid_id: int, p_source: EditSource.Kind, p_box: AABB, p_flips: CellFlips) -> void:
    grid_id    = p_grid_id
    source     = p_source
    box_origin = p_box.position
    box_size   = p_box.size
    flips      = p_flips
    VoxelUtils.for_each_in_bounding_box(box_origin, box_size, func(pos: Vector3i) -> void:
        cells.append(pos))


static func announce(p_source: EditSource.Kind, p_box: AABB, p_flips: CellFlips) -> void:
    VoxelEventBusSingleton.emit(CHANNEL,
        TerrainSdfChangedEvent.new(VoxelConstants.GRID_ID, p_source, p_box, p_flips))
