class_name MaterialPalette

# Single source of truth mapping the per-voxel material id (the 8-bit CHANNEL_INDICES
# value) to a material name and an albedo colour. Index 0 is "natural" — the
# procedurally generated / un-stamped terrain, which the shader paints by slope
# (grass/dirt) rather than from this palette. Indices 1.. are explicit materials a
# CSG stamp can write.
#
# The colours() array is uploaded to terrain.gdshader as the `material_palette`
# uniform; the DC mesher emits each vertex's id, and the shader looks it up here.

const NAMES: Array[StringName] = [
    &"Natural",   # 0 — slope-shaded; not looked up in the palette
    &"Stone",
    &"Dirt",
    &"Sand",
    &"Wood",
    &"Metal",
    &"Bedrock",   # 6 — deep, hard-but-diggable, always "ground" for the flood-to-ground trigger.
                  # MUST stay index 6: TerrainField::BEDROCK_MATERIAL (terrain_field.h) mirrors it.
]

const NATURAL := 0
const BEDROCK := 6

# A neutral placeholder for slot 0 (the shader never reads it — index 0 takes the
# slope path) so the uploaded array stays aligned with NAMES.
const NATURAL_COLOR := Color(0.4, 0.4, 0.4, 1.0)


# Material names a CSG stamp can choose from (everything but Natural).
static func selectable() -> Array[StringName]:
    return NAMES.slice(1)


static func index_of(name: StringName) -> int:
    var i := NAMES.find(name)
    return i if i >= 0 else NATURAL


static func name_of(index: int) -> StringName:
    return NAMES[index] if index >= 0 and index < NAMES.size() else &"?"


static func color_of(index: int) -> Color:
    if index <= NATURAL or index >= NAMES.size():
        return NATURAL_COLOR
    return Materials.from_name(NAMES[index]).albedo


# The palette as a flat colour array, index-aligned with NAMES, for the shader.
static func colors() -> PackedColorArray:
    var out := PackedColorArray()
    for i in NAMES.size():
        out.append(color_of(i))
    return out
