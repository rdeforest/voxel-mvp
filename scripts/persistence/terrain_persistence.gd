class_name TerrainPersistence
extends RefCounted

# godot_voxel writes a modified SDF block to its VoxelStream only when that block
# streams out, and it does NOT save on exit (NOTIFICATION_EXIT_TREE is a no-op).
# So edits in blocks still loaded around the player never reach disk unless we
# ask. Call this on save and on quit, or those edits are lost on the next reload.
# `terrain` is a VoxelLodTerrain in production; left untyped so tests can pass a
# stub (the native save_modified_blocks can't be overridden to spy on it).
static func flush(terrain) -> void:
    if terrain == null or terrain.stream == null:
        return
    terrain.save_modified_blocks()
