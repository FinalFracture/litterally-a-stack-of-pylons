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
	# The harness used to treat every id except 0 as a stub and exit before
	# the world was built. A strategy that returns a builder now runs.
	# A stub still returns null from make_builder() and fails here.
	if _strategy_id != 0:
		var strategy := RoadStrategyRegistry.create()
		var probe = strategy.make_builder()
		if probe == null:
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
		},
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
		"cross_slope": {"value": _cross_max, "limit": "0.025 or superelevation+0.005", "pass": _cross_over == 0},
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
