class_name EditStoreManager
extends RefCounted

# Dual-write shadow of player edits into the EditStore (design 11, S2). godot_voxel stays
# authoritative; on each terrain edit we re-read the edited box from it (LOD0) and write
# that final SDF + material into our EditStore, building the persistent store up against
# the live edits. S3 flips render/collision to read edits from here instead; S5 drops
# godot_voxel and the actions write here directly.

# A generous world-fixed root the edits live in. Generator params mirror
# tools/build_terrain_graph.gd / TerrainField's terrain_defaults (kept in sync until the
# .tres graph retires with godot_voxel — see [[terrain-generation-in-cpp]]).
const ROOT_ORIGIN := Vector3(-8192, -8192, -8192)
const ROOT_SIZE   := 16384.0
const MARGIN      := 2          # cells of slack around the edit box

const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337

var store: EditStore

var _terrain: VoxelLodTerrain
var _reader:  DCRegionReader


func setup(terrain: VoxelLodTerrain) -> void:
    _terrain = terrain
    _reader = DCRegionReader.new()
    store = EditStore.new()
    store.setup(ROOT_ORIGIN, ROOT_SIZE, BASE, AMP, PERIOD, OCTAVES, SEED)
    VoxelEventBusSingleton.subscribe(TerrainSdfChangedEvent.CHANNEL, _on_edit)


# Re-read the edited box from godot_voxel (LOD0, final SDF + material) and shadow it into
# the store. A cubic box (DCRegionReader wants a size) covering the edit plus a margin.
func _on_edit(event: TerrainSdfChangedEvent) -> void:
    var lo := Vector3i(event.box_origin.floor()) - Vector3i.ONE * MARGIN
    var hi := Vector3i((event.box_origin + event.box_size).ceil()) + Vector3i.ONE * MARGIN
    var span := maxi(hi.x - lo.x, maxi(hi.y - lo.y, hi.z - lo.z))
    var size_v := Vector3i.ONE * span
    var sdf := _reader.read_sdf_lod0(_terrain, lo, size_v)
    if sdf.size() != span * span * span:
        return   # region not streamed yet — best-effort shadow, skip this one
    var idx := _reader.read_indices_lod(_terrain, 0, lo, size_v)
    store.write_region(sdf, idx, span, Vector3(lo), 1.0)
