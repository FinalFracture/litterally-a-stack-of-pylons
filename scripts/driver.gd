extends Node

# Follows TRAFFIC_AI.md. The car stays an AnimatableBody3D. This node only picks the aim and the speed.

var _pace: float = 0.0
var _was_turn := false
var _idle: float = 0.0
var _halt := ""
var _halt_along: float = 999.0
var _in_cross := false
var _delayed := false
var _arrival := ""
var _wait_left: float = 0.0
var _door: float = 0.0
var _walker_out := false
var _chain_key := 0
var _chain_dir := Vector3.ZERO
var _side := Vector3.ZERO
var _path_i := 0
var _path_anchor := Vector3.ZERO
var _escaping := false
var _escape_capped := false
var _escape_off := false
var _escape_axis := Vector3.ZERO
var _escape_side := Vector3.ZERO
var _block_at := Vector3.ZERO
var _follow_time: float = 0.0
var _passing := false
var _pass_target: Node3D
var _pass_locked := false
var _pass_rejoining := false
var _pass_rejoin_at := Vector3.ZERO
var _pass_rejoin_dir := Vector3.ZERO
var _pass_event_id := 0
var _pass_event: Dictionary = {}
var _oncoming_id := 0
var _oncoming_choice := 0
var _on_cones := false
var _latched := false
var _chain_ids: Array[int] = []
var _pull := false
var _right_red := false
var _right_arm: float = 0.0
var _right_until := 0
var _right_path: PackedVector3Array = PackedVector3Array()
var _skirting := false
var _skirt_until := 0
var _why := ""
var _target: float = 0.0
var _path_kind := "route"
var _path_alt := 0
var _offer := "natural"
var _light_state := "none"
var _light_m: float = 999.0
var _stop_state := "none"
var _stop_m: float = 999.0
var _seen: Array = []
var _turns: Array[Vector3] = []
var _guides: PackedVector3Array = PackedVector3Array()
var _leader_at := Vector3.ZERO
var _have_leader := false
var _threat_at := Vector3.ZERO
var _have_threat := false
var _threat_act := ""
var _follow_gap: float = -1.0
var _follow_want: float = -1.0
var _limit_note := ""
var _idle_counts := false
var _span_set := false
var _holding := false
var _held_path := PackedVector3Array()
var _held_block := Vector3.ZERO
var _coast_locked := false
var _cone_turn := Vector2(-99999.0, -99999.0)
var _done_ids: Array[int] = []
var _still_t: float = 0.0
var _red_t: float = 0.0
var _still_at := Vector3.ZERO
var _have_still := false
var _unstick := 0
var _reversing := false
var _reverse_from := Vector3.ZERO
var _reverse_time: float = 0.0
var _release_block := false

const PATH_MIN_M := 200.0
const BLOCK_CLOSE_M := 16.0
const STILL_LEAVE := 4.0
const STILL_FLIP := 6.0
const STILL_BACK := 7.2
const STILL_FORCE := 8.4
const RED_HOLD := 9.0


func _ready() -> void:
	var car := get_parent() as Node3D
	if car == null:
		return
	var intel: float = randf_range(0.08, 0.98)
	var base: float = randf_range(0.08, 0.98)
	car.set("drive_intel", intel)
	car.set("drive_base_agg", base)
	car.set("drive_agg", base)


func plan(car: Node3D, delta: float, patrol: Vector3) -> Dictionary:
	_pass_event = {}
	_delayed = false
	_pull = false
	_right_red = false
	_skirting = false
	_seen = []
	_guides = PackedVector3Array()
	_turns = []
	_have_leader = false
	_have_threat = false
	_threat_act = ""
	_follow_gap = -1.0
	_follow_want = -1.0
	_path_kind = "route"
	_offer = "natural"
	_why = ""
	_light_state = "none"
	_light_m = 999.0
	_stop_state = "none"
	_stop_m = 999.0
	_idle_counts = false
	if bool(car.get("pulled_off")):
		return _coast_off(car)
	if _arrival != "":
		return _arrival_plan(car, delta)
	if _reversing and _reverse_hold(car, delta):
		return _reverse_plan(car)
	_pull_cursor(car)
	if bool(car.call("route_done")):
		if bool(car.get("practice_despawn")):
			car.queue_free()
			return {"aim": car.global_position, "speed": 0.0}
		if bool(car.get("drill_lock")):
			_path_alt = 0
			_offer = "natural"
			_why = "reached the end of this drill route"
			_target = 0.0
			return _finish(car, car.global_position, 0.0, PackedVector3Array(), _forward(car))
		# set_drive parked the crew on this polyline. A new loop trip would abandon the call.
		if _assigned_drive(car):
			_why = "waiting at the end of the assigned route"
			_target = 0.0
			car.set("drive_turning", false)
			return _finish(car, car.global_position, 0.0, PackedVector3Array(), _forward(car))
		_roll_arrival(car)
		if _arrival != "":
			return _arrival_plan(car, delta)
		if not is_instance_valid(car):
			return {"aim": patrol, "speed": 0.0}
	_extend_route(car)
	var fwd := _forward(car)
	var travel := _travel_dir(car, fwd)
	_read_controls(car, fwd)
	_scan_emergency(car, fwd)
	_apply_release()
	var path := _build_path(car, fwd)
	# Pursuit follows the direction the car is moving. While reversing, that is opposite the nose.
	var aim := _pursue(path, car.global_position, travel)
	aim.y = 0.65
	var speed := _speed_for(car, delta, fwd, path)
	_mood(car, delta)
	_tick_idle(car, delta)
	var note := _arrival
	if note == "":
		note = _halt
	if _on_cones and note == "":
		note = "cones"
	if _escaping and note == "":
		note = "off"
	car.set("drive_note", note)
	var turning := _turning(car.global_position, fwd, path)
	car.set("drive_turning", turning)
	_explain(turning)
	return _finish(car, aim, speed, path, fwd)


func _arrival_plan(car: Node3D, delta: float) -> Dictionary:
	car.set("drive_note", _arrival)
	var fwd := _forward(car)
	var aim := car.global_position + fwd * 2.0
	var speed := 0.0
	var path := PackedVector3Array()
	if _arrival == "wait":
		_wait_left -= delta
		_delayed = true
		_mood(car, delta)
		if _wait_left <= 0.0:
			_new_trip(car)
		_why = "arrived, waiting at least a minute"
	elif _arrival == "park":
		var stall_plan := _drive_stall(car)
		aim = stall_plan["aim"]
		speed = float(stall_plan["speed"])
		path.append(aim)
		if _arrival == "doors":
			_why = "in the stall, letting a pedestrian out"
		else:
			_why = "driving to a parking stall"
	elif _arrival == "doors":
		var door_plan := _doors_step(car, delta)
		aim = door_plan["aim"]
		speed = float(door_plan["speed"])
		if _arrival == "parked":
			_why = "parked, doors shut"
		else:
			_why = "doors opening, pedestrian stepping out"
	else:
		_why = "holding"
	if not is_instance_valid(car):
		return {"aim": aim, "speed": 0.0}
	_target = speed
	_limit_note = ""
	car.set("drive_turning", false)
	return _finish(car, aim, speed, path, fwd)


func _roll_arrival(car: Node3D) -> void:
	# This playtest keeps the car moving. Parking and letting a rider out stay in this file and are not used.
	var traffic := _traffic(car)
	if traffic != null and traffic.has_method("assign_long_trip"):
		traffic.call("assign_long_trip", car)
		return
	_new_trip(car)


func _extend_route(car: Node) -> void:
	if bool(car.get("drill_lock")):
		return
	# The finite practice road ends at the last route point. Extending a short
	# route to PATH_MIN_M wraps its goal back to the start, making cars reverse.
	if bool(car.get("practice_despawn")):
		_span_set = true
		return
	if _assigned_drive(car):
		return
	var pts := _points(car)
	if pts.size() < 2:
		return
	var goal: int = int(car.get("route_goal"))
	var cursor: int = int(car.call("route_cursor"))
	if goal < 0:
		_new_trip(car)
		return
	# The cone line still owns the car. Rewriting the goal here wrapped the route back through the cones.
	if _latched:
		return
	# The cones carried the car past the only points it had left, and the route then pulled it backward.
	if _route_behind(car as Node3D, pts, cursor, goal):
		_new_trip(car)
		return
	if _span_set:
		return
	var left: float = _span_length(pts, cursor, goal)
	if left < PATH_MIN_M:
		var far := _index_at_length(pts, cursor, PATH_MIN_M)
		if far != cursor:
			car.set("route_goal", far)
	_span_set = true


func _span_length(pts: PackedVector3Array, cursor: int, goal: int) -> float:
	var walked: float = 0.0
	var i := cursor
	var guard := 0
	while guard < pts.size():
		if i == goal:
			return walked
		var nxt: int = (i + 1) % pts.size()
		walked += Vector2(pts[nxt].x - pts[i].x, pts[nxt].z - pts[i].z).length()
		i = nxt
		guard += 1
	return walked


func _index_at_length(pts: PackedVector3Array, cursor: int, need: float) -> int:
	var walked: float = 0.0
	var i := cursor
	var guard := 0
	var last := cursor
	while guard < pts.size():
		var nxt: int = (i + 1) % pts.size()
		if nxt == cursor:
			return last
		var step: float = Vector2(pts[nxt].x - pts[i].x, pts[nxt].z - pts[i].z).length()
		walked += step
		last = nxt
		if walked >= need:
			return nxt
		i = nxt
		guard += 1
	return last


func _route_behind(car: Node3D, pts: PackedVector3Array, cursor: int, goal: int) -> bool:
	var fwd := _travel_dir(car, _forward(car))
	if fwd.length_squared() < 0.01:
		return false
	fwd = fwd.normalized()
	var pos := car.global_position
	var i := cursor
	var guard := 0
	while guard < pts.size():
		# A far vertex off to the side is the lane coming back, not a reverse.
		if _keeps_vertex(pts[i], pos, fwd):
			return false
		if i == goal:
			break
		var nxt: int = i + 1
		if nxt >= pts.size():
			if goal > i:
				break
			nxt = 0
		i = nxt
		guard += 1
	return true


func adopt_drive() -> void:
	_span_set = true
	_path_i = 0
	_arrival = ""
	_path_anchor = Vector3(99999.0, 0.0, 99999.0)
	_latched = false
	_on_cones = false
	_chain_dir = Vector3.ZERO
	_chain_ids.clear()
	_escaping = false
	_escape_capped = false
	_pace = 0.0
	_pass_target = null
	_pass_rejoining = false
	_still_t = 0.0
	_red_t = 0.0
	_have_still = false
	_unstick = 0
	_reversing = false
	_release_block = false
	var host := get_parent()
	if host != null:
		host.set("backing_out", false)


func _assigned_drive(car: Node) -> bool:
	return car.has_method("has_assigned_drive") and bool(car.call("has_assigned_drive"))


func _new_trip(car: Node) -> void:
	if bool(car.get("drill_lock")):
		return
	var pts := _points(car)
	if pts.size() < 2:
		_arrival = ""
		car.call("ack_route")
		return
	var cursor: int = int(car.call("route_cursor"))
	var goal := _index_at_length(pts, cursor, PATH_MIN_M)
	if goal == cursor:
		goal = (cursor + 1) % pts.size()
	car.set("route_goal", goal)
	car.call("ack_route")
	_arrival = ""
	_idle = 0.0
	_span_set = true


func reset_for_drill(intel: float, agg: float) -> void:
	_pace = 0.0
	_was_turn = false
	_idle = 0.0
	_halt = ""
	_halt_along = 999.0
	_in_cross = false
	_delayed = false
	_arrival = ""
	_wait_left = 0.0
	_door = 0.0
	_walker_out = false
	_chain_key = 0
	_chain_dir = Vector3.ZERO
	_side = Vector3.ZERO
	_path_i = 0
	_path_anchor = Vector3(99999.0, 0.0, 99999.0)
	_escaping = false
	_escape_capped = false
	_escape_off = false
	_escape_axis = Vector3.ZERO
	_escape_side = Vector3.ZERO
	_block_at = Vector3.ZERO
	_follow_time = 0.0
	_passing = false
	_pass_target = null
	_pass_locked = false
	_pass_event = {}
	_pass_rejoining = false
	_oncoming_id = 0
	_oncoming_choice = 0
	_on_cones = false
	_latched = false
	_chain_ids.clear()
	_pull = false
	_right_red = false
	_why = ""
	_target = 0.0
	_path_kind = "route"
	_path_alt = 0
	_offer = "natural"
	_idle_counts = false
	_span_set = false
	_holding = false
	_held_path = PackedVector3Array()
	_held_block = Vector3.ZERO
	_coast_locked = false
	_cone_turn = Vector2(-99999.0, -99999.0)
	_done_ids.clear()
	_still_t = 0.0
	_red_t = 0.0
	_have_still = false
	_unstick = 0
	_reversing = false
	_release_block = false
	var car := get_parent() as Node3D
	if car == null:
		return
	car.set("backing_out", false)
	car.set("drive_intel", intel)
	car.set("drive_agg", agg)
	car.set("drive_base_agg", agg)
	car.set("left_asphalt", false)
	car.set("escape_sign", 1.0)
	car.set("drill_lock", true)


func hold_pace() -> void:
	_pace = 0.0
	_target = 0.0


func reject_path() -> void:
	_path_alt += 1
	_side = Vector3.ZERO
	_chain_dir = Vector3.ZERO
	_latched = false
	_chain_key = 0
	_path_i = 0
	_path_anchor = Vector3(99999.0, 0.0, 99999.0)
	_passing = false
	_pass_rejoining = false
	var car := get_parent() as Node3D
	if car == null:
		return
	var sign: float = float(car.get("escape_sign"))
	if absf(sign) < 0.1:
		sign = 1.0
	car.set("escape_sign", -sign)


func _drive_stall(car: Node3D) -> Dictionary:
	var stall := Vector3(32.0, 0.65, -8.0)
	var city := _city(car)
	if city != null and city.has_method("parking_stall"):
		var raw: Variant = city.call("parking_stall")
		if raw is Vector3:
			stall = raw
	var pos := car.global_position
	if Vector2(pos.x - stall.x, pos.z - stall.z).length() < 1.5:
		_arrival = "doors"
		_door = 0.0
		_walker_out = false
		return _hold(car)
	return {"aim": stall, "speed": 3.2}


func _doors_step(car: Node3D, delta: float) -> Dictionary:
	_door += delta
	var open := 0.0
	if _door < 0.7:
		open = _door / 0.7
	elif _door < 2.0:
		open = 1.0
		if not _walker_out:
			_walker_out = true
			_let_out(car)
	elif _door < 2.8:
		open = 1.0 - (_door - 2.0) / 0.8
	else:
		open = 0.0
		_arrival = "parked"
	_swing(car, open)
	return _hold(car)


func _let_out(car: Node3D) -> void:
	var home := car.get_tree().get_first_node_in_group("walker_home")
	if home == null or not home.has_method("spawn_exit"):
		return
	var fwd := _forward(car)
	var at: Vector3 = car.global_position + _right(fwd) * 2.3
	at.y = 0.85
	home.call("spawn_exit", at, at + _right(fwd) * 4.0)


func _swing(car: Node3D, open: float) -> void:
	var heading := car.get_node_or_null("Heading") as Node3D
	if heading == null:
		return
	var door := heading.get_node_or_null("ParkDoor") as Node3D
	if door == null:
		door = Node3D.new()
		door.name = "ParkDoor"
		heading.add_child(door)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.08, 0.7, 0.85)
		mesh.mesh = box
		mesh.position = Vector3(-0.35, 0.45, 0.75)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.72, 0.14, 0.12)
		mesh.material_override = mat
		door.add_child(mesh)
	door.rotation.y = open * 1.15


func _hold(car: Node3D) -> Dictionary:
	return {"aim": car.global_position + _forward(car) * 2.0, "speed": 0.0}


func _coast_off(car: Node3D) -> Dictionary:
	car.set("left_asphalt", true)
	car.set("drive_note", "off")
	var fwd := _forward(car)
	var pos := car.global_position
	var city := _city(car)
	if city != null and city.has_method("on_asphalt") and not bool(city.call("on_asphalt", pos.x, pos.z)):
		_why = "off the asphalt and stopped"
		_target = 0.0
		_limit_note = ""
		car.set("drive_turning", false)
		return _finish(car, pos + fwd * 2.0, 0.0, PackedVector3Array(), fwd)
	# Lock the shoulder once, from the route. Rebuilding it from the nose makes the
	# body yaw toward the aim, and _right of that new nose is 90 degrees away.
	# Two frames later the aim has reversed and the car spins in place.
	# Eastbound route, near curb is +Z. Travel +Z, near curb is -X.
	if not _coast_locked:
		_coast_locked = true
		var sign: float = float(car.get("escape_sign"))
		if absf(sign) < 0.1:
			sign = 1.0
		_escape_axis = _road_axis(car, fwd)
		_escape_side = -_right(_escape_axis) * sign
	var aim: Vector3 = pos + _escape_side * 7.0
	aim.y = 0.65
	_why = "pulled off the road"
	_target = 3.4
	_limit_note = ""
	_path_kind = "escape"
	var path := PackedVector3Array()
	path.append(pos)
	path.append(aim)
	car.set("drive_turning", false)
	return _finish(car, aim, 3.4, path, fwd)


func _pull_cursor(car: Node) -> void:
	var pts := _points(car)
	var goal: int = int(car.get("route_goal"))
	if pts.size() < 2 or goal < 0:
		return
	var cursor: int = int(car.call("route_cursor"))
	var pos := (car as Node3D).global_position
	var behind: int = (cursor - 1 + pts.size()) % pts.size()
	var behind_d: float = Vector2(pts[behind].x - pos.x, pts[behind].z - pos.z).length()
	var guard := 0
	while guard < pts.size() and cursor != goal:
		var nxt: int = (cursor + 1) % pts.size()
		var here: float = Vector2(pts[cursor].x - pos.x, pts[cursor].z - pos.z).length()
		var there: float = Vector2(pts[nxt].x - pos.x, pts[nxt].z - pos.z).length()
		var along: float = _seg_along(pts[cursor], pts[nxt], pos)
		if nxt == goal:
			var left: float = Vector2(pts[goal].x - pos.x, pts[goal].z - pos.z).length()
			if left < 2.5 and (there + 0.8 < here or along > 0.35):
				cursor = goal
			break
		# Step to the next vertex when the car has reached it. Also step when a wrap
		# left the next vertex behind and the car is already on a later leg. The later
		# leg has to be near in route order: the goal sits on the same straight as the start.
		var passed := along > 0.85 and here > 1.2
		var on_later := behind_d > 4.0 and _ahead_has_car(pts, nxt, goal, pos)
		if there + 0.8 < here or passed or on_later:
			cursor = nxt
			guard += 1
			continue
		break
	car.call("set_route_cursor", cursor)
	if cursor == goal:
		var left_goal: float = Vector2(pts[goal].x - pos.x, pts[goal].z - pos.z).length()
		if left_goal < 2.5:
			car.call("mark_arrived")


func _resume_after_cones(car: Node3D, fwd: Vector3) -> void:
	_skip_behind(car, _travel_dir(car, fwd))
	var pts := _points(car)
	var goal_i: int = int(car.get("route_goal"))
	var cursor_i: int = int(car.call("route_cursor"))
	if _assigned_drive(car) or bool(car.get("drill_lock")):
		return
	if pts.size() < 2 or not _route_behind(car, pts, cursor_i, goal_i):
		return
	var traffic := _traffic(car)
	if traffic != null and traffic.has_method("assign_long_trip"):
		traffic.call("assign_long_trip", car)
	else:
		_new_trip(car)
	_skip_behind(car, _travel_dir(car, _forward(car)))


func _skip_behind(car: Node3D, fwd: Vector3) -> void:
	# A vertex sitting on the bumper used to count as the route. The car turned around and drove back down the cone line.
	var pts := _points(car)
	var goal: int = int(car.get("route_goal"))
	if pts.size() < 2 or goal < 0:
		return
	var cursor: int = int(car.call("route_cursor"))
	var pos := car.global_position
	var travel := fwd
	if travel.length_squared() < 0.01:
		return
	travel = travel.normalized()
	var guard := 0
	while guard < pts.size() and cursor != goal:
		if _keeps_vertex(pts[cursor], pos, travel):
			break
		var nxt: int = cursor + 1
		if nxt >= pts.size():
			if goal > cursor:
				break
			nxt = 0
		if nxt == cursor:
			break
		if not _keeps_vertex(pts[nxt], pos, travel) and _worse_reverse(pts[cursor], pts[nxt], pos, travel):
			break
		cursor = nxt
		guard += 1
	car.call("set_route_cursor", cursor)


func _keeps_vertex(point: Vector3, pos: Vector3, travel: Vector3) -> bool:
	var rel := point - pos
	rel.y = 0.0
	var dist: float = rel.length()
	if dist <= 0.4:
		return false
	var align: float = rel.normalized().dot(travel)
	if align > 0.2:
		return true
	return dist > 8.0 and align > -0.25


func _worse_reverse(here: Vector3, nxt: Vector3, pos: Vector3, travel: Vector3) -> bool:
	var rel := here - pos
	rel.y = 0.0
	var ahead := nxt - pos
	ahead.y = 0.0
	if rel.length() <= 3.0 or ahead.length() <= 0.4:
		return false
	var align: float = rel.normalized().dot(travel)
	var nxt_align: float = ahead.normalized().dot(travel)
	return nxt_align + 0.05 < align


func _ahead_has_car(pts: PackedVector3Array, start: int, goal: int, pos: Vector3) -> bool:
	var i := start
	var steps := 0
	while steps < 16 and i != goal:
		var nxt: int = (i + 1) % pts.size()
		if _seg_dist(pts[i], pts[nxt], pos) < 2.8:
			return true
		i = nxt
		steps += 1
	return false


func _read_controls(car: Node3D, fwd: Vector3) -> void:
	_halt = ""
	_halt_along = 999.0
	if bool(car.get("code_three")) and not bool(car.get("wrecker")):
		_in_cross = false
		return
	var traffic := _traffic(car)
	if traffic == null or not traffic.has_method("approach"):
		return
	var info: Dictionary = traffic.call("approach", car, car.global_position, fwd)
	var light := str(info.get("light", "none"))
	var light_along: float = float(info.get("light_along", 999.0))
	var stop := str(info.get("stop", "none"))
	var stop_along: float = float(info.get("stop_along", 999.0))
	_light_state = light
	_light_m = light_along
	_stop_state = stop
	_stop_m = stop_along
	var red := light == "red" or (light == "yellow" and light_along > 3.2)
	if light == "green" or (light == "yellow" and light_along <= 3.2):
		if light_along < 1.4:
			_in_cross = true
		if light_along < -8.0:
			_in_cross = false
	if red:
		# Past the line already counts as in the box. Marking that at 0.15 m let a car skip the stop while still short of the line.
		if _in_cross:
			if light_along < -8.0:
				_in_cross = false
		elif light_along < 20.0:
			_halt = "red"
			_halt_along = light_along
		if light_along < -0.4:
			_in_cross = true
	elif light == "none":
		_in_cross = false
	if stop == "force":
		_halt = ""
		return
	if stop == "wait" and stop_along < 20.0:
		if _halt != "red" or stop_along < _halt_along:
			_halt = "stop"
			_halt_along = stop_along


func _apply_release() -> void:
	if not _release_block:
		return
	if _halt == "red" and _still_t < RED_HOLD and _red_t < RED_HOLD:
		return
	_halt = ""
	_halt_along = 999.0


func note_progress(car: Node3D, delta: float) -> void:
	if bool(car.get("_wrecked")) or _arrival != "":
		_clear_still(car)
		return
	var pos := car.global_position
	if not _have_still:
		_have_still = true
		_still_at = pos
	var moved := Vector2(pos.x - _still_at.x, pos.z - _still_at.z).length()
	if moved >= 1.6:
		_clear_still(car)
		_red_t = 0.0
		if _reversing:
			_reversing = false
			car.set("backing_out", false)
		if not _escaping:
			_unstick = 0
			_release_block = false
		return
	if _red_waiting():
		_red_t += delta
		if _red_t < RED_HOLD:
			_still_at = pos
			_still_t = 0.0
			return
		if _unstick < 1 and not _reversing:
			_begin_leave(car, _forward(car))
	else:
		_red_t = 0.0
	_still_t += delta
	if _reversing:
		return
	var fwd := _forward(car)
	if _still_t >= STILL_FORCE and _unstick < 4:
		_force_off(car, fwd)
	elif _still_t >= STILL_BACK and _unstick < 3:
		_begin_reverse(car, fwd)
	elif _still_t >= STILL_FLIP and _unstick < 2:
		_flip_shoulder(car, fwd)
	elif _still_t >= STILL_LEAVE and _unstick < 1:
		_begin_leave(car, fwd)


func _clear_still(car: Node3D) -> void:
	_still_t = 0.0
	_still_at = car.global_position
	_have_still = true


func _red_waiting() -> bool:
	return _halt == "red" and _light_m > -1.2 and _light_m < 22.0


func _begin_leave(car: Node3D, fwd: Vector3) -> void:
	_unstick = 1
	_escape_capped = false
	_holding = false
	_passing = false
	_pass_rejoining = false
	_release_block = true
	_escaping = true
	if _block_at.length_squared() < 0.1:
		_block_at = car.global_position + fwd * 5.0
	_lock_shoulder(car, fwd, false)
	if not _shoulder_clear(car, fwd):
		_lock_shoulder(car, fwd, true)


func _flip_shoulder(car: Node3D, fwd: Vector3) -> void:
	_unstick = 2
	_escape_capped = false
	_holding = false
	_escaping = true
	_release_block = true
	_lock_shoulder(car, fwd, true)
	if _block_at.length_squared() < 0.1:
		_block_at = car.global_position + fwd * 5.0


func _begin_reverse(car: Node3D, fwd: Vector3) -> void:
	if _reverse_blocked(car):
		_force_off(car, fwd)
		return
	_unstick = 3
	_reversing = true
	_reverse_from = car.global_position
	_reverse_time = 0.0
	_escaping = false
	_release_block = true
	car.set("backing_out", true)


func _force_off(car: Node3D, fwd: Vector3) -> void:
	_unstick = 4
	_reversing = false
	car.set("backing_out", false)
	_escape_capped = false
	_holding = false
	_on_cones = false
	_latched = false
	_passing = false
	_release_block = true
	_escaping = true
	_escape_axis = Vector3.ZERO
	_escape_side = Vector3.ZERO
	if _block_at.length_squared() < 0.1:
		_block_at = car.global_position + fwd * 5.0
	_lock_shoulder(car, fwd, true)
	car.set("left_asphalt", true)
	_reroute(car)


func _lock_shoulder(car: Node3D, fwd: Vector3, flip: bool) -> void:
	var sign: float = float(car.get("escape_sign"))
	if absf(sign) < 0.1:
		sign = 1.0
	if flip:
		sign = -sign
		car.set("escape_sign", sign)
	_escape_axis = _road_axis(car, fwd)
	_escape_side = -_right(_escape_axis) * sign


func _reverse_hold(car: Node3D, delta: float) -> bool:
	_reverse_time += delta
	var backed := Vector2(car.global_position.x - _reverse_from.x, car.global_position.z - _reverse_from.z).length()
	var blocked := _reverse_blocked(car)
	if backed >= 3.6 or _reverse_time >= 1.7 or (blocked and _reverse_time > 0.4):
		car.set("backing_out", false)
		_reversing = false
		_unstick = 4
		_release_block = true
		_escaping = true
		_escape_capped = false
		_holding = false
		_on_cones = false
		_latched = false
		_escape_axis = Vector3.ZERO
		_escape_side = Vector3.ZERO
		_reroute(car)
		return false
	return true


func _reverse_plan(car: Node3D) -> Dictionary:
	var nose := _forward(car)
	var aim := car.global_position - nose * 7.0
	aim.y = 0.65
	_why = "reversing to get clear"
	_path_kind = "reverse"
	_halt = ""
	_halt_along = 999.0
	_target = 3.2
	car.set("backing_out", true)
	car.set("drive_note", "back")
	car.set("drive_turning", false)
	var path := PackedVector3Array()
	path.append(aim)
	return _finish(car, aim, 3.2, path, nose)


func _reroute(car: Node3D) -> void:
	var traffic := _traffic(car)
	if traffic != null and traffic.has_method("assign_long_trip"):
		traffic.call("assign_long_trip", car)
	_span_set = false
	_path_i = 0
	_path_anchor = Vector3(99999.0, 0.0, 99999.0)
	_holding = false


func leaving() -> bool:
	return _escaping or _reversing or _unstick > 0


func wedged() -> bool:
	return _unstick >= 4


func nudged() -> void:
	# The body was shoved clear of a wedge. Drop the path that aimed back into it.
	_holding = false
	_reversing = false
	_escaping = false
	_escape_capped = false
	_escape_off = false
	_escape_axis = Vector3.ZERO
	_escape_side = Vector3.ZERO
	_on_cones = false
	_latched = false
	_passing = false
	_pass_rejoining = false
	_release_block = true
	_unstick = 0
	_still_t = 0.0
	_red_t = 0.0
	_path_i = 0
	_path_anchor = Vector3(99999.0, 0.0, 99999.0)
	var car := get_parent() as Node3D
	if car == null:
		return
	car.set("backing_out", false)
	_reroute(car)


func _escape_speed_ok(car: Node3D, _fwd: Vector3) -> bool:
	var gap := _side_threat(car)
	if gap < 0.0 or gap >= 6.0:
		return true
	return _unstick >= 4


func _side_threat(car: Node3D) -> float:
	if _escape_side.length_squared() < 0.04:
		return -1.0
	return _body_ahead(car, _escape_side.normalized())


func _shoulder_clear(car: Node3D, fwd: Vector3) -> bool:
	var side := _escape_side
	if side.length_squared() < 0.04:
		return false
	side = side.normalized()
	var axis := _escape_axis
	if axis.length_squared() < 0.04:
		axis = fwd
	axis = axis.normalized()
	for raw_dist in [3.2, 6.4]:
		var dist := float(raw_dist)
		var at := car.global_position + side * dist + axis * (dist * 0.25)
		if not _spot_clear(car, at, 2.7):
			return false
	return true


func _spot_clear(car: Node3D, at: Vector3, radius: float) -> bool:
	var reach := radius * radius
	for node in car.get_tree().get_nodes_in_group("hitter"):
		if node == car or not (node is Node3D):
			continue
		var other := node as Node3D
		var dx: float = other.global_position.x - at.x
		var dz: float = other.global_position.z - at.z
		if dx * dx + dz * dz < reach:
			return false
	for node in car.get_tree().get_nodes_in_group("vehicle"):
		if not (node is Node3D):
			continue
		var wreck := node as Node3D
		var wx: float = wreck.global_position.x - at.x
		var wz: float = wreck.global_position.z - at.z
		if wx * wx + wz * wz < reach:
			return false
	for node in car.get_tree().get_nodes_in_group("pedestrian"):
		if not (node is Node3D):
			continue
		var person := node as Node3D
		var px: float = person.global_position.x - at.x
		var pz: float = person.global_position.z - at.z
		if px * px + pz * pz < reach:
			return false
	return true


func _reverse_blocked(car: Node3D) -> bool:
	var back := -_forward(car)
	if back.length_squared() < 0.01:
		return false
	back = back.normalized()
	for node in car.get_tree().get_nodes_in_group("hitter"):
		if node == car or not (node is Node3D):
			continue
		var along := _along_of(car, node, back)
		if along < 1.2 or along > 5.2:
			continue
		var body := node as Node3D
		var rel := body.global_position - car.global_position
		rel.y = 0.0
		if (rel - back * along).length() < 2.1:
			return true
	return false


func _scan_emergency(car: Node3D, fwd: Vector3) -> void:
	var unit := _emergency(car)
	if unit == null:
		return
	var rel := unit.global_position - car.global_position
	rel.y = 0.0
	var dist: float = rel.length()
	var along: float = rel.dot(fwd)
	var their := _flat_vel(unit)
	var behind := along < -1.0 and their.dot(fwd) > 0.4
	var oncoming := false
	if their.length() > 0.4 and along > 1.0:
		oncoming = their.normalized().dot(fwd) < -0.45
	var straight := not bool(car.get("drive_turning"))
	if straight and (behind or oncoming):
		_pull = true
		if dist < 12.0:
			_halt = "yield"
			_halt_along = dist
	if along > 0.5 and along < 16.0 and absf(rel.cross(fwd).y) > 1.2 and _halt != "red":
		var traffic := _traffic(car)
		if traffic != null and traffic.has_method("approach"):
			var info: Dictionary = traffic.call("approach", car, car.global_position, fwd)
			if str(info.get("light", "")) == "green":
				_halt = "yield"
				_halt_along = along
	if dist < 16.0 and (_halt == "stop" or str(info_stop(car, fwd)) == "go"):
		_halt = "yield"
		_halt_along = dist


func info_stop(car: Node3D, fwd: Vector3) -> String:
	var traffic := _traffic(car)
	if traffic == null or not traffic.has_method("approach"):
		return "none"
	var info: Dictionary = traffic.call("approach", car, car.global_position, fwd)
	return str(info.get("stop", "none"))


func _build_path(car: Node3D, fwd: Vector3) -> PackedVector3Array:
	var pos := car.global_position
	var intel: float = float(car.get("drive_intel"))
	var agg: float = float(car.get("drive_agg"))
	_collect_seen(car)
	if _escaping and _block_at.length_squared() > 0.1:
		# Past the cones only counts after the car has been off the asphalt and come back beyond them.
		# Driving through the line while still on the road used to clear the escape and keep going.
		var axis := _escape_axis
		if axis.length_squared() < 0.2:
			axis = _road_axis(car, fwd)
		var passed := pos - _block_at
		var city := _city(car)
		var on_road := true
		if city != null and city.has_method("on_asphalt"):
			on_road = bool(city.call("on_asphalt", pos.x, pos.z))
		if not on_road:
			_escape_off = true
		if _escape_off and on_road and passed.dot(axis) > 6.0:
			_escaping = false
			_escape_off = false
			_escape_axis = Vector3.ZERO
			_escape_side = Vector3.ZERO
			_idle = 0.0
			_unstick = 0
			_release_block = false
			car.set("left_asphalt", false)
	if intel < 0.38 and not _escaping and not _escape_capped:
		var lead := _asphalt_leader(car, fwd)
		if lead != null:
			_escaping = true
			_block_at = lead.global_position
			car.set("escape_sign", float(lead.get("escape_sign")))
	var caution: float = clampf(intel * lerpf(1.15, 0.65, agg), 0.05, 1.0)
	var chain := _pick_chain(car, fwd)
	# A line across the lanes is a wall. Judge that against the route, not the nose:
	# a yaw toward the other lane was making the wall look like a guide, and the car followed it off the map.
	var guide := false
	if chain.size() >= 3 and not _escaping:
		var road := _road_axis(car, fwd)
		# Across the lane the car is driving, or across its route, is a wall. A line along both is a guide.
		var across := _chain_across(chain, road) or _chain_across(chain, fwd)
		guide = not across
		# Cones left on the far side of the yellow line are not a new guide. The car is over there to pass.
		if guide and _far_side_line(chain, car, fwd):
			guide = false
	_on_cones = guide
	var path: PackedVector3Array
	if _on_cones:
		# A new line is a new approach. Keeping the old side slides the offset along the cones.
		var line_key := _key_of(chain)
		if line_key != _chain_key:
			_chain_dir = Vector3.ZERO
			_side = Vector3.ZERO
			_path_i = 0
			_path_anchor = Vector3(99999.0, 0.0, 99999.0)
		_remember_chain(chain)
		_latched = true
		path = _cone_path(car, chain, caution)
		_path_kind = "cones"
		_mark_guides(chain)
	else:
		if _latched:
			_latched = false
			_chain_ids.clear()
			_path_i = 0
			_path_anchor = Vector3(99999.0, 0.0, 99999.0)
			_resume_after_cones(car, fwd)
		_chain_dir = Vector3.ZERO
		_side = Vector3.ZERO
		_chain_key = 0
		path = _route_path(car)
		if _pull:
			path = _shift_path(path, _right(fwd) * 2.5)
			_path_kind = "yield"
		elif _passing or _pass_rejoining:
			path = _passing_path(path, fwd)
			_path_kind = "pass" if _passing or _pass_rejoining else "route"
		else:
			var opened := _through_cones(car, fwd, path)
			if opened.size() >= 1:
				path = opened
				_holding = false
			else:
				path = _around_block(path, car, fwd, caution, intel)
				if _path_kind != "pass":
					_path_kind = "route"
	var corner := _right_corner(car)
	var hot := _halt == "red" or _halt == "jam"
	var dt := get_physics_process_delta_time()
	var now := Time.get_ticks_msec()
	# A one-frame right-on-red was clearing the brake, then the next frame put the red back. The car rolled the light at cruise.
	if now < _right_until:
		_right_red = true
		_halt = ""
		if _right_path.size() >= 2:
			path = _right_path
			_path_kind = "right"
	elif hot and agg > 0.78 and corner.length_squared() > 1.0 and not _on_cones:
		var grass := _grass_turn(car, fwd, corner)
		if grass.size() >= 2 and _path_clear_of_cars(car, grass):
			_right_arm += dt
			if _right_arm >= 0.4:
				_right_until = now + 3000
				_right_path = grass
				_right_red = true
				_halt = ""
				path = grass
				_path_kind = "right"
		else:
			_right_arm = 0.0
	else:
		_right_arm = 0.0
	if _escape_capped and _path_kind != "turn" and _first_turn_distance(path) >= 45.0:
		_escape_capped = false
	if _escaping and not _on_cones and _path_kind != "turn":
		var pinned := _unstick > 0 or _still_t >= STILL_LEAVE or _release_block or _red_t >= RED_HOLD
		if not pinned and _first_turn_distance(path) < 45.0:
			# A casual escape this close to a turn has no room to rejoin. A car that
			# cannot proceed is pinned and still goes around.
			_escaping = false
			_escape_capped = true
			_idle = 0.0
			car.set("left_asphalt", false)
		else:
			path = _escape_path(car, fwd)
			car.set("left_asphalt", true)
			_path_kind = "escape"
			# A jam or a gap halt would keep the speed at zero and the car would never leave.
			if _halt == "gap" or _halt == "jam" or _halt == "stop" or (_release_block and _halt != "red"):
				_halt = ""
				_halt_along = 999.0
	elif not _escaping:
		car.set("left_asphalt", false)
	if path.is_empty():
		path.append(pos + fwd * 4.0)
	return _apply_alt(path, car, fwd)


func _passing_path(path: PackedVector3Array, fwd: Vector3) -> PackedVector3Array:
	if path.size() < 2:
		_passing = false
		_pass_rejoining = false
		_pass_target = null
		return path
	var turn_at := _first_turn_distance(path)
	var car := get_parent() as Node3D
	if turn_at < 12.0 and _passing:
		if _passing:
			_record_pass_event("abort", car, _pass_target, _follow_gap, 0.0, turn_at, _oncoming_clear(car), "turn_too_close")
		_begin_pass_rejoin(car, fwd)
	var rejoin_progress := 0.0
	if _pass_rejoining and car != null:
		rejoin_progress = maxf(0.0, (car.global_position - _pass_rejoin_at).dot(_pass_rejoin_dir))
		if rejoin_progress >= 14.0:
			_pass_rejoining = false
			return path
	var distance := 0.0
	var result := PackedVector3Array()
	# In the one-lane-each-way layout this moves from our lane center to the
	# opposing lane center. A gradual entry and exit keep the aim from snapping.
	# The city grid publishes the module lane spacing. The old 5.25 m gap belongs
	# to the wide practice road and would leave these lanes.
	var lane_gap: float = GameConstants.LANE_OFF
	if car != null:
		var city: Node = _city(car)
		if city != null and city.has_meta("road_lane_m"):
			lane_gap = float(city.get_meta("road_lane_m"))
	var offset: Vector3 = _right(fwd) * lane_gap * 2.0
	for i in path.size():
		if i > 0:
			distance += path[i - 1].distance_to(path[i])
		var weight := clampf(distance / 10.0, 0.0, 1.0) if _passing else 0.0
		if _pass_rejoining:
			weight = 1.0 - clampf((rejoin_progress + distance) / 14.0, 0.0, 1.0)
		if not is_inf(turn_at):
			weight = minf(weight, clampf((turn_at - distance) / 12.0, 0.0, 1.0))
		var point := path[i] + offset * weight
		point.y = path[i].y
		result.append(point)
	return result


func _begin_pass_rejoin(car: Node3D, travel: Vector3) -> void:
	_pass_rejoining = true
	_pass_rejoin_at = car.global_position
	_pass_rejoin_dir = travel
	_pass_rejoin_dir.y = 0.0
	if _pass_rejoin_dir.length_squared() > 0.01:
		_pass_rejoin_dir = _pass_rejoin_dir.normalized()
	else:
		_pass_rejoin_dir = _forward(car)
	_passing = false


func _first_turn_distance(path: PackedVector3Array) -> float:
	if path.size() < 3:
		return INF
	var initial := path[1] - path[0]
	initial.y = 0.0
	if initial.length_squared() < 0.01:
		return INF
	initial = initial.normalized()
	var walked := 0.0
	for i in range(1, path.size()):
		var segment := path[i] - path[i - 1]
		segment.y = 0.0
		walked += segment.length()
		if segment.length_squared() > 0.01 and segment.normalized().dot(initial) < 0.92:
			return walked
	return INF


func _apply_alt(path: PackedVector3Array, car: Node3D, fwd: Vector3) -> PackedVector3Array:
	if _path_alt <= 0 or path.size() < 1:
		_offer = "natural"
		return path
	var mode: int = (_path_alt - 1) % 4
	if mode == 0:
		_offer = "mirror"
		return _mirror_across(path, car.global_position, fwd)
	if mode == 1:
		_offer = "shift_right"
		var wide: float = 2.2 + float(_path_alt) * 0.18
		return _shift_path(path, _right(fwd) * wide)
	if mode == 2:
		_offer = "shift_left"
		var wide_left: float = 2.2 + float(_path_alt) * 0.18
		return _shift_path(path, -_right(fwd) * wide_left)
	_offer = "short"
	_path_kind = "hold"
	var stub := PackedVector3Array()
	var here := car.global_position
	here.y = 0.65
	var tip := here + fwd * (3.0 + float(_path_alt) * 0.35)
	tip.y = 0.65
	stub.append(here)
	stub.append(tip)
	return stub


func _mirror_across(path: PackedVector3Array, origin: Vector3, fwd: Vector3) -> PackedVector3Array:
	var axis := Vector3(fwd.x, 0.0, fwd.z)
	if axis.length_squared() < 0.01:
		axis = Vector3(-1.0, 0.0, 0.0)
	axis = axis.normalized()
	var out := PackedVector3Array()
	for point in path:
		var rel := Vector3(point.x - origin.x, 0.0, point.z - origin.z)
		var along: float = rel.dot(axis)
		var lat := rel - axis * along
		var mirrored := origin + axis * along - lat
		mirrored.y = 0.65
		out.append(mirrored)
	return out


func _cone_path(car: Node3D, chain: Array[Node3D], caution: float) -> PackedVector3Array:
	var ordered := _order(chain)
	var travel := _forward(car)
	var axis := Vector3.ZERO
	if ordered.size() >= 2:
		axis = ordered[ordered.size() - 1] - ordered[0]
		axis.y = 0.0
	var key := _key_of(chain)
	if axis.length_squared() < 0.01:
		axis = travel
	axis = axis.normalized()
	# Lock direction and side on the first approach. A later yaw must not turn the line around.
	if _chain_dir.length_squared() < 0.2:
		if absf(axis.dot(travel)) <= 0.2:
			var prefer := _goal_point(car) - car.global_position
			prefer.y = 0.0
			if prefer.length_squared() > 1.0 and axis.dot(prefer) < 0.0:
				ordered.reverse()
				axis = -axis
		elif axis.dot(travel) < 0.0:
			ordered.reverse()
			axis = -axis
		_chain_dir = axis
		_path_i = 0
	elif axis.dot(_chain_dir) < 0.0:
		ordered.reverse()
		axis = -axis
	if _side.length_squared() < 0.2:
		var nearest := ordered[0]
		var best := 10000.0
		for point in ordered:
			var d: float = Vector2(point.x - car.global_position.x, point.z - car.global_position.z).length()
			if d < best:
				best = d
				nearest = point
		var lat := car.global_position - nearest
		lat.y = 0.0
		lat = lat - axis * lat.dot(axis)
		if lat.length() < 0.2:
			lat = Vector3(axis.z, 0.0, -axis.x)
		else:
			lat = lat.normalized()
		_side = lat
	_chain_key = key
	var offset: float = 0.85 + 0.32 + lerpf(0.35, 1.2, caution)
	var path := PackedVector3Array()
	for point in ordered:
		var at: Vector3 = point + _side * offset
		at.y = 0.65
		at = _keep_asphalt(car, at)
		path.append(at)
	var last: Vector3 = path[path.size() - 1]
	# Stop the cone path 4 m past the last cone. The route is joined after the car clears that point.
	# Folding the route into this polyline put a chord back down the road, and the nose followed it around.
	var past := last + axis * 4.0
	past.y = 0.65
	past = _keep_asphalt(car, past)
	path.append(past)
	return path


func _route_path(car: Node) -> PackedVector3Array:
	var pts := _points(car)
	var path := PackedVector3Array()
	if pts.is_empty():
		return path
	var cursor: int = int(car.call("route_cursor"))
	var goal: int = int(car.get("route_goal"))
	var i := cursor
	var guard := 0
	while guard < pts.size():
		path.append(pts[i])
		if goal >= 0 and i == goal:
			break
		i = (i + 1) % pts.size()
		guard += 1
	if path.is_empty() or not (car is Node3D):
		return path
	var pos := (car as Node3D).global_position
	# Far from the polyline, steer from the car toward the road. A tangent on that road can point backward.
	if not _near_path(path, pos, 4.0):
		var joined := PackedVector3Array()
		var here := pos
		here.y = 0.65
		joined.append(here)
		for point in path:
			joined.append(point)
		return joined
	return path


func _shift_path(path: PackedVector3Array, offset: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for point in path:
		var at: Vector3 = point + offset
		at.y = 0.65
		out.append(at)
	return out


func _nudge(path: PackedVector3Array, car: Node3D, fwd: Vector3, caution: float, intel: float) -> PackedVector3Array:
	var obs: Array = _seen
	var margin: float = lerpf(0.25, 1.15, caution) + (1.0 - intel) * 0.4
	var pos := car.global_position
	for i in path.size():
		if Vector2(path[i].x - pos.x, path[i].z - pos.z).length() > 14.0:
			continue
		var point: Vector3 = path[i]
		var original := point
		for item in obs:
			var rec: Dictionary = item
			var kind := str(rec.get("kind", ""))
			if kind == "player" or kind == "guide":
				continue
			var op: Vector3 = rec["pos"]
			var radius: float = float(rec["radius"])
			var need: float = 0.75 + radius + margin
			var rel := Vector3(point.x - op.x, 0.0, point.z - op.z)
			var dist: float = rel.length()
			if dist >= need or dist > 7.0:
				continue
			if dist < 0.05:
				rel = _right(fwd)
				dist = 0.05
			var pushed: Vector3 = op + rel.normalized() * need
			pushed.y = 0.65
			var shift: float = Vector2(pushed.x - original.x, pushed.z - original.z).length()
			# A person or a wreck needs a wider shove than a cone. 3.3 m refused the gap and the car stopped on top of them.
			var allow := 5.2 if (kind == "ped" or kind == "wreck") else 3.3
			if shift > allow:
				if _may_oncoming(car, intel):
					# _right of an eastbound nose is -Z, toward the center. The pass uses that side, not the curb.
					pushed = original + _right(fwd) * need
					pushed.y = 0.65
					_passing = true
					_path_kind = "pass"
					rec["state"] = "nudge"
					if kind == "ped" or kind == "wreck":
						_skirting = true
				else:
					_halt = "gap"
					_block_at = op
					var along: float = Vector2(op.x - pos.x, op.z - pos.z).length()
					_halt_along = along
					rec["state"] = "refused"
					continue
			else:
				rec["state"] = "nudge"
				if kind == "ped" or kind == "wreck":
					_skirting = true
			point = pushed
			# The outer lane is 1.75 m from the curb. A nudge larger than that was driving onto the grass.
			if not _escaping:
				point = _keep_asphalt(car, point)
		path[i] = point
	return path


func _may_oncoming(car: Node3D, _intel: float) -> bool:
	return _oncoming_clear(car)


func _body_ahead(car: Node3D, travel: Vector3) -> float:
	if travel.length_squared() < 0.01:
		return -1.0
	var dir := travel.normalized()
	var best := 22.0
	var found := false
	for node in car.get_tree().get_nodes_in_group("pedestrian"):
		if _note_ahead(car, node, dir, 1.7, best):
			best = _along_of(car, node, dir)
			found = true
	for node in car.get_tree().get_nodes_in_group("vehicle"):
		if node == car or not (node is RigidBody3D):
			continue
		if _note_ahead(car, node, dir, 2.2, best):
			best = _along_of(car, node, dir)
			found = true
	if not found:
		return -1.0
	return best


func _note_ahead(car: Node3D, node: Node, dir: Vector3, lateral: float, best: float) -> bool:
	if not (node is Node3D):
		return false
	var along := _along_of(car, node, dir)
	if along < 1.0 or along > best:
		return false
	var body := node as Node3D
	var rel := body.global_position - car.global_position
	rel.y = 0.0
	var side: float = (rel - dir * along).length()
	return side <= lateral


func _along_of(car: Node3D, node: Node, dir: Vector3) -> float:
	var body := node as Node3D
	var rel := body.global_position - car.global_position
	rel.y = 0.0
	return rel.dot(dir)


func recover(car: Node3D) -> void:
	# The body has been shoved against geometry. Release a cone line that cannot be driven,
	# or step the route cursor to a vertex that is still ahead.
	_holding = false
	_escaping = false
	_escape_off = false
	_idle = 0.0
	_pace = 0.0
	car.set("left_asphalt", false)
	if _on_cones or _latched:
		for id in _chain_ids:
			if not _done_ids.has(id):
				_done_ids.append(id)
		_latched = false
		_on_cones = false
		_chain_ids.clear()
		_chain_dir = Vector3.ZERO
		_side = Vector3.ZERO
		_path_i = 0
		_path_anchor = Vector3(99999.0, 0.0, 99999.0)
		_resume_after_cones(car, _forward(car))
		return
	var pts := _points(car)
	if pts.size() < 2:
		_new_trip(car)
		return
	var cursor: int = int(car.call("route_cursor"))
	var pos := car.global_position
	var travel := _travel_dir(car, _forward(car))
	var i := cursor
	var guard := 0
	var found := -1
	while guard < pts.size():
		var rel := pts[i] - pos
		rel.y = 0.0
		var ahead: float = rel.dot(travel)
		var dist: float = rel.length()
		if ahead > 6.0 and dist < 70.0:
			found = i
			break
		var nxt: int = (i + 1) % pts.size()
		if nxt == cursor:
			break
		i = nxt
		guard += 1
	if found < 0:
		_new_trip(car)
		return
	car.call("set_route_cursor", found)
	_path_i = 0
	_path_anchor = Vector3(99999.0, 0.0, 99999.0)
	_span_set = false


func _path_clear_of_cars(car: Node3D, path: PackedVector3Array) -> bool:
	for node in car.get_tree().get_nodes_in_group("hitter"):
		if node == car or not (node is Node3D):
			continue
		var other := node as Node3D
		if _near_path(path, other.global_position, 3.4):
			return false
	for node in car.get_tree().get_nodes_in_group("vehicle"):
		if not (node is Node3D):
			continue
		var wreck := node as Node3D
		if _near_path(path, wreck.global_position, 3.4):
			return false
	return true


func _grass_turn(car: Node3D, fwd: Vector3, corner: Vector3) -> PackedVector3Array:
	var right := _right(fwd)
	var grass: Vector3 = corner + right * 6.0
	grass.y = 0.65
	var city := _city(car)
	if city != null and city.has_method("on_asphalt"):
		var hop := 0
		while hop < 4 and bool(city.call("on_asphalt", grass.x, grass.z)):
			grass += right * 1.6
			hop += 1
	grass = _shy_people(car, grass)
	var rejoin := _after_corner(car, corner)
	rejoin = _shy_people(car, rejoin)
	var path := PackedVector3Array()
	var start := car.global_position
	start.y = 0.65
	path.append(start)
	path.append(grass)
	path.append(rejoin)
	return path


func _escape_path(car: Node3D, fwd: Vector3) -> PackedVector3Array:
	# Lock the shoulder to the route, not the nose. _right of an eastbound nose is -Z, toward the center.
	# The near curb is the other way: +Z eastbound, -Z westbound. A yaw was flipping that and cutting through the cones.
	if _escape_axis.length_squared() < 0.2:
		var sign: float = float(car.get("escape_sign"))
		if absf(sign) < 0.1:
			sign = 1.0
		_escape_axis = _road_axis(car, fwd)
		_escape_side = -_right(_escape_axis) * sign
	var axis := _escape_axis
	var side := _escape_side
	var pos := car.global_position
	var out := pos + side * 6.5
	out.y = 0.65
	var city := _city(car)
	if city != null and city.has_method("on_asphalt"):
		var hop := 0
		while hop < 4 and bool(city.call("on_asphalt", out.x, out.z)):
			out += side * 1.5
			hop += 1
	out = _shy_people(car, out)
	var past := _block_at
	if past.length_squared() < 0.1:
		past = pos + axis * 8.0
	past = past + axis * 10.0 + side * 8.0
	past.y = 0.65
	if city != null and city.has_method("on_asphalt"):
		var hop_past := 0
		while hop_past < 4 and bool(city.call("on_asphalt", past.x, past.z)):
			past += side * 1.5
			hop_past += 1
	past = _shy_people(car, past)
	var back := past
	if city != null and city.has_method("nearest_asphalt"):
		var raw: Variant = city.call("nearest_asphalt", past.x + axis.x * 4.0, past.z + axis.z * 4.0)
		if raw is Vector3:
			back = raw
	# Eastbound shoulder is +Z. The curb clamp lands on z=7, and that edge is not on the road, so the car stopped there.
	# Inward is -Z, which steps that lip onto the lane near z=4.9.
	back = _seat_on_road(car, back, -side)
	back.y = 0.65
	var path := PackedVector3Array()
	path.append(out)
	path.append(past)
	path.append(back)
	return path


func _seat_on_road(car: Node3D, at: Vector3, inward: Vector3) -> Vector3:
	var city := _city(car)
	var spot := at
	spot.y = 0.65
	if city == null or not city.has_method("on_asphalt"):
		return spot
	var step := inward
	if step.length_squared() < 0.04:
		return spot
	step = step.normalized()
	var hop := 0
	while hop < 8 and not bool(city.call("on_asphalt", spot.x, spot.z)):
		spot += step * 0.5
		hop += 1
	var seated := spot + step * 1.6
	seated.y = 0.65
	if bool(city.call("on_asphalt", seated.x, seated.z)):
		return seated
	spot.y = 0.65
	return spot


func _shy_people(car: Node, at: Vector3) -> Vector3:
	var out := at
	for node in car.get_tree().get_nodes_in_group("pedestrian"):
		var body := node as Node3D
		if body == null:
			continue
		var rel := out - body.global_position
		rel.y = 0.0
		var dist: float = rel.length()
		if dist < 2.3:
			if dist < 0.05:
				rel = Vector3(1.0, 0.0, 0.0)
				dist = 0.05
			out += rel.normalized() * (2.3 - dist)
	out.y = 0.65
	return out


func _right_corner(car: Node) -> Vector3:
	var pts := _points(car)
	if pts.size() < 3:
		return Vector3.ZERO
	var cursor: int = int(car.call("route_cursor"))
	var i0 := cursor
	var p1: Vector3 = pts[(i0 + 1) % pts.size()]
	var leg0 := p1 - pts[i0]
	leg0.y = 0.0
	var pos := (car as Node3D).global_position
	for _step in 4:
		var i2: int = (i0 + 2) % pts.size()
		var p2: Vector3 = pts[i2]
		var leg1 := p2 - p1
		leg1.y = 0.0
		if leg0.length() > 0.4 and leg1.length() > 0.4:
			var cross: float = leg0.x * leg1.z - leg0.z * leg1.x
			if cross < -0.25 * leg0.length() * leg1.length() and p1.distance_to(pos) < 18.0:
				return p1
		leg0 = leg1
		p1 = p2
		i0 = (i0 + 1) % pts.size()
	return Vector3.ZERO


func _after_corner(car: Node, corner: Vector3) -> Vector3:
	var pts := _points(car)
	var cursor: int = int(car.call("route_cursor"))
	var goal: int = int(car.get("route_goal"))
	var best := corner + _forward(car as Node3D) * 8.0
	var best_d := 10000.0
	var seen_corner := false
	var i := cursor
	var guard := 0
	while guard < pts.size():
		var d: float = Vector2(pts[i].x - corner.x, pts[i].z - corner.z).length()
		if d < 3.0:
			seen_corner = true
		if seen_corner and d > 6.0 and d < best_d:
			best_d = d
			best = pts[i]
			break
		if goal >= 0 and i == goal:
			break
		i = (i + 1) % pts.size()
		guard += 1
	best.y = 0.65
	return best


func _speed_for(car: Node3D, delta: float, fwd: Vector3, path: PackedVector3Array) -> float:
	var intel: float = float(car.get("drive_intel"))
	var agg: float = float(car.get("drive_agg"))
	var base: float = float(car.get("drive_base_agg"))
	var limit: float = maxf(float(car.get("speed")), 1.0)
	var turning := _turning(car.global_position, fwd, path)
	var target: float = _limit_speed(limit, agg, base)
	if turning:
		target *= 0.45
	var travel := _travel_dir(car, fwd)
	var leader := _leader(car, travel)
	if leader != null and not _passing and not _pass_rejoining and not _on_cones and not _escaping:
		var rel := leader.global_position - car.global_position
		rel.y = 0.0
		var along: float = rel.dot(travel)
		var want: float = 3.4 * lerpf(1.4, 0.58, agg) * lerpf(0.82, 1.45, intel)
		var gap: float = along - 2.6
		var their: float = _speed_of(leader)
		_have_leader = true
		_leader_at = leader.global_position
		_follow_gap = gap
		_follow_want = want
		if gap < want:
			var blend: float = clampf((gap - 1.1) / maxf(want - 1.1, 0.4), 0.0, 1.0)
			target = minf(target, maxf(their, 0.0) * blend)
			if their < 0.6 and _halt != "red":
				_halt = "jam"
				_halt_along = gap
		if their > 0.8 and their + 1.0 < _limit_speed(limit, agg, base):
			_follow_time += delta
			var need: float = lerpf(2.5, 0.6, agg)
			# A pass begun near a bend/U-turn is immediately canceled by
			# _passing_path(), which rejoins before the corner even if the leader
			# has not been cleared. Require enough straight road to complete it.
			var turn_distance := _first_turn_distance(path)
			if _follow_time > need and not _pass_locked and turn_distance >= 18.0:
				_pass_locked = true
				var clear := _oncoming_clear(car)
				_passing = clear or randf() < 0.08 + (1.0 - intel) * 0.12
				_pass_rejoining = false
				_record_pass_event("attempt", car, leader, gap, their, turn_distance, clear, "clear" if clear else ("aggressive_gap" if _passing else "oncoming_traffic"))
				if _passing:
					_pass_target = leader
		else:
			_follow_time = 0.0
			_pass_locked = false
	elif leader == null:
		_follow_time = 0.0
		_pass_locked = false
		if not _on_cones and not _passing:
			_passing = false
	if _passing and _pass_target != null:
		if not is_instance_valid(_pass_target):
			_record_pass_event("abort", car, null, _follow_gap, -1.0, _first_turn_distance(path), _oncoming_clear(car), "target_removed")
			_begin_pass_rejoin(car, travel)
			_pass_target = null
		else:
			var passed_rel := _pass_target.global_position - car.global_position
			passed_rel.y = 0.0
			if passed_rel.dot(travel) < -3.0:
				_record_pass_event("complete", car, _pass_target, passed_rel.dot(travel), _speed_of(_pass_target), _first_turn_distance(path), true, "target_cleared")
				_begin_pass_rejoin(car, travel)
				_pass_target = null
	if _passing:
		var threat := _oncoming_body(car, fwd)
		if threat != null:
			var id := threat.get_instance_id()
			if id != _oncoming_id:
				_oncoming_id = id
				_oncoming_choice = 0 if randf() < 0.5 else 1
			_have_threat = true
			_threat_at = threat.global_position
			if intel >= 0.62:
				if _return_open(car, fwd, threat):
					_record_pass_event("abort", car, _pass_target, _follow_gap, _speed_of(threat), _first_turn_distance(path), false, "oncoming_vehicle_return")
					_begin_pass_rejoin(car, travel)
					_pass_target = null
					_threat_act = "back"
				else:
					target = 0.0
					_threat_act = "stop"
			elif _oncoming_choice == 0:
				target = maxf(target, limit * (1.0 + base * 0.35))
				_threat_act = "cut"
			else:
				if _return_open(car, fwd, threat):
					_record_pass_event("abort", car, _pass_target, _follow_gap, _speed_of(threat), _first_turn_distance(path), false, "oncoming_vehicle_dive")
					_begin_pass_rejoin(car, travel)
					_pass_target = null
					_threat_act = "dive"
				else:
					target = 0.0
					_threat_act = "stop"
	var sense := travel
	var motion := _flat_vel(car)
	if motion.length() > 2.0:
		sense = motion.normalized()
	var body_gap := _body_ahead(car, sense)
	var body_brake := false
	if not _on_cones and (_skirting or Time.get_ticks_msec() < _skirt_until):
		if _skirting:
			_skirt_until = Time.get_ticks_msec() + 1500
		# Stay slow until the pass is finished, even on the frames the nose points past the obstacle.
		target = minf(target, 4.5)
		body_brake = true
	elif body_gap >= 0.0 and not _on_cones:
		# The nose sits about 3 m ahead of the center. Stopping at 3.2 m overlapped the wreck.
		body_brake = true
		var body_room: float = body_gap - 5.8
		if body_room <= 0.0:
			target = 0.0
			if _halt != "red" and _halt != "stop":
				_halt = "jam"
				_halt_along = body_gap
		else:
			target = minf(target, sqrt(body_room * 10.0))
	if _escaping and _escape_speed_ok(car, fwd):
		var floor := 3.2
		var side_gap := _side_threat(car)
		if side_gap >= 0.0 and side_gap < 6.0:
			floor = 2.2
		target = maxf(target, floor)
		if _halt == "jam" or _halt == "gap" or _halt == "stop" or _halt == "yield":
			_halt = ""
			_halt_along = 999.0
	target = _braked_target(target)
	if _was_turn and not turning:
		_pace = target
	_was_turn = turning
	var rate: float = lerpf(3.4, 11.0, agg) if target < _pace else (lerpf(2.2, 7.5, agg) * lerpf(0.75, 1.1, intel))
	if target < _pace and (_halt == "red" or _halt == "stop" or _halt == "yield" or _halt == "gap" or _halt == "jam" or body_brake):
		rate = maxf(rate, 9.0)
	_pace = move_toward(_pace, target, rate * delta)
	# Settle only a real stop. A tiny nonzero target is the last creep up to a line, and zeroing it stranded the car short of the sign.
	if target <= 0.0 and _pace < 0.05:
		_pace = 0.0
	_target = target
	return _pace


# Far cars rebuild the path every few ticks. The brake still has to run every tick or the car arrives at the line at cruise.
func needs_tick() -> bool:
	return _halt != "" or _target + 0.35 < _pace or _reversing or _unstick > 0 or _still_t >= 3.0 or _escaping


func roll_speed(delta: float) -> float:
	if _halt_along < 900.0 and _pace > 0.05:
		_halt_along = maxf(_halt_along - _pace * delta, 0.0)
	var target := _braked_target(_target)
	var rate := 3.5
	if target < _pace:
		rate = 9.0 if (_halt != "" or target <= 0.05) else 4.5
	_pace = move_toward(_pace, target, rate * delta)
	if target <= 0.0 and _pace < 0.05:
		_pace = 0.0
	_target = target
	return _pace


func _braked_target(target: float) -> float:
	if _halt == "red" or _halt == "stop" or _halt == "gap" or _halt == "yield":
		var line := 2.6 if _halt == "gap" else 1.8
		var room: float = _halt_along - line
		if room <= 0.0:
			return 0.0
		# 5 m/s² preview. The car is already under cruise when the signal first appears, then the 9 m/s² brake catches it.
		return minf(target, sqrt(room * 10.0))
	if _halt == "jam":
		return minf(target, 0.35)
	return target


func _limit_speed(limit: float, agg: float, base: float) -> float:
	var first := 0.62
	if agg < first:
		var cruise: float = limit * lerpf(0.5, 0.9, agg / first)
		_limit_note = "Under the speeding line. Cruise %.1f on a %.0f limit." % [cruise, limit]
		return cruise
	var share := 0.22
	if agg >= 0.8:
		share = 0.48
	if agg >= 0.92:
		share = 0.85
	var fast: float = limit * (1.0 + base * share)
	_limit_note = "Speeding. Cruise %.1f. That is %.0f percent of base aggression over the %.0f limit." % [fast, share * 100.0, limit]
	return fast


func _tick_idle(car: Node, delta: float) -> void:
	var agg: float = float(car.get("drive_agg"))
	var counts := false
	if _halt == "gap" or _halt == "stop" or _halt == "jam":
		counts = true
	_idle_counts = counts and not _on_cones
	if counts and not _on_cones:
		_idle += delta
	else:
		_idle = maxf(0.0, _idle - delta)
	var leave_after: float = lerpf(7.0, 4.0, agg)
	var capped := _escape_capped and _still_t < STILL_LEAVE
	if counts and _idle > leave_after and not _on_cones and not _escaping and not capped:
		_escaping = true
		_escape_capped = false
		if _block_at.length_squared() < 0.1:
			var fwd := _forward(car as Node3D)
			_block_at = (car as Node3D).global_position + fwd * 4.0


func _mood(car: Node, delta: float) -> void:
	var agg: float = float(car.get("drive_agg"))
	var base: float = float(car.get("drive_base_agg"))
	var delayed: bool = _delayed or _halt != ""
	var goal: float = base
	var rate := 0.05
	if delayed:
		goal = minf(1.0, base + 0.48)
		rate = 0.08
	car.set("drive_agg", move_toward(agg, goal, rate * delta))


func _pursue(path: PackedVector3Array, pos: Vector3, fwd: Vector3) -> Vector3:
	if path.is_empty():
		return pos
	if path.size() == 1:
		var only := path[0]
		only.y = 0.65
		return only
	# A rebuilt path starts somewhere else. Don't keep an index into the old one.
	if path[0].distance_squared_to(_path_anchor) > 16.0:
		_path_i = 0
	_path_anchor = path[0]
	# Wrapping to the first point aims the car back down the path it already drove.
	if _path_i >= path.size() - 1:
		_path_i = maxi(path.size() - 2, 0)
	# Follow the segment under the car, then look ahead along that segment.
	# Nearest-vertex aim pointed backward whenever the car was just past the middle of a leg.
	var best_i := _path_i
	var best_d := 100000.0
	var best_proj := path[_path_i]
	var last_i := path.size() - 1
	for i in range(_path_i, last_i):
		var ab := Vector2(path[i + 1].x - path[i].x, path[i + 1].z - path[i].z)
		if _chain_dir.length_squared() > 0.2 and ab.length_squared() > 0.0001:
			if Vector3(ab.x, 0.0, ab.y).normalized().dot(_chain_dir) < -0.25:
				continue
		var ap := Vector2(pos.x - path[i].x, pos.z - path[i].z)
		var len2: float = ab.length_squared()
		var along := 0.0
		if len2 > 0.0001:
			along = clampf(ap.dot(ab) / len2, 0.0, 1.0)
		var proj := Vector3(path[i].x + ab.x * along, pos.y, path[i].z + ab.y * along)
		var dist: float = Vector2(pos.x - proj.x, pos.z - proj.z).length()
		var closer := dist + 0.45 < best_d
		# Only skip forward once the car is on the path. From far away every segment looks
		# the same distance, and the index ran to the far end of the cone line.
		var entered := best_d < 5.0 and dist <= best_d + 0.45 and along > 0.12 and i > best_i
		if closer or entered:
			best_d = dist
			best_i = i
			best_proj = proj
		elif i > best_i + 2 and dist > best_d + 4.0:
			break
	if best_d > 5000.0 and _on_cones and _chain_dir.length_squared() > 0.2 and _chain_dir.dot(fwd) > 0.2:
		var along_line := pos + _chain_dir * 4.8
		along_line.y = 0.65
		return along_line
	_path_i = best_i
	var remain := 4.8
	var prev := best_proj
	var aim := best_proj
	var cursor := best_i + 1
	while cursor < path.size() and remain > 0.05:
		var step_v := Vector3(path[cursor].x - prev.x, 0.0, path[cursor].z - prev.z)
		var step: float = Vector2(step_v.x, step_v.z).length()
		if step <= 0.001:
			cursor += 1
			continue
		if _chain_dir.length_squared() > 0.2 and step_v.normalized().dot(_chain_dir) < -0.25:
			break
		if step <= remain:
			remain -= step
			aim = path[cursor]
			prev = path[cursor]
			cursor += 1
		else:
			var hop: float = remain / step
			aim = Vector3(lerpf(prev.x, path[cursor].x, hop), 0.65, lerpf(prev.z, path[cursor].z, hop))
			remain = 0.0
	if fwd.length_squared() > 0.01:
		var aim_rel := aim - pos
		aim_rel.y = 0.0
		# A rejoin that sits a few centimeters behind the nose plane is still the lane. Treating that as backward aimed the car straight off the road.
		if aim_rel.length() > 0.4 and aim_rel.normalized().dot(fwd.normalized()) < -0.25:
			var look := _path_i + 1
			var found_ahead := false
			while look < path.size():
				var hop_pt := path[look] - pos
				hop_pt.y = 0.0
				if hop_pt.length() > 0.6 and hop_pt.normalized().dot(fwd.normalized()) > 0.2:
					aim = path[look]
					_path_i = maxi(look - 1, 0)
					found_ahead = true
					break
				look += 1
			if not found_ahead:
				if _escaping and not path.is_empty():
					# The shoulder point sits beside the nose. Aiming straight ahead drove through the cones.
					aim = path[0]
				elif _on_cones and _chain_dir.dot(fwd) > 0.2:
					aim = pos + _chain_dir * 4.8
				elif _doubles_back(path, _path_i, fwd):
					# The route turns back on itself. Aiming along the nose drove straight off the end of the road.
					var turn_i: int = mini(_path_i + 1, path.size() - 1)
					aim = path[turn_i]
				else:
					aim = pos + fwd * 4.8
	aim.y = 0.65
	return aim


func _doubles_back(path: PackedVector3Array, index: int, fwd: Vector3) -> bool:
	if index + 1 >= path.size() or fwd.length_squared() < 0.01:
		return false
	var leg := path[index + 1] - path[index]
	leg.y = 0.0
	if leg.length_squared() < 0.25:
		return false
	return leg.normalized().dot(fwd.normalized()) < -0.35


func _turning(pos: Vector3, _fwd: Vector3, path: PackedVector3Array) -> bool:
	if path.size() < 2:
		return false
	var here := _dir_along(path, pos, 0.0)
	var ahead := _dir_along(path, pos, 5.0)
	if here.length_squared() < 0.0001 or ahead.length_squared() < 0.0001:
		return false
	# Bend of the lane ahead, not the nose against the next dot. A dot the car is
	# passing sits beside the bumper and used to count as a finished turn.
	return here.normalized().angle_to(ahead.normalized()) > 0.35


func _dir_along(path: PackedVector3Array, pos: Vector3, dist: float) -> Vector3:
	if path.size() < 2:
		return Vector3.ZERO
	var i := clampi(_path_i, 0, path.size() - 2)
	var left := dist
	var guard := 0
	while guard < path.size():
		var ab := Vector2(path[i + 1].x - path[i].x, path[i + 1].z - path[i].z)
		var seg_len: float = ab.length()
		if seg_len < 0.001:
			if i >= path.size() - 2:
				break
			i += 1
			guard += 1
			continue
		var along := 0.0
		if guard == 0:
			var ap := Vector2(pos.x - path[i].x, pos.z - path[i].z)
			along = clampf(ap.dot(ab) / ab.length_squared(), 0.0, 1.0)
		var remain: float = seg_len * (1.0 - along)
		if left <= remain:
			return Vector3(ab.x, 0.0, ab.y)
		left -= remain
		if i >= path.size() - 2:
			return Vector3(ab.x, 0.0, ab.y)
		i += 1
		guard += 1
	return Vector3.ZERO


func _pick_chain(car: Node3D, fwd: Vector3) -> Array[Node3D]:
	_forget_finished(car)
	var chains := _chains(car)
	var skip: Array[int] = []
	for id in _done_ids:
		skip.append(id)
	if not _chain_ids.is_empty():
		var held := _held_chain(chains)
		if held.size() >= 3 and not _beyond_chain(car, held):
			return held
		for id in _chain_ids:
			if not skip.has(id):
				skip.append(id)
			if not _done_ids.has(id):
				_done_ids.append(id)
		_chain_ids.clear()
	return _nearest_chain(car, chains, fwd, skip)


func _forget_finished(car: Node3D) -> void:
	var keep: Array[int] = []
	for id in _done_ids:
		if not is_instance_id_valid(id):
			continue
		var found: Object = instance_from_id(id)
		if not (found is Node3D) or not is_instance_valid(found):
			continue
		var body := found as Node3D
		var gap: float = body.global_position.distance_to(car.global_position)
		if gap < 22.0:
			keep.append(id)
	_done_ids = keep


func _nearest_chain(car: Node3D, chains: Array, fwd: Vector3, skip: Array[int]) -> Array[Node3D]:
	var best: Array[Node3D] = []
	var best_d := 16.0
	for item in chains:
		var group := _as_chain(item)
		if _shares(group, skip):
			continue
		var near := 1000.0
		var ahead := false
		for body in group:
			var rel := body.global_position - car.global_position
			rel.y = 0.0
			var d: float = rel.length()
			if d < near:
				near = d
			if rel.dot(fwd) > -1.5:
				ahead = true
		if ahead and near < best_d:
			best_d = near
			best = group
	return best


func _shares(group: Array[Node3D], ids: Array[int]) -> bool:
	if ids.is_empty():
		return false
	var share := 0
	for body in group:
		if ids.has(body.get_instance_id()):
			share += 1
	return share >= 2


func _held_chain(chains: Array) -> Array[Node3D]:
	var best: Array[Node3D] = []
	var best_share := 0
	for item in chains:
		var group := _as_chain(item)
		var share := 0
		for body in group:
			if _chain_ids.has(body.get_instance_id()):
				share += 1
		if share >= 2 and share > best_share:
			best_share = share
			best = group
	return best


func _as_chain(item: Variant) -> Array[Node3D]:
	var group: Array[Node3D] = []
	if item is Array:
		for node in item:
			if node is Node3D:
				group.append(node as Node3D)
	return group


func _remember_chain(chain: Array[Node3D]) -> void:
	_chain_ids.clear()
	for body in chain:
		_chain_ids.append(body.get_instance_id())


func _beyond_chain(car: Node3D, chain: Array[Node3D]) -> bool:
	if _chain_dir.length_squared() < 0.2 or chain.size() < 2:
		return false
	var ordered := _order(chain)
	var span := ordered[ordered.size() - 1] - ordered[0]
	span.y = 0.0
	if span.dot(_chain_dir) < 0.0:
		ordered.reverse()
	var last: Vector3 = ordered[ordered.size() - 1]
	var rel := car.global_position - last
	rel.y = 0.0
	# The exit point sits 4 m past the last cone. Releasing only past that left the car parked on it.
	if rel.dot(_chain_dir) >= 3.0:
		return true
	# A curb clamp can pull that exit point back onto the last cone. Reaching it still ends the line.
	var past: Vector3 = last + _chain_dir * 4.0
	past.y = 0.65
	past = _keep_asphalt(car, past)
	var dx: float = car.global_position.x - past.x
	var dz: float = car.global_position.z - past.z
	return Vector2(dx, dz).length() < 2.2


func _goal_point(car: Node) -> Vector3:
	var pts := _points(car)
	if pts.is_empty():
		return (car as Node3D).global_position
	var goal: int = int(car.get("route_goal"))
	if goal >= 0 and goal < pts.size():
		return pts[goal]
	var cursor: int = int(car.call("route_cursor"))
	return pts[cursor % pts.size()]


func _chains(car: Node) -> Array:
	var nodes: Array[Node3D] = []
	for node in car.get_tree().get_nodes_in_group("stack_target"):
		var body := node as Node3D
		if body == null or _playerish(body):
			continue
		if body.global_position.distance_to((car as Node3D).global_position) > 34.0:
			continue
		nodes.append(body)
	var used: Array[bool] = []
	used.resize(nodes.size())
	var chains: Array = []
	for i in nodes.size():
		if used[i]:
			continue
		var group: Array[Node3D] = []
		var stack: Array[int] = [i]
		used[i] = true
		while stack.size() > 0:
			var at: int = stack.pop_back()
			group.append(nodes[at])
			for j in nodes.size():
				if used[j]:
					continue
				if nodes[at].global_position.distance_to(nodes[j].global_position) <= 2.55:
					used[j] = true
					stack.append(j)
		if group.size() >= 3 and _linear(group):
			chains.append(group)
	return chains


func _linear(group: Array[Node3D]) -> bool:
	var a := group[0].global_position
	var b := a
	var best := 0.0
	for i in group.size():
		for j in range(i + 1, group.size()):
			var d: float = Vector2(group[i].global_position.x - group[j].global_position.x, group[i].global_position.z - group[j].global_position.z).length()
			if d > best:
				best = d
				a = group[i].global_position
				b = group[j].global_position
	if best < 4.0:
		return false
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	var dev := 0.0
	var wide := 0.0
	for body in group:
		var rel := body.global_position - a
		rel.y = 0.0
		var lat: float = (rel - dir * rel.dot(dir)).length()
		dev += lat
		if lat > wide:
			wide = lat
	dev /= float(group.size())
	if dev > 0.7:
		return false
	return best >= wide * 2.4


func _far_side_line(chain: Array[Node3D], car: Node3D, fwd: Vector3) -> bool:
	# Judge against the leg the car is on now. The later U-turn comes back on the other side,
	# and that return leg sits closer to cones over there than the leg the car is still driving.
	var slice := _route_slice(car)
	if slice.size() < 2 or chain.is_empty():
		return false
	var ab := Vector3(slice[1].x - slice[0].x, 0.0, slice[1].z - slice[0].z)
	if ab.length_squared() < 0.25:
		ab = _road_axis(car, fwd)
	var axis := ab.normalized()
	var along: float = Vector3(car.global_position.x - slice[0].x, 0.0, car.global_position.z - slice[0].z).dot(axis)
	var base := Vector3(slice[0].x, 0.0, slice[0].z) + axis * along
	var right := _right(axis)
	var limit: float = GameConstants.LANE_OFF + 1.0
	for body in chain:
		var lat: float = (body.global_position - base).dot(right)
		if lat < limit:
			return false
	return true


func _keep_asphalt(car: Node3D, at: Vector3) -> Vector3:
	var city := _city(car)
	if city == null or not city.has_method("on_asphalt"):
		return at
	if bool(city.call("on_asphalt", at.x, at.z)):
		return at
	if not city.has_method("nearest_asphalt"):
		return at
	var raw: Variant = city.call("nearest_asphalt", at.x, at.z)
	if raw is Vector3:
		var edge: Vector3 = raw
		# A point past the curb clamps onto the exclusive edge. That edge is not on the road, and the car stopped there.
		var inward := edge - at
		inward.y = 0.0
		if inward.length_squared() < 0.01:
			inward = _into_road(city, edge)
		return _seat_on_road(car, edge, inward)
	return at


func _into_road(city: Node, edge: Vector3) -> Vector3:
	# edge - at is zero when the clamp already sits on the lip. Probe each side and step into the road.
	var hops: Array[Vector3] = [
		Vector3(0.0, 0.0, -1.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(-1.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
	]
	for step in hops:
		var probe: Vector3 = edge + step * 0.6
		if bool(city.call("on_asphalt", probe.x, probe.z)):
			return step
	return Vector3(0.0, 0.0, -1.0)


func _chain_across(chain: Array[Node3D], fwd: Vector3) -> bool:
	# A line along the road stays a guide. A line across the lanes is a wall.
	var ordered := _order(chain)
	if ordered.size() < 2:
		return false
	var span := ordered[ordered.size() - 1] - ordered[0]
	span.y = 0.0
	var travel := Vector3(fwd.x, 0.0, fwd.z)
	if span.length_squared() < 0.01 or travel.length_squared() < 0.01:
		return false
	return absf(span.normalized().dot(travel.normalized())) < 0.45


func _order(group: Array[Node3D]) -> Array[Vector3]:
	var a := group[0].global_position
	var b := a
	var best := 0.0
	for i in group.size():
		for j in range(i + 1, group.size()):
			var d: float = Vector2(group[i].global_position.x - group[j].global_position.x, group[i].global_position.z - group[j].global_position.z).length()
			if d > best:
				best = d
				a = group[i].global_position
				b = group[j].global_position
	var axis := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if axis.length_squared() < 0.01:
		axis = Vector3(1.0, 0.0, 0.0)
	axis = axis.normalized()
	var pts: Array[Vector3] = []
	var keys: Array[float] = []
	for body in group:
		pts.append(body.global_position)
		keys.append((body.global_position - a).dot(axis))
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			if keys[j] < keys[i]:
				var key: float = keys[i]
				keys[i] = keys[j]
				keys[j] = key
				var point: Vector3 = pts[i]
				pts[i] = pts[j]
				pts[j] = point
	return pts


func _key_of(group: Array[Node3D]) -> int:
	var key := 0
	for body in group:
		key = key ^ (int(body.global_position.x * 2.0) * 13 + int(body.global_position.z * 2.0) * 29)
	return key


func _obstacles(car: Node3D) -> Array:
	var out: Array = []
	var pos := car.global_position
	for node in car.get_tree().get_nodes_in_group("stack_target"):
		_push_obs(out, node, pos, 0.3, "cone")
	for node in car.get_tree().get_nodes_in_group("pedestrian"):
		_push_obs(out, node, pos, 0.5, "ped")
	for node in car.get_tree().get_nodes_in_group("vehicle"):
		if node is RigidBody3D:
			_push_obs(out, node, pos, 1.6, "wreck")
	for node in car.get_tree().get_nodes_in_group("hitter"):
		if node == car or not (node is Node3D):
			continue
		if _speed_of(node as Node3D) < 0.7:
			_push_obs(out, node, pos, 1.5, "car")
	return out


func _push_obs(out: Array, node: Node, pos: Vector3, radius: float, kind: String) -> void:
	var body := node as Node3D
	if body == null or _playerish(body):
		return
	if body.global_position.distance_to(pos) > 20.0:
		return
	if kind == "cone":
		radius = _cone_radius(body)
	out.append({"pos": body.global_position, "radius": radius, "kind": kind})


func _cone_radius(body: Node) -> float:
	for child in body.get_children():
		if child.get("piece_type") != null:
			var kind := int(child.get("piece_type"))
			if kind == 2:
				return 0.48
			if kind == 1:
				return 0.22
			return 0.3
	return 0.3


func _leader(car: Node3D, fwd: Vector3) -> Node3D:
	var best: Node3D = null
	var best_along := 24.0
	for node in car.get_tree().get_nodes_in_group("hitter"):
		if node == car or not (node is Node3D):
			continue
		var other := node as Node3D
		var rel := other.global_position - car.global_position
		rel.y = 0.0
		var along: float = rel.dot(fwd)
		if along < 1.2 or along > best_along:
			continue
		var lat: float = (rel - fwd * along).length()
		if lat > 2.3:
			continue
		var their := _flat_vel(other)
		if their.length() > 0.4 and their.normalized().dot(fwd) < 0.35:
			continue
		best_along = along
		best = other
	return best


func _asphalt_leader(car: Node3D, fwd: Vector3) -> Node3D:
	for node in car.get_tree().get_nodes_in_group("hitter"):
		if node == car or not (node is Node3D):
			continue
		var other := node as Node3D
		if not bool(other.get("left_asphalt")):
			continue
		var rel := other.global_position - car.global_position
		rel.y = 0.0
		if rel.dot(fwd) < 0.0 or rel.length() > 18.0:
			continue
		return other
	return null


func _emergency(car: Node3D) -> Node3D:
	var best: Node3D = null
	var best_d := 32.0
	for node in car.get_tree().get_nodes_in_group("hitter"):
		if node == car or not (node is Node3D):
			continue
		var other := node as Node3D
		if not bool(other.get("code_three")) or bool(other.get("wrecker")):
			continue
		var d: float = Vector2(other.global_position.x - car.global_position.x, other.global_position.z - car.global_position.z).length()
		if d < best_d:
			best_d = d
			best = other
	return best


func _oncoming_body(car: Node3D, fwd: Vector3) -> Node3D:
	# The opposing lane is across the center line, in the same direction used by
	# the pass offset. Checking the other side missed approaching traffic.
	var opposing_side := _right(fwd)
	for node in car.get_tree().get_nodes_in_group("hitter"):
		if node == car or not (node is Node3D):
			continue
		var other := node as Node3D
		var rel := other.global_position - car.global_position
		rel.y = 0.0
		var along: float = rel.dot(fwd)
		if along < 0.5 or along > 22.0:
			continue
		if rel.dot(opposing_side) < 0.4:
			continue
		var their := _flat_vel(other)
		if their.length() > 0.3 and their.normalized().dot(fwd) < -0.35:
			return other
	return null


func _oncoming_clear(car: Node3D) -> bool:
	return _oncoming_body(car, _forward(car)) == null


func _record_pass_event(event: String, car: Node3D, target: Node3D, gap: float, target_speed: float, turn_distance: float, oncoming_clear: bool, reason: String) -> void:
	_pass_event_id += 1
	var target_position := Vector3.ZERO
	var target_name := "none"
	if is_instance_valid(target):
		target_position = target.global_position
		target_name = str(target.name)
	_pass_event = {
		"id": _pass_event_id,
		"event": event,
		"accepted": _passing,
		"reason": reason,
		"car": str(car.name),
		"car_position": car.global_position,
		"target": target_name,
		"target_position": target_position,
		"gap": gap,
		"target_speed": target_speed,
		"turn_distance": turn_distance,
		"oncoming_clear": oncoming_clear,
		"follow_time": _follow_time,
		"intel": float(car.get("drive_intel")),
		"aggression": float(car.get("drive_agg")),
	}


func _return_open(car: Node3D, fwd: Vector3, threat: Node3D = null) -> bool:
	var right := _right(fwd)
	var merge_lateral := -3.1
	if _pass_target != null and is_instance_valid(_pass_target):
		var target_rel := _pass_target.global_position - car.global_position
		target_rel.y = 0.0
		merge_lateral = clampf(target_rel.dot(right), -4.8, 0.8)
	for node in car.get_tree().get_nodes_in_group("hitter"):
		if node == car or node == threat or not (node is Node3D):
			continue
		var other := node as Node3D
		var rel := other.global_position - car.global_position
		rel.y = 0.0
		var lateral := rel.dot(right)
		if absf(rel.dot(fwd)) < 8.0 and absf(lateral - merge_lateral) < 1.6:
			return false
	return true


func _playerish(body: Node) -> bool:
	if body.is_in_group("soul"):
		return true
	var parent := body.get_parent()
	return parent != null and parent.is_in_group("soul")


func _speed_of(body: Node3D) -> float:
	return _flat_vel(body).length()


func _flat_vel(body: Node3D) -> Vector3:
	var raw: Variant = body.get("travel_velocity")
	var flat := Vector3.ZERO
	if raw is Vector3:
		flat = raw
	elif body is CharacterBody3D:
		flat = (body as CharacterBody3D).velocity
	flat.y = 0.0
	return flat


func _travel_dir(car: Node3D, nose: Vector3) -> Vector3:
	if car.has_method("is_backing") and bool(car.call("is_backing")):
		return -nose
	return nose


func _through_cones(car: Node3D, fwd: Vector3, path: PackedVector3Array) -> PackedVector3Array:
	# Eastbound nose is +X, and _right of that nose is -Z. From the +Z lane, +3.5 along _right lands on z=1.75.
	# Measure the wall against the route, not the car, so a dodge already in progress is not treated as a clear lane.
	var empty := PackedVector3Array()
	var here := car.global_position
	if _cone_turn.x > -9000.0:
		if Vector2(here.x, here.z).distance_to(_cone_turn) < 48.0:
			# The exit is already chosen. Keep that route until the car is through the intersection.
			return path
		_cone_turn = Vector2(-99999.0, -99999.0)
	var slice := _route_slice(car)
	if slice.size() < 2:
		slice = path
	var frame: Dictionary = _route_basis(slice, car.global_position, fwd)
	var base: Vector3 = frame["base"]
	var axis: Vector3 = frame["axis"]
	var right: Vector3 = frame["right"]
	var cones := _cones_ahead(car, base, axis, right)
	var block_along := 24.0
	var blocked := false
	for raw in cones:
		var cone_pos: Vector3 = raw
		var rel := cone_pos - car.global_position
		rel.y = 0.0
		var along: float = rel.dot(axis)
		var lat: float = (cone_pos - base).dot(right)
		if absf(lat) < 1.85 and along < block_along:
			blocked = true
			block_along = along
	if not blocked:
		return empty
	var wall := base + axis * block_along
	wall.y = 0.65
	_block_at = wall
	var found: Dictionary = _clear_lateral(car, base, axis, right, cones, block_along)
	if bool(found.get("ok", false)):
		var gap: float = float(found.get("gap", 0.0))
		var opened := _gap_path(slice, car.global_position, base, axis, right, block_along, gap, wall)
		var near := _cones_near(car, 40.0)
		if not _poly_hits(opened, near, 1.7):
			_holding = false
			if absf(gap) > 2.4:
				_path_kind = "pass"
			else:
				_path_kind = "route"
			return opened
	# The straight lane is walled. An open exit at this intersection is the way around.
	# A gap that rejoins the lane on the far side of the line is a drive through the cones.
	var turned := _open_exit(car, axis)
	if turned.size() >= 2:
		return turned
	_halt = "gap"
	_halt_along = maxf(block_along - 4.5, 0.0)
	_holding = false
	_path_kind = "route"
	return _hold_short(slice, car.global_position, axis, block_along)


func _open_exit(car: Node3D, axis: Vector3) -> PackedVector3Array:
	var empty := PackedVector3Array()
	if bool(car.get("drill_lock")):
		return empty
	var pos := car.global_position
	var junc := _junction_ahead(pos, axis)
	if junc.x < -9000.0:
		return empty
	if _cone_turn.distance_to(junc) < 3.0:
		return empty
	var cones := _cones_near(car, 40.0)
	# Physical left is _right(axis). Eastbound +X, left is -Z, and that lane sits at x = center + LANE_OFF.
	var left := _axis_dir(_right(axis))
	var right_exit := _axis_dir(-_right(axis))
	var taken := _exit_poly(car, junc, axis, left, cones)
	if taken.is_empty():
		taken = _exit_poly(car, junc, axis, right_exit, cones)
	if taken.is_empty():
		return empty
	return _take_exit(car, taken, junc)


func _junction_ahead(pos: Vector3, axis: Vector3) -> Vector2:
	var spots: Array[Vector2] = _generated_junctions()
	if spots.is_empty():
		return _loop_junction_ahead(pos, axis)
	var best := Vector2(-99999.0, -99999.0)
	var best_d := 48.0
	for spot in spots:
		var rel := Vector3(spot.x - pos.x, 0.0, spot.y - pos.z)
		var along: float = rel.dot(axis)
		var lat: float = (rel - axis * along).length()
		if along > 2.0 and along < best_d and lat < 16.0:
			best_d = along
			best = spot
	return best


func _generated_junctions() -> Array[Vector2]:
	var none: Array[Vector2] = []
	var car := get_parent() as Node3D
	if car == null:
		return none
	var city := _city(car)
	if city == null or not city.has_meta("road_junctions"):
		return none
	var raw: Variant = city.get_meta("road_junctions")
	if not (raw is Array):
		return none
	var spots: Array[Vector2] = []
	for item in raw:
		if item is Vector2:
			spots.append(item)
	return spots


func _loop_junction_ahead(pos: Vector3, axis: Vector3) -> Vector2:
	var best := Vector2(-99999.0, -99999.0)
	var best_d := 48.0
	var xi := 0
	while xi < GameConstants.LOOP_X.size():
		var x: float = GameConstants.LOOP_X[xi]
		var zi := 0
		while zi < GameConstants.LOOP_Z.size():
			var z: float = GameConstants.LOOP_Z[zi]
			var rel := Vector3(x - pos.x, 0.0, z - pos.z)
			var along: float = rel.dot(axis)
			var lat: float = (rel - axis * along).length()
			if along > 2.0 and along < best_d and lat < 16.0:
				best_d = along
				best = Vector2(x, z)
			zi += 1
		xi += 1
	return best


func _exit_poly(car: Node3D, junc: Vector2, approach: Vector3, exit_dir: Vector3, cones: Array[Vector3]) -> PackedVector3Array:
	var empty := PackedVector3Array()
	if exit_dir.length_squared() < 0.5:
		return empty
	var backs: Array[float] = [-14.0, -8.0, -4.0]
	var forwards: Array[float] = [16.0, 24.0, 10.0]
	for back in backs:
		var mouth := _lane_at(junc, approach, back)
		for ahead in forwards:
			var corner := _lane_at(junc, exit_dir, ahead)
			var poly := PackedVector3Array()
			var here := car.global_position
			here.y = 0.65
			poly.append(here)
			if Vector2(mouth.x - here.x, mouth.z - here.z).length() > 3.0:
				poly.append(mouth)
			poly.append(corner)
			var dist: float = ahead + 36.0
			while dist < 210.0:
				var at := _lane_at(junc, exit_dir, dist)
				if not _asphalt_at(car, at):
					break
				poly.append(at)
				dist += 36.0
			if poly.size() >= 3 and _poly_clear(car, poly, cones):
				return poly
	return empty


func _lane_at(center: Vector2, travel: Vector3, dist: float) -> Vector3:
	# Right-hand lane. Facing +X, the lane is +Z. Facing +Z, the lane is -X.
	var lane: float = _module_lane()
	var dir := _axis_dir(travel)
	if absf(dir.x) >= absf(dir.z):
		var z: float = center.y + lane if dir.x > 0.0 else center.y - lane
		return Vector3(center.x + dir.x * dist, 0.65, z)
	var x: float = center.x - lane if dir.z > 0.0 else center.x + lane
	return Vector3(x, 0.65, center.y + dir.z * dist)


func _module_lane() -> float:
	var car := get_parent() as Node3D
	if car == null:
		return GameConstants.LANE_OFF
	var city := _city(car)
	if city != null and city.has_meta("road_lane_m"):
		return float(city.get_meta("road_lane_m"))
	return GameConstants.LANE_OFF


func _axis_dir(dir: Vector3) -> Vector3:
	if absf(dir.x) >= absf(dir.z):
		if dir.x >= 0.0:
			return Vector3(1.0, 0.0, 0.0)
		return Vector3(-1.0, 0.0, 0.0)
	if dir.z >= 0.0:
		return Vector3(0.0, 0.0, 1.0)
	return Vector3(0.0, 0.0, -1.0)


func _take_exit(car: Node3D, poly: PackedVector3Array, junc: Vector2) -> PackedVector3Array:
	var lined := PackedVector3Array()
	var here := car.global_position
	here.y = 0.65
	lined.append(here)
	for point in poly:
		if lined[lined.size() - 1].distance_to(point) > 3.0:
			lined.append(point)
	if lined.size() < 2:
		return PackedVector3Array()
	car.call("set_route", lined, PackedByteArray(), 1)
	car.set("route_goal", lined.size() - 1)
	_span_set = true
	_path_i = 0
	_path_anchor = Vector3(99999.0, 0.0, 99999.0)
	_cone_turn = junc
	_path_kind = "turn"
	_escaping = false
	_escape_capped = false
	_idle = 0.0
	_holding = false
	if _halt == "gap":
		_halt = ""
		_halt_along = 999.0
	return lined


func _cones_near(car: Node3D, reach: float) -> Array[Vector3]:
	var cones: Array[Vector3] = []
	var pos := car.global_position
	for node in car.get_tree().get_nodes_in_group("stack_target"):
		var body := node as Node3D
		if body == null or _playerish(body):
			continue
		if Vector2(body.global_position.x - pos.x, body.global_position.z - pos.z).length() > reach:
			continue
		cones.append(body.global_position)
	return cones


func _poly_hits(poly: PackedVector3Array, cones: Array[Vector3], pad: float) -> bool:
	if poly.size() < 2 or cones.is_empty():
		return false
	for i in range(poly.size() - 1):
		var a: Vector3 = poly[i]
		var b: Vector3 = poly[i + 1]
		var span := Vector2(b.x - a.x, b.z - a.z)
		var length: float = span.length()
		var steps: int = maxi(1, int(length / 1.4))
		for s in steps + 1:
			var t: float = float(s) / float(steps)
			var at := Vector2(lerpf(a.x, b.x, t), lerpf(a.z, b.z, t))
			for cone in cones:
				if Vector2(at.x - cone.x, at.y - cone.z).length() < pad:
					return true
	return false


func _poly_clear(car: Node3D, poly: PackedVector3Array, cones: Array[Vector3]) -> bool:
	if poly.size() < 2:
		return false
	for i in range(poly.size() - 1):
		var a: Vector3 = poly[i]
		var b: Vector3 = poly[i + 1]
		var span := Vector2(b.x - a.x, b.z - a.z)
		var length: float = span.length()
		var steps: int = maxi(1, int(length / 1.4))
		for s in steps + 1:
			var t: float = float(s) / float(steps)
			var at := Vector3(lerpf(a.x, b.x, t), 0.65, lerpf(a.z, b.z, t))
			if not _asphalt_at(car, at):
				return false
			for cone in cones:
				if Vector2(at.x - cone.x, at.z - cone.z).length() < 1.7:
					return false
	return true


func _asphalt_at(car: Node3D, at: Vector3) -> bool:
	var city := _city(car)
	if city == null or not city.has_method("on_asphalt"):
		return true
	return bool(city.call("on_asphalt", at.x, at.z))


func _road_axis(car: Node3D, fwd: Vector3) -> Vector3:
	var axis := Vector3(fwd.x, 0.0, fwd.z)
	if axis.length_squared() < 0.01:
		axis = Vector3(1.0, 0.0, 0.0)
	axis = axis.normalized()
	var slice := _route_slice(car)
	if slice.size() < 2:
		return axis
	var pos := car.global_position
	var best_d := 100000.0
	var best := axis
	for i in range(slice.size() - 1):
		var ab := Vector3(slice[i + 1].x - slice[i].x, 0.0, slice[i + 1].z - slice[i].z)
		if ab.length_squared() < 0.25:
			continue
		var len2: float = Vector2(ab.x, ab.z).length_squared()
		var t := 0.0
		var ap := Vector3(pos.x - slice[i].x, 0.0, pos.z - slice[i].z)
		if len2 > 0.0001:
			t = clampf(ap.dot(ab) / len2, 0.0, 1.0)
		var proj := Vector3(slice[i].x, 0.0, slice[i].z) + ab * t
		var dist: float = Vector2(pos.x - proj.x, pos.z - proj.z).length()
		if dist < best_d:
			best_d = dist
			best = ab.normalized()
	if best_d < 18.0:
		return best
	return axis


func _route_slice(car: Node3D) -> PackedVector3Array:
	var pts := _points(car)
	var out := PackedVector3Array()
	if pts.size() < 2:
		return out
	var cursor: int = int(car.call("route_cursor"))
	var goal: int = int(car.get("route_goal"))
	var i := cursor
	var guard := 0
	while guard < pts.size():
		out.append(pts[i])
		if goal >= 0 and i == goal:
			break
		i = (i + 1) % pts.size()
		guard += 1
	return out


func _cones_ahead(car: Node3D, base: Vector3, axis: Vector3, right: Vector3) -> Array[Vector3]:
	var cones: Array[Vector3] = []
	# The far lane is about 10.5 m from this one, and the far curb is about 12 m. A shorter window hid that lane and left a false gap.
	var half: float = GameConstants.ROAD_HALF * 2.0 + 1.5
	var pos := car.global_position
	for node in car.get_tree().get_nodes_in_group("stack_target"):
		var body := node as Node3D
		if body == null or _playerish(body):
			continue
		var rel := body.global_position - pos
		rel.y = 0.0
		var along: float = rel.dot(axis)
		# Cones inside 2 m used to drop out of the scan. The halt cleared and the car drove through the line.
		if along < 0.35 or along > 24.0:
			continue
		var lat: float = (body.global_position - base).dot(right)
		if absf(lat) > half:
			continue
		cones.append(body.global_position)
	return cones


func _clear_lateral(car: Node3D, base: Vector3, axis: Vector3, right: Vector3, cones: Array[Vector3], block_along: float) -> Dictionary:
	var city := _city(car)
	var best := 1000.0
	var gap := 0.0
	var have := false
	var lat := -10.5
	while lat <= 10.51:
		var blocked := false
		for raw in cones:
			var cone_pos: Vector3 = raw
			var cone_lat: float = (cone_pos - base).dot(right)
			if absf(cone_lat - lat) < 1.85:
				blocked = true
				break
		if not blocked:
			var at := base + axis * block_along + right * lat
			var on_road := true
			if city != null and city.has_method("on_asphalt"):
				on_road = bool(city.call("on_asphalt", at.x, at.z))
			if on_road:
				var cost: float = absf(lat)
				if at.z * base.z < 0.0:
					cost += 8.0
				if not have or cost < best:
					best = cost
					gap = lat
					have = true
		lat += 1.75
	return {"ok": have, "gap": gap}


func _hold_short(path: PackedVector3Array, pos: Vector3, axis: Vector3, block_along: float) -> PackedVector3Array:
	# Stay short of the wall. A minimum of 1.2 m aimed the bumper past a line the car had already reached.
	var stop_at: float = block_along - 4.5
	var out := PackedVector3Array()
	var here := pos
	here.y = 0.65
	out.append(here)
	if stop_at < 0.4:
		return out
	for point in path:
		var rel := point - pos
		rel.y = 0.0
		var along: float = rel.dot(axis)
		if along > 1.0 and along < stop_at - 0.4:
			out = _append_far(out, point)
	var stop := pos + axis * stop_at
	return _append_far(out, stop)


func _gap_path(path: PackedVector3Array, pos: Vector3, base: Vector3, axis: Vector3, right: Vector3, block_along: float, gap: float, wall: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var here := pos
	here.y = 0.65
	out.append(here)
	var lead: float = maxf(minf(block_along - 6.0, 8.0), 2.0)
	out = _append_far(out, base + axis * lead + right * gap)
	out = _append_far(out, base + axis * maxf(block_along - 2.0, lead) + right * gap)
	out = _append_far(out, base + axis * (block_along + 8.0) + right * gap)
	out = _append_far(out, base + axis * (block_along + 18.0))
	var tail := _route_tail(path, wall, 20.0)
	for point in tail:
		out = _append_far(out, point)
	return out


func _route_tail(path: PackedVector3Array, wall: Vector3, extra: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if path.size() < 2:
		return out
	var best_i := 0
	var best_d := 100000.0
	var best_t := 0.0
	for i in range(path.size() - 1):
		var ab := Vector2(path[i + 1].x - path[i].x, path[i + 1].z - path[i].z)
		var ap := Vector2(wall.x - path[i].x, wall.z - path[i].z)
		var len2: float = ab.length_squared()
		var t := 0.0
		if len2 > 0.0001:
			t = clampf(ap.dot(ab) / len2, 0.0, 1.0)
		var proj := Vector2(path[i].x, path[i].z) + ab * t
		var dist: float = proj.distance_to(Vector2(wall.x, wall.z))
		if dist < best_d:
			best_d = dist
			best_i = i
			best_t = t
	var left: float = extra
	var seg_i := best_i
	var seg_t: float = best_t
	var guard := 0
	while guard < path.size() and seg_i < path.size() - 1:
		var ab2 := Vector2(path[seg_i + 1].x - path[seg_i].x, path[seg_i + 1].z - path[seg_i].z)
		var remain: float = ab2.length() * (1.0 - seg_t)
		if left <= remain:
			break
		left -= remain
		seg_i += 1
		seg_t = 0.0
		guard += 1
	var start: int = seg_i + 1
	if start < path.size():
		for j in range(start, path.size()):
			out.append(path[j])
	return out


func _route_basis(path: PackedVector3Array, pos: Vector3, fwd: Vector3) -> Dictionary:
	var axis := Vector3(fwd.x, 0.0, fwd.z)
	if axis.length_squared() < 0.01:
		axis = Vector3(1.0, 0.0, 0.0)
	axis = axis.normalized()
	var base := pos
	if path.size() >= 2:
		var best_d := 100000.0
		var best := pos
		var best_dir := axis
		for i in range(path.size() - 1):
			var ab := Vector3(path[i + 1].x - path[i].x, 0.0, path[i + 1].z - path[i].z)
			var len2: float = Vector2(ab.x, ab.z).length_squared()
			var t := 0.0
			if len2 > 0.0001:
				var ap := Vector3(pos.x - path[i].x, 0.0, pos.z - path[i].z)
				t = clampf(ap.dot(ab) / len2, 0.0, 1.0)
			var proj := Vector3(path[i].x, 0.0, path[i].z) + ab * t
			var dist: float = Vector2(pos.x - proj.x, pos.z - proj.z).length()
			if dist < best_d:
				best_d = dist
				best = proj
				if ab.length_squared() > 0.25:
					best_dir = ab.normalized()
		if best_d < 12.0:
			base = best
			if best_dir.dot(axis) > 0.2:
				axis = best_dir
	base.y = 0.65
	return {"base": base, "axis": axis, "right": _right(axis)}


func _append_far(path: PackedVector3Array, point: Vector3) -> PackedVector3Array:
	var at := point
	at.y = 0.65
	if path.is_empty() or path[path.size() - 1].distance_to(at) > 0.45:
		path.append(at)
	return path


func _around_block(path: PackedVector3Array, car: Node3D, nose: Vector3, caution: float, intel: float) -> PackedVector3Array:
	var travel := _travel_dir(car, nose)
	var block := _close_block(car, travel, BLOCK_CLOSE_M)
	var found: bool = block.x < 90000.0
	if _holding:
		var same := false
		if found:
			same = Vector2(block.x - _held_block.x, block.z - _held_block.z).length() < 3.5
		if _passed_block(car, travel) or not same:
			_holding = false
		else:
			return _held_path
	if not found:
		return path
	var nudged := _nudge(path, car, nose, caution, intel)
	var skirt := nudged
	if not _path_moved(path, nudged) and _halt != "gap":
		skirt = _skirt(path, car, travel, nose, block)
	_held_path = skirt
	_held_block = block
	_holding = true
	return skirt


func _path_moved(before: PackedVector3Array, after: PackedVector3Array) -> bool:
	var count: int = mini(before.size(), after.size())
	for i in count:
		var dx: float = before[i].x - after[i].x
		var dz: float = before[i].z - after[i].z
		if Vector2(dx, dz).length() > 0.35:
			return true
	return after.size() != before.size()


func _passed_block(car: Node3D, travel: Vector3) -> bool:
	if travel.length_squared() < 0.01:
		return false
	var rel := Vector3(_held_block.x - car.global_position.x, 0.0, _held_block.z - car.global_position.z)
	return rel.dot(travel.normalized()) < -2.0


func _close_block(car: Node3D, travel: Vector3, reach: float) -> Vector3:
	var none := Vector3(99999.0, 0.0, 99999.0)
	if travel.length_squared() < 0.01:
		return none
	var dir := travel.normalized()
	var pos := car.global_position
	var best := none
	var best_along := reach
	for item in _seen:
		var rec: Dictionary = item
		var kind := str(rec.get("kind", ""))
		if kind == "player" or kind == "guide":
			continue
		var op: Vector3 = rec["pos"]
		var rel := Vector3(op.x - pos.x, 0.0, op.z - pos.z)
		var along: float = rel.dot(dir)
		if along < 0.8 or along > best_along:
			continue
		var lat: float = (rel - dir * along).length()
		var radius: float = float(rec["radius"])
		# A wreck in the opposing lane is not a reason to leave our lane. Vehicle
		# widths are already represented by the recorded radius, so keep the
		# extra clearance tight enough to respect the lane separation.
		var extra := 0.25 if kind == "wreck" or kind == "car" else 1.5
		if lat > radius + extra:
			continue
		best_along = along
		best = op
	return best


func _skirt(path: PackedVector3Array, car: Node3D, travel: Vector3, nose: Vector3, block: Vector3) -> PackedVector3Array:
	var dir := travel.normalized()
	var right := _right(nose)
	var rel := Vector3(block.x - car.global_position.x, 0.0, block.z - car.global_position.z)
	var lat: float = rel.dot(right)
	var sign := 1.0
	if lat > 0.3:
		sign = -1.0
	var city := _city(car)
	if city != null and city.has_method("on_asphalt"):
		for raw_offset in [2.4, 2.8, 3.2]:
			var offset := float(raw_offset)
			var preferred := _skirt_path(path, car, dir, right, block, sign * offset)
			if _path_is_asphalt_and_clear(preferred, car, city, block):
				return preferred
			var other := _skirt_path(path, car, dir, right, block, -sign * offset)
			if _path_is_asphalt_and_clear(other, car, city, block):
				return other
	# Commit to the shoulder escape only after both asphalt sides failed.
	_escaping = true
	_block_at = block
	_escape_axis = dir
	_escape_side = right * sign
	_escape_off = false
	return _skirt_path(path, car, dir, right, block, sign * 3.2)


func _skirt_path(path: PackedVector3Array, car: Node3D, dir: Vector3, right: Vector3, block: Vector3, offset: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var approach := block - dir * 4.0
	approach.y = 0.65
	var to_approach := approach - car.global_position
	to_approach.y = 0.0
	if to_approach.dot(dir) > 1.0:
		out.append(approach)
	var side_point := block - dir * 3.0 + right * offset
	side_point.y = 0.65
	out.append(side_point)
	var pass_point := block + dir * 4.0 + right * offset
	pass_point.y = 0.65
	out.append(pass_point)
	var kept := false
	for point in path:
		var along: float = Vector3(point.x - block.x, 0.0, point.z - block.z).dot(dir)
		if along > 8.0:
			out.append(point)
			kept = true
	if not kept:
		var resume := block + dir * 12.0
		resume.y = 0.65
		out.append(resume)
	return out


func _path_is_asphalt_and_clear(path: PackedVector3Array, car: Node3D, city: Node, block: Vector3) -> bool:
	if path.is_empty():
		return false
	var previous := car.global_position
	for point in path:
		var segment := point - previous
		var steps := maxi(1, int(ceil(segment.length() / 0.75)))
		for step in range(steps + 1):
			var sample: Vector3 = previous.lerp(point, float(step) / float(steps))
			if not bool(city.call("on_asphalt", sample.x, sample.z)):
				return false
			for item in _seen:
				var rec: Dictionary = item
				var obstacle: Vector3 = rec["pos"]
				if Vector2(obstacle.x - block.x, obstacle.z - block.z).length() < 2.5:
					continue
				var clearance: float = float(rec["radius"]) + 0.9
				if Vector2(obstacle.x - sample.x, obstacle.z - sample.z).length() < clearance:
					return false
		previous = point
	return true


func _forward(car: Node3D) -> Vector3:
	var heading := car.get_node_or_null("Heading") as Node3D
	if heading != null:
		var facing: Vector3 = -heading.global_transform.basis.x
		facing.y = 0.0
		if facing.length_squared() > 0.01:
			return facing.normalized()
	var vel := _flat_vel(car)
	if vel.length_squared() > 0.05:
		return vel.normalized()
	return Vector3(-1.0, 0.0, 0.0)


func _right(fwd: Vector3) -> Vector3:
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	if side.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, 1.0)
	return side.normalized()


func _points(car: Node) -> PackedVector3Array:
	var raw: Variant = car.call("route_points")
	if raw is PackedVector3Array:
		return raw
	return PackedVector3Array()


func _traffic(car: Node) -> Node:
	return car.get_tree().get_first_node_in_group("traffic")


func _city(car: Node) -> Node:
	var traffic := car.get_parent()
	if traffic == null:
		return null
	var main := traffic.get_parent()
	if main == null:
		return null
	return main.get_node_or_null("City")


func _collect_seen(car: Node3D) -> void:
	_seen = _obstacles(car)
	for item in _seen:
		var rec: Dictionary = item
		rec["state"] = "seen"
	var soul := car.get_tree().get_first_node_in_group("soul") as Node3D
	if soul != null:
		_seen.append({"pos": soul.global_position, "radius": 0.4, "kind": "player", "state": "ignored"})


func _mark_guides(chain: Array[Node3D]) -> void:
	for body in chain:
		var at := body.global_position
		_guides.append(at)
		var marked := false
		for item in _seen:
			var rec: Dictionary = item
			if str(rec.get("kind", "")) != "cone":
				continue
			var op: Vector3 = rec["pos"]
			if Vector2(op.x - at.x, op.z - at.z).length() < 0.45:
				rec["kind"] = "guide"
				rec["state"] = "guide"
				marked = true
				break
		if not marked:
			_seen.append({"pos": at, "radius": 0.35, "kind": "guide", "state": "guide"})


func _explain(turning: bool) -> void:
	var why := "driving"
	if _on_cones:
		why = "following the cone line"
	elif _passing:
		why = "pulling out to pass"
	elif _have_leader:
		why = "following the car ahead"
	if turning and _halt == "":
		why = why + ", slowing for the turn"
	if _threat_act == "stop":
		why = "oncoming car, stopping to let it by"
	elif _threat_act == "back":
		why = "oncoming car, moving back to this lane"
	elif _threat_act == "cut":
		why = "oncoming car, speeding up to cut in"
	elif _threat_act == "dive":
		why = "oncoming car, diving back into this lane"
	elif _right_red:
		why = "taking the planned right turn off the asphalt"
	elif _path_kind == "turn" and _halt == "":
		why = "turning onto the open road beside the cone line"
	elif _escaping:
		why = "leaving the asphalt to get around the block"
	elif _halt == "red":
		why = "stopped for the red light" if _halt_along < 1.7 else "braking for the red light"
	elif _halt == "stop":
		why = "stopped at the sign" if _halt_along < 1.7 else "braking for the stop sign"
	elif _halt == "gap":
		why = "the gap looks too narrow"
	elif _halt == "yield":
		why = "yielding so the emergency vehicle can pass"
	elif _halt == "jam":
		why = "waiting behind a car that is not moving"
	_why = why
	if _path_alt > 0:
		_why = "proposal %d (%s). %s" % [_path_alt, _offer, _why]


func _finish(car: Node3D, aim: Vector3, speed: float, path: PackedVector3Array, fwd: Vector3) -> Dictionary:
	_mark_turns(path)
	var blockers: Array = []
	for item in _seen:
		var rec: Dictionary = item
		var pos: Vector3 = rec["pos"]
		var radius: float = float(rec["radius"])
		blockers.append({
			"pos": pos,
			"radius": radius,
			"kind": str(rec.get("kind", "cone")),
			"state": str(rec.get("state", "seen")),
			"on_path": _near_path(path, pos, radius + 0.85),
		})
	var cursor := -1
	if car.has_method("route_cursor"):
		cursor = int(car.call("route_cursor"))
	car.set("drive_sight", {
		"path": path,
		"aim": aim,
		"fwd": fwd,
		"note": str(car.get("drive_note")),
		"halt": _halt,
		"halt_along": _halt_along,
		"intel": float(car.get("drive_intel")),
		"agg": float(car.get("drive_agg")),
		"base": float(car.get("drive_base_agg")),
		"pace": speed,
		"target": _target,
		"limit": float(car.get("speed")),
		"turning": bool(car.get("drive_turning")),
		"on_cones": _on_cones,
		"passing": _passing,
		"pass_event": _pass_event.duplicate(true),
		"escaping": _escaping,
		"holding": _holding,
		"block_at": _block_at,
		"pull": _pull,
		"idle": _idle,
		"idle_counts": _idle_counts,
		"leave_after": lerpf(7.0, 4.0, float(car.get("drive_agg"))),
		"still": _still_t,
		"red_t": _red_t,
		"reversing": _reversing,
		"unstick": _unstick,
		"light": _light_state,
		"light_m": _light_m,
		"stop": _stop_state,
		"stop_m": _stop_m,
		"why": _why,
		"limit_note": _limit_note,
		"path_kind": _path_kind,
		"path_alt": _path_alt,
		"path_offer": _offer,
		"blockers": blockers,
		"turns": _turns.duplicate(),
		"leader": _leader_at,
		"have_leader": _have_leader,
		"threat": _threat_at,
		"have_threat": _have_threat,
		"follow_gap": _follow_gap,
		"follow_want": _follow_want,
		"cursor": cursor,
		"goal": int(car.get("route_goal")),
		"right_red": _right_red,
		"path_i": _path_i,
	})
	return {"aim": aim, "speed": speed}


func _mark_turns(path: PackedVector3Array) -> void:
	_turns = []
	if path.size() < 3:
		return
	var last := Vector3(-10000.0, 0.0, -10000.0)
	for i in range(1, path.size() - 1):
		var incoming := path[i] - path[i - 1]
		var outgoing := path[i + 1] - path[i]
		incoming.y = 0.0
		outgoing.y = 0.0
		if incoming.length() < 0.35 or outgoing.length() < 0.35:
			continue
		if incoming.normalized().angle_to(outgoing.normalized()) > 0.28 and path[i].distance_to(last) > 5.0:
			_turns.append(path[i])
			last = path[i]


func _near_path(path: PackedVector3Array, pos: Vector3, reach: float) -> bool:
	if path.is_empty():
		return false
	for i in range(path.size() - 1):
		if _seg_dist(path[i], path[i + 1], pos) <= reach:
			return true
	if path.size() == 1:
		return Vector2(path[0].x - pos.x, path[0].z - pos.z).length() <= reach
	return false


func _seg_dist(a: Vector3, b: Vector3, pos: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(pos.x - a.x, pos.z - a.z)
	var len2: float = ab.length_squared()
	if len2 < 0.0001:
		return ap.length()
	var t: float = clampf(ap.dot(ab) / len2, 0.0, 1.0)
	return ap.distance_to(ab * t)


func _seg_along(a: Vector3, b: Vector3, pos: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(pos.x - a.x, pos.z - a.z)
	var len2: float = ab.length_squared()
	if len2 < 0.0001:
		return 0.0
	return ap.dot(ab) / len2
