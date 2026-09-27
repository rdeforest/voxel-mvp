class_name SavedWorld
extends RefCounted

# The on-disk save is two files: the WorldSnapshot (player, tracked-voxel support, tunables,
# windows) and the EditStore blob (terrain + imprinted parts). The snapshot's tracked voxels
# describe the blob's contents, so the pair loads only as a pair: both halves present, both in this
# build's format, carrying the same save id. Anything else is refused: neither half is applied, and
# saving over it is refused too, so the files survive for a look (or a build that can read them).
# The console `reset` is the explicit way to start over and overwrite them.
#
# A save writes both halves under temporary names, then renames them into place, snapshot first.
# It is committed once both temporaries read back whole with its id; that read-back is the proof,
# because FileAccess reports only failed writes into its buffer, and a failure flushing the tail at
# close is dropped. A crash (or failed rename) after the commit is finished by the next read or
# save, which renames what's left; anything short of it leaves the previous pair in place. This
# covers the process dying, not the machine: Godot's FileAccess has no fsync, so after a power loss
# the rename can outlive the data it points at.

const TMP_SUFFIX := ".tmp"

var snapshot_path:  String
var editstore_path: String

var snapshot: Dictionary = {}   # parsed WorldSnapshot; empty when absent or refused
var refusal:  String     = ""   # why this build won't load or overwrite the pair; "" when it will


func _init(p_snapshot_path: String, p_editstore_path: String) -> void:
    snapshot_path  = p_snapshot_path
    editstore_path = p_editstore_path


# Finishes a committed save a crash interrupted, then reads and vets both halves without
# applying anything.
static func read(p_snapshot_path: String, p_editstore_path: String) -> SavedWorld:
    var saved   := SavedWorld.new(p_snapshot_path, p_editstore_path)
    var problem := saved._finish_committed_save()
    if not problem.is_empty():
        saved.refusal = "an interrupted save couldn't be finished (%s)" % problem
    else:
        saved.refusal = saved._vet()
    if not saved.refusal.is_empty():
        saved.snapshot = {}
    return saved


# Applies the pair; false when there's no save, or when the blob didn't load (then `refusal` says
# why, and the snapshot isn't applied over fresh terrain).
func load_into(world: Node, edit_store: EditStoreManager) -> bool:
    if not refusal.is_empty() or snapshot.is_empty():
        return false

    if not edit_store.load_from(editstore_path):
        refusal = "terrain save didn't load"
        return false

    WorldSnapshot.apply(snapshot, world)
    return true


# Writes both halves. "" on success, otherwise what went wrong, for the caller to report. A committed
# save still waiting on its renames is finished first, so this one can't overwrite its temporaries.
func save(world: Node, edit_store: EditStoreManager) -> String:
    if not refusal.is_empty():
        return "not overwriting a save this build can't read (%s)" % refusal

    var pending := _finish_committed_save()
    if not pending.is_empty():
        return "an earlier save couldn't be finished (%s)" % pending

    var save_id := Crypto.new().generate_random_bytes(8).decode_s64(0)
    var problem := _write_temporaries(world, edit_store, save_id)
    if not problem.is_empty():
        return problem
    if _committed_snapshot() != _tmp(snapshot_path):
        return "the save didn't read back whole; the previous save is kept"

    problem = _finish_committed_save()
    return "" if problem.is_empty() else "%s; the save completes on the next save or load" % problem


func _write_temporaries(world: Node, edit_store: EditStoreManager, save_id: int) -> String:
    var err := WorldSnapshot.save(_tmp(snapshot_path), world, save_id)
    if err != OK:
        return "world snapshot: %s" % error_string(err)

    err = edit_store.save_to(_tmp(editstore_path), save_id)
    return "" if err == OK else "terrain: %s" % error_string(err)


# Why the pair on disk won't load, or "" when it will (or when there's no save at all).
func _vet() -> String:
    var has_snapshot  := FileAccess.file_exists(snapshot_path)
    var has_editstore := FileAccess.file_exists(editstore_path)
    if not has_snapshot and not has_editstore:
        return ""
    if not has_editstore:
        return "the world snapshot has no terrain save beside it"
    if not has_snapshot:
        return "the terrain save has no world snapshot beside it"

    snapshot = WorldSnapshot.read(snapshot_path)
    var reasons := PackedStringArray([WorldSnapshot.refusal(snapshot), EditStoreManager.refusal(editstore_path)])
    var problem := "; ".join(Array(reasons).filter(func(r: String) -> bool: return not r.is_empty()))
    if problem.is_empty() and snapshot["save_id"] != EditStoreManager.save_id(editstore_path):
        problem = "the world snapshot and terrain save come from different saves"
    return problem


# The snapshot file that commits the save waiting under temporary names: the blob temporary reads
# back whole, and so does this snapshot (its temporary, or the one already renamed into place),
# carrying the blob's id. "" when there's no committed save; anything else under a temporary name
# never committed, and is left for the next save to overwrite.
func _committed_snapshot() -> String:
    var blob_tmp := _tmp(editstore_path)
    if not FileAccess.file_exists(blob_tmp) or not EditStoreManager.refusal(blob_tmp).is_empty():
        return ""

    var save_id := EditStoreManager.save_id(blob_tmp)
    for file in [_tmp(snapshot_path), snapshot_path]:
        if _holds_save(file, save_id):
            return file
    return ""

# Renames a committed save's remaining temporaries into place. "" when that worked or there was
# nothing to finish, otherwise the rename that failed.
func _finish_committed_save() -> String:
    var snapshot_file := _committed_snapshot()
    if snapshot_file.is_empty():
        return ""

    var problem := "" if snapshot_file == snapshot_path else _commit(snapshot_path)
    if problem.is_empty():
        problem = _commit(editstore_path)
    return problem


static func _holds_save(snapshot_file: String, save_id: int) -> bool:
    var snap := WorldSnapshot.read(snapshot_file)
    return WorldSnapshot.refusal(snap).is_empty() and snap["save_id"] == save_id

static func _tmp(path: String) -> String:
    return path + TMP_SUFFIX

# Renames `path`'s temporary into place over it.
static func _commit(path: String) -> String:
    var err := DirAccess.rename_absolute(_tmp(path), path)
    return "" if err == OK else "renaming %s: %s" % [path.get_file(), error_string(err)]
