extends Node
class_name DebugServer

# Localhost-only debug HTTP endpoint so Claude (or any tool) can read live telemetry and drive console
# commands without a human relaying numbers. Debug/editor builds only — never shipped. Two routes:
#   GET /stats          -> JSON of live mesher/render telemetry (the perf-overlay data, machine-readable)
#   GET /cmd?c=<urlenc> -> run a Limbo console command (fire-and-forget; read the effect back via /stats)
# System load (CPU/GPU/temps) is read separately from /proc + nvidia-smi by the tool itself.

const PORT := 8088

var _server := TCPServer.new()
var _world_preview: DcWorldPreview
var _conns: Array = [] # [{peer: StreamPeerTCP, buf: PackedByteArray}]


func setup(world_preview: DcWorldPreview) -> void:
	_world_preview = world_preview


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # serve even while the tree is paused
	var err := _server.listen(PORT, "127.0.0.1")
	if err != OK:
		push_warning("DebugServer: listen on %d failed (%d)" % [PORT, err])
	else:
		print("DebugServer: http://127.0.0.1:%d/stats" % PORT)


func _exit_tree() -> void:
	_server.stop()


func _process(_dt: float) -> void:
	while _server.is_connection_available():
		_conns.append({ "peer": _server.take_connection(), "buf": PackedByteArray() })
	var keep: Array = []
	for c in _conns:
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue # client gone — drop
		var avail := peer.get_available_bytes()
		var buf: PackedByteArray = c.buf
		if avail > 0:
			buf.append_array(peer.get_data(avail)[1])
			c.buf = buf
		var req := buf.get_string_from_utf8()
		if req.find("\r\n\r\n") == -1:
			keep.append(c) # request line + headers not complete yet — read more next frame
			continue
		_handle(peer, req)
	_conns = keep


func _handle(peer: StreamPeerTCP, req: String) -> void:
	var line := req.get_slice("\r\n", 0)        # e.g. "GET /stats HTTP/1.1"
	var path := line.get_slice(" ", 1)
	var route := path
	var query := ""
	var qpos := path.find("?")
	if qpos != -1:
		route = path.substr(0, qpos)
		query = path.substr(qpos + 1)
	if route == "/stats":
		_respond(peer, "application/json", _stats_json())
	elif route == "/cmd":
		var cmd := _query_value(query, "c").uri_decode()
		var console := get_node_or_null("/root/LimboConsole")
		if cmd != "" and console != null:
			console.execute_command(cmd, true)
		_respond(peer, "application/json", JSON.stringify({ "ok": cmd != "" and console != null, "ran": cmd }))
	else:
		_respond(peer, "text/plain", "routes: /stats  /cmd?c=<command>\n")


func _query_value(query: String, key: String) -> String:
	for pair in query.split("&"):
		if pair.begins_with(key + "="):
			return pair.substr(key.length() + 1)
	return ""


func _stats_json() -> String:
	var wp := _world_preview
	if wp == null:
		return JSON.stringify({ "error": "no world_preview" })
	var m := wp._mesher
	return JSON.stringify({
		"fps": Engine.get_frames_per_second(),
		"frame_gen_ms": Perf.frame_gen_ms(),
		"eps": wp._eps_px,
		"refine_queue": m.get_last_refine_queue_size(),
		"refine_pending": m.get_refine_pending(),
		"cells": m.get_octree_cell_count(),
		"cells_ram_mb": int(m.get_cell_resident_bytes() / 1048576),
		"cells_disk_mb": int(m.get_cell_arena_bytes() / 1048576),
		"job_ms": wp._job_work_ms,
		"job_kind": wp._job_kind(),
		"refine_us": wp.refine_us,
		"retain_m": wp.retain_margin_m,
		"coverage_m": wp.win_radius_m,
		"threads": m.get_thread_count(),
		"phase": {
			"build_ms": m.get_last_build_ms(),
			"reconcile_ms": m.get_last_reconcile_ms(),
			"reaccum_ms": m.get_last_reaccum_ms(),
			"collapse_ms": m.get_last_collapse_ms(),
			"reset_ms": m.get_last_reset_ms(),
			"collapse_walk_ms": m.get_last_collapse_pass_ms(),
			"pass1_ms": m.get_last_pass1_ms(),
			"pass2_ms": m.get_last_pass2_ms(),
		},
	})


func _respond(peer: StreamPeerTCP, content_type: String, body: String) -> void:
	var b := body.to_utf8_buffer()
	var head := "HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [content_type, b.size()]
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(b)
	peer.disconnect_from_host()
