extends Node

# Writes one drive trace for the car nearest the player, plus every time a car body leaves the asphalt.
# phase is turn, nominal, leave, or park. off is how far the body sits past the asphalt, in meters.
# turn_s, nominal_s, leave_s, and park_s are time spent off the asphalt in that phase.

var _file: FileAccess
var _time: float = 0.0
var _frame := 0
var _flips := 0
var _prev_fwd := Vector3.ZERO
var _have_prev := false
var _focus_id := 0
var _path := ""
var _open: Dictionary = {}
var _turn_s: float = 0.0
var _nominal_s: float = 0.0
var _leave_s: float = 0.0
var _park_s: float = 0.0
var _noses: Dictionary = {}
var _off_events := 0
var _worst: float = 0.0
var _worst_phase := ""
var _worst_road := ""
var _worst_at := Vector2.ZERO


func _ready() -> void:
	_path = ProjectSettings.globalize_path("res://../logs/traffic_drive.log")
	DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		push_error("drive log failed: %s" % _path)
		return
	_file.store_line("t\tframe\tevent\tname\tx\tz\tfx\tfz\tax\taz\tmx\tmz\tspd\ttarget\tkind\tphase\tasphalt\tbody\toff\troad\twhy\thalt\tcones\tcur\tpi\tdot")
	_file.store_line("# While DriveDrill is running, tick rows are omitted. Read traffic_drill.log for tasks, path approvals, and grades.")


func _physics_process(delta: float) -> void:
	_time += delta
	_frame += 1
	if _file == null:
		return
	var city := _city()
	var soul := get_tree().get_first_node_in_group("soul") as Node3D
	var seen: Dictionary = {}
	for node in get_tree().get_nodes_in_group("hitter"):
		if not (node is Node3D):
			continue
		var car := node as Node3D
		if typeof(car.get("drive_sight")) != TYPE_DICTIONARY:
			continue
		var sight: Dictionary = car.get("drive_sight")
		if sight.is_empty():
			continue
		var id := car.get_instance_id()
		if soul != null and not _open.has(id):
			var dx: float = car.global_position.x - soul.global_position.x
			var dz: float = car.global_position.z - soul.global_position.z
			if dx * dx + dz * dz > 8100.0:
				seen[id] = true
				continue
		var surf := _body_surface(car, city)
		var phase := _phase(sight, car)
		sight["surface_phase"] = phase
		sight["surface_off"] = float(surf["off"])
		sight["surface_asphalt"] = bool(surf["center"])
		sight["surface_body"] = bool(surf["body"])
		sight["surface_road"] = str(surf["road"])
		seen[id] = true
		_track_off(car, sight, surf, phase, delta)
	var stale: Array[int] = []
	for key in _open.keys():
		var id := int(key)
		if not seen.has(id):
			stale.append(id)
	for id in stale:
		var rec: Dictionary = _open[id]
		_file.store_line("  surface gone phase=%s dur=%0.2f max_off=%0.2f road=%s" % [_mix(rec), _time - float(rec["t"]), float(rec["max"]), str(rec["road"])])
		_open.erase(id)
		_noses.erase(id)
	var car := _focus()
	if car == null:
		return
	if car.get_instance_id() != _focus_id:
		_focus_id = car.get_instance_id()
		_have_prev = false
		_prev_fwd = Vector3.ZERO
	var sight: Dictionary = car.get("drive_sight")
	var fwd := _nose(car)
	var aim := _vec(sight.get("aim", car.global_position))
	var aim_flat := Vector3(aim.x - car.global_position.x, 0.0, aim.z - car.global_position.z)
	var dot := 1.0
	if fwd.length_squared() > 0.01 and aim_flat.length_squared() > 0.01:
		dot = fwd.normalized().dot(aim_flat.normalized())
	var flip := false
	if _have_prev and fwd.length_squared() > 0.01 and _prev_fwd.length_squared() > 0.01:
		flip = fwd.normalized().dot(_prev_fwd.normalized()) < 0.0
	if flip:
		_flips += 1
	var sample := _frame % 6 == 0 and not _drilling()
	if sample or flip:
		var event := "flip" if flip else "tick"
		_write_row(event, car, sight, fwd, dot)
		if flip:
			_file.store_line("  path %s" % _slice(sight))
	_prev_fwd = fwd
	_have_prev = true
	if _frame % 120 == 0:
		_file.flush()


func _exit_tree() -> void:
	if _file == null:
		return
	_file.store_line("end\t%0.3f\tflips\t%d\toff_events\t%d\tturn_s\t%0.2f\tnominal_s\t%0.2f\tleave_s\t%0.2f\tpark_s\t%0.2f\tworst_m\t%0.2f\tworst_phase\t%s\tworst_road\t%s\tworst_at\t%0.1f,%0.1f" % [
		_time,
		_flips,
		_off_events,
		_turn_s,
		_nominal_s,
		_leave_s,
		_park_s,
		_worst,
		_worst_phase,
		_worst_road,
		_worst_at.x,
		_worst_at.y,
	])
	_file.flush()
	_file.close()
	_file = null


func _track_off(car: Node3D, sight: Dictionary, surf: Dictionary, phase: String, delta: float) -> void:
	var off: float = float(surf["off"])
	var id := car.get_instance_id()
	var outside := off >= 0.08
	if outside:
		if phase == "turn":
			_turn_s += delta
		elif phase == "leave":
			_leave_s += delta
		elif phase == "park":
			_park_s += delta
		else:
			_nominal_s += delta
		if off > _worst:
			_worst = off
			_worst_phase = phase
			_worst_road = str(surf["road"])
			_worst_at = Vector2(float(surf["x"]), float(surf["z"]))
		if not _open.has(id):
			_off_events += 1
			_open[id] = {
				"t": _time,
				"max": off,
				"road": str(surf["road"]),
				"x": float(surf["x"]),
				"z": float(surf["z"]),
				"turn": phase == "turn",
				"nominal": phase == "nominal",
				"leave": phase == "leave",
				"park": phase == "park",
			}
			var fwd := _nose(car)
			_write_row("off", car, sight, fwd, 1.0)
			_file.store_line("  surface phase=%s road=%s off=%0.2f center=%s at=(%0.1f,%0.1f)" % [
				phase,
				str(surf["road"]),
				off,
				"on" if bool(surf["center"]) else "off",
				float(surf["x"]),
				float(surf["z"]),
			])
			_file.store_line("  path %s" % _slice(sight))
			_file.flush()
			return
		var rec: Dictionary = _open[id]
		rec[phase] = true
		if off > float(rec["max"]):
			rec["max"] = off
			rec["road"] = str(surf["road"])
			rec["x"] = float(surf["x"])
			rec["z"] = float(surf["z"])
		return
	if not _open.has(id):
		return
	var done: Dictionary = _open[id]
	var fwd_back := _nose(car)
	_write_row("on", car, sight, fwd_back, 1.0)
	_file.store_line("  surface back phase=%s road=%s dur=%0.2f max_off=%0.2f at=(%0.1f,%0.1f)" % [
		_mix(done),
		str(done["road"]),
		_time - float(done["t"]),
		float(done["max"]),
		float(done["x"]),
		float(done["z"]),
	])
	_open.erase(id)
	_file.flush()


func _drilling() -> bool:
	return get_tree().get_first_node_in_group("drive_drill") != null


func _focus() -> Node3D:
	var cars: Array = get_tree().get_nodes_in_group("hitter")
	var soul := get_tree().get_first_node_in_group("soul") as Node3D
	var best: Node3D = null
	var best_d := 100000.0
	for node in cars:
		if not (node is Node3D):
			continue
		var car := node as Node3D
		if typeof(car.get("drive_sight")) != TYPE_DICTIONARY:
			continue
		var sight: Dictionary = car.get("drive_sight")
		if sight.is_empty():
			continue
		var dist := 0.0
		if soul != null:
			dist = Vector2(car.global_position.x - soul.global_position.x, car.global_position.z - soul.global_position.z).length()
		if best == null or dist < best_d:
			best = car
			best_d = dist
	return best


func _write_row(event: String, car: Node3D, sight: Dictionary, fwd: Vector3, dot: float) -> void:
	var aim := _vec(sight.get("aim", car.global_position))
	var travel := _vec(car.get("travel_velocity"))
	var asphalt := "1" if bool(sight.get("surface_asphalt", false)) else "0"
	var body := "1" if bool(sight.get("surface_body", false)) else "0"
	_file.store_line("%0.3f\t%d\t%s\t%s\t%0.2f\t%0.2f\t%0.2f\t%0.2f\t%0.2f\t%0.2f\t%0.2f\t%0.2f\t%0.2f\t%0.2f\t%s\t%s\t%s\t%s\t%0.2f\t%s\t%s\t%s\t%s\t%d\t%d\t%0.2f" % [
		_time,
		_frame,
		event,
		car.name,
		car.global_position.x,
		car.global_position.z,
		fwd.x,
		fwd.z,
		aim.x,
		aim.z,
		travel.x,
		travel.z,
		float(sight.get("pace", 0.0)),
		float(sight.get("target", 0.0)),
		str(sight.get("path_kind", "")),
		str(sight.get("surface_phase", "")),
		asphalt,
		body,
		float(sight.get("surface_off", 0.0)),
		str(sight.get("surface_road", "")),
		str(sight.get("why", "")),
		str(sight.get("halt", "")),
		"1" if bool(sight.get("on_cones", false)) else "0",
		int(sight.get("cursor", -1)),
		int(sight.get("path_i", -1)),
		dot,
	])


func _body_surface(car: Node3D, city: Node) -> Dictionary:
	var origin := car.global_position
	var empty := {"center": true, "body": true, "off": 0.0, "road": "", "x": origin.x, "z": origin.z}
	if city == null or not city.has_method("surface_at"):
		return empty
	var hx: float = 1.4
	var hz: float = 0.7
	var shape_node := car.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node != null and shape_node.shape is BoxShape3D:
		var box := shape_node.shape as BoxShape3D
		hx = box.size.x * 0.5
		hz = box.size.z * 0.5
	var fwd := _nose(car)
	var right := _right(car)
	var samples: Array[Vector3] = [Vector3.ZERO]
	if fwd != Vector3.ZERO and right != Vector3.ZERO:
		samples.append(fwd * hx + right * hz)
		samples.append(fwd * hx - right * hz)
		samples.append(-fwd * hx + right * hz)
		samples.append(-fwd * hx - right * hz)
		samples.append(right * hz)
		samples.append(-right * hz)
	var center: Dictionary = _probe(city, origin.x, origin.z)
	var worst := 0.0
	var worst_x := origin.x
	var worst_z := origin.z
	var road := str(center.get("road", ""))
	var body_on := true
	for offset in samples:
		var hit: Dictionary = _probe(city, origin.x + offset.x, origin.z + offset.z)
		var gap: float = float(hit.get("off", 0.0))
		if gap >= 0.05:
			body_on = false
		if gap > worst:
			worst = gap
			worst_x = origin.x + offset.x
			worst_z = origin.z + offset.z
			road = str(hit.get("road", road))
	if worst < 0.05:
		worst = 0.0
		body_on = true
	return {
		"center": bool(center.get("asphalt", false)),
		"body": body_on,
		"off": worst,
		"road": road,
		"x": worst_x,
		"z": worst_z,
	}


func _probe(city: Node, x: float, z: float) -> Dictionary:
	var raw: Variant = city.call("surface_at", x, z)
	if raw is Dictionary:
		return raw
	return {"asphalt": true, "off": 0.0, "road": ""}


func _phase(sight: Dictionary, car: Node3D) -> String:
	var kind := str(sight.get("path_kind", ""))
	if kind == "escape" or kind == "right" or kind == "yield" or bool(sight.get("escaping", false)) or bool(sight.get("right_red", false)):
		return "leave"
	var why := str(sight.get("why", ""))
	var note := str(sight.get("note", ""))
	if why.contains("stall") or why.contains("parked") or why.contains("doors") or note == "park" or note == "doors" or note == "parked":
		return "park"
	if bool(sight.get("turning", false)) or _nose_turning(car):
		return "turn"
	return "nominal"


func _nose_turning(car: Node3D) -> bool:
	# The planned path can already be the next straight while the nose is still sweeping the corner.
	var fwd := _nose(car)
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		return false
	fwd = fwd.normalized()
	var id := car.get_instance_id()
	var hist: Array = _noses.get(id, [])
	hist.append({"t": _time, "fwd": fwd})
	var kept: Array = []
	var older := fwd
	var have_older := false
	for item in hist:
		if not (item is Dictionary):
			continue
		var sample: Dictionary = item
		var age: float = _time - float(sample["t"])
		if age > 0.7:
			continue
		kept.append(sample)
		if not have_older and age >= 0.35:
			older = sample["fwd"]
			have_older = true
	if not have_older and kept.size() > 1:
		var first: Dictionary = kept[0]
		if _time - float(first["t"]) >= 0.25:
			older = first["fwd"]
			have_older = true
	_noses[id] = kept
	if not have_older:
		return false
	return older.angle_to(fwd) > 0.40


func _mix(rec: Dictionary) -> String:
	var text := ""
	if bool(rec.get("turn", false)):
		text = "turn"
	if bool(rec.get("nominal", false)):
		if text != "":
			text += "+"
		text += "nominal"
	if bool(rec.get("leave", false)):
		if text != "":
			text += "+"
		text += "leave"
	if bool(rec.get("park", false)):
		if text != "":
			text += "+"
		text += "park"
	if text == "":
		return "nominal"
	return text


func _city() -> Node:
	var traffic := get_parent()
	if traffic == null:
		return null
	var main := traffic.get_parent()
	if main == null:
		return null
	return main.get_node_or_null("City")


func _nose(car: Node3D) -> Vector3:
	var heading := car.get_node_or_null("Heading") as Node3D
	if heading == null:
		return Vector3.ZERO
	var facing := -heading.global_transform.basis.x
	facing.y = 0.0
	if facing.length_squared() < 0.01:
		return Vector3.ZERO
	return facing.normalized()


func _right(car: Node3D) -> Vector3:
	var heading := car.get_node_or_null("Heading") as Node3D
	if heading == null:
		return Vector3.ZERO
	# Nose is local -X. The driver's right is local -Z.
	var side := -heading.global_transform.basis.z
	side.y = 0.0
	if side.length_squared() < 0.01:
		return Vector3.ZERO
	return side.normalized()


func _slice(sight: Dictionary) -> String:
	var path := PackedVector3Array()
	var raw: Variant = sight.get("path", PackedVector3Array())
	if raw is PackedVector3Array:
		path = raw
	var index := int(sight.get("path_i", 0))
	var from := maxi(index - 2, 0)
	var to := mini(index + 3, path.size())
	var text := "i=%d n=%d" % [index, path.size()]
	for i in range(from, to):
		var mark := ""
		if i == index:
			mark = "*"
		text += " %s%d:(%0.1f,%0.1f)" % [mark, i, path[i].x, path[i].z]
	return text


func _vec(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw
	return Vector3.ZERO
