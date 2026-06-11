class_name PartIndex
extends RefCounted

# Identity sidecar (manifesto #7): the voxel field carries only SDF + material; this index
# carries part identity — who placed what, its live cells, and ancestry — so queries like
# "every part derived from ancestor X" work without polluting the field. The mesher and PBD
# never see it. Built at imprint (PartPlacedEvent) and kept consistent as cells are carved
# (VoxelRemovedEvent). A later refinement uses _cell_to_part so a new part placed over an
# existing one keeps the older part's material on the cells it still owns.

var _records:      Dictionary[int, PartRecord] = {}
var _cell_to_part: Dictionary[Vector3i, int]   = {}
var _next_id:      int                          = 1


func _init() -> void:
    VoxelEventBusSingleton.subscribe(PartPlacedEvent.CHANNEL,   _on_part_placed)
    VoxelEventBusSingleton.subscribe(VoxelRemovedEvent.CHANNEL, _on_voxel_removed)


# --- bus handlers ---

func _on_part_placed(event: PartPlacedEvent) -> void:
    var id := _next_id
    _next_id += 1
    _records[id] = PartRecord.new(id, event.cells.duplicate(), event.material,
        event.dimensions, event.transform, event.ancestry)
    for cell in event.cells:
        _release_cell(cell)            # the newest part claims overlapped cells
        _cell_to_part[cell] = id

# A carved cell leaves its part; a part with no cells left is gone.
func _on_voxel_removed(event: VoxelRemovedEvent) -> void:
    _release_cell(event.pos)


func _release_cell(cell: Vector3i) -> void:
    if not _cell_to_part.has(cell):
        return
    var owner_id: int = _cell_to_part[cell]
    _cell_to_part.erase(cell)
    var record: PartRecord = _records.get(owner_id)
    if record != null:
        record.cells.erase(cell)
        if record.cells.is_empty():
            _records.erase(owner_id)


# --- queries ---

func count() -> int:
    return _records.size()

func part_at(cell: Vector3i) -> int:
    return _cell_to_part.get(cell, -1)

func record(id: int) -> PartRecord:
    return _records.get(id)

# Every part id whose ancestry chain passes through `ancestor_id` (inclusive of direct
# children). Ancestry is always -1 until the derive-from feature is built, so this returns
# empty today — the plumbing is here for when it lands.
func descendants_of(ancestor_id: int) -> Array[int]:
    var out: Array[int] = []
    for id in _records:
        if _records[id].ancestry == ancestor_id:
            out.append(id)
    return out
