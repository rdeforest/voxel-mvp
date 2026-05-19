class_name Part
extends Schematic

# Outer bounding box of the Part in local space. The procedural mesh,
# collision, and footprint all derive from this. The Part is bottom-anchored:
# the box's local-space bottom face sits at Y=0.
@export var dimensions:    Vector3    = Vector3.ONE

@export var material_name: StringName = &"Wood"

# Optional hand-authored scene. Overrides the procedural build for parts that
# need custom geometry, joinery, or shader work. `dimensions` is still
# authoritative for footprint computation either way.
@export var scene:         PackedScene


func instantiate(material_override: StringName = &"") -> Node3D:
    if scene != null:
        return scene.instantiate()
    var name: StringName = material_override if material_override != &"" else material_name
    return _build_procedural(name)


func _build_procedural(name: StringName) -> StaticBody3D:
    var body := StaticBody3D.new()
    var mid  := Vector3(0.0, dimensions.y * 0.5, 0.0)

    var box := BoxMesh.new()
    box.size = dimensions

    var mat := StandardMaterial3D.new()
    mat.albedo_color = Materials.from_name(name).albedo
    mat.roughness    = 0.85

    var mi := MeshInstance3D.new()
    mi.mesh              = box
    mi.material_override = mat
    mi.position          = mid
    body.add_child(mi)

    var shape := BoxShape3D.new()
    shape.size = dimensions

    var cs := CollisionShape3D.new()
    cs.shape    = shape
    cs.position = mid
    body.add_child(cs)

    return body
