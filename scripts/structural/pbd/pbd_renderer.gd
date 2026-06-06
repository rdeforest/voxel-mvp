class_name PbdRenderer
extends RefCounted

# Renders a PbdSim's live members as stress-coloured lines (green = slack → red = at
# the member's force limit, the Poly-Bridge view). The per-member loop + colour ramp
# live in C++ (PbdSim.get_stress_geometry); here we just hand the verts+colours to an
# ArrayMesh in a single add_surface_from_arrays — no per-member GDScript round-trips.

static func make_material() -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.vertex_color_use_as_albedo = true
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    return m


static func draw(sim: PbdSim, mesh: ArrayMesh) -> void:
    mesh.clear_surfaces()
    if sim == null or sim.live_member_count() == 0:
        return
    var g := sim.get_stress_geometry()
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = g["verts"]
    arrays[Mesh.ARRAY_COLOR] = g["colors"]
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
