class_name Simplex
extends RefCounted

# Dense two-phase simplex (Bland's rule, so it cannot cycle) for the tiny linear programs edits
# solve: minimise c.x subject to A x <= b, x >= 0. Returns x, or an empty array when no x
# satisfies the constraints. `b` may be negative (a ">=" row written as "<="). The caller's
# objective must be bounded below on the feasible set (e.g. a nonnegative cost).

const EPS := 1e-9


static func minimize(c: PackedFloat64Array, a: Array[PackedFloat64Array], b: PackedFloat64Array) -> PackedFloat64Array:
    var m := a.size()
    var n := c.size()
    var art := n + m            # first artificial column; columns: x | slack | artificial | rhs
    var w   := n + 2 * m        # rhs column
    var t: Array[PackedFloat64Array] = []
    var basis: Array[int] = []
    var phase1 := PackedFloat64Array()
    phase1.resize(w)
    for i in m:
        # Row i: a_i.x + s_i = b_i, negated when b_i < 0 so the rhs is >= 0; such a row
        # starts on an artificial (its slack would be negative), every other on its slack.
        var sgn := -1.0 if b[i] < 0.0 else 1.0
        var row := PackedFloat64Array()
        row.resize(w + 1)
        for j in n:
            row[j] = sgn * a[i][j]
        row[n + i] = sgn
        row[w] = sgn * b[i]
        if sgn < 0.0:
            row[art + i] = 1.0
            phase1[art + i] = 1.0
            basis.append(art + i)
        else:
            basis.append(n + i)
        t.append(row)

    # Phase 1: drive the artificials to zero. Any left positive = infeasible.
    _run(t, basis, phase1, w, w)
    for i in m:
        if basis[i] >= art and t[i][w] > 1e-7:
            return PackedFloat64Array()
    # Pivot zero-valued artificials out of the basis so phase 2 can't grow them; a row with no
    # non-artificial entry is redundant and stays as is (all zero, it never constrains).
    for i in m:
        if basis[i] >= art:
            for j in art:
                if absf(t[i][j]) > EPS:
                    _pivot(t, basis, i, j, w)
                    break

    # Phase 2: the real objective, artificials barred from re-entering.
    var phase2 := PackedFloat64Array()
    phase2.resize(w)
    for j in n:
        phase2[j] = c[j]
    _run(t, basis, phase2, art, w)
    var x := PackedFloat64Array()
    x.resize(n)
    for i in m:
        if basis[i] < n:
            x[basis[i]] = t[i][w]
    return x


# Pivot until no column below `ncols` has a negative reduced cost (Bland: lowest index enters,
# lowest basis index leaves on a ratio tie). Stops on an unbounded column (callers are bounded).
static func _run(t: Array[PackedFloat64Array], basis: Array[int], cost: PackedFloat64Array,
        ncols: int, w: int) -> void:
    var m := t.size()
    while true:
        var enter := -1
        for j in ncols:
            var r := cost[j]
            for i in m:
                r -= cost[basis[i]] * t[i][j]
            if r < -EPS:
                enter = j
                break
        if enter < 0:
            return
        var leave := -1
        var best := INF
        for i in m:
            if t[i][enter] > EPS:
                var ratio := t[i][w] / t[i][enter]
                if ratio < best - EPS or (absf(ratio - best) <= EPS and basis[i] < basis[leave]):
                    best = ratio
                    leave = i
        if leave < 0:
            return
        _pivot(t, basis, leave, enter, w)


static func _pivot(t: Array[PackedFloat64Array], basis: Array[int], r: int, col: int, w: int) -> void:
    var row := t[r]
    var p := row[col]
    for j in w + 1:
        row[j] /= p
    t[r] = row
    for i in t.size():
        if i == r:
            continue
        var f := t[i][col]
        if absf(f) <= 0.0:
            continue
        var other := t[i]
        for j in w + 1:
            other[j] -= f * row[j]
        t[i] = other
    basis[r] = col
