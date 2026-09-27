class_name PartIndex
extends RefCounted

# Identity sidecar (manifesto #7): the voxel field carries only SDF + material; this index
# carries part identity — who placed what, its live cells, and ancestry — so queries like
# "every part derived from ancestor X" work without polluting the field. The mesher and the
# structural sim never see it. Built at imprint (PartPlacedEvent) and kept consistent as writes of
# any kind empty cells (the air flips of TerrainSdfChangedEvent, whoever made them). A later
# refinement uses _cell_to_part so a new part placed over an existing one keeps the older part's
# material on the cells it still owns.

var _records:      Dictionary[int, PartRecord] = {}
var _cell_to_part: Dictionary[Vector3i, int]   = {}
var _next_id:      int                          = 1


func _init() -> void:
    VoxelEventBusSingleton.subscribe(PartPlacedEvent.CHANNEL,        _on_part_placed)
    VoxelEventBusSingleton.subscribe(TerrainSdfChangedEvent.CHANNEL, _on_matter_changed)


# --- bus handlers ---

# A record lives exactly as long as it owns a cell, so a placement that made no cell solid (a
# part thinner than a cell, or one wholly inside existing solid) leaves none: with no cell to
# carve, nothing could ever release it.
func _on_part_placed(event: PartPlacedEvent) -> void:
    if event.cells.is_empty():
        return

    var id := _next_id
    _next_id += 1
    _records[id] = PartRecord.new(id, event.cells.duplicate(), event.material,
        event.dimensions, event.transform, event.ancestry)
    for cell in event.cells:
        _release_cell(cell)            # the newest part claims overlapped cells
        _cell_to_part[cell] = id

# An emptied cell leaves its part; a part with no cells left is gone.
func _on_matter_changed(event: TerrainSdfChangedEvent) -> void:
    for cell in event.flips.air:
        _release_cell(cell)


func _release_cell(cell: Vector3i) -> void:
    if not _cell_to_part.has(cell):
        return
    var owner_id: int = _cell_to_part[cell]
    _cell_to_part.erase(cell)
    var rec: PartRecord = _records.get(owner_id)
    if rec != null:
        rec.cells.erase(cell)
        if rec.cells.is_empty():
            _records.erase(owner_id)


# --- persistence ---

# The index as saved beside the world (WorldSnapshot): every record, and the next id to hand out so
# ids stay unique across a reload. Cell ownership isn't stored: each cell belongs to exactly one
# record, so it is rebuilt from the records.
func encode() -> Dictionary:
    var records: Array = []
    for id in _records:
        var rec := _records[id]
        records.append({
            "id":         rec.id,
            "cells":      rec.cells.duplicate(),
            "material":   String(rec.material),
            "dimensions": rec.dimensions,
            "transform":  rec.transform,
            "ancestry":   rec.ancestry,
        })
    return {"next_id": _next_id, "records": records}

# Why `data` isn't an index encode() could have written, or "" when it is. restore() trusts what
# this passes: a load that let two records claim one cell, or reissued a saved id, would quietly
# break the one-owner and unique-id invariants the rest of the index relies on.
static func refusal(data: Variant) -> String:
    if not (data is Dictionary and data.get("next_id") is int and data.get("records") is Array):
        return "part index is malformed"

    var ids   := {}
    var owned := {}
    for entry in data["records"]:
        if not (entry is Dictionary and entry.get("id") is int and entry.get("cells") is Array):
            return "part index has a malformed record"
        var id: int = entry["id"]
        if ids.has(id) or id < 1 or id >= data["next_id"]:
            return "part index reuses or pre-issues id %d" % id
        if entry["cells"].is_empty():
            return "part %d owns no cell" % id

        ids[id] = true
        for cell in entry["cells"]:
            if owned.has(cell):
                return "parts %d and %d both claim cell %s" % [owned[cell], id, cell]
            owned[cell] = id
    return ""

# Replaces the whole index with a saved one that refusal() passed.
func restore(data: Dictionary) -> void:
    _records.clear()
    _cell_to_part.clear()
    _next_id = data["next_id"]

    for entry: Dictionary in data["records"]:
        var cells: Array[Vector3i] = []
        cells.assign(entry["cells"])
        var rec := PartRecord.new(entry["id"], cells, StringName(entry["material"]),
            entry["dimensions"], entry["transform"], entry["ancestry"])
        _records[rec.id] = rec
        for cell in cells:
            _cell_to_part[cell] = rec.id


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
