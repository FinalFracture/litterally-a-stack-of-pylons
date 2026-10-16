extends SceneTree

## RS-1 measure-only network report. Reads roads.json through TfRoadBuilder,
## builds chunk collision, and writes res://_diag/road_report.json and
## res://_diag/road_report.md. It does not edit the road builder or the tiles.
##
## Thresholds are the Road System Spec acceptance table (2026-10-16):
##   downward ray from +2 m hits road collision on 100% of samples
##   along step <= 0.02 m, across step <= 0.03 m beyond the design cross-slope
##   road surface - terrain in [0, 0.05] m (deck and bridge are exempt; the stamp is skipped)
##   edge drop within 3 m with no barrier <= 3 m
##   cone push never falls through the carriageway, escapes a barrier, or gets stuck under geometry
##   junction deviation <= 0.03 m and tilt <= 2% (3% when an approach grade is >= 6%)
## Along step is the break between 1 m samples (second difference), so a steady grade is not a lip.
## Cone headings are straight, +45 deg and -45 deg from the tangent, plus a straight push off each edge.
## Walks ride the terrain outside barriers and into fill ends.
##
## Height for the step and gap tests is the driving surface, not the first face
## the ray meets. Parapet tops, wing walls and fill shells sit in the same body
## as the carriageway. A hit counts as a road hit either way. The height used
## for the step and the gap is the first road face whose normal is walkable and
## whose height is within 0.20 m of the design. If none is, the first road hit
## is kept, so a carriageway that is actually in the wrong place still fails.

const SAMPLE_M := 1.0
const ACROSS_M := 0.5
const CONE_M := 50.0
const PUSH_SPEED := 5.0
const STEP_ALONG := 0.02
const STEP_ACROSS := 0.03
const GAP_MAX := 0.05
const DROP_MAX := 3.0
const JUNC_DEV := 0.03
const JUNC_TILT := 0.02
const JUNC_TILT_STEEP := 0.03
const CONE_BELOW := 0.15
const FAIL_CAP := 14
const REGRESSIONS: Array[Dictionary] = [
	{"id": "float_skirt_3153", "x": 3153.0, "z": -6143.0, "note": "float and skirts"},
	{"id": "float_skirt_3218", "x": 3218.0, "z": -6368.0, "note": "float and skirts"},
	{"id": "float_skirt_3320", "x": 3320.0, "z": -6511.0, "note": "float and skirts"},
	{"id": "raised_strip_3365", "x": 3365.0, "z": -6510.0, "note": "raised strip"},
	{"id": "pole_3491", "x": 3491.4, "z": -2494.1, "note": "RL-INT-01 pole outside every carriageway", "check": "pole"},
	{"id": "pole_3417", "x": 3417.2, "z": -4994.1, "note": "RL-INT-01 pole outside every carriageway", "check": "pole"},
	{"id": "paint_crown", "x": 0.0, "z": 0.0, "note": "RL-INT-02 paint follows the crowned surface", "check": "paint"},
	{"id": "step_visitor", "x": 3363.4, "z": -6511.8, "note": "RL-INT-05 visitor T", "check": "step"},
	{"id": "step_rim", "x": 3373.0, "z": -6338.5, "note": "RL-INT-05 rim T", "check": "step"},
	{"id": "step_canyon", "x": 3387.5, "z": -6000.0, "note": "RL-INT-05 canyon springs", "check": "step"},
	{"id": "lane_taper", "x": 3378.6, "z": -6300.0, "note": "RL-INT-08 US-93 lane taper", "check": "taper"},
	{"id": "hole_3373", "x": 3373.0, "z": -6486.0, "note": "2 m hole on the south approach", "check": "hole"},
	{"id": "bridge_ceiling", "x": 3378.8, "z": -6627.3, "note": "ceiling beside the bridge span", "check": "ceiling"},
	{"id": "map_addison", "x": 5005.0, "z": -2500.0, "note": "map-edge exit on solid ground", "check": "exit"},
	{"id": "map_falls", "x": 5005.0, "z": -5000.0, "note": "map-edge exit on solid ground", "check": "exit"},
	{"id": "map_pole", "x": 5005.0, "z": -4200.0, "note": "map-edge exit on solid ground", "check": "exit"},
]

var _gen: TwinFallsTerrainGenerator
var _builder: TfRoadBuilder
var _space: PhysicsDirectSpaceState3D
var _host: Node3D
var _stats: Dictionary = {}
var _order: PackedStringArray = PackedStringArray()
var _failures: Array[Dictionary] = []
var _fail_n: Dictionary = {}
var _worst: Array[Dictionary] = []
var _junctions: Array[Dictionary] = []
var _regressions: Array[Dictionary] = []
var _pushes: Array[Dictionary] = []
var _fill_ends: Array[Dictionary] = []
var _components := 1
var _cone_tests := 0
var _cone_fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	_gen = load("res://scripts/world/twin_falls_terrain_generator.gd").new()
	_gen.prepare()
	_builder = _gen._roads
	_host = Node3D.new()
	_host.name = "RoadReport"
	root.add_child(_host)
	_index_roads()
	var coords := _chunks()
	print("ROAD_REPORT roads=%d chunks=%d" % [_order.size(), coords.size()])
	_build_chunks(coords)
	_load_bridge()
	await physics_frame
	await physics_frame
	_space = _host.get_world_3d().direct_space_state
	for id in _order:
		_measure_road(id)
		_grade_road(id)
	_measure_junctions()
	_measure_ends()
	_components = _components_of()
	_geometric_regressions()
	await _cones()
	_apply_junctions()
	_finish_status()
	var payload := _payload()
	var paths := _write(payload)
	_print_lines(payload)
	print("ROAD_REPORT wrote %s and %s in %d s" % [paths[0], paths[1], (Time.get_ticks_msec() - t0) / 1000])
	quit(0)


func _index_roads() -> void:
	for road in _builder._roads:
		if bool(road["rail"]):
			continue
		var id := str(road["id"])
		var chain: PackedFloat32Array = road["chain"]
		var metres := 0.0 if chain.is_empty() else float(chain[chain.size() - 1])
		_order.append(id)
		_stats[id] = {
			"id": id,
			"name": str(_builder._name_of.get(id, id)),
			"metres": metres,
			"samples": 0,
			"hits": 0,
			"misses": 0,
			"max_step_along": 0.0,
			"max_step_across": 0.0,
			"max_gap": 0.0,
			"min_gap": 0.0,
			"gap_n": 0,
			"max_drop": 0.0,
			"max_drop_at": [0.0, 0.0],
			"cone_tests": 0,
			"cone_fails": 0,
			"junc_dev": 0.0,
			"junc_tilt": 0.0,
			"junc_limit": JUNC_TILT,
			"junc_n": 0,
			"unclassified": 0,
			"ends": [],
			"hit_pass": true,
			"step_pass": true,
			"gap_pass": true,
			"drop_pass": true,
			"cone_pass": true,
			"junc_pass": true,
			"end_pass": true,
			"status": "FAIL",
			"_y0": -99999.0,
			"_y1": -99999.0,
			"_gap_seen": false,
		}


func _chunks() -> Array[Vector2i]:
	var bag := {}
	for road in _builder._roads:
		if bool(road["rail"]):
			continue
		var chain: PackedFloat32Array = road["chain"]
		if chain.is_empty():
			continue
		var length := float(chain[chain.size() - 1])
		var s := 0.0
		while s <= length + 0.01:
			var pose := _pose(road, s)
			_pad_chunk(bag, pose["x"], pose["z"])
			_pad_chunk(bag, pose["lx"], pose["lz"])
			_pad_chunk(bag, pose["rx"], pose["rz"])
			s += 25.0
	for item in _builder._junctions:
		var pos: Array = item.get("pos", [])
		if pos.size() >= 3:
			_pad_chunk(bag, float(pos[0]), float(pos[2]))
	for spot in REGRESSIONS:
		_pad_chunk(bag, float(spot["x"]), float(spot["z"]))
	var out: Array[Vector2i] = []
	for key in bag.keys():
		out.append(key)
	return out


func _pad_chunk(bag: Dictionary, x: float, z: float) -> void:
	var home := WorldConfig.chunk_of(x, z)
	bag[home] = true
	var origin := WorldConfig.chunk_origin(home)
	if x - origin.x < 40.0:
		bag[home + Vector2i(-1, 0)] = true
	if origin.x + 500.0 - x < 40.0:
		bag[home + Vector2i(1, 0)] = true
	if z - origin.y < 40.0:
		bag[home + Vector2i(0, -1)] = true
	if origin.y + 500.0 - z < 40.0:
		bag[home + Vector2i(0, 1)] = true


func _build_chunks(coords: Array[Vector2i]) -> void:
	var n := 0
	for coord in coords:
		var dc := _gen._data_of(coord)
		if dc.x < 0:
			continue
		var t0 := Time.get_ticks_msec()
		var pay = _gen._build(coord, dc, _gen._is_hi(dc.x, dc.y))
		var chunk := Node3D.new()
		chunk.name = "C_%d_%d" % [coord.x, coord.y]
		_host.add_child(chunk)
		_gen._job_body(chunk, pay)
		var pack: Dictionary = pay.roads
		if not pack.is_empty():
			var face_v: Variant = pack.get("faces", null)
			if face_v is PackedVector3Array and (face_v as PackedVector3Array).size() >= 9:
				_builder._job_body(chunk, face_v)
		pay.parts = []
		n += 1
		print("CHUNK %s %d ms" % [coord, Time.get_ticks_msec() - t0])
	print("CHUNKS_BUILT %d" % n)


func _load_bridge() -> void:
	for mark in _builder._marks:
		if str(mark["id"]) == "perrine_bridge":
			_builder._job_mark(_host, mark)
			print("BRIDGE loaded")
			return
	print("BRIDGE missing")


func _measure_road(id: String) -> void:
	var road: Dictionary = _builder._roads[int(_builder._by_id[id])]
	var chain: PackedFloat32Array = road["chain"]
	if chain.size() < 2:
		return
	var length := float(chain[chain.size() - 1])
	var s := 0.0
	var prev_gap_l := 0.0
	var prev_gap_r := 0.0
	var have_prev := false
	while true:
		var pose := _pose(road, minf(s, length))
		_sample_station(road, pose, s)
		# Cone stations every 50 m, including the start. The pose already has barrier flags.
		if s <= 0.01 or is_equal_approx(fmod(s, CONE_M), 0.0):
			_queue_pushes(road, pose)
			_queue_walks(road, pose)
		_watch_fill(id, pose, true, prev_gap_l, have_prev)
		_watch_fill(id, pose, false, prev_gap_r, have_prev)
		prev_gap_l = float(pose["gap_l"])
		prev_gap_r = float(pose["gap_r"])
		have_prev = true
		if s >= length - 0.001:
			break
		s = minf(s + SAMPLE_M, length)
	print("MEASURED %s samples=%d" % [id, int(_stats[id]["samples"])])


func _sample_station(road: Dictionary, pose: Dictionary, s: float) -> void:
	var id := str(road["id"])
	var st: Dictionary = _stats[id]
	var half := float(pose["half"])
	var lats: Array[float] = []
	var lat := -half
	while lat <= half + 0.001:
		lats.append(lat)
		lat += ACROSS_M
	if lats.is_empty() or absf(lats[lats.size() - 1] - half) > 0.02:
		lats.append(half)
	var prev_y := 0.0
	var prev_e := 0.0
	var have := false
	var cy := float(pose["y"])
	var cy_dist := 1.0e9
	for offset in lats:
		var at := _at_lat(pose, offset)
		var expected := float(at["ey"])
		var hit := _ray(Vector3(at["x"], expected + 2.0, at["z"]), Vector3(at["x"], expected - 80.0, at["z"]))
		st["samples"] = int(st["samples"]) + 1
		var hit_y := expected
		var road_hit := _is_road(hit)
		if road_hit:
			st["hits"] = int(st["hits"]) + 1
			hit_y = _driving_y(Vector3(at["x"], expected, at["z"]), expected, hit)
		else:
			st["misses"] = int(st["misses"]) + 1
			_blame(id, "hit", at["x"], at["z"], 0.0, 1.0)
		if not bool(pose["elevated"]):
			var ground := _gen.drawn_height_at(at["x"], at["z"])
			if ground > -70.0 and road_hit:
				var gap := hit_y - ground
				if not bool(st["_gap_seen"]):
					st["max_gap"] = gap
					st["min_gap"] = gap
					st["_gap_seen"] = true
				else:
					st["max_gap"] = maxf(float(st["max_gap"]), gap)
					st["min_gap"] = minf(float(st["min_gap"]), gap)
				st["gap_n"] = int(st["gap_n"]) + 1
				if gap < -0.001 or gap > GAP_MAX + 0.0001:
					_blame(id, "gap", at["x"], at["z"], gap, GAP_MAX if gap > 0.0 else 0.0)
		if have:
			var residual := absf((hit_y - prev_y) - (expected - prev_e))
			if residual > float(st["max_step_across"]):
				st["max_step_across"] = residual
			if residual > STEP_ACROSS + 0.0001:
				_blame(id, "step_across", at["x"], at["z"], residual, STEP_ACROSS)
		if absf(offset) < cy_dist:
			cy_dist = absf(offset)
			cy = hit_y
		prev_y = hit_y
		prev_e = expected
		have = true
	var y0 := float(st["_y0"])
	var y1 := float(st["_y1"])
	if y0 > -9000.0 and y1 > -9000.0:
		var lip := absf((cy - y1) - (y1 - y0))
		if lip > float(st["max_step_along"]):
			st["max_step_along"] = lip
		if lip > STEP_ALONG + 0.0001:
			_blame(id, "step_along", pose["x"], pose["z"], lip, STEP_ALONG)
	st["_y0"] = y1
	st["_y1"] = cy
	_sample_edge(id, pose, true)
	_sample_edge(id, pose, false)
	pose["s"] = s


func _sample_edge(id: String, pose: Dictionary, left: bool, blame: bool = true) -> void:
	var edge := Vector3(float(pose["lx" if left else "rx"]), float(pose["ly" if left else "ry"]), float(pose["lz" if left else "rz"]))
	var outward: Vector3 = pose["out_l"] if left else pose["out_r"]
	var barrier := _barrier(edge, outward)
	var worst := 0.0
	var dist := 0.5
	while dist <= 3.001:
		var p := edge + outward * dist
		var ground := _gen.drawn_height_at(p.x, p.z)
		if ground > -70.0:
			worst = maxf(worst, edge.y - ground)
		dist += 0.5
	pose["gap_l" if left else "gap_r"] = edge.y - _gen.drawn_height_at(edge.x, edge.z)
	pose["bar_l" if left else "bar_r"] = barrier
	if barrier or not blame:
		return
	var st: Dictionary = _stats[id]
	if worst > float(st["max_drop"]):
		st["max_drop"] = worst
		st["max_drop_at"] = [edge.x, edge.z]
	if worst > DROP_MAX + 0.001:
		_blame(id, "edge_drop", edge.x, edge.z, worst, DROP_MAX)


func _watch_fill(id: String, pose: Dictionary, left: bool, prev_gap: float, have_prev: bool) -> void:
	if not have_prev:
		return
	var gap := float(pose["gap_l" if left else "gap_r"])
	var crossed := (prev_gap < 0.30 and gap >= 0.45) or (gap < 0.30 and prev_gap >= 0.45)
	if not crossed:
		return
	var edge := Vector3(float(pose["lx" if left else "rx"]), float(pose["ly" if left else "ry"]), float(pose["lz" if left else "rz"]))
	var outward: Vector3 = pose["out_l"] if left else pose["out_r"]
	for prior in _fill_ends:
		if str(prior["id"]) == id and Vector2(float(prior["x"]) - edge.x, float(prior["z"]) - edge.z).length() < 8.0:
			return
	_fill_ends.append({
		"id": id,
		"x": edge.x,
		"z": edge.z,
		"y": edge.y,
		"out": outward,
		"tangent": pose["tangent"],
		"gap": maxf(gap, prev_gap),
	})


func _queue_pushes(road: Dictionary, pose: Dictionary) -> void:
	var id := str(road["id"])
	var tangent: Vector3 = pose["tangent"]
	var headings: Array[float] = [0.0, deg_to_rad(45.0), deg_to_rad(-45.0)]
	var labels: PackedStringArray = PackedStringArray(["straight", "plus45", "minus45"])
	for i in headings.size():
		var dir := _yaw(tangent, headings[i])
		_pushes.append(_push_job(id, pose, 0.0, dir, labels[i]))
	_pushes.append(_push_job(id, pose, float(pose["lane"]), pose["out_r"], "off_right"))
	_pushes.append(_push_job(id, pose, -float(pose["lane"]), pose["out_l"], "off_left"))


func _push_job(id: String, pose: Dictionary, lat: float, dir: Vector3, label: String) -> Dictionary:
	var at := _at_lat(pose, lat)
	return {
		"id": id,
		"x": float(at["x"]),
		"z": float(at["z"]),
		"y": float(at["ey"]),
		"dir": dir,
		"half": float(pose["half"]),
		"cx": float(pose["x"]),
		"cz": float(pose["z"]),
		"tangent": pose["tangent"],
		"out_l": pose["out_l"],
		"out_r": pose["out_r"],
		"bar_l": bool(pose.get("bar_l", false)),
		"bar_r": bool(pose.get("bar_r", false)),
		"label": label,
	}


func _queue_walks(road: Dictionary, pose: Dictionary) -> void:
	# Walks are stored on the pose and run immediately. They are ray tests.
	_walk_side(str(road["id"]), pose, true)
	_walk_side(str(road["id"]), pose, false)


func _walk_side(id: String, pose: Dictionary, left: bool) -> void:
	var edge := Vector3(float(pose["lx" if left else "rx"]), float(pose["ly" if left else "ry"]), float(pose["lz" if left else "rz"]))
	var outward: Vector3 = pose["out_l"] if left else pose["out_r"]
	var tangent: Vector3 = pose["tangent"]
	var barrier := bool(pose["bar_l" if left else "bar_r"])
	var start := edge + outward * (1.6 if barrier else 1.2)
	if barrier:
		var probe := _ray(edge + Vector3(0, 0.5, 0), edge + outward * 3.0 + Vector3(0, 0.5, 0))
		if not probe.is_empty() and not _is_ground(probe):
			start = (probe["position"] as Vector3) + outward * 0.45
	_walk(id, start, tangent, edge.y, "walk_along")
	_walk(id, start, -tangent, edge.y, "walk_along")
	_walk(id, edge + outward * 2.5, -outward, edge.y, "walk_in")


func _walk(id: String, start: Vector3, dir: Vector3, road_y: float, test: String) -> void:
	if dir.length_squared() < 0.01:
		return
	dir = Vector3(dir.x, 0.0, dir.z).normalized()
	var base := _support(start + Vector3(0, 4.0, 0))
	if base.y < -70.0:
		_cone_fail(id, test, start.x, start.z, 1.0, "no support")
		return
	var steps := 16
	for i in steps:
		var chest := base + Vector3(0, 0.22, 0)
		var ahead := _ray(chest, chest + dir * 0.32)
		if not ahead.is_empty() and not _is_ground(ahead) and absf(float((ahead["normal"] as Vector3).y)) < 0.55:
			return
		var nxt := base + dir * 0.3
		var supported := _support(nxt + Vector3(0, 3.0, 0))
		if supported.y < -70.0:
			_cone_fail(id, test, nxt.x, nxt.z, road_y - base.y, "void")
			return
		base = supported
		if _under(base) and base.y < road_y - 0.20:
			_cone_fail(id, test, base.x, base.z, road_y - base.y, "under")
			return
	_cone_ok(id)


func _support(from_above: Vector3) -> Vector3:
	var hit := _ray(from_above, from_above + Vector3(0, -30.0, 0))
	if hit.is_empty():
		return Vector3(from_above.x, -99.0, from_above.z)
	var at: Vector3 = hit["position"]
	return Vector3(at.x, at.y + 0.02, at.z)


func _under(base: Vector3) -> bool:
	var origin := base + Vector3(0, 0.06, 0)
	var hit := _ray(origin, origin + Vector3(0, 1.2, 0))
	if hit.is_empty() or _is_ground(hit):
		return false
	var at: Vector3 = hit["position"]
	return at.y - base.y < 1.05


func _cones() -> void:
	for end in _fill_ends:
		var tangent: Vector3 = end["tangent"]
		var outward: Vector3 = end["out"]
		var start := Vector3(float(end["x"]), float(end["y"]), float(end["z"])) + outward * 2.2
		_walk(str(end["id"]), start, -outward, float(end["y"]), "walk_fill")
		_walk(str(end["id"]), start, tangent, float(end["y"]), "walk_fill")
		_walk(str(end["id"]), start, -tangent, float(end["y"]), "walk_fill")
	for spot in REGRESSIONS:
		var near := _nearest(float(spot["x"]), float(spot["z"]))
		if near.is_empty():
			continue
		var road: Dictionary = _builder._roads[int(_builder._by_id[str(near["id"])])]
		var pose := _pose(road, float(near["s"]))
		_sample_edge(str(road["id"]), pose, true, false)
		_sample_edge(str(road["id"]), pose, false, false)
		_queue_pushes(road, pose)
	if _pushes.is_empty():
		return
	var pool: Array[RigidBody3D] = []
	for i in 24:
		var body := _make_cone()
		_host.add_child(body)
		body.freeze = true
		body.global_position = Vector3(0, -400.0, 0)
		pool.append(body)
	var pending := _pushes.duplicate()
	var batch_i := 0
	while not pending.is_empty():
		var batch: Array[Dictionary] = []
		var left: Array[Dictionary] = []
		for job in pending:
			if batch.size() >= pool.size():
				left.append(job)
				continue
			var far := true
			for other in batch:
				var dx := float(job["x"]) - float(other["x"])
				var dz := float(job["z"]) - float(other["z"])
				if dx * dx + dz * dz < 40.0 * 40.0:
					far = false
					break
			if far:
				batch.append(job)
			else:
				left.append(job)
		if batch.is_empty():
			batch.append(pending[0])
			left = pending.slice(1)
		pending = left
		await _run_batch(pool, batch)
		batch_i += 1
		if batch_i % 10 == 0:
			print("CONE_BATCH %d left=%d fails=%d" % [batch_i, pending.size(), _cone_fails])
	for body in pool:
		body.queue_free()
	print("CONE_DONE tests=%d fails=%d" % [_cone_tests, _cone_fails])


func _run_batch(pool: Array[RigidBody3D], batch: Array[Dictionary]) -> void:
	var frames := 60
	for job in batch:
		var need := int(ceil((float(job["half"]) + 1.6) / PUSH_SPEED * 60.0 + 24.0))
		frames = maxi(frames, mini(need, 160))
	for i in batch.size():
		var job: Dictionary = batch[i]
		var body := pool[i]
		var dir: Vector3 = job["dir"]
		body.freeze = false
		body.sleeping = false
		body.global_position = Vector3(float(job["x"]), float(job["y"]) + 0.25, float(job["z"]))
		body.linear_velocity = dir * PUSH_SPEED
		body.angular_velocity = Vector3.ZERO
	await physics_frame
	for f in frames:
		for i in batch.size():
			var body := pool[i]
			var dir: Vector3 = batch[i]["dir"]
			var v := body.linear_velocity
			body.linear_velocity = Vector3(dir.x * PUSH_SPEED, v.y, dir.z * PUSH_SPEED)
		await physics_frame
	for i in batch.size():
		_score_push(batch[i], pool[i])
		pool[i].freeze = true
		pool[i].global_position = Vector3(0, -400.0, float(i))


func _score_push(job: Dictionary, body: RigidBody3D) -> void:
	var id := str(job["id"])
	var center := body.global_position
	var up_from := center + Vector3(0, 0.05, 0)
	var up := _ray(up_from, up_from + Vector3(0, 1.1, 0))
	var down := _ray(center + Vector3(0, 0.6, 0), center + Vector3(0, -25.0, 0))
	var stuck := false
	if not up.is_empty() and not _is_ground(up):
		var at: Vector3 = up["position"]
		if at.y - (center.y - 0.2) < 1.0 and center.y < float(job["y"]) - 0.05:
			stuck = true
	var on_road := false
	var road_y := float(job["y"])
	if not down.is_empty() and _is_road(down):
		on_road = true
		road_y = float((down["position"] as Vector3).y)
	if stuck:
		_cone_fail(id, "cone_" + str(job["label"]), center.x, center.z, float(job["y"]) - center.y, "under")
		return
	if on_road and center.y < road_y - 0.02:
		_cone_fail(id, "cone_" + str(job["label"]), center.x, center.z, road_y - center.y, "below")
		return
	if on_road:
		_cone_ok(id)
		return
	var side := _exit_side(job, center)
	var barred := bool(job["bar_l"]) if side < 0.0 else bool(job["bar_r"])
	if side != 0.0 and barred:
		_cone_fail(id, "cone_" + str(job["label"]), center.x, center.z, float(job["y"]) - center.y, "escape")
		return
	var supported := false
	if not down.is_empty():
		var ground_y := float((down["position"] as Vector3).y)
		supported = center.y - ground_y < 0.8 and center.y - ground_y > -0.2
	if supported:
		_cone_ok(id)
		return
	if body.linear_velocity.y < -0.8:
		_cone_fail(id, "cone_" + str(job["label"]), center.x, center.z, float(job["y"]) - center.y, "falling")
		return
	_cone_fail(id, "cone_" + str(job["label"]), center.x, center.z, float(job["y"]) - center.y, "void")


func _exit_side(job: Dictionary, center: Vector3) -> float:
	var right: Vector3 = job["out_r"]
	var rel := Vector3(center.x - float(job["cx"]), 0.0, center.z - float(job["cz"]))
	var lateral := rel.dot(right)
	if absf(lateral) <= float(job["half"]) + 0.35:
		return 0.0
	# +1 is the right edge, -1 is the left edge.
	return 1.0 if lateral > 0.0 else -1.0


func _cone_ok(id: String) -> void:
	_cone_tests += 1
	if not _stats.has(id):
		return
	var st: Dictionary = _stats[id]
	st["cone_tests"] = int(st["cone_tests"]) + 1


func _cone_fail(id: String, test: String, x: float, z: float, value: float, why: String) -> void:
	_cone_tests += 1
	_cone_fails += 1
	if _stats.has(id):
		var st: Dictionary = _stats[id]
		st["cone_tests"] = int(st["cone_tests"]) + 1
		st["cone_fails"] = int(st["cone_fails"]) + 1
	_blame(id, test, x, z, value, 0.0)
	if why != "":
		pass


func _make_cone() -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	body.mass = 1.4
	body.continuous_cd = true
	body.can_sleep = false
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = Vector3(0, -0.12, 0)
	var packed := load("res://scenes/player/colliders/standard_cone_world_collider.tscn") as PackedScene
	var inst := packed.instantiate()
	for child in inst.get_children():
		if child is CollisionShape3D:
			var copy := (child as CollisionShape3D).duplicate() as CollisionShape3D
			body.add_child(copy)
	inst.free()
	return body


func _measure_junctions() -> void:
	var i := 0
	for item in _builder._junctions:
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var radius := float(item.get("radius", 8.0))
		var cx := float(pos[0])
		var cz := float(pos[2])
		var pts: Array[Vector3] = []
		var x := -radius
		while x <= radius + 0.01:
			var z := -radius
			while z <= radius + 0.01:
				if x * x + z * z <= radius * radius:
					var expected := float(item.get("flat_y", pos[1])) + float(item.get("sx", 0.0)) * x + float(item.get("sz", 0.0)) * z
					var hit := _ray(Vector3(cx + x, expected + 8.0, cz + z), Vector3(cx + x, expected - 40.0, cz + z))
					if _is_road(hit):
						var y := _driving_y(Vector3(cx + x, expected, cz + z), expected, hit)
						pts.append(Vector3(cx + x, y, cz + z))
				z += 1.0
			x += 1.0
		var fit := _fit_plane(pts)
		var steep := _approach_grade(item) >= 0.06
		var limit := JUNC_TILT_STEEP if steep else JUNC_TILT
		var jid := str(item.get("id", "j%d" % i))
		var rec := {
			"id": jid,
			"x": cx,
			"z": cz,
			"roads": item.get("roads", []),
			"dev": float(fit["dev"]),
			"tilt": float(fit["tilt"]),
			"limit": limit,
			"samples": pts.size(),
			"pass": pts.size() >= 4 and float(fit["dev"]) <= JUNC_DEV + 0.0001 and float(fit["tilt"]) <= limit + 0.0001,
		}
		_junctions.append(rec)
		if not bool(rec["pass"]):
			var blame_id := jid
			var roads: Array = item.get("roads", [])
			if not roads.is_empty():
				blame_id = str(roads[0])
			_blame(blame_id, "junction", cx, cz, maxf(float(fit["dev"]), float(fit["tilt"])), JUNC_DEV if float(fit["dev"]) >= float(fit["tilt"]) else limit)
		i += 1


func _apply_junctions() -> void:
	for rec in _junctions:
		for rid in rec["roads"]:
			var id := str(rid)
			if not _stats.has(id):
				continue
			var st: Dictionary = _stats[id]
			st["junc_n"] = int(st["junc_n"]) + 1
			if float(rec["dev"]) > float(st["junc_dev"]):
				st["junc_dev"] = float(rec["dev"])
			if float(rec["tilt"]) > float(st["junc_tilt"]):
				st["junc_tilt"] = float(rec["tilt"])
				st["junc_limit"] = float(rec["limit"])
			if not bool(rec["pass"]):
				st["junc_pass"] = false


func _approach_grade(item: Dictionary) -> float:
	var pos: Array = item.get("pos", [])
	if pos.size() < 3:
		return 0.0
	var worst := 0.0
	for rid in item.get("roads", []):
		if not _builder._by_id.has(str(rid)):
			continue
		var road: Dictionary = _builder._roads[int(_builder._by_id[str(rid)])]
		var pts: PackedVector3Array = road["pts"]
		var chain: PackedFloat32Array = road["chain"]
		for i in pts.size() - 1:
			var mid := (pts[i] + pts[i + 1]) * 0.5
			if Vector2(mid.x - float(pos[0]), mid.z - float(pos[2])).length() > 24.0:
				continue
			var ds := float(chain[i + 1] - chain[i])
			if ds < 0.5:
				continue
			worst = maxf(worst, absf(pts[i + 1].y - pts[i].y) / ds)
	return worst


func _fit_plane(pts: Array[Vector3]) -> Dictionary:
	if pts.size() < 4:
		return {"dev": 99.0, "tilt": 99.0}
	var n := float(pts.size())
	var sx := 0.0
	var sz := 0.0
	var sy := 0.0
	var sxx := 0.0
	var szz := 0.0
	var sxz := 0.0
	var sxy := 0.0
	var szy := 0.0
	for p in pts:
		sx += p.x
		sz += p.z
		sy += p.y
		sxx += p.x * p.x
		szz += p.z * p.z
		sxz += p.x * p.z
		sxy += p.x * p.y
		szy += p.z * p.y
	var a := _solve3(sxx, sxz, sx, sxy, sxz, szz, sz, szy, sx, sz, n, sy)
	var dev := 0.0
	for p in pts:
		dev = maxf(dev, absf(p.y - (a.x * p.x + a.y * p.z + a.z)))
	return {"dev": dev, "tilt": Vector2(a.x, a.y).length()}


func _solve3(a00: float, a01: float, a02: float, b0: float, a10: float, a11: float, a12: float, b1: float, a20: float, a21: float, a22: float, b2: float) -> Vector3:
	var m := [
		[a00, a01, a02, b0],
		[a10, a11, a12, b1],
		[a20, a21, a22, b2],
	]
	for col in 3:
		var pivot := col
		var best := absf(m[col][col])
		for row in range(col + 1, 3):
			if absf(m[row][col]) > best:
				best = absf(m[row][col])
				pivot = row
		if best < 1.0e-8:
			return Vector3(0, 0, b2 / maxf(a22, 1.0))
		var tmp: Array = m[col]
		m[col] = m[pivot]
		m[pivot] = tmp
		var div: float = m[col][col]
		for k in 4:
			m[col][k] = float(m[col][k]) / div
		for row in 3:
			if row == col:
				continue
			var f: float = m[row][col]
			for k in 4:
				m[row][k] = float(m[row][k]) - f * float(m[col][k])
	return Vector3(float(m[0][3]), float(m[1][3]), float(m[2][3]))


func _measure_ends() -> void:
	var worst_cut := -999.0
	var worst_rec: Dictionary = {}
	for id in _order:
		var road: Dictionary = _builder._roads[int(_builder._by_id[id])]
		var pts: PackedVector3Array = road["pts"]
		var chain: PackedFloat32Array = road["chain"]
		if pts.size() < 2:
			continue
		for end_i in [0, pts.size() - 1]:
			var p := pts[end_i]
			var kind := _end_kind(road, end_i)
			var tangent := _end_tangent(pts, end_i)
			var ahead := p + tangent * 1.0
			var ground := _gen.drawn_height_at(ahead.x, ahead.z)
			var seam := 0.0 if ground < -70.0 else ground - p.y
			var row := {"which": "start" if end_i == 0 else "end", "kind": kind, "x": p.x, "z": p.z, "seam": seam}
			(_stats[id]["ends"] as Array).append(row)
			if kind == "unclassified":
				_stats[id]["unclassified"] = int(_stats[id]["unclassified"]) + 1
				_blame(id, "end", p.x, p.z, seam, 0.0)
			if kind == "unclassified" or kind == "dead_end":
				if seam > worst_cut:
					worst_cut = seam
					worst_rec = {"id": "dirt_cut_end", "road": id, "x": p.x, "z": p.z, "note": "dirt-cut road end", "seam_m": seam, "pass": absf(seam) <= 0.50}
	if not worst_rec.is_empty():
		_regressions.append(worst_rec)
	elif not _order.is_empty():
		_regressions.append({"id": "dirt_cut_end", "note": "no unclassified end", "pass": true})


func _end_kind(road: Dictionary, index: int) -> String:
	var pts: PackedVector3Array = road["pts"]
	var p := pts[index]
	var kinds: PackedStringArray = road["kind"]
	var kind := ""
	if index == 0 and kinds.size() > 0:
		kind = kinds[0]
	elif index > 0 and index - 1 < kinds.size():
		kind = kinds[index - 1]
	if kind == "bridge" or kind == "deck":
		return "bridge"
	if _near_bridge_end(p) or _near_junction(str(road["id"]), p):
		return "bridge" if _near_bridge_end(p) and not _near_junction(str(road["id"]), p) else "junction"
	if _near_bridge_end(p):
		return "bridge"
	if p.x <= 5.0 or p.x >= 4995.0 or -p.z <= 5.0 or -p.z >= 7995.0:
		return "map_edge"
	# The spec's fourth end type. A stub that is not a junction, an abutment,
	# or a map-edge exit is a dead end. The dirt-cut regression still records
	# a hard step at that end; this only stops calling it unclassified.
	return "dead_end"


func _near_junction(road_id: String, p: Vector3) -> bool:
	for item in _builder._junctions:
		var ids: Array = item.get("roads", [])
		if not ids.has(road_id):
			continue
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		if Vector2(p.x - float(pos[0]), p.z - float(pos[2])).length() <= float(item.get("radius", 8.0)) + 4.0:
			return true
	return false


func _near_bridge_end(p: Vector3) -> bool:
	if not _builder._by_id.has("us93_perrine_bridge"):
		return false
	var road: Dictionary = _builder._roads[int(_builder._by_id["us93_perrine_bridge"])]
	var pts: PackedVector3Array = road["pts"]
	if pts.is_empty():
		return false
	for end_i in [0, pts.size() - 1]:
		if Vector2(p.x - pts[end_i].x, p.z - pts[end_i].z).length() <= 16.0:
			return true
	return false


func _end_tangent(pts: PackedVector3Array, index: int) -> Vector3:
	var a: Vector3
	var b: Vector3
	if index == 0:
		a = pts[0]
		b = pts[1]
		return _flat_dir(a - b)
	a = pts[index - 1]
	b = pts[index]
	return _flat_dir(b - a)


func _components_of() -> int:
	var parent := {}
	for id in _order:
		parent[id] = id
	for item in _builder._junctions:
		var ids: Array = item.get("roads", [])
		var first := ""
		for rid in ids:
			var id := str(rid)
			if not parent.has(id):
				continue
			if first == "":
				first = id
			else:
				_union(parent, first, id)
	for i in _order.size():
		var a: Dictionary = _builder._roads[int(_builder._by_id[_order[i]])]
		var pa: PackedVector3Array = a["pts"]
		if pa.is_empty():
			continue
		for j in range(i + 1, _order.size()):
			var b: Dictionary = _builder._roads[int(_builder._by_id[_order[j]])]
			var pb: PackedVector3Array = b["pts"]
			if pb.is_empty():
				continue
			if _ends_touch(pa, pb):
				_union(parent, _order[i], _order[j])
	var roots := {}
	for id in _order:
		roots[_find(parent, id)] = true
	return roots.size()


func _ends_touch(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	var ends_a: Array[Vector3] = [a[0], a[a.size() - 1]]
	var ends_b: Array[Vector3] = [b[0], b[b.size() - 1]]
	for pa in ends_a:
		for pb in ends_b:
			if Vector2(pa.x - pb.x, pa.z - pb.z).length() <= 3.0:
				return true
	return false


func _union(parent: Dictionary, a: String, b: String) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[rb] = ra


func _find(parent: Dictionary, id: String) -> String:
	var root := id
	while str(parent[root]) != root:
		root = str(parent[root])
	var cur := id
	while cur != root:
		var nxt := str(parent[cur])
		parent[cur] = root
		cur = nxt
	return root


func _geometric_regressions() -> void:
	for spot in REGRESSIONS:
		if str(spot.get("check", "")) != "":
			continue
		var x := float(spot["x"])
		var z := float(spot["z"])
		var near := _nearest(x, z)
		var ground := _gen.drawn_height_at(x, z)
		var hit := _ray(Vector3(x, 220.0, z), Vector3(x, -40.0, z))
		var hit_y := -999.0
		var hit_name := "miss"
		if not hit.is_empty():
			hit_y = float((hit["position"] as Vector3).y)
			hit_name = str((hit["collider"] as Node).name)
		var gap := hit_y - ground if hit_y > -70.0 and ground > -70.0 else 999.0
		var rec := {
			"id": str(spot["id"]),
			"note": str(spot["note"]),
			"x": x,
			"z": z,
			"road": str(near.get("id", "")),
			"road_dist_m": float(near.get("dist", -1.0)),
			"hit": hit_name,
			"hit_y": hit_y,
			"terrain_y": ground,
			"gap_m": gap,
			"pass": false,
		}
		if str(spot["id"]).begins_with("float"):
			rec["pass"] = _is_road(hit) and gap >= -0.001 and gap <= GAP_MAX
		else:
			var step := float(near.get("step", 99.0))
			rec["step_m"] = step
			rec["pass"] = _is_road(hit) and step <= STEP_ALONG and gap >= -0.001 and gap <= GAP_MAX
		_regressions.append(rec)
	_guard_regression()
	_junction_regression()
	_qa_regressions()


func _guard_regression() -> void:
	var worst := 0.0
	var at := Vector3.ZERO
	var rid := ""
	for id in ["canyon_springs_grade", "rim_road_south"]:
		if not _builder._by_id.has(id):
			continue
		var road: Dictionary = _builder._roads[int(_builder._by_id[id])]
		var chain: PackedFloat32Array = road["chain"]
		if chain.is_empty():
			continue
		var s := 0.0
		var length := float(chain[chain.size() - 1])
		while s <= length:
			var pose := _pose(road, s)
			for left in [true, false]:
				var edge := Vector3(float(pose["lx" if left else "rx"]), float(pose["ly" if left else "ry"]), float(pose["lz" if left else "rz"]))
				var outward: Vector3 = pose["out_l"] if left else pose["out_r"]
				if not _barrier(edge, outward):
					s += 10.0
					continue
				var foot := edge + outward * 0.2
				var ground := _gen.drawn_height_at(foot.x, foot.z)
				if ground > -70.0:
					var gap := edge.y - ground
					if gap > worst:
						worst = gap
						at = foot
						rid = id
			s += 10.0
	_regressions.append({
		"id": "guardrail_on_skirt",
		"note": "guardrail on a skirt",
		"road": rid,
		"x": at.x,
		"z": at.z,
		"gap_m": worst,
		"pass": worst <= 0.05,
	})


func _junction_regression() -> void:
	var worst: Dictionary = {}
	for rec in _junctions:
		if worst.is_empty() or float(rec["dev"]) > float(worst["dev"]):
			worst = rec
	if worst.is_empty():
		_regressions.append({"id": "jagged_junction", "note": "no junction", "pass": false})
		return
	_regressions.append({
		"id": "jagged_junction",
		"note": "jagged junction blob",
		"junction": str(worst["id"]),
		"x": float(worst["x"]),
		"z": float(worst["z"]),
		"dev_m": float(worst["dev"]),
		"tilt": float(worst["tilt"]),
		"pass": bool(worst["pass"]),
	})


func _qa_regressions() -> void:
	for spot in REGRESSIONS:
		var kind := str(spot.get("check", ""))
		if kind == "":
			continue
		var rec := {
			"id": str(spot["id"]),
			"note": str(spot["note"]),
			"x": float(spot["x"]),
			"z": float(spot["z"]),
			"pass": false,
		}
		if kind == "pole":
			_qa_pole(rec)
		elif kind == "paint":
			_qa_paint(rec)
		elif kind == "step":
			_qa_step(rec)
		elif kind == "taper":
			_qa_taper(rec)
		elif kind == "hole":
			_qa_hole(rec)
		elif kind == "ceiling":
			_qa_ceiling(rec)
		elif kind == "exit":
			_qa_exit(rec)
		_regressions.append(rec)


func _qa_pole(rec: Dictionary) -> void:
	var x := float(rec["x"])
	var z := float(rec["z"])
	var best_d := 1.0e9
	var item: Dictionary = {}
	for junc in _builder._junctions:
		var pos: Array = junc.get("pos", [])
		if pos.size() < 3:
			continue
		var d := Vector2(float(pos[0]) - x, float(pos[2]) - z).length()
		if d < best_d:
			best_d = d
			item = junc
	if item.is_empty():
		rec["margin_m"] = -1.0
		return
	var pos: Array = item.get("pos", [])
	var at := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	var roads: Array = []
	for id in item.get("roads", []):
		if not _builder._by_id.has(str(id)):
			continue
		var road: Dictionary = _builder._roads[int(_builder._by_id[str(id)])]
		if not bool(road["rail"]):
			roads.append(road)
	var stand: Vector3 = _builder._sign_stand(at, roads)
	var margin: float = _builder._stand_margin(stand, roads)
	rec["stand_x"] = stand.x
	rec["stand_z"] = stand.z
	rec["margin_m"] = margin
	rec["pass"] = margin >= 1.6


func _qa_paint(rec: Dictionary) -> void:
	# Centre of a crowned lane. Edge lerp sits one crown drop low; the painter
	# has to add the tent back. Checked on the function the ribbon calls.
	var left_y := 100.0
	var right_y := 100.0
	var crown := 0.146
	var centre := _builder._paint_y(left_y - crown, right_y - crown, 0.5, crown)
	var edge := _builder._paint_y(left_y - crown, right_y - crown, 0.02, crown)
	rec["centre_y"] = centre
	rec["edge_err_m"] = absf(edge - (left_y - crown))
	rec["pass"] = absf(centre - left_y) <= 0.005 and absf(edge - (left_y - crown)) <= 0.01


func _qa_step(rec: Dictionary) -> void:
	var x := float(rec["x"])
	var z := float(rec["z"])
	var item := _nearest_junction(x, z)
	if item.is_empty():
		rec["dev_m"] = 99.0
		return
	var worst := 0.0
	var samples := 0
	for dx in [-2.0, 0.0, 2.0]:
		for dz in [-2.0, 0.0, 2.0]:
			var px: float = x + float(dx)
			var pz: float = z + float(dz)
			var plane := _builder._plane_at(item, px, pz) + 0.02
			var hit := _ray(Vector3(px, plane + 2.0, pz), Vector3(px, plane - 4.0, pz))
			if not _is_road(hit):
				continue
			var y := _driving_y(Vector3(px, plane, pz), plane, hit)
			worst = maxf(worst, absf(y - plane))
			samples += 1
	rec["dev_m"] = worst
	rec["samples"] = samples
	rec["pass"] = samples >= 3 and worst <= 0.03


func _qa_taper(rec: Dictionary) -> void:
	if not _builder._by_id.has("us93_south_approach") or not _builder._by_id.has("us93_blue_lakes_s"):
		return
	var wide: Dictionary = _builder._roads[int(_builder._by_id["us93_south_approach"])]
	var narrow: Dictionary = _builder._roads[int(_builder._by_id["us93_blue_lakes_s"])]
	var wpts: PackedVector3Array = wide["pts"]
	var npts: PackedVector3Array = narrow["pts"]
	var wchain: PackedFloat32Array = wide["chain"]
	var bi := 0
	var best := 1.0e9
	for i in wpts.size():
		var d := Vector2(wpts[i].x - 3378.6, wpts[i].z + 6300.0).length()
		if d < best:
			best = d
			bi = i
	var joint := _builder._half_at(wide, bi)
	var other := float(narrow["half"])
	var s0 := float(wchain[bi])
	var far := joint
	for i in wpts.size():
		if absf(float(wchain[i]) - s0) >= 30.0:
			far = _builder._half_at(wide, i)
			break
	# The far half is measured 30 m along the chain, toward the 4-lane section.
	var full := float(wide["half"])
	rec["joint_half_m"] = joint
	rec["narrow_half_m"] = other
	rec["far_half_m"] = far
	rec["pass"] = absf(joint - other) <= 0.08 and far > full - 0.4


func _qa_hole(rec: Dictionary) -> void:
	var x := float(rec["x"])
	var z := float(rec["z"])
	var near := _nearest(x, z)
	var road: Dictionary = _builder._roads[int(_builder._by_id[str(near.get("id", "us93_south_approach"))])]
	var pose := _pose(road, float(near.get("s", 0.0)))
	var expected := float(pose["y"])
	var hit := _ray(Vector3(x, expected + 4.0, z), Vector3(x, expected - 8.0, z))
	var ground := _gen.drawn_height_at(x, z)
	var hit_y := -999.0
	if _is_road(hit):
		hit_y = _driving_y(Vector3(x, expected, z), expected, hit)
	var gap := hit_y - ground if hit_y > -70.0 and ground > -70.0 else 999.0
	rec["hit_y"] = hit_y
	rec["terrain_y"] = ground
	rec["gap_m"] = gap
	rec["pass"] = _is_road(hit) and absf(hit_y - expected) <= 0.15 and gap >= -0.001 and gap <= GAP_MAX


func _qa_ceiling(rec: Dictionary) -> void:
	var x := float(rec["x"])
	var z := float(rec["z"])
	var near := _nearest(x, z)
	var road_y := 142.76
	if not near.is_empty() and _builder._by_id.has(str(near["id"])):
		var road: Dictionary = _builder._roads[int(_builder._by_id[str(near["id"])])]
		var pose := _pose(road, float(near["s"]))
		road_y = float(pose["y"])
	var base := _support(Vector3(x, road_y + 4.0, z))
	var under := _under(base)
	rec["base_y"] = base.y
	rec["road_y"] = road_y
	rec["pass"] = base.y > -70.0 and not (under and base.y < road_y - 0.20)


func _qa_exit(rec: Dictionary) -> void:
	var x := float(rec["x"])
	var z := float(rec["z"])
	var near := _nearest(x, z)
	var road_y := 0.0
	if not near.is_empty() and _builder._by_id.has(str(near["id"])):
		var road: Dictionary = _builder._roads[int(_builder._by_id[str(near["id"])])]
		var pts: PackedVector3Array = road["pts"]
		road_y = pts[pts.size() - 1].y
		if absf(pts[0].x - x) + absf(pts[0].z - z) < absf(pts[pts.size() - 1].x - x) + absf(pts[pts.size() - 1].z - z):
			road_y = pts[0].y
	var hit := _ray(Vector3(x, road_y + 30.0, z), Vector3(x, road_y - 40.0, z))
	var hit_y := -999.0
	var name := "miss"
	if not hit.is_empty():
		hit_y = float((hit["position"] as Vector3).y)
		name = str((hit["collider"] as Node).name)
	rec["hit"] = name
	rec["hit_y"] = hit_y
	rec["road_y"] = road_y
	rec["pass"] = _is_road(hit) and absf(hit_y - road_y) < 1.5


func _nearest_junction(x: float, z: float) -> Dictionary:
	var best := 1.0e9
	var found: Dictionary = {}
	for item in _builder._junctions:
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var d := Vector2(float(pos[0]) - x, float(pos[2]) - z).length()
		if d < best:
			best = d
			found = item
	return found


func _nearest(x: float, z: float) -> Dictionary:
	var best := 1.0e12
	var found: Dictionary = {}
	for id in _order:
		var road: Dictionary = _builder._roads[int(_builder._by_id[id])]
		var pts: PackedVector3Array = road["pts"]
		var chain: PackedFloat32Array = road["chain"]
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var ab := Vector2(b.x - a.x, b.z - a.z)
			var len2 := ab.length_squared()
			var t := 0.0 if len2 < 0.01 else clampf(Vector2(x - a.x, z - a.z).dot(ab) / len2, 0.0, 1.0)
			var px := lerpf(a.x, b.x, t)
			var pz := lerpf(a.z, b.z, t)
			var d := Vector2(x - px, z - pz).length()
			if d < best:
				best = d
				var s := lerpf(float(chain[i]), float(chain[i + 1]), t)
				var step := 0.0
				if i > 0 and i + 1 < pts.size():
					var d0 := maxf(float(chain[i] - chain[i - 1]), 0.5)
					var d1 := maxf(float(chain[i + 1] - chain[i]), 0.5)
					step = absf((pts[i + 1].y - pts[i].y) / d1 - (pts[i].y - pts[i - 1].y) / d0)
				found = {"id": id, "dist": d, "s": s, "step": step}
	return found


func _pose(road: Dictionary, s: float) -> Dictionary:
	var pts: PackedVector3Array = road["pts"]
	var left: PackedVector3Array = road["left"]
	var right: PackedVector3Array = road["right"]
	var chain: PackedFloat32Array = road["chain"]
	var bank: PackedFloat32Array = road["bank"]
	var crown: PackedFloat32Array = road["crown"]
	var kinds: PackedStringArray = road["kind"]
	var i := 0
	while i + 1 < chain.size() and float(chain[i + 1]) < s:
		i += 1
	i = clampi(i, 0, pts.size() - 2)
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


func _at_lat(pose: Dictionary, lat: float) -> Dictionary:
	var half := maxf(float(pose["half"]), 0.001)
	var u := clampf(lat / half, -1.0, 1.0)
	var sec: Vector3 = pose["sec"]
	var ey := sec.y
	if u < 0.0:
		ey = lerpf(sec.y, sec.x, -u)
	elif u > 0.0:
		ey = lerpf(sec.y, sec.z, u)
	var lx := float(pose["lx"])
	var lz := float(pose["lz"])
	var rx := float(pose["rx"])
	var rz := float(pose["rz"])
	var t := clampf(0.5 + lat / (half * 2.0), 0.0, 1.0)
	return {"x": lerpf(lx, rx, t), "z": lerpf(lz, rz, t), "ey": ey}


func _barrier(edge: Vector3, outward: Vector3) -> bool:
	if outward.length_squared() < 0.01:
		return false
	var high := Vector3(0, 0.55, 0)
	var casts: Array[Vector3] = [
		edge + outward * 0.05 + high,
		edge + outward * 3.0 + high,
	]
	var dirs: Array[Vector3] = [outward, -outward]
	for i in 2:
		var hit := _ray(casts[i], casts[i] + dirs[i] * 3.2)
		if hit.is_empty() or _is_ground(hit):
			continue
		var n: Vector3 = hit["normal"]
		if absf(n.y) > 0.65:
			continue
		var at: Vector3 = hit["position"]
		if at.y > edge.y + 0.12 and at.y < edge.y + 1.6:
			return true
	return false


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.hit_back_faces = true
	q.collide_with_bodies = true
	q.collide_with_areas = false
	return _space.intersect_ray(q)


func _is_ground(hit: Dictionary) -> bool:
	if hit.is_empty():
		return false
	var body := hit["collider"] as Node
	return body != null and body.name == "TerrainBody"


func _is_road(hit: Dictionary) -> bool:
	return not hit.is_empty() and not _is_ground(hit)


## Walk the ray down through parapets and shells to the carriageway.
## `first` is the hit already cast from the design height; it is not recast.
func _driving_y(at: Vector3, expected: float, first: Dictionary) -> float:
	# A parapet cap or guard top is a walkable face in the same body, about
	# 0.8 m above the lane. Keep every walkable road face within 0.20 m of
	# the design and use the one closest to it. The first face in that window
	# can be a wing or a flare while the carriageway is a few centimetres lower.
	var best := Vector2(expected, 1.0e9)
	var near := _ray(Vector3(at.x, expected + 0.22, at.z), Vector3(at.x, expected - 0.35, at.z))
	best = _consider_drive(near, expected, best)
	var hit := first
	var from := Vector3(at.x, expected + 2.0, at.z)
	var to := Vector3(at.x, expected - 80.0, at.z)
	var guard := 0
	while guard < 8:
		if hit.is_empty() or not _is_road(hit):
			break
		best = _consider_drive(hit, expected, best)
		var at_hit: Vector3 = hit["position"]
		from = at_hit + Vector3(0.0, -0.06, 0.0)
		if from.y <= to.y + 0.05:
			break
		hit = _ray(from, to)
		guard += 1
	if best.y < 10.0:
		return best.x
	if _is_road(first):
		return float((first["position"] as Vector3).y)
	return expected


func _consider_drive(hit: Dictionary, expected: float, best: Vector2) -> Vector2:
	if not _is_road(hit):
		return best
	var n: Vector3 = hit["normal"]
	if n.y < 0.45:
		return best
	var y := float((hit["position"] as Vector3).y)
	var d := absf(y - expected)
	if d <= 0.20 and d < best.y:
		return Vector2(y, d)
	return best


func _flat_dir(v: Vector3) -> Vector3:
	v.y = 0.0
	if v.length_squared() < 0.0001:
		return Vector3(0, 0, -1)
	return v.normalized()


func _yaw(tangent: Vector3, ang: float) -> Vector3:
	var c := cos(ang)
	var s := sin(ang)
	return Vector3(tangent.x * c - tangent.z * s, 0.0, tangent.x * s + tangent.z * c).normalized()


func _blame(id: String, test: String, x: float, z: float, value: float, limit: float) -> void:
	var key := "%s|%s" % [id, test]
	var n := int(_fail_n.get(key, 0))
	_fail_n[key] = n + 1
	var row := {"road": id, "test": test, "x": x, "z": z, "value": value, "limit": limit}
	if n < FAIL_CAP:
		_failures.append(row)
	var over := absf(value - limit)
	if _worst.size() < 10:
		_worst.append(row)
	else:
		var small := 0
		for i in _worst.size():
			var other: Dictionary = _worst[i]
			if absf(float(other["value"]) - float(other["limit"])) < absf(float(_worst[small]["value"]) - float(_worst[small]["limit"])):
				small = i
		if over > absf(float(_worst[small]["value"]) - float(_worst[small]["limit"])):
			_worst[small] = row


func _grade_road(id: String) -> void:
	var st: Dictionary = _stats[id]
	var samples := int(st["samples"])
	var misses := int(st["misses"])
	st["hit_pass"] = samples > 0 and misses == 0
	st["step_pass"] = float(st["max_step_along"]) <= STEP_ALONG + 0.0001 and float(st["max_step_across"]) <= STEP_ACROSS + 0.0001
	if int(st["gap_n"]) == 0:
		st["gap_pass"] = true
	else:
		st["gap_pass"] = float(st["min_gap"]) >= -0.001 and float(st["max_gap"]) <= GAP_MAX + 0.0001
	st["drop_pass"] = float(st["max_drop"]) <= DROP_MAX + 0.001


func _finish_status() -> void:
	for id in _order:
		var st: Dictionary = _stats[id]
		st["cone_pass"] = int(st["cone_fails"]) == 0
		st["end_pass"] = int(st["unclassified"]) == 0
		if int(st["junc_n"]) == 0:
			st["junc_pass"] = true
		var ok: bool = st["hit_pass"] and st["step_pass"] and st["gap_pass"] and st["drop_pass"] and st["cone_pass"] and st["junc_pass"] and st["end_pass"]
		st["status"] = "PASS" if ok else "FAIL"
		var rate := 0.0 if int(st["samples"]) == 0 else 100.0 * float(st["hits"]) / float(st["samples"])
		print("%s %s hit=%.2f step=%.3f/%.3f gap=%.3f/%.3f drop=%.2f cone=%d/%d junc=%.3f ends=%d" % [
			st["status"], id, rate, float(st["max_step_along"]), float(st["max_step_across"]),
			float(st["min_gap"]), float(st["max_gap"]), float(st["max_drop"]),
			int(st["cone_fails"]), int(st["cone_tests"]), float(st["junc_dev"]), int(st["unclassified"]),
		])


func _payload() -> Dictionary:
	var roads := {}
	var rows: Array[Dictionary] = []
	var samples := 0
	var hits := 0
	var max_step_a := 0.0
	var max_step_c := 0.0
	var max_gap := 0.0
	var min_gap := 0.0
	var gap_init := false
	var max_drop := 0.0
	var failed := 0
	var junc_fail := 0
	for rec in _junctions:
		if not bool(rec["pass"]):
			junc_fail += 1
	for id in _order:
		var st: Dictionary = _stats[id]
		roads[id] = str(st["status"]).to_lower()
		if str(st["status"]) == "FAIL":
			failed += 1
		samples += int(st["samples"])
		hits += int(st["hits"])
		max_step_a = maxf(max_step_a, float(st["max_step_along"]))
		max_step_c = maxf(max_step_c, float(st["max_step_across"]))
		max_drop = maxf(max_drop, float(st["max_drop"]))
		if int(st["gap_n"]) > 0:
			if not gap_init:
				max_gap = float(st["max_gap"])
				min_gap = float(st["min_gap"])
				gap_init = true
			else:
				max_gap = maxf(max_gap, float(st["max_gap"]))
				min_gap = minf(min_gap, float(st["min_gap"]))
		rows.append({
			"id": id,
			"name": str(st["name"]),
			"status": str(st["status"]),
			"metres": float(st["metres"]),
			"samples": int(st["samples"]),
			"hit_rate": 0.0 if int(st["samples"]) == 0 else float(st["hits"]) / float(st["samples"]),
			"max_step_along_m": float(st["max_step_along"]),
			"max_step_across_m": float(st["max_step_across"]),
			"max_gap_m": float(st["max_gap"]),
			"min_gap_m": float(st["min_gap"]),
			"max_edge_drop_m": float(st["max_drop"]),
			"edge_drop_at": st["max_drop_at"],
			"cone_tests": int(st["cone_tests"]),
			"cone_fails": int(st["cone_fails"]),
			"junction_dev_m": float(st["junc_dev"]),
			"junction_tilt": float(st["junc_tilt"]),
			"junction_tilt_limit": float(st["junc_limit"]),
			"unclassified_ends": int(st["unclassified"]),
			"ends": st["ends"],
			"tests": {
				"hit": bool(st["hit_pass"]),
				"step": bool(st["step_pass"]),
				"gap": bool(st["gap_pass"]),
				"edge_drop": bool(st["drop_pass"]),
				"cone": bool(st["cone_pass"]),
				"junction": bool(st["junc_pass"]),
				"ends": bool(st["end_pass"]),
			},
		})
	var network_pass := failed == 0 and _components == 1
	return {
		"spec": "Road System Spec 2026-10-16 section 5",
		"measure_only": true,
		"thresholds": {
			"hit_rate": 1.0,
			"step_along_m": STEP_ALONG,
			"step_across_m": STEP_ACROSS,
			"gap_m": [0.0, GAP_MAX],
			"edge_drop_m": DROP_MAX,
			"junction_dev_m": JUNC_DEV,
			"junction_tilt": [JUNC_TILT, JUNC_TILT_STEEP],
			"cone_below_m": CONE_BELOW,
		},
		"network": {
			"status": "PASS" if network_pass else "FAIL",
			"roads": _order.size(),
			"roads_pass": _order.size() - failed,
			"roads_fail": failed,
			"samples": samples,
			"hit_rate": 0.0 if samples == 0 else float(hits) / float(samples),
			"max_step_along_m": max_step_a,
			"max_step_across_m": max_step_c,
			"max_gap_m": max_gap,
			"min_gap_m": min_gap,
			"max_edge_drop_m": max_drop,
			"cone_tests": _cone_tests,
			"cone_fails": _cone_fails,
			"junctions": _junctions.size(),
			"junctions_fail": junc_fail,
			"components": _components,
			"worst": _worst,
		},
		"roads": roads,
		"per_road": rows,
		"junctions": _junctions,
		"regressions": _regressions,
		"failures": _failures,
	}


func _write(payload: Dictionary) -> PackedStringArray:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_diag"))
	var json_path := "res://_diag/road_report.json"
	var md_path := "res://_diag/road_report.md"
	var jf := FileAccess.open(json_path, FileAccess.WRITE)
	if jf == null:
		push_error("road_report.json failed: %s" % error_string(FileAccess.get_open_error()))
		quit(1)
		return PackedStringArray()
	jf.store_string(JSON.stringify(payload, "\t"))
	jf.close()
	var mf := FileAccess.open(md_path, FileAccess.WRITE)
	if mf == null:
		push_error("road_report.md failed: %s" % error_string(FileAccess.get_open_error()))
		quit(1)
		return PackedStringArray()
	mf.store_string(_markdown(payload))
	mf.close()
	return PackedStringArray([json_path, md_path])


func _markdown(payload: Dictionary) -> String:
	var net: Dictionary = payload["network"]
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Road report baseline")
	lines.append("")
	lines.append("Measure only. Thresholds from the Road System Spec acceptance table. Deck and bridge samples are exempt from the terrain-gap test because the stamp is skipped under them. Along step is the 1 m slope break, so a steady grade is not counted as a lip. Across step subtracts the design crown and bank.")
	lines.append("")
	lines.append("Network **%s**. %d roads, %d pass, %d fail. Samples %d. Hit rate %.2f%%. Components %d." % [
		str(net["status"]), int(net["roads"]), int(net["roads_pass"]), int(net["roads_fail"]),
		int(net["samples"]), 100.0 * float(net["hit_rate"]), int(net["components"]),
	])
	lines.append("")
	lines.append("| Metric | Value | Limit |")
	lines.append("|---|---:|---:|")
	lines.append("| Max along step | %.3f m | 0.020 m |" % float(net["max_step_along_m"]))
	lines.append("| Max across step | %.3f m | 0.030 m |" % float(net["max_step_across_m"]))
	lines.append("| Gap min / max | %.3f / %.3f m | 0.000 to 0.050 m |" % [float(net["min_gap_m"]), float(net["max_gap_m"])])
	lines.append("| Max edge drop with no barrier | %.2f m | 3.00 m |" % float(net["max_edge_drop_m"]))
	lines.append("| Cone fails | %d / %d | 0 |" % [int(net["cone_fails"]), int(net["cone_tests"])])
	lines.append("| Junctions failing | %d / %d | 0 |" % [int(net["junctions_fail"]), int(net["junctions"])])
	lines.append("")
	lines.append("| Road | Status | Hit | Step along | Step across | Gap min | Gap max | Edge drop | Cone fails | Junction dev | Ends |")
	lines.append("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
	for row in payload["per_road"]:
		var item: Dictionary = row
		lines.append("| %s | %s | %.1f%% | %.3f | %.3f | %.3f | %.3f | %.2f | %d | %.3f | %d |" % [
			str(item["id"]), str(item["status"]), 100.0 * float(item["hit_rate"]),
			float(item["max_step_along_m"]), float(item["max_step_across_m"]),
			float(item["min_gap_m"]), float(item["max_gap_m"]), float(item["max_edge_drop_m"]),
			int(item["cone_fails"]), float(item["junction_dev_m"]), int(item["unclassified_ends"]),
		])
	lines.append("")
	lines.append("## Regressions")
	lines.append("")
	for rec in payload["regressions"]:
		var item: Dictionary = rec
		lines.append("- **%s** %s. %s at (%.1f, %.1f). %s" % [
			"PASS" if bool(item.get("pass", false)) else "FAIL",
			str(item.get("id", "")),
			str(item.get("note", "")),
			float(item.get("x", 0.0)),
			float(item.get("z", 0.0)),
			_reg_detail(item),
		])
	lines.append("")
	lines.append("## Worst locations")
	lines.append("")
	for rec in net["worst"]:
		var item: Dictionary = rec
		lines.append("- %s %s at (%.1f, %.1f) value %.3f limit %.3f" % [
			str(item["road"]), str(item["test"]), float(item["x"]), float(item["z"]), float(item["value"]), float(item["limit"]),
		])
	lines.append("")
	return "\n".join(lines)


func _reg_detail(item: Dictionary) -> String:
	var bits: PackedStringArray = PackedStringArray()
	if item.has("road") and str(item["road"]) != "":
		bits.append("road %s" % str(item["road"]))
	if item.has("gap_m"):
		bits.append("gap %.3f m" % float(item["gap_m"]))
	if item.has("step_m"):
		bits.append("step %.3f m" % float(item["step_m"]))
	if item.has("dev_m"):
		bits.append("dev %.3f m tilt %.3f" % [float(item["dev_m"]), float(item.get("tilt", 0.0))])
	if item.has("seam_m"):
		bits.append("seam %.3f m" % float(item["seam_m"]))
	if item.has("hit"):
		bits.append("hit %s" % str(item["hit"]))
	return ", ".join(bits)


func _print_lines(payload: Dictionary) -> void:
	var net: Dictionary = payload["network"]
	print("NETWORK %s roads=%d pass=%d fail=%d hit=%.2f components=%d" % [
		str(net["status"]), int(net["roads"]), int(net["roads_pass"]), int(net["roads_fail"]),
		100.0 * float(net["hit_rate"]), int(net["components"]),
	])
