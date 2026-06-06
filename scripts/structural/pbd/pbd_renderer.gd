class_name PbdRenderer
extends RefCounted

# Draws a PbdNetwork's live members into an ImmediateMesh as lines coloured by
# axial-force ratio (green = slack → red = at the member's limit) — the Poly-Bridge
# stress view. Shared by PbdDemo and the live PbdStructure.

static func make_material() -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.vertex_color_use_as_albedo = true
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    return m


static func draw(net: PbdNetwork, im: ImmediateMesh) -> void:
    im.clear_surfaces()
    if net == null or net.member_count() == 0:
        return
    im.surface_begin(Mesh.PRIMITIVE_LINES)
    for k in net.member_count():
        if net.m_broken[k] != 0:
            continue
        var col := stress_color(net, k)
        im.surface_set_color(col)
        im.surface_add_vertex(net.pos[net.m_a[k]])
        im.surface_set_color(col)
        im.surface_add_vertex(net.pos[net.m_b[k]])
    im.surface_end()


static func stress_color(net: PbdNetwork, k: int) -> Color:
    var f := net.m_force[k]
    var limit: float = net.m_tension[k] if f >= 0.0 else net.m_compression[k]
    var r := clampf(absf(f) / maxf(limit, 0.001), 0.0, 1.0)
    return Color(r, 1.0 - r, 0.0)
