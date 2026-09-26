"""Line-for-line port of Mat3::svd (engine/voxel_dc/mat3.cpp) to classify which reflection branch
each input reaches, and to check the test/test_mpm_svd.gd assertions against deliberately wrong
reflection handling (the C++ can't be mutated from GDScript).

  godot --path . --headless -s res://scripts/dev/dump_svd_random_inputs.gd | grep -E '^(F|E) ' \
      | python3 scripts/dev/svd_branch_port.py

"E" lines print how far the port's current variant is from the engine's debug_svd on that input.

Variants: current (the code), report (the 2026-06-22 rule as written), anyflip (negate sigma2 once
whenever any column flips), noflip, v_only, u_only (a missing flip).
See docs/bugs/closed/mpm-svd-reflection-sign.md.
"""
import math, sys
def mul(a,b): return [[sum(a[i][k]*b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
def T(a): return [[a[j][i] for j in range(3)] for i in range(3)]
def det(m): return (m[0][0]*(m[1][1]*m[2][2]-m[1][2]*m[2][1]) - m[0][1]*(m[1][0]*m[2][2]-m[1][2]*m[2][0]) + m[0][2]*(m[1][0]*m[2][1]-m[1][1]*m[2][0]))
def I(): return [[1.0 if i==j else 0.0 for j in range(3)] for i in range(3)]
def eigen(s):
    a=[r[:] for r in s]; v=I()
    for sweep in range(16):
        off=abs(a[0][1])+abs(a[0][2])+abs(a[1][2])
        if off<1e-300: break
        for p,q in ((0,1),(0,2),(1,2)):
            apq=a[p][q]
            if abs(apq)<1e-300: continue
            phi=0.5*math.atan2(2*apq,a[q][q]-a[p][p]); c=math.cos(phi); sn=math.sin(phi)
            j=I(); j[p][p]=c; j[q][q]=c; j[p][q]=sn; j[q][p]=-sn
            a=mul(mul(T(j),a),j); v=mul(v,j)
    return v,[a[0][0],a[1][1],a[2][2]]
def cross(a,b): return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def svd(f, variant="current"):
    v,ev=eigen(mul(T(f),f)); sig=[math.sqrt(max(e,0.0)) for e in ev]
    order=[0,1,2]
    for i in range(3):
        for j in range(i+1,3):
            if sig[order[j]]>sig[order[i]]: order[i],order[j]=order[j],order[i]
    ss=[sig[o] for o in order]; v=[[v[r][order[i]] for i in range(3)] for r in range(3)]
    fv=mul(f,v); u=[[0.0]*3 for _ in range(3)]
    for i in range(3):
        if ss[i]>1e-12:
            for r in range(3): u[r][i]=fv[r][i]/ss[i]
        else:
            a=(i+1)%3;b=(i+2)%3
            cr=cross([u[r][a] for r in range(3)],[u[r][b] for r in range(3)]); n=math.sqrt(sum(x*x for x in cr)) or 1
            for r in range(3): u[r][i]=cr[r]/n
    dv=det(v); du=det(u); case=("V" if dv<0 else "")+("U" if du<0 else "")
    if variant=="current":
        if dv<0:
            for r in range(3): v[r][2]=-v[r][2]
            ss[2]=-ss[2]
        if du<0:
            for r in range(3): u[r][2]=-u[r][2]
            ss[2]=-ss[2]
    elif variant=="report":  # the 2026-06-22 proposal as written
        if dv<0 and du<0:
            for r in range(3): v[r][2]=-v[r][2]; u[r][2]=-u[r][2]
        elif dv<0:
            for r in range(3): v[r][2]=-v[r][2]
            ss[2]=-ss[2]
        elif du<0:
            for r in range(3): u[r][2]=-u[r][2]
            ss[2]=-ss[2]
    elif variant=="anyflip":  # "negate sigma2 once" whenever any column flips
        if dv<0:
            for r in range(3): v[r][2]=-v[r][2]
        if du<0:
            for r in range(3): u[r][2]=-u[r][2]
        if dv<0 or du<0: ss[2]=-ss[2]
    elif variant=="noflip":
        pass
    elif variant=="v_only":
        if dv<0:
            for r in range(3): v[r][2]=-v[r][2]
            ss[2]=-ss[2]
    elif variant=="u_only":
        if du<0:
            for r in range(3): u[r][2]=-u[r][2]
            ss[2]=-ss[2]
    sg=[[ss[i] if i==j else 0 for j in range(3)] for i in range(3)]
    rec=mul(mul(u,sg),T(v)); err=math.sqrt(sum((rec[i][j]-f[i][j])**2 for i in range(3) for j in range(3)))
    return dict(case=case or "none",det_u=det(u),det_v=det(v),s=ss,err=err,detf=det(f))

def check(r):
    fails = []
    if r['err'] > 1e-9: fails.append('recon')
    if abs(r['det_u'] - 1) > 1e-9: fails.append('detU')
    if abs(r['det_v'] - 1) > 1e-9: fails.append('detV')
    if (r['s'][2] < 0) != (r['detf'] < 0): fails.append('sign')
    if abs(r['s'][0] * r['s'][1] * r['s'][2] - r['detf']) > 1e-9: fails.append('prod')
    return fails


VARIANTS = ["current", "report", "anyflip", "noflip", "v_only", "u_only"]

def engine_diff(r, e):
    port = [r['det_u'], r['det_v'], *r['s'], r['err']]
    return max(abs(a - b) for a, b in zip(port, e))


if __name__ == "__main__":
    port = {}
    for line in sys.stdin:
        p = line.split()
        x = list(map(float, p[2:]))
        if p[0] == "E":
            print(f"{p[1]:22} port-vs-engine max |diff| = {engine_diff(port[p[1]], x):.3e}")
            continue
        f = [x[0:3], x[3:6], x[6:9]]
        port[p[1]] = svd(f)
        cols = " ".join(f"{v}:{','.join(check(svd(f, v))) or 'ok'}" for v in VARIANTS)
        print(f"{p[1]:22} case={port[p[1]]['case']:5} {cols}")
