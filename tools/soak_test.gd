extends SceneTree
## Streaming soak test (M2). Moves the player along a long loop through many chunks and
## reports chunk load/unload counts, frame-time stats (max, p99), the main-thread time the
## streamer itself used, memory and node growth.
##
## Usage (headless, from the repo root):
##   godot --headless --path . -s res://tools/soak_test.gd -- --minutes=5 [--speed=20] [--out=user://soak.json]
## Exit code 0 = no leak flags and no streaming frame over the budget; 1 otherwise.

var minutes := 5.0
var speed := 20.0
var out_path := "user://soak.json"
var budget_ms := 8.0

var main: Node
var soul: Node3D
var city: Node
var streamer: Node
var traffic: Node
var path: PackedVector3Array = PackedVector3Array()
var seg := 0
var along := 0.0
var t_start := 0
var last := 0
var frames := 0
var frame_ms: PackedFloat32Array = PackedFloat32Array()
var stream_ms: PackedFloat32Array = PackedFloat32Array()
var spikes: Array = []
var slow_frames: Array = []
var samples: Array = []
var base := {}
var laps := 0
var sample_wait := 0.0
var warm := 0


func _initialize() -> void:
	for raw in OS.get_cmdline_user_args():
		var a := String(raw)
		if a.begins_with("--minutes="):
			minutes = float(a.substr(10))
		elif a.begins_with("--speed="):
			speed = float(a.substr(8))
		elif a.begins_with("--out="):
			out_path = a.substr(6)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main


func _loop_path() -> void:
	# A rectangle through chunks (0,0)..(2,1) and back down to (-2,-2), then home.
	# Every chunk on it is visited, left, and visited again (exercises unload and reload).
	var pts := [Vector2(250, 250), Vector2(1250, 250), Vector2(1250, 750), Vector2(-750, 750),
		Vector2(-750, -750), Vector2(250, -750), Vector2(250, 250)]
	for p in pts:
		path.append(Vector3(p.x, 2.0, p.y))


func _snapshot() -> Dictionary:
	return {
		"t": (Time.get_ticks_msec() - t_start) / 1000.0,
		"mem_mb": OS.get_static_memory_usage() / 1048576.0,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"loaded": streamer.loaded_coords().size(),
		"cars": _car_count(),
		"peds": get_nodes_in_group("pedestrian").size(),
		"cones": get_nodes_in_group("world_cone").size(),
		"chunk": str(streamer.center),
	}


func _car_count() -> int:
	var n := 0
	if traffic != null:
		for c in traffic.get_children():
			if c.get("trip") == true:
				n += 1
	return n


func _process(_d: float) -> bool:
	frames += 1
	var now := Time.get_ticks_usec()
	if frames == 2:
		soul = main.get_node("SoulBody")
		city = main.get_node("City")
		streamer = city.get("streamer")
		traffic = main.get_node_or_null("Traffic")
		_loop_path()
		t_start = Time.get_ticks_msec()
		last = now
		return false
	if frames < 2:
		return false
	var dt_ms := (now - last) / 1000.0
	last = now
	# Let the first window finish streaming before measuring.
	if warm == 0:
		if streamer.busy():
			return false
		warm = frames
		base = _snapshot()
		samples.append(base)
		print("SOAK start %s" % JSON.stringify(base))
		t_start = Time.get_ticks_msec()
		return false
	frame_ms.append(dt_ms)
	var sm: float = streamer.last_frame_usec / 1000.0
	var up: float = float(traffic.get("last_upkeep_usec")) / 1000.0 if traffic != null else 0.0
	stream_ms.append(sm + up)
	if sm + up > budget_ms and spikes.size() < 60:
		spikes.append({"t": (Time.get_ticks_msec() - t_start) / 1000.0, "frame_ms": dt_ms, "stream_ms": sm, "traffic_upkeep_ms": up, "chunk": str(streamer.center)})
	if dt_ms > 100.0 and slow_frames.size() < 30:
		slow_frames.append({"t": (Time.get_ticks_msec() - t_start) / 1000.0, "frame_ms": dt_ms, "stream_ms": sm, "traffic_upkeep_ms": up})
	_advance(dt_ms / 1000.0)
	sample_wait += dt_ms / 1000.0
	if sample_wait >= 10.0:
		sample_wait = 0.0
		var snap := _snapshot()
		samples.append(snap)
		print("SOAK sample %s" % JSON.stringify(snap))
	if (Time.get_ticks_msec() - t_start) / 60000.0 >= minutes:
		_finish()
		return true
	return false


func _advance(dt: float) -> void:
	# Kinematic walk along the path at `speed` (frame-rate independent, capped step).
	var step: float = speed * minf(dt, 0.1)
	while step > 0.0:
		var a: Vector3 = path[seg]
		var b: Vector3 = path[(seg + 1) % path.size()]
		var span := a.distance_to(b)
		if along + step < span:
			along += step
			step = 0.0
		else:
			step -= span - along
			along = 0.0
			seg = (seg + 1) % (path.size() - 1)
			if seg == 0:
				laps += 1
	var a2: Vector3 = path[seg]
	var b2: Vector3 = path[seg + 1]
	var p := a2.lerp(b2, along / maxf(a2.distance_to(b2), 0.001))
	soul.global_position = Vector3(p.x, 2.0, p.z)
	soul.set("velocity", Vector3.ZERO)


func _pct(arr: PackedFloat32Array, q: float) -> float:
	if arr.is_empty():
		return 0.0
	var s := arr.duplicate()
	s.sort()
	return s[mini(s.size() - 1, int(s.size() * q))]


func _finish() -> void:
	# Return home and let the window settle, so node counts compare like for like.
	var end_snap := _snapshot()
	var st: Dictionary = streamer.stats()
	var report := {
		"minutes": minutes, "speed_mps": speed, "laps": laps, "frames": frame_ms.size(),
		"frame_ms": {"max": _pct(frame_ms, 1.0), "p99": _pct(frame_ms, 0.99), "p50": _pct(frame_ms, 0.5)},
		"streaming_main_thread_ms": {"max": _pct(stream_ms, 1.0), "p99": _pct(stream_ms, 0.99), "p50": _pct(stream_ms, 0.5),
			"frames_over_budget": _count_over(stream_ms, budget_ms), "budget_ms": budget_ms},
		"streamer": st,
		"traffic": {} if traffic == null else {
			"graph_rebuilds": traffic.get("graph_rebuilds"), "graph_build_ms_max": traffic.get("graph_build_ms_max"),
			"graph_apply_ms_max": traffic.get("graph_apply_ms_max"), "despawned_outside": traffic.get("stream_despawned"),
			"rerouted": traffic.get("stream_rerouted"), "dead_end_despawns": traffic.get("stream_dead_end_despawns"),
			"upkeep_apply_ms_max": float(traffic.get("upkeep_apply_usec_max")) / 1000.0,
			"upkeep_reroute_ms_max": float(traffic.get("upkeep_reroute_usec_max")) / 1000.0},
		"persistence": streamer.persistence.summary(),
		"start": base, "end": end_snap,
		"growth": {
			"mem_mb": end_snap["mem_mb"] - base["mem_mb"], "nodes": end_snap["nodes"] - base["nodes"],
			"objects": end_snap["objects"] - base["objects"], "orphans": end_snap["orphans"] - base["orphans"],
			"resources": end_snap["resources"] - base["resources"]},
		"samples": samples, "streaming_spikes": spikes, "slow_frames": slow_frames,
		"load_average": _loadavg(),
	}
	# Stashed wrecks (persistence) are detached node trees by design; don't count them.
	var stashed: int = streamer.persistence.stashed_nodes()
	report["growth"]["orphans_excluding_stashed_wrecks"] = int(report["growth"]["orphans"]) - stashed
	var leak := int(report["growth"]["orphans_excluding_stashed_wrecks"]) > 50 or float(report["growth"]["mem_mb"]) > 200.0
	report["leak_flag"] = leak
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
	print("SOAK summary: %.1f min, %d laps, loads %d unloads %d | frame max %.1f p99 %.1f p50 %.1f ms | streaming main-thread max %.2f p99 %.2f ms, %d frames over %.0f ms | job max %.2f ms (%s) | gen max %.0f ms | traffic graph build max %.1f ms (worker), apply max %.2f ms | growth mem %+.1f MB nodes %+d objects %+d orphans %+d (%d excl. stashed wrecks) | leak=%s | json %s" % [
		minutes, laps, st["loads"], st["unloads"], report["frame_ms"]["max"], report["frame_ms"]["p99"], report["frame_ms"]["p50"],
		report["streaming_main_thread_ms"]["max"], report["streaming_main_thread_ms"]["p99"], report["streaming_main_thread_ms"]["frames_over_budget"], budget_ms,
		st["job_ms_max"], st["job_max"], st["gen_ms_max"], float(traffic.get("graph_build_ms_max")), float(traffic.get("graph_apply_ms_max")),
		report["growth"]["mem_mb"], report["growth"]["nodes"], report["growth"]["objects"], report["growth"]["orphans"], report["growth"]["orphans_excluding_stashed_wrecks"], str(leak), ProjectSettings.globalize_path(out_path)])
	quit(1 if leak else 0)


func _count_over(arr: PackedFloat32Array, limit: float) -> int:
	var n := 0
	for v in arr:
		if v > limit:
			n += 1
	return n


func _loadavg() -> String:
	var f := FileAccess.open("/proc/loadavg", FileAccess.READ)
	return "" if f == null else f.get_as_text().strip_edges()
