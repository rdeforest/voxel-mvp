class_name Tool
extends RefCounted

# A Tool groups related EditModes (activities) under one name.
#   None         — walking around; clicks probe the targeted cell.
#   Landscape    — Dig, Fill, Flatten, Raise, Lower, FillVoxel, EmptyVoxel.
#   Construction — Build, Remove.
#
# The player carries a tool_index and a per-tool last-activity index, so
# switching tools and back returns to the previously-selected activity in
# each tool. Activities are picked with number keys (1..9) within the
# active tool; Tab cycles tools.

var name:       String
var activities: Array[EditMode] = []


func _init(p_name: String, p_activities: Array[EditMode]) -> void:
    name       = p_name
    activities = p_activities
