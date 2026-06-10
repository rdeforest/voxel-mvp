class_name EditStoreManager
extends RefCounted

# Owns the authoritative EditStore and its on-disk persistence (design 11). The store is the
# sparse SDF+material layer that holds the player's edits over the procedural TerrainField;
# actions write it directly (StoreWrite / stamp_sphere), render + collision sample it.
#
# Persistence (S4): save_to/load_from blob the sparse edited tree to disk, versioned like
# WorldSnapshot. Replaces godot_voxel's SQLite stream.

# A generous world-fixed root the edits live in. Generator params mirror TerrainField's
# terrain_defaults ([[terrain-generation-in-cpp]]).
const ROOT_ORIGIN := Vector3(-8192, -8192, -8192)
const ROOT_SIZE   := 16384.0

const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337

const SAVE_MAGIC   := 0x45445331   # "EDS1" — guards against loading a stale/foreign blob
const SAVE_VERSION := 1

var store: EditStore


func setup() -> void:
    store = EditStore.new()
    store.setup(ROOT_ORIGIN, ROOT_SIZE, BASE, AMP, PERIOD, OCTAVES, SEED)


# --- persistence (S4) ---

func save_to(path: String) -> Error:
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        return FileAccess.get_open_error()
    f.store_32(SAVE_MAGIC)
    f.store_32(SAVE_VERSION)
    f.store_buffer(store.serialize())
    return OK

# Deserialize into the existing store instance (render/collision hold its reference, so we
# mutate in place rather than replace). Skips a blob whose magic/version doesn't match.
func load_from(path: String) -> bool:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return false
    if f.get_32() != SAVE_MAGIC or f.get_32() != SAVE_VERSION:
        return false
    store.deserialize(f.get_buffer(f.get_length() - f.get_position()))
    return true
