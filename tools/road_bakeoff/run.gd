extends "res://tools/road_report.gd"

## Headless bake-off. Measures collision and the drawn surface.
##
##   godot --headless --path <project> -s res://tools/road_bakeoff/run.gd -- --road_strategy=N --site=ID
##
## ID is one entry in sites.json, or "all". Output is bakeoff_out/<strategy>/<site>.json
## and a short markdown file beside it. fps, frame time and draw calls are
## "not_measured_headless".

const SITES_PATH := "res://tools/road_bakeoff/sites.json"
const PINS: Array[Dictionary] = [
	{"x": 3153.0, "z": -6143.0},
	{"x": 3218.0, "z": -6368.0},
	{"x": 3320.0, "z": -6511.0},
	{"x": 3365.0, "z": -6510.0},
]

var _lab := false
var _site: Dictionary = {}
var _strategy_id := 0
var _spec: Dictionary = {}
var _cone_starts: Array = []
var _cone_skipped := 0
var _across_002 := 0
var _cross_excluded := 0
var _lane_grade_max := 0.0
var _fine_ms := 0
var _perrine_m := 1.0e9
var _perrine_fail := false
var _patches: Array[Dictionary] = []


func _initialize() -> void:
	_bakeoff.call_deferred()


func _make_generator():
	if _lab:
		return load("res://scripts/world/road_strategies/road_lab_generator.gd").new()
	return super._make_generator()


func _bakeoff() -> void:
	var wanted := _arg("site")
	if wanted == "":
		wanted = "dev"
	var catalog := _catalog()
	var queue: Array[Dictionary] = []
	if wanted == "all":
		for item in catalog:
			queue.append(item)
	else:
		var found := false
		for item in catalog:
			if str(item.get("id", "")) == wanted:
				queue.append(item)
				found = true
				break
		if not found:
			push_error("unknown site %s" % wanted)
			quit(1)
			return
	_strategy_id = RoadStrategyRegistry.current_id()
	_spec = RoadStrategyRegistry.spec_for(_strategy_id)
	if _strategy_id != 0:
		var strategy := RoadStrategyRegistry.create()
		strategy.fail_unimplemented()
		bakeoff_gap_max = float(_spec.get("gap_max", 0.05))
		for item in queue:
			_site = item
			_write_result({}, "", "", 0.0, 0.0, true)
		quit(1)
		return
	for item in queue:
		await _one(item)
	quit(0)


func _one(site: Dictionary) -> void:
	_site = site
	_lab = str(site.get("kind", "")) == "synthetic"
	bakeoff_mode = true
	bakeoff_force_low = _lab
	bakeoff_load_bridge = not _lab
	bakeoff_gap_max = float(_spec.get("gap_max", 0.05))
	bakeoff_rect_on = true
	bakeoff_rect = _rect_of(site)
	bakeoff_pins = PINS
	print("BAKEOFF strategy=%d site=%s lab=%s" % [_strategy_id, site.get("id", ""), _lab])
	var t0 := Time.get_ticks_msec()
	await _boot_world()
	if _builder == null:
		_write_result({}, "", "", 0.0, 0.0, true)
		return
	var hash_a := collision_hash()
	var build_s := float(Time.get_ticks_msec() - t0) / 1000.0
	var t1 := Time.get_ticks_msec()
	await _boot_world()
	var hash_b := collision_hash()
	var det_s := float(Time.get_ticks_msec() - t1) / 1000.0
	await _measure_all()
	_write_result(_payload(), hash_a, hash_b, build_s, det_s, false)
	print("BAKEOFF site=%s build=%.0f s determinism=%.0f s hash=%s" % [
		site.get("id", ""), build_s, det_s, "match" if hash_a == hash_b else "DIFFER",
	])


func _rect_of(site: Dictionary) -> Rect2:
	var centre: Array = site.get("centre", [0, 0])
	var size: Array = site.get("size", [400, 400])
	var w := float(size[0])
	var h := float(size[1])
	return Rect2(float(centre[0]) - w * 0.5, float(centre[1]) - h * 0.5, w, h)


func _write_result(net_payload: Dictionary, hash_a: String, hash_b: String, build_s: float, det_s: float, stub: bool) -> void:
	var sid := str(_site.get("id", "site"))
	var dir := "res://bakeoff_out/%d" % _strategy_id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var mem_mb := float(OS.get_static_memory_usage()) / (1024.0 * 1024.0)
	var nodes := 0
	if _host != null:
		nodes = count_nodes(_host)
	var road_tris := _bakeoff_faces.size() / 3
	var triangles := _mesh_tris + road_tris
	var net: Dictionary = net_payload.get("network", {})
	var gates := {}
	if stub:
		gates = {"implemented": {"value": 0, "limit": 1, "pass": false}}
	else:
		gates = _gates(net, mem_mb, triangles, hash_a == hash_b)
	var failures := []
	for item in _failures:
		failures.append({
			"gate": str(item.get("test", "")),
			"x": float(item.get("x", 0.0)),
			"z": float(item.get("z", 0.0)),
			"value": float(item.get("value", 0.0)),
		})
	var doc := {
		"strategy": {"id": _strategy_id, "name": str(_spec.get("name", "")), "gap_max_m": bakeoff_gap_max},
		"site": sid,
		"seed": 20261008,
		"git_commit": _git_commit(),
		"gates": gates,
		"failures": failures,
		"failure_counts": _fail_n.duplicate(),
		"determinism_hash": hash_a,
		"determinism_hash_b": hash_b,
		"build_seconds": build_s,
		"stats": {
			"determinism_build_seconds": det_s,
			"samples": int(net.get("samples", 0)),
			"roads": int(net.get("roads", 0)),
			"chunks_note": str(_site.get("notes", "")),
			"node_count": nodes,
			"terrain_triangles": _mesh_tris,
			"road_triangles": road_tris,
			"memory_mb": mem_mb,
			"barrier_samples": _seat_n,
			"junctions": _junctions.size(),
			"junctions_missing_features": _feature_missing,
			"prescreen_step_along_m": _prescreen_max("prescreen_along"),
			"prescreen_step_across_m": _prescreen_max("prescreen_across"),
			"lane_grade_max": _lane_grade_max,
			"cone_diagnostic": "not_simulated",
			"fine_step_seconds": float(_fine_ms) / 1000.0,
			"perrine_nearest_cone_m": _perrine_m if _perrine_m < 1.0e8 else -1.0,
			"perrine_escape_fail": _perrine_fail,
		},
		"junction_patches": _patches_out(),
		"cone_starts": _cone_starts,
		"cone_skipped_outside_built_chunks": _cone_skipped,
		"step_across_at_0_02_fails": _across_002,
		"cross_slope_junction_excluded": _cross_excluded,
		"not_measured_headless": ["fps", "frame_time_ms", "draw_calls"],
	}
	var json_path := "%s/%s.json" % [dir, sid]
	var md_path := "%s/%s.md" % [dir, sid]
	var jf := FileAccess.open(json_path, FileAccess.WRITE)
	if jf == null:
		push_error("bakeoff json failed")
		return
	jf.store_string(JSON.stringify(doc, "\t"))
	jf.close()
	var mf := FileAccess.open(md_path, FileAccess.WRITE)
	if mf != null:
		mf.store_string(_summary(doc))
		mf.close()
	print("BAKEOFF wrote %s" % json_path)


func _gates(net: Dictionary, mem_mb: float, triangles: int, same_hash: bool) -> Dictionary:
	var hit := float(net.get("hit_rate", 0.0))
	var along := float(net.get("max_step_along_m", 0.0))
	var across := float(net.get("max_step_across_m", 0.0))
	var gap_lo := float(net.get("min_gap_m", 0.0))
	var gap_hi := float(net.get("max_gap_m", 0.0))
	var drop := float(net.get("max_edge_drop_m", 0.0))
	var cones := int(net.get("cone_fails", 0))
	var dev := 0.0
	var tilt := 0.0
	var jfail := 0
	for rec in _junctions:
		dev = maxf(dev, float(rec.get("dev", 0.0)))
		tilt = maxf(tilt, float(rec.get("tilt", 0.0)))
		if not bool(rec.get("pass", false)):
			jfail += 1
	var ends := 0
	for id in _order:
		ends += int(_stats[id].get("unclassified", 0))
	return {
		"hit_rate": _gate(hit, 1.0, hit >= 1.0 - 0.0000001 and int(net.get("samples", 0)) > 0),
		"step_along_m": _gate(along, 0.02, along <= 0.02 + 0.0001),
		"step_across_m": _gate(across, 0.03, across <= 0.03 + 0.0001),
		"gap_min_m": _gate(gap_lo, 0.0, gap_lo >= -0.001),
		"gap_max_m": _gate(gap_hi, bakeoff_gap_max, gap_hi <= bakeoff_gap_max + 0.0001),
		"verge_gap_m": _gate(_verge_abs, 0.10, _verge_over == 0),
		"grade": {"value": _grade_max, "limit": "class_cap+0.005", "pass": _grade_over == 0},
		"cross_slope": {"value": _cross_max, "limit": "patch excluded; 10 m blend <= 0.04; else 0.025 or superelevation+0.005", "pass": _cross_over == 0},
		"edge_drop_m": _gate(drop, 3.0, drop <= 3.0 + 0.001),
		"vertical_faces": _gate(_vertical_faces, 0, _vertical_faces == 0),
		"cone_fails": _gate(cones, 0, cones == 0),
		"junction_dev_m": _gate(dev, 0.03, jfail == 0),
		"junction_tilt": {"value": tilt, "limit": "0.02, or 0.03 on a grade >= 6%", "pass": jfail == 0},
		"unclassified_ends": _gate(ends, 0, ends == 0),
		"junction_features_missing": _gate(_feature_missing, 0, _feature_missing == 0),
		"barrier_seat_m": _gate(_seat_max, 0.05, _seat_over == 0),
		"components": _gate(int(net.get("components", 0)), 1, int(net.get("components", 0)) == 1),
		"determinism": _gate(1 if same_hash else 0, 1, same_hash),
		"memory_mb": _gate(mem_mb, 3072.0, mem_mb < 3072.0),
		"triangles": _gate(triangles, 1500000, triangles < 1500000),
	}


func _gate(value, limit, ok: bool) -> Dictionary:
	return {"value": value, "limit": limit, "pass": ok}


func _summary(doc: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var strategy: Dictionary = doc["strategy"]
	lines.append("# Bake-off %s / %s" % [strategy.get("name", ""), doc.get("site", "")])
	lines.append("")
	lines.append("Seed %s. Commit `%s`. Build %.1f s." % [doc.get("seed", ""), doc.get("git_commit", ""), float(doc.get("build_seconds", 0.0))])
	lines.append("")
	lines.append("| Gate | Value | Limit | |")
	lines.append("|---|---:|---:|:---:|")
	var gates: Dictionary = doc["gates"]
	for key in gates.keys():
		var g: Dictionary = gates[key]
		lines.append("| %s | %s | %s | %s |" % [key, g.get("value", ""), g.get("limit", ""), "PASS" if bool(g.get("pass", false)) else "FAIL"])
	lines.append("")
	lines.append("Determinism hash `%s`." % str(doc.get("determinism_hash", "")))
	lines.append("")
	lines.append("Not measured headless: %s." % ", ".join(doc.get("not_measured_headless", [])))
	lines.append("")
	var fails: Array = doc.get("failures", [])
	lines.append("Stored failures: %d (the report keeps the first %d per road per gate)." % [fails.size(), FAIL_CAP])
	lines.append("")
	var shown := 0
	for item in fails:
		if shown >= 30:
			break
		lines.append("- %s at (%.1f, %.1f) = %s" % [item.get("gate", ""), float(item.get("x", 0.0)), float(item.get("z", 0.0)), item.get("value", "")])
		shown += 1
	lines.append("")
	return "\n".join(lines)


func _catalog() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SITES_PATH))
	if parsed is Dictionary:
		var sites: Variant = parsed.get("sites", [])
		if sites is Array:
			return sites
	return []


func _arg(name: String) -> String:
	for raw in OS.get_cmdline_user_args():
		var arg := String(raw)
		var prefix := "--%s=" % name
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return ""


func _git_commit() -> String:
	var out: Array = []
	var code := OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "rev-parse", "HEAD"], out)
	if code != 0 or out.is_empty():
		return ""
	return str(out[0]).strip_edges()


func _reset_scores() -> void:
	super._reset_scores()
	_cone_starts = []
	_cone_skipped = 0
	_across_002 = 0
	_cross_excluded = 0
	_lane_grade_max = 0.0
	_fine_ms = 0
	_perrine_m = 1.0e9
	_perrine_fail = false
	_patches = []


func _road_surface_is_terrain() -> bool:
	# 1 terrain-as-road, 4 and 5 corridor heightfields, 6 TIN, 10 the solved surface.
	return _strategy_id == 1 or _strategy_id == 4 or _strategy_id == 5 or _strategy_id == 6 or _strategy_id == 10


func _counts_as_hit(hit: Dictionary, expected: float) -> bool:
	if not _road_surface_is_terrain():
		return _is_road(hit)
	if hit.is_empty():
		return false
	return absf(float((hit["position"] as Vector3).y) - expected) <= 0.050


func _measure_all() -> void:
	if bakeoff_mode:
		_build_junction_patches()
	await super._measure_all()
	if bakeoff_mode:
		print("BAKEOFF fine=%.1f s skipped_cones=%d across_0_02=%d cross_excluded=%d perrine_m=%.2f perrine_fail=%s" % [
			float(_fine_ms) / 1000.0, _cone_skipped, _across_002, _cross_excluded, _perrine_m, _perrine_fail,
		])


func _measure_road(id: String) -> void:
	super._measure_road(id)
	if bakeoff_mode:
		_fine_steps(id)


func _queue_walks(_road: Dictionary, _pose: Dictionary) -> void:
	if bakeoff_mode:
		return
	super._queue_walks(_road, _pose)


func _queue_pushes(road: Dictionary, pose: Dictionary) -> void:
	if not bakeoff_mode:
		super._queue_pushes(road, pose)
		return
	_queue_edge_gates(road, pose, "every50")
	_record_diagnostic_starts(road, pose)


func _queue_pin_cones() -> void:
	if not bakeoff_mode:
		super._queue_pin_cones()
		return
	for pin in bakeoff_pins:
		var x := float(pin["x"])
		var z := float(pin["z"])
		if not _in_site(x, z):
			continue
		var found := _nearest_pose(x, z)
		if found.is_empty():
			_blame("pin", "cone_pin", x, z, 1.0e9, 40.0)
			continue
		if float(found["d"]) > 40.0:
			_blame("pin", "cone_pin", x, z, float(found["d"]), 40.0)
			continue
		var road: Dictionary = found["road"]
		var pose: Dictionary = found["pose"]
		_sample_edge(str(road["id"]), pose, true, false)
		_sample_edge(str(road["id"]), pose, false, false)
		_queue_edge_gates(road, pose, "pin")


func _end_kind(road: Dictionary, index: int) -> String:
	if not bakeoff_mode:
		return super._end_kind(road, index)
	var tag := ""
	if index == 0 and road.has("start_kind"):
		tag = str(road["start_kind"])
	elif index != 0 and road.has("end_kind"):
		tag = str(road["end_kind"])
	if tag != "":
		return tag
	return "unclassified"


func _score_push(job: Dictionary, body: RigidBody3D) -> void:
	if not bakeoff_mode or not bool(job.get("gate", false)):
		super._score_push(job, body)
		return
	var center := body.global_position
	var end_built := _chunk_built(center.x, center.z)
	if not bool(job.get("built", false)) or not end_built:
		_cone_skipped += 1
		return
	var id := str(job["id"])
	var road_y := float(job["y"])
	var barrier := bool(job.get("barrier", false))
	var up_from := center + Vector3(0, 0.05, 0)
	var up := _ray(up_from, up_from + Vector3(0, 1.1, 0))
	var stuck := false
	if not up.is_empty() and not _is_ground(up):
		var at: Vector3 = up["position"]
		if at.y - (center.y - 0.2) < 1.0 and center.y < road_y - 0.05:
			stuck = true
	var down := _ray(center + Vector3(0, 0.6, 0), center + Vector3(0, -25.0, 0))
	var on_road := false
	var surface_y := road_y
	if not down.is_empty() and _is_road(down):
		on_road = true
		surface_y = float((down["position"] as Vector3).y)
	var below := on_road and center.y < surface_y - 0.02
	var supported := false
	if not down.is_empty():
		var ground_y := float((down["position"] as Vector3).y)
		supported = center.y - ground_y < 0.8 and center.y - ground_y > -0.2
	var drop := road_y - center.y
	var side := _exit_side(job, center)
	var escaped := side != 0.0
	var falling := body.linear_velocity.y < -0.8 and not supported
	var fail := false
	var why := ""
	if barrier:
		if stuck or below or escaped or not on_road:
			fail = true
			why = "contained"
	else:
		if stuck or below or not supported or falling or drop > 3.0:
			fail = true
			why = "rest"
	_note_perrine(center, fail)
	if fail:
		_cone_fail(id, "cone_" + str(job.get("edge", job.get("label", "edge"))), center.x, center.z, drop, why)
	else:
		_cone_ok(id)


func _note_perrine(center: Vector3, fail: bool) -> void:
	var d := Vector2(center.x - 3353.0, center.z + 6626.4).length()
	if d + 0.001 < _perrine_m:
		_perrine_m = d
		_perrine_fail = fail
	elif d <= _perrine_m + 0.001:
		_perrine_fail = _perrine_fail or fail
	elif d < 8.0 and fail:
		_perrine_fail = true


func _queue_edge_gates(road: Dictionary, pose: Dictionary, kind: String) -> void:
	_add_gate_cone(road, pose, false, kind)
	_add_gate_cone(road, pose, true, kind)


func _add_gate_cone(road: Dictionary, pose: Dictionary, left: bool, kind: String) -> void:
	var edge_name := "left" if left else "right"
	var angle := -90.0 if left else 90.0
	var dir: Vector3 = pose["out_l"] if left else pose["out_r"]
	var barrier := _edge_barrier(road, pose, left)
	var built := _chunk_built(float(pose["x"]), float(pose["z"]))
	_cone_starts.append(_start_row(float(pose["x"]), float(pose["z"]), edge_name, kind, 0.0, angle, barrier, built))
	if not built:
		_cone_skipped += 1
		return
	var job: Dictionary = _push_job(str(road["id"]), pose, 0.0, dir, edge_name)
	job["gate"] = true
	job["built"] = true
	job["barrier"] = barrier
	job["edge"] = edge_name
	job["kind"] = kind
	_pushes.append(job)


func _record_diagnostic_starts(road: Dictionary, pose: Dictionary) -> void:
	# Listed so the scorecard can see the launches. Not simulated: a second
	# physics pass on top of the 0.05 m step sweep is not the cheap extra.
	var offsets := _diag_offsets(road)
	var angles: Array[float] = [60.0, 90.0, 120.0]
	for lat in offsets:
		for mag in angles:
			for left in [true, false]:
				var angle := -mag if left else mag
				if absf(float(lat)) < 0.001 and absf(mag - 90.0) < 0.001:
					continue
				var at := _at_lat(pose, float(lat)) if absf(float(lat)) <= float(pose["half"]) + 0.001 else _beyond_edge(pose, float(lat))
				var built := _chunk_built(float(at["x"]), float(at["z"]))
				_cone_starts.append(_start_row(float(at["x"]), float(at["z"]), "left" if left else "right", "diagnostic", float(lat), angle, _edge_barrier(road, pose, left), built))


func _start_row(x: float, z: float, edge: String, kind: String, lane_offset: float, angle: float, barrier: bool, built: bool) -> Dictionary:
	return {
		"x": x,
		"z": z,
		"edge": edge,
		"kind": kind,
		"lane_offset": lane_offset,
		"angle": angle,
		"barrier": barrier,
		"built": built,
	}


func _edge_barrier(road: Dictionary, pose: Dictionary, left: bool) -> bool:
	var kind := str(pose.get("kind", ""))
	if kind == "deck" or kind == "bridge":
		return true
	if str(road.get("class", "")) == "rim_local" or str(road.get("id", "")) == "rim_road_south":
		return true
	return bool(pose.get("bar_l", false)) if left else bool(pose.get("bar_r", false))


func _diag_offsets(road: Dictionary) -> Array[float]:
	var offs: Array[float] = [0.0]
	var lane_w := float(road.get("lane_w", 3.3))
	var lanes := maxi(int(road.get("lanes", 1)), 1)
	var half := float(road["half"])
	var i := 0
	while i < lanes:
		offs.append(-half + (float(i) + 0.5) * lane_w)
		i += 1
	if half > 0.45:
		offs.append(half - 0.4)
		offs.append(-(half - 0.4))
	return offs


func _chunk_built(x: float, z: float) -> bool:
	var home := WorldConfig.chunk_of(x, z)
	return _built_chunk_ids.has(home)


func _nearest_pose(x: float, z: float) -> Dictionary:
	var best_id := ""
	var best_s := 0.0
	var best_d := 1.0e9
	for id in _order:
		var candidate: Dictionary = _builder._roads[int(_builder._by_id[id])]
		var chain: PackedFloat32Array = candidate["chain"]
		if chain.size() < 2:
			continue
		var length := float(chain[chain.size() - 1])
		var s := 0.0
		while s <= length + 0.01:
			var pose := _pose(candidate, minf(s, length))
			var d := Vector2(float(pose["x"]) - x, float(pose["z"]) - z).length()
			if d < best_d:
				best_d = d
				best_id = id
				best_s = s
			s += 4.0
	if best_id == "":
		return {}
	var road: Dictionary = _builder._roads[int(_builder._by_id[best_id])]
	return {"road": road, "pose": _pose(road, best_s), "d": best_d}


func _prescreen_max(key: String) -> float:
	var worst := 0.0
	for id in _order:
		worst = maxf(worst, float(_stats[id].get(key, 0.0)))
	return worst


func _patches_out() -> Array:
	var out: Array = []
	for item in _patches:
		out.append({"id": str(item["id"]), "polygon": item["polygon"]})
	return out


func _bakeoff_station(road: Dictionary, pose: Dictionary, s: float) -> void:
	var id := str(road["id"])
	var zone := _slope_zone(float(pose["x"]), float(pose["z"]))
	if zone == "patch":
		_cross_excluded += 1
	else:
		var half := maxf(float(pose["half"]), 0.5)
		var ly := _own_surface_y(Vector3(float(pose["lx"]), float(pose["ly"]), float(pose["lz"])), float(pose["ly"]))
		var ry := _own_surface_y(Vector3(float(pose["rx"]), float(pose["ry"]), float(pose["rz"])), float(pose["ry"]))
		var width := half * 2.0
		var measured := (ry - ly) / width
		var sec: Vector3 = pose["sec"]
		var design := (sec.z - sec.x) / width
		var shown := absf(measured)
		var bad := false
		var limit := 0.025
		if zone == "blend":
			limit = 0.04
			bad = shown > 0.04 + 0.0001
		else:
			bad = shown > 0.025 + 0.0001
			if absf(design) > 0.025:
				limit = 0.005
				var residual := absf(measured - design)
				bad = residual > 0.005 + 0.0001
				shown = residual
		if shown > _cross_max:
			_cross_max = shown
		if bad:
			_cross_over += 1
			_blame(id, "cross_slope", float(pose["x"]), float(pose["z"]), shown, limit)
	if not bool(pose["elevated"]):
		var outer := float(road.get("shoulder", 0.0)) + float(road.get("ditch", 0.0))
		if outer > 0.05:
			_verge_at(id, pose, true, outer)
			_verge_at(id, pose, false, outer)
	var length := float(road["chain"][road["chain"].size() - 1])
	var mark := s <= 0.01 or s >= length - 0.05 or fmod(s, 10.0) < 0.05
	if not mark:
		return
	var cy := _own_surface_y(Vector3(float(pose["x"]), float(pose["y"]), float(pose["z"])), float(pose["y"]))
	if _last_grade.has(id):
		var prev: Dictionary = _last_grade[id]
		var ds := s - float(prev["s"])
		if ds >= 5.0:
			var grade := absf(cy - float(prev["y"])) / ds
			if grade > _grade_max:
				_grade_max = grade
			var cap := float(road.get("cap", 0.06)) + 0.005
			if grade > cap + 0.000001:
				_grade_over += 1
				_blame(id, "grade", float(pose["x"]), float(pose["z"]), grade, cap)
	_last_grade[id] = {"s": s, "y": cy}


func _own_surface_y(at: Vector3, expected: float) -> float:
	var hit := _ray(at + Vector3(0, 2.0, 0), at + Vector3(0, -80.0, 0))
	if not _counts_as_hit(hit, expected):
		return expected
	if _road_surface_is_terrain():
		return float((hit["position"] as Vector3).y)
	return _driving_y(at, expected, hit)


func _fine_steps(id: String) -> void:
	var t0 := Time.get_ticks_msec()
	var road: Dictionary = _builder._roads[int(_builder._by_id[id])]
	var chain: PackedFloat32Array = road["chain"]
	if chain.size() < 2:
		return
	var length := float(chain[chain.size() - 1])
	var reach := float(road["half"]) + float(road.get("shoulder", 0.0)) + float(road.get("ditch", 0.0))
	var stripes := _along_offsets(road, reach)
	var rays := 0
	for lat in stripes:
		var lane_line := _is_lane_line(road, lat)
		var prev_y := 0.0
		var prev_e := 0.0
		var have := false
		var mark_s := -1.0
		var mark_y := 0.0
		var s := 0.0
		while true:
			var pose := _pose_fast(road, minf(s, length))
			var outside := not _in_site(float(pose["x"]), float(pose["z"]))
			var off_deck := bool(pose["elevated"]) and absf(lat) > float(pose["half"]) + 0.001
			if outside or off_deck:
				have = false
				mark_s = -1.0
			else:
				var sample := _stripe_sample(pose, lat)
				rays += 1
				if not bool(sample["hit"]):
					have = false
					mark_s = -1.0
				else:
					var hit_y := float(sample["y"])
					var ey := float(sample["ey"])
					if have:
						var residual := absf((hit_y - prev_y) - (ey - prev_e))
						var st: Dictionary = _stats[id]
						if residual > float(st["max_step_along"]):
							st["max_step_along"] = residual
						if residual > STEP_ALONG + 0.0001:
							_blame(id, "step_along", float(sample["x"]), float(sample["z"]), residual, STEP_ALONG)
					if lane_line:
						if mark_s < 0.0:
							mark_s = s
							mark_y = hit_y
						elif s - mark_s >= 9.5:
							var grade := absf(hit_y - mark_y) / maxf(s - mark_s, 0.001)
							if grade > _lane_grade_max:
								_lane_grade_max = grade
							mark_s = s
							mark_y = hit_y
					prev_y = hit_y
					prev_e = ey
					have = true
			if s >= length - 0.0001:
				break
			s = minf(s + 0.05, length)
	var s2 := 0.0
	while s2 <= length + 0.001:
		var pose2 := _pose_fast(road, minf(s2, length))
		if _in_site(float(pose2["x"]), float(pose2["z"])):
			var span := reach
			if bool(pose2["elevated"]):
				span = float(pose2["half"])
			var lat2 := -span
			var prev_y2 := 0.0
			var prev_e2 := 0.0
			var have2 := false
			while lat2 <= span + 0.001:
				var sample2 := _stripe_sample(pose2, lat2)
				rays += 1
				if not bool(sample2["hit"]):
					have2 = false
				else:
					var hit_y2 := float(sample2["y"])
					var ey2 := float(sample2["ey"])
					if have2:
						var residual2 := absf((hit_y2 - prev_y2) - (ey2 - prev_e2))
						var st2: Dictionary = _stats[id]
						if residual2 > float(st2["max_step_across"]):
							st2["max_step_across"] = residual2
						if residual2 > 0.02 + 0.0001:
							_across_002 += 1
						if residual2 > STEP_ACROSS + 0.0001:
							_blame(id, "step_across", float(sample2["x"]), float(sample2["z"]), residual2, STEP_ACROSS)
					prev_y2 = hit_y2
					prev_e2 = ey2
					have2 = true
				lat2 += 0.05
		if s2 >= length - 0.0001:
			break
		s2 = minf(s2 + 1.0, length)
	_fine_ms += Time.get_ticks_msec() - t0
	print("FINE %s rays=%d ms=%d along=%.4f across=%.4f" % [
		id, rays, Time.get_ticks_msec() - t0,
		float(_stats[id]["max_step_along"]), float(_stats[id]["max_step_across"]),
	])


func _pose_fast(road: Dictionary, s: float) -> Dictionary:
	var chain: PackedFloat32Array = road["chain"]
	var lo := 0
	var hi := chain.size() - 1
	while lo + 1 < hi:
		var mid := (lo + hi) >> 1
		if float(chain[mid]) < s:
			lo = mid
		else:
			hi = mid
	var pts: PackedVector3Array = road["pts"]
	var left: PackedVector3Array = road["left"]
	var right: PackedVector3Array = road["right"]
	var bank: PackedFloat32Array = road["bank"]
	var crown: PackedFloat32Array = road["crown"]
	var kinds: PackedStringArray = road["kind"]
	var i := clampi(lo, 0, pts.size() - 2)
	var span := maxf(float(chain[i + 1] - chain[i]), 0.001)
	var t := clampf((s - float(chain[i])) / span, 0.0, 1.0)
	var p := pts[i].lerp(pts[i + 1], t)
	var lp := left[i].lerp(left[i + 1], t)
	var rp := right[i].lerp(right[i + 1], t)
	var half := float(road["half"])
	var b := lerpf(float(bank[i]), float(bank[i + 1]), t)
	var c := lerpf(float(crown[i]), float(crown[i + 1]), t)
	var kind := kinds[i] if i < kinds.size() else "grade"
	if t >= 0.999 and i + 1 < kinds.size():
		var nxt := kinds[i + 1]
		if nxt == "deck" or nxt == "bridge":
			kind = nxt
	var elevated := kind == "deck" or kind == "bridge" or bool(road["rail"])
	var sec := Vector3(p.y, p.y, p.y) if elevated else _builder._section(p.y, b, c, half)
	lp.y = sec.x
	rp.y = sec.z
	var tangent := _flat_dir(pts[i + 1] - pts[i])
	var across := Vector3(rp.x - lp.x, 0.0, rp.z - lp.z)
	var out_l := Vector3.ZERO
	var out_r := Vector3.ZERO
	if across.length_squared() > 0.01:
		var side := across.normalized()
		out_r = side
		out_l = -side
	var lanes := maxi(int(road["lanes"]), 1)
	return {
		"x": p.x, "z": p.z, "y": sec.y, "hit_y": sec.y,
		"lx": lp.x, "ly": lp.y, "lz": lp.z,
		"rx": rp.x, "ry": rp.y, "rz": rp.z,
		"half": half, "sec": sec, "tangent": tangent,
		"out_l": out_l, "out_r": out_r,
		"elevated": elevated, "kind": kind,
		"lane": half * (1.0 - 1.0 / float(lanes)),
		"gap_l": 0.0, "gap_r": 0.0, "bar_l": false, "bar_r": false,
	}


func _stripe_sample(pose: Dictionary, lat: float) -> Dictionary:
	var at: Dictionary = _at_lat(pose, lat) if absf(lat) <= float(pose["half"]) + 0.001 else _beyond_edge(pose, lat)
	var expected := float(at["ey"])
	var hit := _ray(Vector3(float(at["x"]), expected + 2.0, float(at["z"])), Vector3(float(at["x"]), expected - 80.0, float(at["z"])))
	if not _counts_as_hit(hit, expected):
		return {"hit": false, "x": float(at["x"]), "z": float(at["z"]), "y": expected, "ey": expected}
	var y := expected
	if _road_surface_is_terrain():
		y = float((hit["position"] as Vector3).y)
	else:
		y = _driving_y(Vector3(float(at["x"]), expected, float(at["z"])), expected, hit)
	return {"hit": true, "x": float(at["x"]), "z": float(at["z"]), "y": y, "ey": expected}


func _along_offsets(road: Dictionary, reach: float) -> Array[float]:
	var raw: Array[float] = []
	var lat := -reach
	while lat <= reach + 0.001:
		raw.append(lat)
		lat += 0.5
	var lane_w := float(road.get("lane_w", 0.0))
	var half := float(road["half"])
	var n := int(road.get("lanes", 1))
	if lane_w > 0.2:
		var i := 0
		while i <= n:
			raw.append(-half + float(i) * lane_w)
			i += 1
	var uniq: Array[float] = []
	for v in raw:
		if _stripe_excluded(road, v):
			continue
		if absf(v) > reach + 0.001:
			continue
		var seen := false
		for u in uniq:
			if absf(u - v) < 0.02:
				seen = true
				break
		if not seen:
			uniq.append(v)
	return uniq


func _stripe_excluded(road: Dictionary, lat: float) -> bool:
	if absf(lat) <= 0.05:
		return true
	if int(road.get("lanes", 1)) >= 4 and absf(lat) <= 0.30:
		return true
	return false


func _is_lane_line(road: Dictionary, lat: float) -> bool:
	var lane_w := float(road.get("lane_w", 0.0))
	if lane_w < 0.5:
		return false
	var half := float(road["half"])
	var n := int(road.get("lanes", 1))
	var i := 0
	while i <= n:
		if absf(lat - (-half + float(i) * lane_w)) <= 0.05:
			return absf(lat) > 0.05
		i += 1
	return false


func _build_junction_patches() -> void:
	_patches = []
	var i := 0
	for item in _builder._junctions:
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var poly := _patch_polygon(item)
		if poly.size() < 3:
			continue
		var ring: Array = []
		var near := _in_site(float(pos[0]), float(pos[2]))
		for p in poly:
			ring.append([p.x, p.y])
			if _in_site(p.x, p.y):
				near = true
		if not near:
			i += 1
			continue
		_patches.append({
			"id": str(item.get("id", "j%d" % i)),
			"polygon": ring,
			"poly": poly,
		})
		i += 1


func _patch_polygon(item: Dictionary) -> PackedVector2Array:
	var pos: Array = item.get("pos", [])
	var cx := float(pos[0])
	var cz := float(pos[2])
	var radius := float(item.get("radius", 8.0))
	var pts: Array[Vector2] = []
	pts.append(Vector2(cx, cz))
	for rid in item.get("roads", []):
		if not _builder._by_id.has(str(rid)):
			continue
		var road: Dictionary = _builder._roads[int(_builder._by_id[str(rid)])]
		var chain: PackedFloat32Array = road["chain"]
		if chain.size() < 2:
			continue
		var length := float(chain[chain.size() - 1])
		var s := 0.0
		while s <= length + 0.01:
			var pose := _pose(road, minf(s, length))
			if Vector2(float(pose["x"]) - cx, float(pose["z"]) - cz).length() <= radius:
				pts.append(Vector2(float(pose["x"]), float(pose["z"])))
				pts.append(Vector2(float(pose["lx"]), float(pose["lz"])))
				pts.append(Vector2(float(pose["rx"]), float(pose["rz"])))
			s += 2.0
	var hull := _convex_hull(pts)
	if hull.size() < 3:
		return hull
	return _expand_hull(hull, 1.0)


func _convex_hull(pts: Array[Vector2]) -> PackedVector2Array:
	var clean: Array[Vector2] = []
	for p in pts:
		var dup := false
		for q in clean:
			if p.distance_squared_to(q) < 0.01:
				dup = true
				break
		if not dup:
			clean.append(p)
	if clean.size() < 3:
		var tiny := PackedVector2Array()
		for p in clean:
			tiny.append(p)
		return tiny
	clean.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.x < b.x or (is_equal_approx(a.x, b.x) and a.y < b.y)
	)
	var lower: Array[Vector2] = []
	var upper: Array[Vector2] = []
	for p in clean:
		while lower.size() >= 2 and _turn(lower[lower.size() - 2], lower[lower.size() - 1], p) <= 0.0:
			lower.remove_at(lower.size() - 1)
		lower.append(p)
	var i := clean.size() - 1
	while i >= 0:
		var p: Vector2 = clean[i]
		while upper.size() >= 2 and _turn(upper[upper.size() - 2], upper[upper.size() - 1], p) <= 0.0:
			upper.remove_at(upper.size() - 1)
		upper.append(p)
		i -= 1
	if lower.size() > 0:
		lower.remove_at(lower.size() - 1)
	if upper.size() > 0:
		upper.remove_at(upper.size() - 1)
	var hull := PackedVector2Array()
	for p in lower:
		hull.append(p)
	for p in upper:
		hull.append(p)
	return hull


func _turn(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)


func _expand_hull(hull: PackedVector2Array, dist: float) -> PackedVector2Array:
	var n := hull.size()
	var out := PackedVector2Array()
	for i in n:
		var prev: Vector2 = hull[(i - 1 + n) % n]
		var cur: Vector2 = hull[i]
		var nxt: Vector2 = hull[(i + 1) % n]
		var d0 := (cur - prev).normalized()
		var d1 := (nxt - cur).normalized()
		var n0 := Vector2(d0.y, -d0.x)
		var n1 := Vector2(d1.y, -d1.x)
		var bis := n0 + n1
		if bis.length() < 0.001:
			bis = n0
		else:
			bis = bis.normalized()
		var denom := bis.dot(n0)
		var miter := dist
		if absf(denom) > 0.25:
			miter = dist / denom
		miter = minf(miter, dist * 3.0)
		out.append(cur + bis * miter)
	return out


func _slope_zone(x: float, z: float) -> String:
	var p := Vector2(x, z)
	var best := 1.0e9
	var inside := false
	for item in _patches:
		var poly: PackedVector2Array = item["poly"]
		if _point_in_poly(p, poly):
			inside = true
			break
		best = minf(best, _dist_to_poly(p, poly))
	if inside:
		return "patch"
	if best <= 10.0:
		return "blend"
	return "open"


func _point_in_poly(p: Vector2, poly: PackedVector2Array) -> bool:
	var n := poly.size()
	if n < 3:
		return false
	var inside := false
	var j := n - 1
	for i in n:
		var a := poly[i]
		var b := poly[j]
		var dy := b.y - a.y
		if (a.y > p.y) != (b.y > p.y) and absf(dy) > 0.0000001:
			var xint := (b.x - a.x) * (p.y - a.y) / dy + a.x
			if p.x < xint:
				inside = not inside
		j = i
	return inside


func _dist_to_poly(p: Vector2, poly: PackedVector2Array) -> float:
	var n := poly.size()
	var best := 1.0e9
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		best = minf(best, _dist_to_seg(p, a, b))
	return best


func _dist_to_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var den := ab.length_squared()
	if den < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / den, 0.0, 1.0)
	return p.distance_to(a + ab * t)
