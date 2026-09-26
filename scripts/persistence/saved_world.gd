class_name SavedWorld
extends RefCounted

# The on-disk save is two files: the WorldSnapshot (player, tracked-voxel support, tunables,
# windows) and the EditStore blob (terrain + imprinted parts). The snapshot's tracked voxels
# describe the blob's contents, so when either half exists but this build can't read it, the
# whole pair is refused: neither half is applied, and saving over it is refused too, so the files
# survive for a build that can read them. The console `reset` is the explicit way to start over
# and overwrite them. A lone half (the other file absent) still loads on its own, and a pair
# whose halves came from different saves isn't detected: docs/bugs/save-pair-consistency.md.

var snapshot_path:  String
var editstore_path: String

var snapshot: Dictionary = {}   # parsed WorldSnapshot; empty when absent or refused
var refusal:  String     = ""   # why this build won't load or overwrite the pair; "" when it will


func _init(p_snapshot_path: String, p_editstore_path: String) -> void:
    snapshot_path  = p_snapshot_path
    editstore_path = p_editstore_path


# Reads and vets both halves without applying anything.
static func read(p_snapshot_path: String, p_editstore_path: String) -> SavedWorld:
    var saved   := SavedWorld.new(p_snapshot_path, p_editstore_path)
    var reasons := PackedStringArray()

    if FileAccess.file_exists(p_snapshot_path):
        saved.snapshot = WorldSnapshot.read(p_snapshot_path)
        reasons.append(WorldSnapshot.refusal(saved.snapshot))
    if FileAccess.file_exists(p_editstore_path):
        reasons.append(EditStoreManager.refusal(p_editstore_path))

    saved.refusal = "; ".join(Array(reasons).filter(func(r: String) -> bool: return not r.is_empty()))
    if not saved.refusal.is_empty():
        saved.snapshot = {}
    return saved


# Applies whatever of the pair exists; false when nothing was loaded.
func load_into(world: Node, edit_store: EditStoreManager) -> bool:
    if not refusal.is_empty():
        return false

    var loaded := false
    if not snapshot.is_empty():
        WorldSnapshot.apply(snapshot, world)
        loaded = true
    if FileAccess.file_exists(editstore_path):
        loaded = edit_store.load_from(editstore_path) or loaded
    return loaded


# Writes both halves. "" on success, otherwise what went wrong, for the caller to report.
func save(world: Node, edit_store: EditStoreManager) -> String:
    if not refusal.is_empty():
        return "not overwriting a save this build can't read (%s)" % refusal

    var err := WorldSnapshot.save(snapshot_path, world)
    if err != OK:
        return "world snapshot: %s" % error_string(err)

    err = edit_store.save_to(editstore_path)
    if err != OK:
        return "terrain: %s" % error_string(err)
    return ""
