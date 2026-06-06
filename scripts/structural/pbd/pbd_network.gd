class_name PbdNetwork
extends RefCounted

# A graph of point particles joined by breakable distance constraints ("members"),
# simulated by PbdSolver (Position-Based Dynamics). Pure data + topology — no
# terrain, no scene — so it's headless-unit-testable. A node with mass <= 0 is a
# pinned anchor (inv_mass 0; the solver never moves it). Members carry both tension
# (len > rest) and compression (len < rest) and break past per-member strain limits,
# which is what lets cantilevers/bridges fail emergently.

var pos:      PackedVector3Array = PackedVector3Array()   # current position
var vel:      PackedVector3Array = PackedVector3Array()   # velocity
var prev:     PackedVector3Array = PackedVector3Array()   # position at substep start (scratch)
var inv_mass: PackedFloat32Array = PackedFloat32Array()   # 0 = pinned anchor

var m_a:           PackedInt32Array   = PackedInt32Array()
var m_b:           PackedInt32Array   = PackedInt32Array()
var m_rest:        PackedFloat32Array = PackedFloat32Array()   # rest length
var m_compliance:  PackedFloat32Array = PackedFloat32Array()   # XPBD compliance (inverse stiffness)
# Break limits are AXIAL FORCE, not strain: near-rigid members barely deform, so
# strain is a useless failure criterion — they fail when the force they carry
# exceeds the material's limit. The solver extracts force from the XPBD multiplier
# (force = -lambda / h^2; positive = tension, negative = compression).
var m_tension:     PackedFloat32Array = PackedFloat32Array()   # max tensile force
var m_compression: PackedFloat32Array = PackedFloat32Array()   # max compressive force
var m_broken:      PackedByteArray    = PackedByteArray()
var m_lambda:      PackedFloat32Array = PackedFloat32Array()   # XPBD multiplier accumulator (reset per substep)
var m_force:       PackedFloat32Array = PackedFloat32Array()   # peak signed axial force this step (+tension)


func add_node(p: Vector3, mass: float) -> int:
    var i := pos.size()
    pos.append(p)
    vel.append(Vector3.ZERO)
    prev.append(p)
    inv_mass.append(0.0 if mass <= 0.0 else 1.0 / mass)
    return i


func add_member(a: int, b: int, compliance: float, tension: float, compression: float) -> int:
    var k := m_a.size()
    m_a.append(a)
    m_b.append(b)
    m_rest.append(pos[a].distance_to(pos[b]))
    m_compliance.append(compliance)
    m_tension.append(tension)
    m_compression.append(compression)
    m_broken.append(0)
    m_lambda.append(0.0)
    m_force.append(0.0)
    return k


func node_count() -> int:
    return pos.size()

func member_count() -> int:
    return m_a.size()

func live_member_count() -> int:
    var n := 0
    for k in m_broken.size():
        if m_broken[k] == 0:
            n += 1
    return n

# Signed strain: > 0 stretched (tension), < 0 compressed.
func strain(k: int) -> float:
    var rest := m_rest[k]
    if rest <= 0.0:
        return 0.0
    return (pos[m_a[k]].distance_to(pos[m_b[k]]) - rest) / rest
