extends GutTest

# The Perf HUD's bookkeeping: its per-label dicts must forget labels that stopped reporting (a label
# carrying a count makes a new key per value), and its frame-history rings must read oldest-first
# once they wrap.

const PerfHud := preload("res://scripts/ui/perf.gd")


func test_labels_that_stop_reporting_are_erased() -> void:
    var hud: Node = add_child_autofree(PerfHud.new())
    hud.report("DC collision (3 regions)", 1.0)
    hud.status("dcworld", "eps_px 0.5")

    await wait_process_frames(PerfHud.STALE_FRAMES + 5)

    assert_eq(hud._times.size(), 0, "a timing label unreported past STALE_FRAMES is gone from the dict")
    assert_eq(hud._status.size(), 0, "a status key unreported past STALE_FRAMES is gone from the dict")


func test_ring_reads_oldest_first_after_wrapping() -> void:
    var hud: Node  = autofree(PerfHud.new())
    var extra      := 10
    var marked_at  := PerfHud.GRAPH_CAP + 3
    for v in PerfHud.GRAPH_CAP + extra:
        hud._pending_mark = v == marked_at
        hud._last_queue   = float(v) * 2.0
        hud._record(float(v))

    assert_eq(hud._count, PerfHud.GRAPH_CAP, "the ring holds exactly GRAPH_CAP frames")
    for i in PerfHud.GRAPH_CAP:
        var slot: int = hud._slot(i)
        var frame     := i + extra
        assert_eq(hud._frames[slot], float(frame), "frame %d is the %d-th oldest" % [frame, i])
        assert_eq(hud._queue[slot], float(frame) * 2.0, "the queue ring stays parallel")
        assert_eq(hud._marks[slot], 1 if frame == marked_at else 0, "the mark stays on its frame")
