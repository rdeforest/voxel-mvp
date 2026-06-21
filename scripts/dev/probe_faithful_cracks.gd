extends SceneTree
const BASE := 30.0; const AMP := 140.0; const PERIOD := 1000.0; const OCT := 2; const SEED := 1337
const CELL := 0.25; const DEPTH := 12
func _surf(s: EditStore, x: float, z: float) -> float:
    var lo := -400.0; var hi := 400.0
    for _i in 48:
        var mm := (lo+hi)*0.5
        if s.sample(Vector3(x,mm,z))<0.0: lo=mm
        else: hi=mm
    return (lo+hi)*0.5
# strict interior count-1 edges: both endpoints > MARGIN lattice from ALL window faces
func _strict_cracks(arr: Array, wmin: Vector3i, wmax: Vector3i, world_origin: Vector3i, margin: float) -> int:
    var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
    var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
    var ec := {}
    for i in range(0, idx.size(), 3):
        for e in [[idx[i],idx[i+1]],[idx[i+1],idx[i+2]],[idx[i+2],idx[i]]]:
            var k := Vector2i(mini(e[0],e[1]), maxi(e[0],e[1])); ec[k] = ec.get(k,0)+1
    var wlo := Vector3(wmin - world_origin); var whi := Vector3(wmax - world_origin)  # root-local
    var n := 0
    for k in ec:
        if ec[k] != 1: continue
        var a: Vector3 = verts[k.x]; var b: Vector3 = verts[k.y]
        if _interior(a, wlo, whi, margin) and _interior(b, wlo, whi, margin): n += 1
    return n
func _interior(p: Vector3, lo: Vector3, hi: Vector3, m: float) -> bool:
    return p.x>lo.x+m and p.x<hi.x-m and p.y>lo.y+m and p.y<hi.y-m and p.z>lo.z+m and p.z<hi.z-m
func _init():
    var s := EditStore.new(); s.setup(Vector3(-8192,-8192,-8192),16384.0,BASE,AMP,PERIOD,OCT,SEED)
    var surf := _surf(s,0.0,0.0)
    var player := Vector3(0.0, surf, 0.0)
    var root := Vector3i((Vector3(player)/CELL - Vector3.ONE*(float(1<<DEPTH)*0.5)).floor())
    var cam := Vector3(player)/CELL - Vector3(root)
    var r := int(128.0/CELL)
    var c := Vector3i((Vector3(player)/CELL).round())
    var wmin := c - Vector3i.ONE*r; var wmax := c + Vector3i.ONE*r
    for eps in [94.0, 32.0]:
        var m := DCOctreeMesher.new()
        var t0 := Time.get_ticks_usec()
        var arr: Array = m.mesh_world(s, root, DEPTH, CELL, cam, 500.0, eps, true, PackedColorArray(), wmin, wmax)
        var dt := (Time.get_ticks_usec()-t0)/1000.0
        var v := (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
        var strict := _strict_cracks(arr, wmin, wmax, root, 32.0)
        print("eps=%.0f: %.0fms, %d verts, refined=%d cells, STRICT interior cracks(>32)=%d" % [eps, dt, v, m.get_last_refined_count(), strict])
    quit()
