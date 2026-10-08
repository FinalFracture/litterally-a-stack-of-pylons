extends Node

# Cone runs on Practice Road. The car waits until Return, then tries that task.
# These tasks leave the path gate open so a cone dodge is graded once, at the end.
# Grades are written to logs/traffic_drill.log.

const _CONE := preload("res://scenes/player/standard_cone.tscn")
const _BARREL := preload("res://scenes/player/barrel.tscn")

var _tasks: Array = []
var _index := 0
var _state := "boot"
var _car: Node3D
var _time: float = 0.0
var _delta: float = 0.016
var _run_t: float = 0.0
var _file: FileAccess
var _task: Dictionary = {}
var _props: Array[Node3D] = []
var _approved: Dictionary = {}
var _seen: Dictionary = {}
var _shown_key := ""
var _pending_key := ""
var _pending_for: float = 0.0
var _yes := 0
var _no := 0
var _accepts := 0
var _rejects := 0
var _wrong: PackedStringArray = PackedStringArray()
var _panel: ColorRect
var _bar: ColorRect
var _label: Label
var _moved: float = 0.0
var _max_spd: float = 0.0
var _min_spd: float = 99.0
var _max_off: float = 0.0
var _max_lat: float = 0.0
var _yaw_acc: float = 0.0
var _prev_yaw: float = 0.0
var _have_yaw := false
var _saw_fast := false
var _saw_slow := false
var _slow_time: float = 0.0
var _min_cone: float = 99.0
var _reversed := false
var _released := false
var _prev := Vector3.ZERO
var _pose_t: float = 0.0
var _poses := 0
var _snap := ""
var _ask_reason := ""


func _ready() -> void:
	add_to_group("drive_drill")


func _physics_process(delta: float) -> void:
	# Return and Y/N stay in this file. This playtest does not start them.
	if _state == "boot":
		return
	_delta = delta
	_time += delta
	if _state == "boot":
		_arm(0)
		return
	if _state == "run":
		_run_t += delta
		_sample(delta)
		var reason := _window_done()
		if reason != "":
			_ask(reason)
	_banner()


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var code := key.physical_keycode
	var used := false
	if code == KEY_ENTER or code == KEY_KP_ENTER:
		used = _on_return()
	elif code == KEY_BACKSPACE:
		used = _on_reject()
	elif code == KEY_Y:
		used = _on_grade(true)
	elif code == KEY_N:
		used = _on_grade(false)
	if used:
		get_viewport().set_input_as_handled()


func allow_motion(car: Node) -> bool:
	if _state == "boot" or _state == "done":
		return true
	if _car == null:
		return false
	if car != _car:
		return true
	if _state == "run" or _state == "path":
		_review_path()
	if _state == "done":
		return true
	var go := _state == "run"
	if not go:
		var driver := car.get_node_or_null("Driver")
		if driver != null and driver.has_method("hold_pace"):
			driver.call("hold_pace")
	return go


func _on_return() -> bool:
	if _state == "arm":
		_run_t = 0.0
		_reset_trace()
		_state = "run"
		_event("GO t=%0.2f n=%d id=%s" % [_time, _n(), _id()])
		_banner()
		return true
	if _state == "path" and _shown_key != "":
		_approved[_shown_key] = true
		_accepts += 1
		_event("PATH_ACCEPT t=%0.2f n=%d id=%s key=%s" % [_time, _n(), _id(), _shown_key])
		_state = "run"
		_banner()
		return true
	return false


func _on_reject() -> bool:
	if _state != "path" or _car == null:
		return false
	_rejects += 1
	_event("PATH_REJECT t=%0.2f n=%d id=%s key=%s" % [_time, _n(), _id(), _shown_key])
	var driver := _car.get_node_or_null("Driver")
	if driver != null and driver.has_method("reject_path"):
		driver.call("reject_path")
	_shown_key = ""
	_pending_key = ""
	_pending_for = 0.0
	return true


func _on_grade(correct: bool) -> bool:
	if _state != "ask":
		return false
	var verdict := "correct" if correct else "wrong"
	var which := "y" if correct else "n"
	if correct:
		_yes += 1
	else:
		_no += 1
		_wrong.append("n=%d id=%s title=\"%s\"" % [_n(), _id(), _q(str(_task.get("title", "")))])
	_event("GRADE t=%0.2f n=%d id=%s verdict=%s key=%s" % [_time, _n(), _id(), verdict, which])
	_event("RESULT n=%d id=%s verdict=%s reason=%s %s" % [_n(), _id(), verdict, _ask_reason, _snap])
	_summary()
	if _index + 1 >= _tasks.size():
		_finish_round()
		return true
	_arm(_index + 1)
	return true


func _arm(index: int) -> void:
	_index = index
	_task = _tasks[index]
	_state = "arm"
	_approved.clear()
	_seen.clear()
	_shown_key = ""
	_pending_key = ""
	_pending_for = 0.0
	_released = false
	_run_t = 0.0
	_clear_props()
	_car = _find_car()
	if _car == null:
		_event("ERROR t=%0.2f missing=BlockCar" % _time)
		return
	var pts := _points_of(_task)
	_spawn_props()
	_pin()
	_car.set("speed", 7.0)
	_car.set("brake_miss", 0.0)
	_car.set("look_ahead", 6.0)
	_car.set("trip", true)
	_car.set("drill_lock", true)
	if _car.has_method("set_route"):
		var back := PackedByteArray()
		if bool(_task.get("back", false)):
			for _i in pts.size():
				back.append(1)
		_car.call("set_route", pts, back, 1)
	_car.set("route_goal", maxi(pts.size() - 1, 0))
	if _car.has_method("ack_route"):
		_car.call("ack_route")
	var face := Vector3(-1.0, 0.0, 0.0)
	if pts.size() >= 2:
		face = pts[1] - pts[0]
	if _car.has_method("park_at"):
		_car.call("park_at", pts[0], face)
	var driver := _car.get_node_or_null("Driver")
	if driver != null and driver.has_method("reset_for_drill"):
		driver.call("reset_for_drill", float(_task.get("intel", 0.55)), float(_task.get("agg", 0.55)))
	_watch(pts[0], face)
	_event("TASK t=%0.2f n=%d id=%s title=\"%s\" prompt=\"%s\"" % [_time, _n(), _id(), _q(str(_task.get("title", ""))), _q(str(_task.get("prompt", "")))])
	_event("SETUP n=%d x=%0.2f z=%0.2f pin=%d intel=%0.2f agg=%0.2f cones=%d barrels=%d route=%s" % [
		_n(), pts[0].x, pts[0].z, int(_task.get("pin", 0)), float(_task.get("intel", 0.55)), float(_task.get("agg", 0.55)),
		_vec_count(_task.get("cones", PackedVector3Array())), _vec_count(_task.get("barrels", PackedVector3Array())), _route_text(pts),
	])
	_event("WAIT_GO n=%d key=return" % _n())
	if index == 0:
		var sign := "no"
		var city := _city()
		if city != null and city.get_node_or_null("StallSign") != null:
			sign = "yes"
		print("DRILL_READY tasks=%d stall_sign=%s" % [_tasks.size(), sign])
	_banner()


func _ask(reason: String) -> void:
	_state = "ask"
	_ask_reason = reason
	_snap = _measure()
	_event("ASK t=%0.2f n=%d id=%s reason=%s %s" % [_time, _n(), _id(), reason, _snap])
	_banner()


func _finish_round() -> void:
	_state = "done"
	var traffic := get_parent()
	if traffic != null and _car != null and traffic.has_method("assign_long_trip"):
		traffic.call("assign_long_trip", _car)
	_event("DONE t=%0.2f correct=%d wrong=%d" % [_time, _yes, _no])
	for line in _wrong:
		_event("WRONG %s" % line)
	_summary()
	_banner()


func _review_path() -> void:
	var sight := _sight()
	if sight.is_empty():
		return
	if not _needs_gate(sight):
		if _state == "path":
			_state = "run"
		return
	var key := _gate_key(sight)
	if bool(_approved.get(key, false)):
		if _state == "path":
			_state = "run"
		return
	if _state == "path" and key != _shown_key and _shown_key != "":
		if key != _pending_key:
			_pending_key = key
			_pending_for = 0.0
			return
		_pending_for += _delta
		if _pending_for < 0.15:
			return
	_pending_key = key
	_pending_for = 0.0
	if _state == "path" and key == _shown_key:
		return
	_state = "path"
	_shown_key = key
	if bool(_seen.get(key, false)):
		_event("PATH_REPEAT t=%0.2f n=%d id=%s key=%s" % [_time, _n(), _id(), key])
	_seen[key] = true
	_event("PATH_PROPOSE t=%0.2f n=%d id=%s %s pts=%s" % [_time, _n(), _id(), _proposal(sight, key), _pts_text(sight)])


func _needs_gate(sight: Dictionary) -> bool:
	if bool(_task.get("open", false)):
		return false
	if int(sight.get("path_alt", 0)) > 0:
		return true
	var kind := str(sight.get("path_kind", "route"))
	if kind != "route" and kind != "":
		return true
	if _max_offset(sight) > 1.15:
		return true
	var raw: Variant = sight.get("blockers", [])
	if raw is Array:
		for item in raw:
			if not (item is Dictionary):
				continue
			var rec: Dictionary = item
			var state := str(rec.get("state", ""))
			if (state == "nudge" or state == "guide") and bool(rec.get("on_path", false)):
				return true
	return false


func _gate_key(sight: Dictionary) -> String:
	var kind := str(sight.get("path_kind", "route"))
	var offer := str(sight.get("path_offer", "natural"))
	var alt := int(sight.get("path_alt", 0))
	var bucket := int(round(_max_offset(sight)))
	return "%s|%s|%d|%d" % [kind, offer, alt, bucket]


func _proposal(sight: Dictionary, key: String) -> String:
	return "proposal=%d offer=%s kind=%s side=%s off=%0.2f key=%s why=\"%s\"" % [
		int(sight.get("path_alt", 0)),
		str(sight.get("path_offer", "natural")),
		str(sight.get("path_kind", "")),
		_side_name(sight),
		_max_offset(sight),
		key,
		_q(str(sight.get("why", ""))),
	]


func _sample(delta: float) -> void:
	if _car == null:
		return
	var pos := _car.global_position
	if _prev != Vector3.ZERO:
		_moved += Vector2(pos.x - _prev.x, pos.z - _prev.z).length()
	_prev = pos
	var spd := _speed_of(_car)
	_max_spd = maxf(_max_spd, spd)
	if _run_t > 0.25:
		_min_spd = minf(_min_spd, spd)
	if spd > 2.2:
		_saw_fast = true
	if spd < 0.35 and _in_box():
		_slow_time += delta
		_saw_slow = true
	elif spd < 0.35 and _saw_fast:
		_saw_slow = true
	var nose := _nose(_car)
	var yaw := atan2(nose.z, nose.x)
	if _have_yaw:
		_yaw_acc += wrapf(yaw - _prev_yaw, -PI, PI)
	_prev_yaw = yaw
	_have_yaw = true
	var travel: Variant = _car.get("travel_velocity")
	if travel is Vector3:
		var vel: Vector3 = travel
		vel.y = 0.0
		if vel.length() > 0.45 and nose.dot(vel.normalized()) < -0.25:
			_reversed = true
	_max_off = maxf(_max_off, _surface_off())
	_max_lat = maxf(_max_lat, _route_off())
	_note_cones()
	if bool(_task.get("release", false)) and not _released and _slow_time > 0.55:
		_released = true
		var traffic := get_parent()
		if traffic != null and traffic.has_method("pin_phase"):
			traffic.call("pin_phase", -1)
		_event("LIGHT t=%0.2f n=%d id=%s phase=free reason=stopped" % [_time, _n(), _id()])
	_pose_t += delta
	if _pose_t >= 0.5 and _poses < 16:
		_pose_t = 0.0
		_poses += 1
		_event("POSE t=%0.2f n=%d id=%s %s" % [_time, _n(), _id(), _measure()])


func _window_done() -> String:
	var watch := str(_task.get("watch", "coast"))
	var limit: float = float(_task.get("limit", 12.0))
	if watch == "hold" and _run_t >= 2.4:
		return "hold"
	if watch == "fast" and _max_spd > 3.2 and _moved > 4.0:
		return "fast"
	if watch == "coast" and _moved > 16.0:
		return "coast"
	if watch == "brake" and _saw_fast and _saw_slow:
		return "brake"
	if watch == "stop_box" and _in_box() and _slow_time > 0.9:
		return "stop_box"
	if watch == "reach" and _reached():
		return "reach"
	if watch == "escape" and _left_road():
		return "escape"
	if watch == "stall" and _in_stall() and _speed_of(_car) < 0.75:
		return "stall"
	if watch == "then_past" and _slow_time > 0.45 and _reached():
		return "then_past"
	if _run_t >= limit:
		return "timeout"
	return ""


func _reset_trace() -> void:
	_moved = 0.0
	_max_spd = 0.0
	_min_spd = 99.0
	_max_off = 0.0
	_max_lat = 0.0
	_yaw_acc = 0.0
	_have_yaw = false
	_saw_fast = false
	_saw_slow = false
	_slow_time = 0.0
	_min_cone = 99.0
	_reversed = false
	_pose_t = 0.0
	_poses = 0
	_prev = Vector3.ZERO
	if _car != null:
		_prev = _car.global_position


func _measure() -> String:
	var pos := Vector3.ZERO
	var nose := Vector3(-1.0, 0.0, 0.0)
	var spd := 0.0
	if _car != null:
		pos = _car.global_position
		nose = _nose(_car)
		spd = _speed_of(_car)
	var slow := _min_spd
	if slow > 90.0:
		slow = spd
	var sight := _sight()
	var light := str(sight.get("light", "none"))
	var stop_word := str(sight.get("stop", "none"))
	var why := _q(str(sight.get("why", "")))
	return "x=%0.2f z=%0.2f spd=%0.2f hx=%0.2f hz=%0.2f moved=%0.2f max_spd=%0.2f min_spd=%0.2f max_off=%0.2f max_lat=%0.2f yaw=%0.2f min_cone=%0.2f reversed=%d asphalt=%d light=%s stop=%s why=\"%s\"" % [
		pos.x, pos.z, spd, nose.x, nose.z, _moved, _max_spd, slow, _max_off, _max_lat, _yaw_acc, _min_cone, 1 if _reversed else 0, 1 if _surface_off() < 0.08 else 0, light, stop_word, why,
	]


func _in_box() -> bool:
	if _car == null or not bool(_task.get("has_box", false)):
		return false
	var x := _car.global_position.x
	var z := _car.global_position.z
	var x0: float = float(_task.get("x0", 0.0))
	var x1: float = float(_task.get("x1", 0.0))
	var z0: float = float(_task.get("z0", 0.0))
	var z1: float = float(_task.get("z1", 0.0))
	return x >= minf(x0, x1) and x <= maxf(x0, x1) and z >= minf(z0, z1) and z <= maxf(z0, z1)


func _left_road() -> bool:
	if _car == null:
		return false
	var sight := _sight()
	var idle: float = float(sight.get("idle", 0.0))
	if not bool(sight.get("escaping", false)):
		return false
	if _surface_off() < 0.2:
		return false
	if _speed_of(_car) <= 0.8:
		return false
	return _saw_slow or idle > 2.0


func _reached() -> bool:
	if _car == null:
		return false
	var radius: float = float(_task.get("rr", 3.5))
	var dx: float = _car.global_position.x - float(_task.get("rx", 0.0))
	var dz: float = _car.global_position.z - float(_task.get("rz", 0.0))
	return Vector2(dx, dz).length() <= radius


func _in_stall() -> bool:
	if _car == null:
		return false
	var stall := Vector3(32.0, 0.65, -10.2)
	var city := _city()
	if city != null and city.has_method("parking_stall"):
		var raw: Variant = city.call("parking_stall")
		if raw is Vector3:
			stall = raw
	var dx: float = _car.global_position.x - stall.x
	var dz: float = _car.global_position.z - stall.z
	return Vector2(dx, dz).length() < 1.8


func _note_cones() -> void:
	if _car == null:
		return
	for body in _props:
		if not is_instance_valid(body):
			continue
		var d: float = Vector2(body.global_position.x - _car.global_position.x, body.global_position.z - _car.global_position.z).length()
		if d < _min_cone:
			_min_cone = d


func _watch(at: Vector3, fwd: Vector3) -> void:
	var soul := get_tree().get_first_node_in_group("soul") as Node3D
	if soul == null:
		return
	var face := Vector3(fwd.x, 0.0, fwd.z)
	if face.length_squared() < 0.01:
		face = Vector3(-1.0, 0.0, 0.0)
	face = face.normalized()
	var left := Vector3(-face.z, 0.0, face.x)
	var spot := at + left * 8.0
	spot.y = 0.7
	var city := _city()
	if city != null and city.has_method("on_asphalt"):
		if bool(city.call("on_asphalt", spot.x, spot.z)):
			spot = at + left * 12.0
			spot.y = 0.7
	soul.global_position = spot
	if soul is CharacterBody3D:
		(soul as CharacterBody3D).velocity = Vector3.ZERO
	var aim := Vector3(at.x, soul.global_position.y, at.z)
	if soul.global_position.distance_squared_to(aim) > 0.25:
		soul.look_at(aim, Vector3.UP)
	var rig := get_tree().root.get_node_or_null("Main/CameraRig")
	if rig != null and rig.has_method("look_toward"):
		rig.call("look_toward", at)


func _pin() -> void:
	# Negative pin leaves the light cycling. A fixed phase is only for a task that asks for one.
	var phase := int(_task.get("pin", -1))
	if phase < 0:
		return
	var traffic := get_parent()
	if traffic != null and traffic.has_method("pin_phase"):
		traffic.call("pin_phase", phase)


func _spawn_props() -> void:
	var cones := _as_pts(_task.get("cones", PackedVector3Array()))
	var barrels := _as_pts(_task.get("barrels", PackedVector3Array()))
	for at in cones:
		_spawn("cone", at)
	for at in barrels:
		_spawn("barrel", at)


func _spawn(kind: String, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "DrillProp"
	body.position = Vector3(at.x, 0.0, at.z)
	body.collision_layer = 1
	body.collision_mask = 1
	body.add_to_group("stack_target")
	var scene: PackedScene = _CONE
	var lift: float = GameConstants.STANDARD_H * 0.5
	if kind == "barrel":
		scene = _BARREL
		lift = GameConstants.BARREL_H * 0.5
	var piece := scene.instantiate() as Node3D
	if piece != null:
		body.add_child(piece)
		piece.position = Vector3(0.0, lift, 0.0)
	var city := _city()
	if city != null:
		city.add_child(body)
	else:
		add_child(body)
	_props.append(body)


func _clear_props() -> void:
	for body in _props:
		if is_instance_valid(body):
			body.remove_from_group("stack_target")
			body.global_position = Vector3(0.0, -40.0, 0.0)
			body.queue_free()
	_props.clear()


func _find_car() -> Node3D:
	var traffic := get_parent()
	if traffic == null:
		return null
	var node := traffic.get_node_or_null("BlockCar")
	if node is Node3D:
		return node as Node3D
	return null


func _city() -> Node:
	var traffic := get_parent()
	if traffic == null or traffic.get_parent() == null:
		return null
	return traffic.get_parent().get_node_or_null("City")


func _sight() -> Dictionary:
	if _car == null:
		return {}
	var raw: Variant = _car.get("drive_sight")
	if raw is Dictionary:
		return raw
	return {}


func _nose(car: Node3D) -> Vector3:
	var heading := car.get_node_or_null("Heading") as Node3D
	if heading == null:
		return Vector3(-1.0, 0.0, 0.0)
	var facing: Vector3 = -heading.global_transform.basis.x
	facing.y = 0.0
	if facing.length_squared() < 0.01:
		return Vector3(-1.0, 0.0, 0.0)
	return facing.normalized()


func _speed_of(car: Node3D) -> float:
	var raw: Variant = car.get("travel_velocity")
	if raw is Vector3:
		var vel: Vector3 = raw
		vel.y = 0.0
		return vel.length()
	return 0.0


func _surface_off() -> float:
	if _car == null:
		return 0.0
	var city := _city()
	if city == null or not city.has_method("surface_at"):
		return 0.0
	var raw: Variant = city.call("surface_at", _car.global_position.x, _car.global_position.z)
	if raw is Dictionary:
		return float((raw as Dictionary).get("off", 0.0))
	return 0.0


func _route_off() -> float:
	if _car == null or not _car.has_method("route_points"):
		return 0.0
	var raw: Variant = _car.call("route_points")
	if raw is PackedVector3Array:
		return _poly_dist(raw, _car.global_position)
	return 0.0


func _max_offset(sight: Dictionary) -> float:
	var path := _as_pts(sight.get("path", PackedVector3Array()))
	if _car == null or not _car.has_method("route_points"):
		return 0.0
	var raw: Variant = _car.call("route_points")
	if not (raw is PackedVector3Array):
		return 0.0
	var route: PackedVector3Array = raw
	var worst := 0.0
	var count := 0
	for point in path:
		worst = maxf(worst, _poly_dist(route, point))
		count += 1
		if count >= 10:
			break
	return worst


func _side_name(sight: Dictionary) -> String:
	var path := _as_pts(sight.get("path", PackedVector3Array()))
	if _car == null or not _car.has_method("route_points"):
		return "center"
	var raw: Variant = _car.call("route_points")
	if not (raw is PackedVector3Array):
		return "center"
	var acc := 0.0
	var count := 0
	for point in path:
		acc += _signed_lat(raw, point)
		count += 1
		if count >= 8:
			break
	if count == 0:
		return "center"
	var mean: float = acc / float(count)
	if mean > 0.75:
		return "left"
	if mean < -0.75:
		return "right"
	return "center"


func _poly_dist(route: PackedVector3Array, point: Vector3) -> float:
	if route.is_empty():
		return 0.0
	if route.size() == 1:
		return Vector2(point.x - route[0].x, point.z - route[0].z).length()
	var best := 100000.0
	for i in range(route.size() - 1):
		best = minf(best, _seg_dist(route[i], route[i + 1], point))
	return best


func _signed_lat(route: PackedVector3Array, point: Vector3) -> float:
	if route.size() < 2:
		return 0.0
	var best := 0.0
	var best_d := 100000.0
	for i in range(route.size() - 1):
		var ab := Vector2(route[i + 1].x - route[i].x, route[i + 1].z - route[i].z)
		var len2: float = ab.length_squared()
		if len2 < 0.01:
			continue
		var ap := Vector2(point.x - route[i].x, point.z - route[i].z)
		var t: float = clampf(ap.dot(ab) / len2, 0.0, 1.0)
		var dist: float = ap.distance_to(ab * t)
		if dist < best_d:
			best_d = dist
			best = (ab.x * ap.y - ab.y * ap.x) / sqrt(len2)
	return best


func _seg_dist(a: Vector3, b: Vector3, point: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(point.x - a.x, point.z - a.z)
	var len2: float = ab.length_squared()
	if len2 < 0.0001:
		return ap.length()
	var t: float = clampf(ap.dot(ab) / len2, 0.0, 1.0)
	return ap.distance_to(ab * t)


func _points_of(task: Dictionary) -> PackedVector3Array:
	return _as_pts(task.get("pts", PackedVector3Array()))


func _as_pts(raw: Variant) -> PackedVector3Array:
	if raw is PackedVector3Array:
		return raw
	return PackedVector3Array()


func _vec_count(raw: Variant) -> int:
	if raw is PackedVector3Array:
		return (raw as PackedVector3Array).size()
	return 0


func _pts_text(sight: Dictionary) -> String:
	return _route_text(_as_pts(sight.get("path", PackedVector3Array())))


func _route_text(pts: PackedVector3Array) -> String:
	var text := ""
	var count := 0
	for point in pts:
		if count > 0:
			text += ";"
		text += "%0.1f,%0.1f" % [point.x, point.z]
		count += 1
		if count >= 10:
			break
	return text


func _n() -> int:
	return _index + 1


func _id() -> String:
	return str(_task.get("id", ""))


func _q(text: String) -> String:
	return text.replace("\"", "'")


func _event(line: String) -> void:
	if _file == null:
		return
	_file.store_line(line)
	_file.flush()


func _summary() -> void:
	var left := _tasks.size() - _yes - _no
	_event("SUMMARY correct=%d wrong=%d left=%d path_accept=%d path_reject=%d" % [_yes, _no, left, _accepts, _rejects])


func _open_log() -> void:
	var path := ProjectSettings.globalize_path("res://../logs/traffic_drill.log")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_error("drill log failed: %s" % path)
		return
	_event("# traffic_drill round=cones")
	_event("# Practice Road, x=-40 to 300. Eastbound right lane z=5.25. Westbound right lane z=-5.25. No stop and no light.")
	_event("# Order: clear U-turn east, one lane of cones then U-turn west, both lanes then U-turn east, full road then leave the asphalt.")
	_event("# The player places the cones. A U-turn bows outward and uses the opposite lanes. The last leg waits, then drives on the grass.")
	_event("# One event per line. Keys stay fixed so a later pass can score the driver.")
	_event("# TASK arms the task. WAIT_GO waits for Return. GO starts the clock.")
	_event("# POSE is a half-second sample while the car is allowed to move.")
	_event("# PATH_PROPOSE is a path the car wants. The car does not move on it yet.")
	_event("# PATH_REJECT asks for a different path. PATH_ACCEPT lets the car follow that path.")
	_event("# ASK means the action window ended. GRADE is the human verdict: correct or wrong.")
	_event("# RESULT is that verdict plus the measured trace. The last SUMMARY is the tally.")
	_event("# WRONG lines list the tasks marked wrong.")
	_event("ROUND n=1 tasks=%d" % _tasks.size())


func _exit_tree() -> void:
	if _file == null:
		return
	if _state != "done":
		_event("STOP t=%0.2f reason=quit state=%s n=%d" % [_time, _state, _n()])
		_summary()
	_file.close()
	_file = null


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DrillBanner"
	layer.layer = 40
	add_child(layer)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	_panel = ColorRect.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.color = Color(0.03, 0.04, 0.05, 0.92)
	_panel.position = Vector2(16, 8)
	_panel.size = Vector2(760, 148)
	root.add_child(_panel)
	_bar = ColorRect.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.color = Color(1.0, 0.55, 0.18, 0.95)
	_bar.size = Vector2(760, 4)
	_panel.add_child(_bar)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.position = Vector2(14, 12)
	_label.size = Vector2(732, 128)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.96, 0.94, 0.88))
	_panel.add_child(_label)
	root.resized.connect(_fit_banner)
	_fit_banner()


func _fit_banner() -> void:
	if _panel == null:
		return
	var view := get_viewport().get_visible_rect().size
	var width: float = maxf(view.x - 32.0, 360.0)
	_panel.size = Vector2(width, 148.0)
	_bar.size = Vector2(width, 4.0)
	_label.size = Vector2(width - 28.0, 128.0)


func _banner() -> void:
	if _label == null:
		return
	_fit_banner()
	var title := str(_task.get("title", ""))
	var prompt := str(_task.get("prompt", ""))
	if _state == "boot":
		_label.text = "Driver drill"
		return
	if _state == "done":
		_bar.color = Color(0.95, 0.78, 0.2, 0.95)
		_label.text = "Cone run finished.  Correct %d.  Wrong %d.\nReview logs/traffic_drill.log" % [_yes, _no]
		return
	var head := "TASK %d/%d   %s" % [_n(), _tasks.size(), title]
	if _state == "arm":
		_bar.color = Color(1.0, 0.55, 0.18, 0.95)
		_label.text = "%s\n%s\nReturn — start this task" % [head, prompt]
	elif _state == "path":
		_bar.color = Color(0.35, 0.75, 0.95, 0.95)
		var sight := _sight()
		var why := str(sight.get("why", "a new path"))
		_label.text = "%s\nPath change: %s\nReturn — approve this path      Backspace — reject and show another" % [head, why]
	elif _state == "ask":
		_bar.color = Color(0.95, 0.78, 0.2, 0.95)
		_label.text = "%s\nDid the car do this correctly?\nY — yes      N — no" % head
	else:
		_bar.color = Color(0.45, 0.75, 0.42, 0.95)
		_label.text = "%s\n%s\nWatching. The grade comes when the action window ends." % [head, prompt]


func _catalog() -> void:
	# Practice Road. Eastbound right lane is +Z. A U-turn bows toward the end of the road, then uses the opposite lanes.
	var right: float = GameConstants.LANE_OFF
	var west: float = -right
	_open(_reach(_add("clear_east", "End of the road", "Leave the lanes empty. Cone piles are on the grass, off the road. The car drives to the east end, makes a wide U-turn, and comes back.", _join([
		_span(8.0, right, 250.0, right, 12),
		_uturn(250.0, 18.0, right, west, 16),
		_span(250.0, west, 200.0, west, 4),
	]), "reach", 95.0), 224.0, west, 6.0))
	_open(_reach(_add("one_lane", "One lane blocked", "Pick up cones from the pile on the grass beside you. Put them in one lane, in front of the car. It drives to the west end and makes a wide U-turn.", _join([
		_span(240.0, west, 20.0, west, 12),
		_uturn(20.0, -18.0, west, right, 16),
		_span(20.0, right, 70.0, right, 4),
	]), "reach", 95.0), 52.0, right, 6.0))
	_open(_reach(_add("both_lanes", "Both lanes blocked", "Pick up cones from the pile on the grass beside you. Put them across both lanes on this side of the yellow line. It drives to the east end and makes a wide U-turn.", _join([
		_span(30.0, right, 250.0, right, 12),
		_uturn(250.0, 18.0, right, west, 16),
		_span(250.0, west, 200.0, west, 4),
	]), "reach", 95.0), 224.0, west, 6.0))
	_open(_add("all_lanes", "Road blocked", "Pick up cones from the pile on the grass beside you. Put them across all four lanes. The car should wait, then leave the asphalt once its aggression is high enough.", _join([
		_span(240.0, west, 20.0, west, 12),
		_uturn(20.0, -18.0, west, right, 16),
		_span(20.0, right, 70.0, right, 4),
	]), "escape", 150.0))


func _add(id: String, title: String, prompt: String, pts: PackedVector3Array, watch: String, limit: float) -> Dictionary:
	var task := {
		"id": id,
		"title": title,
		"prompt": prompt,
		"pts": pts,
		"watch": watch,
		"limit": limit,
		"pin": -1,
		"intel": 0.55,
		"agg": 0.55,
		"rx": 0.0,
		"rz": 0.0,
		"rr": 3.5,
		"x0": 0.0,
		"z0": 0.0,
		"x1": 0.0,
		"z1": 0.0,
		"has_box": false,
		"cones": PackedVector3Array(),
		"barrels": PackedVector3Array(),
		"release": false,
	}
	_tasks.append(task)
	return task


func _open(task: Dictionary) -> Dictionary:
	task["open"] = true
	return task


func _uturn(x_center: float, bulge: float, z0: float, z1: float, steps: int) -> PackedVector3Array:
	# Bulge is along X. Positive bows east. Angle 0 keeps the arrival heading; angle PI leaves the other way.
	var out := PackedVector3Array()
	var count: int = maxi(steps, 4)
	for i in count + 1:
		var ang: float = PI * float(i) / float(count)
		var blend: float = 0.5 - 0.5 * cos(ang)
		out.append(Vector3(x_center + bulge * sin(ang), 0.65, lerpf(z0, z1, blend)))
	return out


func _reach(task: Dictionary, x: float, z: float, radius: float) -> Dictionary:
	task["rx"] = x
	task["rz"] = z
	task["rr"] = radius
	return task


func _box(task: Dictionary, x0: float, z0: float, x1: float, z1: float) -> Dictionary:
	task["has_box"] = true
	task["x0"] = x0
	task["z0"] = z0
	task["x1"] = x1
	task["z1"] = z1
	return task


func _shift_lane(x0: float, x1: float, z0: float, z1: float, steps: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var count: int = maxi(steps, 1)
	for i in count + 1:
		var t: float = float(i) / float(count)
		var blend: float = 0.5 - 0.5 * cos(PI * t)
		out.append(Vector3(lerpf(x0, x1, t), 0.65, lerpf(z0, z1, blend)))
	return out


func _join(parts: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for part in parts:
		if not (part is PackedVector3Array):
			continue
		var pts: PackedVector3Array = part
		for point in pts:
			if out.is_empty() or out[out.size() - 1].distance_to(point) > 0.2:
				out.append(point)
	return out


func _xz(pairs: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var i := 0
	while i + 1 < pairs.size():
		out.append(Vector3(float(pairs[i]), 0.65, float(pairs[i + 1])))
		i += 2
	return out


func _span(x0: float, z0: float, x1: float, z1: float, n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n:
		var t := 0.0
		if n > 1:
			t = float(i) / float(n - 1)
		out.append(Vector3(lerpf(x0, x1, t), 0.65, lerpf(z0, z1, t)))
	return out


func _clump(x: float, z: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.append(Vector3(x - 0.7, 0.65, z - 0.5))
	out.append(Vector3(x + 0.6, 0.65, z - 0.4))
	out.append(Vector3(x - 0.2, 0.65, z + 0.7))
	out.append(Vector3(x + 0.8, 0.65, z + 0.5))
	return out
