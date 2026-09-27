class_name EditStoreManager
extends RefCounted

# Owns the authoritative EditStore and its on-disk persistence (design 11). The store is the
# sparse SDF+material layer that holds the player's edits over the procedural TerrainField;
# actions write it directly (StoreWrite / stamp_sphere), render + collision sample it.
#
# Persistence (S4): save_to/load_from blob the sparse edited tree to disk. The blob is one half of
# a save; SavedWorld pairs it with the WorldSnapshot through the save id in the header.

# A generous world-fixed root the edits live in. Generator params mirror TerrainField's
# terrain_defaults ([[terrain-generation-in-cpp]]).
const ROOT_ORIGIN := Vector3(-8192, -8192, -8192)
const ROOT_SIZE   := 16384.0

const BASE    := 30.0
const AMP     := 140.0
const PERIOD  := 1000.0
const OCTAVES := 2
const SEED    := 1337

# One save format until there are play testers: a blob of any other version is refused, not
# migrated. v3 added the save id.
const SAVE_MAGIC   := 0x45445331   # "EDS1" — guards against loading a stale/foreign blob
const SAVE_VERSION := 3
const HEADER_BYTES := 16           # magic + version (32-bit each), save id (64-bit)

var store: EditStore


func setup() -> void:
    store = EditStore.new()
    store.setup(ROOT_ORIGIN, ROOT_SIZE, BASE, AMP, PERIOD, OCTAVES, SEED)


# --- persistence (S4) ---

# `save_id` ties this blob to the WorldSnapshot written beside it.
func save_to(path: String, save_id: int) -> Error:
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        return FileAccess.get_open_error()

    var written := f.store_32(SAVE_MAGIC) and f.store_32(SAVE_VERSION) and f.store_64(save_id) \
        and f.store_buffer(store.serialize())
    return OK if written else ERR_FILE_CANT_WRITE

# Deserialize into the existing store instance (render/collision hold its reference, so we
# mutate in place rather than replace). Skips a blob whose header refuses it, or that deserialize()
# refuses (it logs why and keeps the store).
func load_from(path: String) -> bool:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null or not _header_refusal(f).is_empty():
        return false

    return store.deserialize(f.get_buffer(f.get_length() - HEADER_BYTES))

# Why this build won't load the blob at `path`, or "" when it will: the header, then the blob itself
# (EditStore.blob_problem), so a damaged save is refused before anything is applied.
static func refusal(path: String) -> String:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return "terrain save can't be opened (%s)" % error_string(FileAccess.get_open_error())

    var problem := _header_refusal(f)
    if problem.is_empty():
        problem = EditStore.blob_problem(f.get_buffer(f.get_length() - HEADER_BYTES))
        if not problem.is_empty():
            problem = "terrain save is damaged (%s)" % problem
    return problem

# The save id in the header of a blob refusal() accepted.
static func save_id(path: String) -> int:
    var f := FileAccess.open(path, FileAccess.READ)
    f.seek(HEADER_BYTES - 8)
    return f.get_64()

static func _header_refusal(f: FileAccess) -> String:
    if f.get_length() < HEADER_BYTES or f.get_32() != SAVE_MAGIC:
        return "terrain save is not an EditStore blob"

    var version := f.get_32()
    if version != SAVE_VERSION:
        return "terrain save is format v%d; this build reads only v%d" % [version, SAVE_VERSION]

    f.get_64()
    return ""
