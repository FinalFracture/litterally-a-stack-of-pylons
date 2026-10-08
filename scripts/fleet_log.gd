extends Node

# One row per driving car. The id is the car node name (City01, ...), which traffic assigns once.
# Beats are once a second. Path, halt, terrain, cone, light, and stop changes are their own rows.
# Set PYLONS_FLEET_SEC to a number to quit after that many seconds of traffic time and to drop
# a cone wall, a standing pedestrian, and a frozen wreck so those responses show up in the log.

const _CONE := preload("res://scenes/player/standard_cone.tscn")
const BEAT_SEC := 1.0
const TERRAIN_SEC := 0.5
const RED_HOLD_SEC := 9.0

var _file: FileAccess
var _time := 0.0
var _frame := 0
var _clock := false
var _limit := 0.0
var _cars: Dictionary = {}
var _gone: Dictionary = {}
var _stim := {"cone": false, "guide": false, "ped": false, "wreck": false}
var _stim_ids: Dictionary = {}
var _flips := 0
var _run_red := 0
var _blew_stop := 0
var _max_stuck := 0.0
var _max_stuck_name := ""
var _over10: Dictionary = {}
var _cone_on := 0
var _off_samples := 0
var _terrain_samples := 0
var _speed_sum := 0.0
var _speed_n := 0
var _moving_n := 0
var _quit := false


func _ready() -> void:
	var path := ProjectSettings.globalize_path("res://../logs/traffic_fleet.log")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_error("fleet log failed: %s" % path)
		return
	var raw := OS.get_environment("PYLONS_FLEET_SEC")
	if raw != "":
		_limit = float(raw)
	_file.store_line("t\tframe\tevent\tid\tkind\tx\tz\thx\thz\tspd\ttarget\twhy\tpath\toffers\tlight\tlight_m\tstop\tstop_m\thalt\tasphalt\tbody\toff\troad\tintel\tagg\tgap\twant\tcones\tpassing\tholding\tescape\tidle\tstuck\tblockers\tpts")
	_file.store_line("# id is the unique car name. beat rows are 1 Hz. Sliding along the same path is not a path row.")


func _physics_process(delta: float) -> void:
	if _file == null or _quit:
		return
	var driving := _hitters()
	if not _clock:
		if driving.size() < 10:
			return
		_clock = true
		_time = 0.0
		_store(["0.000", "0", "clock", str(driving.size()), "", "", "", "", "", "", "", "fleet clock started", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""])
	_time += delta
	_frame += 1
	var city := _city()
	var seen: Dictionary = {}
	for node in driving:
		var car := node as Node3D
		var id := car.get_instance_id()
		seen[id] = true
		_watch(car, city, delta)
	var missing: Array[int] = []
	for key in _cars.keys():
		var known := int(key)
		if not seen.has(known):
			missing.append(known)
	for id in missing:
		var rec: Dictionary = _cars[id]
		var last: Vector3 = rec.get("pos", Vector3.ZERO)
		_store_event("gone", str(rec.get("name", "")), rec, last, 0.0, city)
		_gone[id] = true
		_cars.erase(id)
	if _limit > 0.0:
		_stimuli()
		var tick := int(_time / 10.0)
		if tick != int((_time - delta) / 10.0):
			print("FLEET_TICK %0.0f cars=%d" % [_time, _cars.size()])
		if _time >= _limit:
			_finish()
	elif int(_time * 2.0) != int((_time - delta) * 2.0):
		_file.flush()


func _watch(car: Node3D, city: Node, delta: float) -> void:
	var id := car.get_instance_id()
	var rec: Dictionary = _cars.get(id, {})
	if rec.is_empty():
		rec = _fresh(car)
		_cars[id] = rec
		_store_event("born", car.name, rec, car.global_position, 0.0, city)
	rec["name"] = car.name
	rec["pos"] = car.global_position
	var shove_mark: Variant = car.get("shove_mark")
	if shove_mark is String and str(shove_mark) != "":
		car.set("shove_mark", "")
		_store_event("shove", car.name, rec, car.global_position, _speed(car), city)
	var sight := _sight(car)
	var spd := _speed(car)
	rec["spd_sum"] = float(rec["spd_sum"]) + spd
	rec["spd_n"] = int(rec["spd_n"]) + 1
	_speed_sum += spd
	_speed_n += 1
	if spd > 1.2:
		_moving_n += 1
		rec["move_s"] = float(rec["move_s"]) + delta
	else:
		rec["slow_s"] = float(rec["slow_s"]) + delta
	var nose := _nose(car)
	if bool(rec["have_nose"]) and nose.length_squared() > 0.01 and spd > 0.4:
		var prev: Vector3 = rec["nose"]
		if prev.length_squared() > 0.01 and prev.dot(nose) < -0.2:
			_flips += 1
			_store_event("flip", car.name, rec, car.global_position, spd, city)
	if nose.length_squared() > 0.01:
		rec["nose"] = nose
		rec["have_nose"] = true
	if bool(car.get("_wrecked")) and not bool(rec["wrecked"]):
		rec["wrecked"] = true
		_store_event("wreck", car.name, rec, car.global_position, spd, city)
	_apply_sight(car, rec, sight, spd, city, delta)
	_track_stall(car, rec, spd, city, delta)
	var beat_at: float = float(rec["beat"])
	if _time - beat_at >= BEAT_SEC:
		rec["beat"] = _time
		_store_event("beat", car.name, rec, car.global_position, spd, city)


func _apply_sight(car: Node3D, rec: Dictionary, sight: Dictionary, spd: float, city: Node, delta: float) -> void:
	if sight.is_empty():
		return
	var kind := str(sight.get("path_kind", ""))
	var offer := str(sight.get("path_offer", ""))
	var alt := int(sight.get("path_alt", 0))
	var points: PackedVector3Array = _path_of(sight)
	var shape := _shape(points)
	var path_changed := kind != str(rec["kind"]) or offer != str(rec["offer"]) or alt != int(rec["alt"]) or shape != str(rec["shape"])
	rec["kind"] = kind
	rec["offer"] = offer
	rec["alt"] = alt
	rec["shape"] = shape
	rec["sight"] = sight
	rec["why"] = str(sight.get("why", ""))
	var halt := str(sight.get("halt", ""))
	if halt != str(rec["halt"]):
		rec["halt"] = halt
		_store_event("halt", car.name, rec, car.global_position, spd, city)
	var light := str(sight.get("light", "none"))
	var stop := str(sight.get("stop", "none"))
	if light != str(rec["light"]) or stop != str(rec["stop"]):
		rec["light"] = light
		rec["stop"] = stop
		_store_event("signal", car.name, rec, car.global_position, spd, city)
	var cones := bool(sight.get("on_cones", false))
	if cones != bool(rec["cones"]):
		rec["cones"] = cones
		if cones:
			_cone_on += 1
		_store_event("cone", car.name, rec, car.global_position, spd, city)
	var light_m: float = float(sight.get("light_m", 999.0))
	var stop_m: float = float(sight.get("stop_m", 999.0))
	if light == "red" and light_m > 0.2 and light_m < 1.6 and spd > 2.0:
		if not bool(rec["run_red"]):
			rec["run_red"] = true
			_run_red += 1
			_store_event("run_red", car.name, rec, car.global_position, spd, city)
	elif light != "red" or light_m > 14.0 or light_m < -1.0:
		rec["run_red"] = false
	if stop == "wait" and halt == "stop" and stop_m < -0.4 and spd > 1.6:
		if not bool(rec["blew"]):
			rec["blew"] = true
			_blew_stop += 1
			_store_event("blew_stop", car.name, rec, car.global_position, spd, city)
	elif stop != "wait":
		rec["blew"] = false
	var probe_at: float = float(rec["probe"])
	if city != null and _time - probe_at >= TERRAIN_SEC:
		rec["probe"] = _time
		var surf := _surface(car, city)
		_terrain_samples += 1
		var body_on := bool(surf["body"])
		var center_on := bool(surf["center"])
		var off: float = float(surf["off"])
		if not body_on:
			_off_samples += 1
			rec["off_s"] = float(rec["off_s"]) + TERRAIN_SEC
		if center_on != bool(rec["asphalt"]) or body_on != bool(rec["body"]) or (off >= 0.08) != (float(rec["off"]) >= 0.08):
			rec["asphalt"] = center_on
			rec["body"] = body_on
			rec["off"] = off
			rec["road"] = str(surf["road"])
			_store_event("terrain", car.name, rec, car.global_position, spd, city)
		else:
			rec["off"] = off
			rec["road"] = str(surf["road"])
	if path_changed and str(rec["born_path"]) == "1":
		_store_event("path", car.name, rec, car.global_position, spd, city)
	rec["born_path"] = "1"


func _fresh(car: Node3D) -> Dictionary:
	return {
		"name": car.name,
		"kind": "",
		"offer": "",
		"alt": -1,
		"shape": "",
		"halt": "",
		"light": "",
		"stop": "",
		"cones": false,
		"nose": Vector3.ZERO,
		"have_nose": false,
		"asphalt": true,
		"body": true,
		"off": 0.0,
		"road": "",
		"sight": {},
		"why": "",
		"beat": -10.0,
		"probe": -10.0,
		"stuck_t": 0.0,
		"stuck": false,
		"anchor": Vector3.ZERO,
		"have_anchor": false,
		"stall_t": 0.0,
		"stall_max": 0.0,
		"stall_marks": 0,
		"red_t": 0.0,
		"run_red": false,
		"blew": false,
		"wrecked": false,
		"born_path": "0",
		"spd_sum": 0.0,
		"spd_n": 0,
		"move_s": 0.0,
		"slow_s": 0.0,
		"off_s": 0.0,
	}


func _stimuli() -> void:
	if not bool(_stim["cone"]) and _time >= 12.0:
		_stim["cone"] = true
		_drop_line("cone_wall")
	if not bool(_stim["guide"]) and _time >= 20.0:
		_stim["guide"] = true
		_drop_line("cone_guide")
	if not bool(_stim["ped"]) and _time >= 28.0:
		_stim["ped"] = true
		_drop_ped()
	if not bool(_stim["wreck"]) and _time >= 44.0:
		_stim["wreck"] = true
		_drop_wreck()


func _ahead_spot(car: Node3D, dist: float) -> Dictionary:
	var fwd := _nose(car)
	var pos := car.global_position + fwd * dist
	var sight: Variant = car.get("drive_sight")
	if sight is Dictionary:
		var raw: Variant = (sight as Dictionary).get("path")
		if raw is PackedVector3Array:
			var path: PackedVector3Array = raw
			var walked := 0.0
			var prev := car.global_position
			var origin := car.global_position
			for point in path:
				var step := Vector3(point.x - prev.x, 0.0, point.z - prev.z)
				var leng := step.length()
				if leng < 0.05:
					prev = point
					continue
				var mid := Vector3(prev.x - origin.x, 0.0, prev.z - origin.z)
				if walked < 0.1 and mid.length() > 0.5 and mid.normalized().dot(fwd) < -0.2:
					prev = point
					continue
				if walked + leng >= dist:
					var hop: float = (dist - walked) / leng
					pos = prev.lerp(point, hop)
					fwd = step / leng
					break
				walked += leng
				prev = point
				fwd = step / leng
	var rel := pos - car.global_position
	rel.y = 0.0
	var nose := _nose(car)
	# A path vertex behind the bumper is not the lane ahead. Drop the obstacle down the nose instead.
	if rel.length() < dist * 0.5 or rel.dot(nose) < dist * 0.5:
		pos = car.global_position + nose * dist
		fwd = nose
	pos.y = 0.0
	return {"pos": pos, "dir": fwd}


func _drop_line(mode: String) -> void:
	var car := _candidate()
	if car == null:
		_store(["%0.3f" % _time, str(_frame), "stim", "", "", "", "", "", "", "", "", mode + " missed", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""])
		return
	_stim_ids[car.get_instance_id()] = mode
	var fwd := _nose(car)
	var count := 5
	var span := 1.15
	var along := 13.0
	if mode != "cone_wall":
		count = 6
		span = 1.7
		along = 8.0
	for i in count:
		var travel := along
		if mode != "cone_wall":
			travel = along + float(i) * span
		var spot := _ahead_spot(car, travel)
		var at := Vector3.ZERO
		var dir := fwd
		var raw_pos: Variant = spot["pos"]
		var raw_dir: Variant = spot["dir"]
		if raw_pos is Vector3:
			at = raw_pos
		if raw_dir is Vector3:
			dir = raw_dir
		fwd = dir
		var right := _side(dir)
		if mode == "cone_wall":
			at += right * ((float(i) - 2.0) * span)
		else:
			at += right * 1.05
		at.y = 0.0
		_cone(at)
	_store(["%0.3f" % _time, str(_frame), "stim", car.name, str(car.get("vehicle_kind")), "%0.2f" % car.global_position.x, "%0.2f" % car.global_position.z, "%0.2f" % fwd.x, "%0.2f" % fwd.z, "%0.2f" % _speed(car), "", mode, "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""])


func _drop_ped() -> void:
	var car := _candidate()
	if car == null:
		_store(["%0.3f" % _time, str(_frame), "stim", "", "", "", "", "", "", "", "", "ped missed", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""])
		return
	_stim_ids[car.get_instance_id()] = "ped"
	var spot := _ahead_spot(car, 14.0)
	var fwd := _nose(car)
	var at := car.global_position + fwd * 14.0
	var raw_pos: Variant = spot["pos"]
	var raw_dir: Variant = spot["dir"]
	if raw_pos is Vector3:
		at = raw_pos
	if raw_dir is Vector3:
		fwd = raw_dir
	at.y = 0.85
	var body := CharacterBody3D.new()
	body.name = "FleetPed"
	body.collision_layer = 1
	body.collision_mask = 1
	body.set_script(load("res://scripts/pedestrian.gd"))
	body.set("points", PackedVector3Array([at, at]))
	body.set("point_index", 0)
	body.set("from_point", at)
	body.set("to_point", at)
	body.set("speed", 0.0)
	body.position = at
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.6
	capsule.radius = 0.28
	shape.shape = capsule
	body.add_child(shape)
	var home := get_tree().get_first_node_in_group("walker_home")
	if home == null:
		home = get_parent()
	home.add_child(body)
	body.global_position = at
	_store(["%0.3f" % _time, str(_frame), "stim", car.name, str(car.get("vehicle_kind")), "%0.2f" % at.x, "%0.2f" % at.z, "%0.2f" % fwd.x, "%0.2f" % fwd.z, "%0.2f" % _speed(car), "", "pedestrian in lane", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""])


func _drop_wreck() -> void:
	var car := _candidate()
	if car == null:
		_store(["%0.3f" % _time, str(_frame), "stim", "", "", "", "", "", "", "", "", "wreck missed", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""])
		return
	_stim_ids[car.get_instance_id()] = "wreck"
	var spot := _ahead_spot(car, 16.0)
	var fwd := _nose(car)
	var at := car.global_position + fwd * 16.0
	var raw_pos: Variant = spot["pos"]
	var raw_dir: Variant = spot["dir"]
	if raw_pos is Vector3:
		at = raw_pos
	if raw_dir is Vector3:
		fwd = raw_dir
	at.y = 0.65
	var body := RigidBody3D.new()
	body.name = "FleetWreck"
	body.freeze = true
	body.collision_layer = 1
	body.collision_mask = 1
	body.add_to_group("vehicle")
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 1.25, 1.3)
	shape.shape = box
	shape.position = Vector3(0.0, 0.4, 0.0)
	body.add_child(shape)
	var home := get_parent()
	home.add_child(body)
	body.global_position = at
	_store(["%0.3f" % _time, str(_frame), "stim", car.name, str(car.get("vehicle_kind")), "%0.2f" % at.x, "%0.2f" % at.z, "%0.2f" % fwd.x, "%0.2f" % fwd.z, "%0.2f" % _speed(car), "", "frozen wreck in lane", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""])


func _candidate() -> Node3D:
	var soul := get_tree().get_first_node_in_group("soul") as Node3D
	var best: Node3D = null
	var best_spd := 3.0
	for node in _hitters():
		var car := node as Node3D
		if _stim_ids.has(car.get_instance_id()):
			continue
		if bool(car.get("_wrecked")):
			continue
		var spd := _speed(car)
		if spd < best_spd:
			continue
		if soul != null:
			var dx: float = car.global_position.x - soul.global_position.x
			var dz: float = car.global_position.z - soul.global_position.z
			if dx * dx + dz * dz < 324.0:
				continue
		var sight := _sight(car)
		if str(sight.get("path_kind", "")) != "route":
			continue
		if str(sight.get("halt", "")) != "":
			continue
		var fwd := _nose(car)
		if fwd == Vector3.ZERO:
			continue
		var ahead := car.global_position + fwd * 12.0
		var city := _city()
		if city != null and city.has_method("on_asphalt") and not bool(city.call("on_asphalt", ahead.x, ahead.z)):
			continue
		best = car
		best_spd = spd
	return best


func _cone(at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "FleetCone"
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 1
	body.add_to_group("stack_target")
	var piece := _CONE.instantiate() as Node3D
	piece.position = Vector3(0.0, GameConstants.STANDARD_H * 0.5, 0.0)
	body.add_child(piece)
	get_parent().add_child(body)


func _store_event(event: String, id: String, rec: Dictionary, at: Vector3, spd: float, city: Node) -> void:
	var sight: Dictionary = rec.get("sight", {})
	if not (sight is Dictionary):
		sight = {}
	var nose: Vector3 = rec.get("nose", Vector3.ZERO)
	var pos := at
	if pos == Vector3.ZERO and id != "":
		pos = at
	var points := _path_of(sight)
	var blockers := _blockers(sight)
	_store([
		"%0.3f" % _time,
		str(_frame),
		event,
		id,
		_kind_of(id),
		"%0.2f" % pos.x,
		"%0.2f" % pos.z,
		"%0.2f" % nose.x,
		"%0.2f" % nose.z,
		"%0.2f" % spd,
		"%0.2f" % float(sight.get("target", 0.0)),
		str(sight.get("why", rec.get("why", ""))),
		str(sight.get("path_kind", rec.get("kind", ""))),
		str(sight.get("path_offer", rec.get("offer", ""))),
		str(sight.get("light", rec.get("light", ""))),
		"%0.1f" % float(sight.get("light_m", 999.0)),
		str(sight.get("stop", rec.get("stop", ""))),
		"%0.1f" % float(sight.get("stop_m", 999.0)),
		str(sight.get("halt", rec.get("halt", ""))),
		"1" if bool(rec.get("asphalt", true)) else "0",
		"1" if bool(rec.get("body", true)) else "0",
		"%0.2f" % float(rec.get("off", 0.0)),
		str(rec.get("road", "")),
		"%0.2f" % float(sight.get("intel", 0.0)),
		"%0.2f" % float(sight.get("agg", 0.0)),
		"%0.2f" % float(sight.get("follow_gap", -1.0)),
		"%0.2f" % float(sight.get("follow_want", -1.0)),
		"1" if bool(sight.get("on_cones", rec.get("cones", false))) else "0",
		"1" if bool(sight.get("passing", false)) else "0",
		"1" if bool(sight.get("holding", false)) else "0",
		"1" if bool(sight.get("escaping", false)) else "0",
		"%0.1f" % float(sight.get("idle", 0.0)),
		"%0.1f" % float(rec.get("stall_t", 0.0)),
		blockers,
		_poly(points),
	])


func _track_stall(car: Node3D, rec: Dictionary, spd: float, city: Node, delta: float) -> void:
	if bool(car.get("_wrecked")):
		rec["stall_t"] = 0.0
		rec["red_t"] = 0.0
		rec["have_anchor"] = false
		return
	var sight: Dictionary = rec.get("sight", {})
	var pos := car.global_position
	var light_m := float(sight.get("light_m", 999.0))
	var red_hold := str(sight.get("halt", "")) == "red" and light_m > -1.2 and light_m < 22.0
	if red_hold:
		rec["red_t"] = float(rec.get("red_t", 0.0)) + delta
	else:
		rec["red_t"] = 0.0
	if red_hold and float(rec["red_t"]) < RED_HOLD_SEC:
		rec["stall_t"] = 0.0
		rec["anchor"] = pos
		rec["have_anchor"] = true
		rec["stall_marks"] = 0
		return
	if not bool(rec.get("have_anchor", false)):
		rec["anchor"] = pos
		rec["have_anchor"] = true
	var anchor: Vector3 = rec["anchor"]
	var moved := Vector2(pos.x - anchor.x, pos.z - anchor.z).length()
	if moved >= 1.6:
		var was := float(rec.get("stall_t", 0.0))
		if was >= 4.0:
			_store_event("moved", car.name, rec, pos, spd, city)
		rec["stall_t"] = 0.0
		rec["anchor"] = pos
		rec["stall_marks"] = 0
		return
	rec["stall_t"] = float(rec.get("stall_t", 0.0)) + delta
	var stall := float(rec["stall_t"])
	if stall > float(rec.get("stall_max", 0.0)):
		rec["stall_max"] = stall
	if stall > _max_stuck:
		_max_stuck = stall
		_max_stuck_name = car.name
	var mark := int(rec.get("stall_marks", 0))
	var want := 0
	if stall >= 10.0:
		want = 3
	elif stall >= 8.0:
		want = 2
	elif stall >= 4.0:
		want = 1
	if want <= mark:
		return
	rec["stall_marks"] = want
	var label := "stall4"
	if want == 2:
		label = "stall8"
	elif want == 3:
		label = "stall10"
		_over10[car.name] = stall
	_store_event(label, car.name, rec, pos, spd, city)


func _kind_of(id: String) -> String:
	if id == "":
		return ""
	var node := get_parent().get_node_or_null(id) if get_parent() != null else null
	if node == null:
		return ""
	return str(node.get("vehicle_kind"))


func _finish() -> void:
	_quit = true
	var stalled := 0
	var worst_name := ""
	var worst_slow := 0.0
	for key in _cars.keys():
		var rec: Dictionary = _cars[key]
		var slow: float = float(rec["slow_s"])
		var samples := int(rec["spd_n"])
		var mean := 0.0
		if samples > 0:
			mean = float(rec["spd_sum"]) / float(samples)
		if mean < 1.0:
			stalled += 1
		if slow > worst_slow:
			worst_slow = slow
			worst_name = str(rec["name"])
		_store_event("end", str(rec["name"]), rec, Vector3.ZERO, mean, _city())
	var mean_spd := 0.0
	if _speed_n > 0:
		mean_spd = _speed_sum / float(_speed_n)
	var move_share := 0.0
	if _speed_n > 0:
		move_share = float(_moving_n) / float(_speed_n)
	var off_share := 0.0
	if _terrain_samples > 0:
		off_share = float(_off_samples) / float(_terrain_samples)
	for key in _cars.keys():
		var open: Dictionary = _cars[key]
		var open_max: float = float(open.get("stall_max", 0.0))
		if open_max > 10.0:
			_over10[str(open.get("name", ""))] = open_max
		if open_max > _max_stuck:
			_max_stuck = open_max
			_max_stuck_name = str(open.get("name", ""))
	var who := ""
	for name in _over10.keys():
		who += " " + str(name)
	var line := "FLEET_DONE t=%0.1f cars=%d mean_spd=%0.2f moving=%0.2f off_share=%0.3f flips=%d run_red=%d blew_stop=%d stuck=%d cone_on=%d stalled=%d slowest=%s %0.1fs max_stuck=%0.2f stuck_car=%s over10=%d%s" % [
		_time, _cars.size() + _gone.size(), mean_spd, move_share, off_share, _flips, _run_red, _blew_stop, _over10.size(), _cone_on, stalled, worst_name, worst_slow, _max_stuck, _max_stuck_name, _over10.size(), who,
	]
	_file.store_line("# " + line)
	_file.flush()
	_file.close()
	_file = null
	print(line)
	get_tree().quit()


func _hitters() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("hitter"):
		if node is Node3D and bool(node.get("trip")):
			out.append(node as Node3D)
	return out


func _sight(car: Node3D) -> Dictionary:
	var raw: Variant = car.get("drive_sight")
	if raw is Dictionary:
		return raw
	return {}


func _path_of(sight: Dictionary) -> PackedVector3Array:
	var raw: Variant = sight.get("path", PackedVector3Array())
	if raw is PackedVector3Array:
		return raw
	return PackedVector3Array()


func _speed(car: Node3D) -> float:
	var raw: Variant = car.get("travel_velocity")
	if raw is Vector3:
		var vel := raw as Vector3
		vel.y = 0.0
		return vel.length()
	return 0.0


func _surface(car: Node3D, city: Node) -> Dictionary:
	var origin := car.global_position
	var empty := {"center": true, "body": true, "off": 0.0, "road": ""}
	if city == null or not city.has_method("surface_at"):
		return empty
	var fwd := _nose(car)
	var right := _side(fwd)
	var hx := 1.3
	var hz := 0.65
	var shape_node := car.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node != null and shape_node.shape is BoxShape3D:
		var box := shape_node.shape as BoxShape3D
		hx = box.size.x * 0.5
		hz = box.size.z * 0.5
	var center: Dictionary = _probe(city, origin.x, origin.z)
	var worst := 0.0
	var road := str(center.get("road", ""))
	var body_on := true
	var corners: Array[Vector3] = [Vector3.ZERO]
	if fwd != Vector3.ZERO:
		corners.append(fwd * hx + right * hz)
		corners.append(fwd * hx - right * hz)
		corners.append(-fwd * hx + right * hz)
		corners.append(-fwd * hx - right * hz)
	for offset in corners:
		var hit: Dictionary = _probe(city, origin.x + offset.x, origin.z + offset.z)
		var gap: float = float(hit.get("off", 0.0))
		if gap >= 0.08:
			body_on = false
		if gap > worst:
			worst = gap
			road = str(hit.get("road", road))
	return {"center": bool(center.get("asphalt", false)), "body": body_on, "off": worst, "road": road}


func _probe(city: Node, x: float, z: float) -> Dictionary:
	var raw: Variant = city.call("surface_at", x, z)
	if raw is Dictionary:
		return raw
	return {"asphalt": true, "off": 0.0, "road": ""}


func _blockers(sight: Dictionary) -> String:
	var cone := 0
	var ped := 0
	var other := 0
	var wreck := 0
	var raw: Variant = sight.get("blockers", [])
	if raw is Array:
		for item in raw:
			if not (item is Dictionary):
				continue
			var rec: Dictionary = item
			if not bool(rec.get("on_path", false)):
				continue
			var kind := str(rec.get("kind", ""))
			if kind == "cone" or kind == "guide":
				cone += 1
			elif kind == "ped":
				ped += 1
			elif kind == "wreck":
				wreck += 1
			elif kind == "car":
				other += 1
	return "cone:%d,ped:%d,car:%d,wreck:%d" % [cone, ped, other, wreck]


func _shape(points: PackedVector3Array) -> String:
	if points.size() < 2:
		return "n%d" % points.size()
	var origin := points[0]
	var bend := points[mini(3, points.size() - 1)]
	var tail := points[points.size() - 1]
	return "%d,%d|%d,%d|%d" % [
		int(roundf(bend.x - origin.x)),
		int(roundf(bend.z - origin.z)),
		int(roundf(tail.x / 20.0)),
		int(roundf(tail.z / 20.0)),
		points.size(),
	]


func _poly(points: PackedVector3Array) -> String:
	if points.is_empty():
		return ""
	var out := PackedStringArray()
	var step := 1
	if points.size() > 8:
		step = ceili(float(points.size()) / 8.0)
	var i := 0
	while i < points.size():
		out.append("%0.1f,%0.1f" % [points[i].x, points[i].z])
		i += step
	var last := points.size() - 1
	if (last % step) != 0:
		out.append("%0.1f,%0.1f" % [points[last].x, points[last].z])
	return ";".join(out)


func _store(cells: Array) -> void:
	if _file == null:
		return
	var out := PackedStringArray()
	for value in cells:
		out.append(str(value).replace("\t", " ").replace("\n", " "))
	_file.store_line("\t".join(out))


func _nose(car: Node3D) -> Vector3:
	var heading := car.get_node_or_null("Heading") as Node3D
	if heading == null:
		return Vector3.ZERO
	var facing := -heading.global_transform.basis.x
	facing.y = 0.0
	if facing.length_squared() < 0.01:
		return Vector3.ZERO
	return facing.normalized()


func _side(fwd: Vector3) -> Vector3:
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	if side.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, 1.0)
	return side.normalized()


func _city() -> Node:
	var traffic := get_parent()
	if traffic == null:
		return null
	var main := traffic.get_parent()
	if main == null:
		return null
	return main.get_node_or_null("City")


func _exit_tree() -> void:
	if _file == null:
		return
	_file.flush()
	_file.close()
	_file = null
