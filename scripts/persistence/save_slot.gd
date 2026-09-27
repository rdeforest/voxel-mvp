class_name SaveSlot
extends RefCounted

# Where a save pair lives. The default slot, DEFAULT, is F5 / F9's: SavePaths' two files in
# user://saves/. A named slot (console `save <name>` / `load <name>`, doc 22's instrument layer) is
# its own directory, user://saves/<name>/, holding a pair of the same two file names. Every slot is
# a SavedWorld, with its refusals: a pair this build can't read is neither loaded nor overwritten.
#
# Loading reloads the World scene, which reads its save in _ready; the slot to read waits here.

const DEFAULT := ""

static var _pending_load := DEFAULT


# Whether `name` can be a slot: DEFAULT, or a plain file name that isn't hidden (nor ".."), nor
# one of the default slot's own files: named slots share its directory, and a slot directory made
# where F5 renames its pair in would break every later F5.
static func is_valid(name: String) -> bool:
    if name == DEFAULT:
        return true
    return name == name.validate_filename() and not name.begins_with(".") and not _default_files().has(name)

static func _default_files() -> PackedStringArray:
    var out := PackedStringArray()
    for file in [SavePaths.SNAPSHOT_NAME, SavePaths.EDITSTORE_NAME]:
        out.append(file)
        out.append(file + SavedWorld.TMP_SUFFIX)
    return out

static func dir_of(name: String) -> String:
    return SavePaths.root if name == DEFAULT else "%s/%s" % [SavePaths.root, name]

static func snapshot_path(name: String) -> String:
    return "%s/%s" % [dir_of(name), SavePaths.SNAPSHOT_NAME]

static func editstore_path(name: String) -> String:
    return "%s/%s" % [dir_of(name), SavePaths.EDITSTORE_NAME]


# The slot's pair, read and vetted, nothing applied.
static func read(name: String) -> SavedWorld:
    return SavedWorld.read(snapshot_path(name), editstore_path(name))


# Saves `world` into the slot. "" on success, otherwise why not.
static func save(name: String, world: Node, edit_store: EditStoreManager) -> String:
    if not is_valid(name):
        return "\"%s\" isn't a plain file name" % name

    var err := DirAccess.make_dir_recursive_absolute(dir_of(name))
    if err != OK:
        return "can't make %s: %s" % [dir_of(name), error_string(err)]
    return read(name).save(world, edit_store)


# Marks the slot for the next World load, once it's known to hold a pair this build loads. "" when
# marked, otherwise why not; the caller then reloads the scene.
static func request_load(name: String) -> String:
    if not is_valid(name):
        return "\"%s\" isn't a plain file name" % name

    var saved := read(name)
    if not saved.refusal.is_empty():
        return saved.refusal
    if saved.snapshot.is_empty():
        return "there is no save %s" % ("in the default slot" if name == DEFAULT else "named \"%s\"" % name)

    _pending_load = name
    return ""


# The slot a load asked for, once: DEFAULT when none did.
static func take_pending_load() -> String:
    var name := _pending_load
    _pending_load = DEFAULT
    return name
