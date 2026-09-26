#!/usr/bin/env python3
"""Every table and figure in the Characterization section of
docs/bugs/single-voxel-edits-unexpected.md, from probe_single_voxel.gd's output.

Usage: scripts/dev/summarize_single_voxel.py out.tsv
Reads out.tsv, and out.census.tsv / out.occupancy.tsv beside it when present.
"""

import csv
import os
import statistics
import sys
from collections import Counter, defaultdict

CURRENT = ("fill", "empty")
HOLLOW = ("cave_ceiling", "cave_wall", "cave_floor", "overhang_roof")
SAME = 1e-4      # the TSV's float precision: values this close are the same number
DIFFER = 1e-3    # m^3: live and dense volume changes further apart than this differ


def load(path):
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return list(csv.DictReader(f, delimiter="\t"))


def num(row, key):
    return float(row[key]) if row.get(key, "") not in ("", "inf") else None


def nums(rows, key):
    return [v for v in (num(r, key) for r in rows) if v is not None]


def med(values):
    values = [v for v in values if v is not None]
    return f"{statistics.median(values):.2f}" if values else "-"


def pct(part, whole, places=1):
    return f"{100.0 * part / whole:.{places}f} %" if whole else "-"


def fmt(counter):
    return ", ".join(f"{k}:{v}" for k, v in sorted(counter.items())) or "-"


def done(rows):
    return [r for r in rows if r["refused"] == ""]


def table(header):
    print("| " + " | ".join(header) + " |")
    print("|" + "---|" * len(header))


def census(rows):
    print("## Census (validate() only)\n")
    table(["verb", "clicks", "executes", "refused (reason:n)"])
    for verb in ("fill", "empty", "legacy_fill", "legacy_empty"):
        rs = [r for r in rows if r["verb"] == verb]
        ok = len(done(rs))
        refused = Counter(r["refused"] for r in rs if r["refused"])
        print(f"| {verb} | {len(rs)} | {ok} ({pct(ok, len(rs))})"
              f" | {', '.join(f'{k}:{v} ({pct(v, len(rs))})' for k, v in sorted(refused.items())) or '-'} |")
    print()
    for verb in CURRENT:
        rs = done([r for r in rows if r["verb"] == verb])
        p = sorted(nums(rs, "push"))
        flipping = sum(1 for r in rs if int(r["corner_flips"]) > 0)
        infeasible = Counter(r["cls"] for r in rows if r["verb"] == verb and r["refused"] == "lp_infeasible")
        print(f"- {verb}: push n={len(p)} median {statistics.median(p):.2f} p90 {p[len(p) * 9 // 10]:.2f}"
              f" max {p[-1]:.2f}; a corner changes sign in {flipping} ({pct(flipping, len(rs))});"
              f" LP infeasible by class: {fmt(infeasible)}")
    print()


def single_edits(rows):
    print("## Single edits per class (live mesh)\n")
    groups = defaultdict(list)
    for r in rows:
        if r["scenario"].startswith(("single_", "legacy_")):
            groups[(r["verb"], r["cls"])].append(r)
    table(["verb", "class", "n", "refused (reason:n)", "target solid frac before -> after", "dV in target",
           "dV outside", "centroid off (m)", "centroid along n from centre (m)", "centroid along n from hit (m)",
           "max surface shift (m)", "neighbours touched", "target centre flipped", "other centres flipped"])
    for (verb, cls), rs in sorted(groups.items()):
        ok = done(rs)
        refused = Counter(r["refused"] for r in rs if r["refused"])
        print(f"| {verb} | {cls} | {len(rs)} | {fmt(refused)}"
              f" | {med(nums(ok, 'live_frac_was'))} -> {med(nums(ok, 'live_frac_now'))}"
              f" | {med(nums(ok, 'live_own'))} | {med(nums(ok, 'live_spill'))} | {med(nums(ok, 'live_centroid'))}"
              f" | {med(nums(ok, 'live_centroid_n'))} | {med(nums(ok, 'live_centroid_hit_n'))}"
              f" | {med(nums(ok, 'live_shift'))} | {med(nums(ok, 'live_touched'))}"
              f" | {sum(r['target_flip'] == 'true' for r in ok)}/{len(ok)}"
              f" | {sum(int(r['other_flips']) for r in ok)} |")
    print()


def headline(rows):
    print("## Headline medians over every executed edit (live mesh)\n")
    table(["verb", "n", "total dV", "dV in target", "dV outside", "median outside/total",
           "outside/total of medians", "target frac before -> after", "centroid off", "along n from centre",
           "along n from hit", "max shift", "neighbours touched"])
    for verb in ("fill", "empty", "legacy_fill", "legacy_empty"):
        ok = done([r for r in rows if r["verb"] == verb])
        total = [num(r, "live_own") + num(r, "live_spill") for r in ok]
        ratio = [num(r, "live_spill") / t for r, t in zip(ok, total) if t > 0]
        spill, whole = statistics.median(nums(ok, "live_spill")), statistics.median(total)
        print(f"| {verb} | {len(ok)} | {med(total)} | {med(nums(ok, 'live_own'))} | {spill:.2f}"
              f" | {med(ratio)} | {spill / whole:.2f}"
              f" | {med(nums(ok, 'live_frac_was'))} -> {med(nums(ok, 'live_frac_now'))}"
              f" | {med(nums(ok, 'live_centroid'))} | {med(nums(ok, 'live_centroid_n'))}"
              f" | {med(nums(ok, 'live_centroid_hit_n'))} | {med(nums(ok, 'live_shift'))}"
              f" | {med(nums(ok, 'live_touched'))} |")
    print()


def _pred_errors(ok):
    centre, nb, nb_side = 0.0, 0.0, 0
    for r in ok:
        centre = max(centre, abs(num(r, "centre_pred") - num(r, "centre_now")))
        for pred, now in zip(r["nb_pred"].split(";"), r["nb_now"].split(";")):
            if pred:
                nb = max(nb, abs(float(pred) - float(now)))
                nb_side += (float(pred) < 0.0) != (float(now) < 0.0)
    return centre, nb, nb_side


def lp_check(rows):
    print("## LP intent vs outcome\n")
    table(["rule", "executed", "target centre flipped", "target min corner flipped", "edits flipping another centre",
           "other centres flipped", "max |centre pred - now|", "max |neighbour pred - now|",
           "neighbours whose predicted sign was wrong"])
    for rule, verbs in (("current", CURRENT), ("legacy", ("legacy_fill", "legacy_empty"))):
        ok = done([r for r in rows if r["verb"] in verbs])
        centre, nb, nb_side = _pred_errors(ok)
        print(f"| {rule} | {len(ok)} | {sum(r['target_flip'] == 'true' for r in ok)}"
              f" | {sum(r['corner_flip'] == 'true' for r in ok)} | {sum(int(r['other_flips']) > 0 for r in ok)}"
              f" | {sum(int(r['other_flips']) for r in ok)} | {centre:.4f} | {nb:.4f} | {nb_side} |")
    print("\n(Legacy predicted neighbours cover only the lattice its one-point write spans.)\n")


def shapes(rows):
    print("## Shape over all executed edits (live mesh)\n")
    table(["verb", "executed", "most-changed target solid frac after (fill: max, empty: min)", "max dV in target",
           "min dV outside", "cube", "bump/dent", "invisible"])
    by = defaultdict(list)
    for r in done(rows):
        by[r["verb"]].append(r)
    for verb, rs in sorted(by.items()):
        counts = Counter(r["live_shape"] for r in rs)
        fracs = nums(rs, "live_frac_now")
        best = max(fracs) if verb.endswith("fill") else min(fracs)
        print(f"| {verb} | {len(rs)} | {best:.2f} | {max(nums(rs, 'live_own')):.2f}"
              f" | {min(nums(rs, 'live_spill')):.2f} | {counts['cube']}"
              f" | {counts['bump'] + counts['dent']} | {counts['invisible']} |")
    print()


def render_modes(rows):
    print("## Live vs dense, and measurement guards\n")
    ok = done(rows)
    diffs, shape_diff, by_cls = [], 0, Counter()
    for r in ok:
        d = abs(num(r, "live_added") + num(r, "live_removed") - num(r, "dense_added") - num(r, "dense_removed"))
        if d > DIFFER:
            diffs.append(d)
            by_cls[r["cls"]] += 1
        shape_diff += r["live_shape"] != r["dense_shape"]
    print(f"- executed edits: {len(ok)}; live and dense total |dV| differ by > {DIFFER} m3 in {len(diffs)}"
          f" (max {max(diffs, default=0.0):.2f} m3); shape class differs in {shape_diff}")
    print(f"- differing edits by class: {fmt(by_cls)}")
    for mode in ("live", "dense"):
        far = nums(ok, f"{mode}_moved_far")
        capped = nums(ok, f"{mode}_capped")
        print(f"- {mode}: edits moving vertices outside the +-2 cell diff box: {sum(v > 0 for v in far)}"
              f" (max {max(far, default=0):.0f} vertices); edits with a window-capped column: {sum(v > 0 for v in capped)}")
    print()


def _sequences(rows):
    seqs = []
    for r in rows:
        if r["scenario"].startswith(("single_", "legacy_")):
            continue
        if r["step"] == "0":
            seqs.append([])
        seqs[-1].append(r)
    return seqs


def sequences(rows):
    print("## Click sequences\n")
    seqs = _sequences(rows)
    groups = defaultdict(list)
    for seq in seqs:
        for r in seq:
            groups[(r["scenario"], int(r["step"]))].append((r, seq[0]))
    table(["scenario", "step", "n", "refused (reason:n)", "live shape", "dV in target", "dV outside",
           "same cell as step 0"])
    for (scen, step), pairs in sorted(groups.items()):
        rs = [r for r, _ in pairs]
        ok = done(rs)
        print(f"| {scen} | {step} | {len(rs)} | {fmt(Counter(r['refused'] for r in rs if r['refused']))}"
              f" | {fmt(Counter(r['live_shape'] for r in ok))} | {med(nums(ok, 'live_own'))}"
              f" | {med(nums(ok, 'live_spill'))} | {sum(r['cell'] == first['cell'] for r, first in pairs)} |")
    print()
    _followups(seqs)


def _followups(seqs):
    print("Step 1 after a step 0 that executed (same cell as step 0?, outcome):\n")
    table(["scenario", "step 0 executed", "step 1 outcomes", "step 1 same-cell executed: dV in target / outside"])
    by = defaultdict(list)
    for seq in seqs:
        if len(seq) > 1 and seq[0]["refused"] == "":
            by[seq[0]["scenario"]].append(seq)
    for scen, ss in sorted(by.items()):
        outcomes = Counter((s[1]["cell"] == s[0]["cell"], s[1]["refused"] or "done") for s in ss)
        same_done = [s[1] for s in ss if s[1]["cell"] == s[0]["cell"] and s[1]["refused"] == ""]
        label = ", ".join(f"{'same' if same else 'other'} cell {why}:{n}" for (same, why), n in sorted(outcomes.items()))
        print(f"| {scen} | {len(ss)} | {label} | {med(nums(same_done, 'live_own'))} / {med(nums(same_done, 'live_spill'))} |")
    print()


def paint(rows):
    print("## Material paint (fills, live mesh)\n")
    fills = [r for r in done(rows) if r["verb"].endswith("fill")]
    groups = defaultdict(list)
    for r in fills:
        groups[(r["verb"], r["cls"])].append(r)
    header = ["verb", "class", "fills", "new painted verts in target cell", "new painted verts outside",
              "moved verts", "moved verts painted", "fills with no painted vert in target"]
    table(header)
    for (verb, cls), rs in sorted(groups.items()):
        print("| " + " | ".join([verb, cls] + [str(v) for v in _paint_sums(rs)]) + " |")
    print()
    for verb in ("fill", "legacy_fill"):
        n, inside, outside, moved, painted, none_in = _paint_sums([r for r in fills if r["verb"] == verb])
        print(f"- {verb}: {painted} of {moved} moved verts painted ({pct(painted, moved)}); new painted"
              f" {inside} in target vs {outside} outside ({outside / max(inside, 1):.1f}x);"
              f" {none_in} of {n} fills ({pct(none_in, n)}) put none in the target")
    print()


def _paint_sums(rs):
    s = lambda k: sum(int(r[k]) for r in rs)
    none_in = sum(1 for r in rs if int(r["live_paint_in"]) == 0)
    return [len(rs), s("live_paint_in"), s("live_paint_out"), s("live_moved"), s("live_paint_moved"), none_in]


def occupancy(rows):
    print("## Occupancy measure vs field sign (every 2nd grid point)\n")
    table(["terrain", "phase", "mode", "regions", "points", "mismatch", "points |sdf| >= 0.3",
           "mismatch there", "worst region there", "window-capped columns"])
    groups = defaultdict(list)
    for r in rows:
        groups[("hollow" if r["cls"] in HOLLOW else "open", r["phase"], r["mode"])].append(r)
    for (terrain, phase, mode), rs in sorted(groups.items()):
        s = lambda k: sum(int(r[k]) for r in rs)
        worst = max(int(r["far_mismatch"]) / max(int(r["far_points"]), 1) for r in rs)
        print(f"| {terrain} | {phase} | {mode} | {len(rs)} | {s('points')} | {pct(s('mismatch'), s('points'), 2)}"
              f" | {s('far_points')} | {pct(s('far_mismatch'), s('far_points'), 2)} | {100 * worst:.2f} %"
              f" | {s('capped')} |")
    print()


def main():
    base = os.path.splitext(sys.argv[1])[0]
    rows = load(sys.argv[1])
    census_rows = load(base + ".census.tsv")
    if census_rows:
        census(census_rows)
    single_edits(rows)
    headline(rows)
    lp_check(rows)
    shapes(rows)
    render_modes(rows)
    sequences(rows)
    paint(rows)
    occupancy_rows = load(base + ".occupancy.tsv")
    if occupancy_rows:
        occupancy(occupancy_rows)


main()
