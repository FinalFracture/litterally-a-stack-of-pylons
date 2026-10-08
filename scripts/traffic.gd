extends Node3D

const _CAR := preload("res://scenes/lane_car.tscn")
const _AUDIO := preload("res://scripts/ambience.gd")
const _LOG := preload("res://scripts/drive_log.gd")
const _PATH_LOG := preload("res://scripts/path_change_log.gd")
const _PASS_LOG := preload("res://scripts/pass_attempt_log.gd")
const _FLEET_LOG := preload("res://scripts/fleet_log.gd")
const _DRILL := preload("res://scripts/drive_drill.gd")

const GREEN_TIME := 6.0
const YELLOW_TIME := 1.6
const HOLD_AT := 1.45
const SLOW_FROM := 8.0
const YELLOW_PASS := 3.2
const RELEASE_AT := -12.0
const REACH := 8.0
const CAR_Y := 0.65
const FLEET := 36
const RED := Color(0.78, 0.08, 0.07)
const GREEN := Color(0.12, 0.62, 0.24)

var _lights: Array[Dictionary]
var _stops: Array[Dictionary]
# One queue per crossing. Two four-ways must not share a holder.
var _boxes: Dictionary = {}
var _phase := 0
var _phase_left := GREEN_TIME
var _ew_mat: StandardMaterial3D
var _ns_mat: StandardMaterial3D
var _trip_wait := 0.0
var _seq := 0
var _pin_phase := -1
var _practice_scene := false
var _drive_ready := false
var _node_at: Array[Vector2] = []
var _leave: Array = []
var _in_main: PackedByteArray = PackedByteArray()
var _spots: Array[Dictionary] = []
var _spot_i := 0
var _fleet_target := FLEET
@export var vehicle_traffic_enabled := true


func _ready() -> void:
	if not vehicle_traffic_enabled:
		return
	var raw_fleet := OS.get_environment("PYLONS_FLEET")
	if raw_fleet != "":
		_fleet_target = maxi(int(raw_fleet), 1)
	add_to_group("traffic")
	if _practice_scene:
		_build_lines()
		_build_lamps()
		_practice_road_cars()
	else:
		_bind_generated()
		_city_cars()
	_paint_lamps()
	_music()
	var log := Node.new()
	log.name = "DriveLog"
	log.set_script(_LOG)
	add_child(log)
	var path_log := Node.new()
	path_log.name = "PathChangeLog"
	path_log.set_script(_PATH_LOG)
	add_child(path_log)
	var pass_log := Node.new()
	pass_log.name = "PassAttemptLog"
	pass_log.set_script(_PASS_LOG)
	add_child(pass_log)
	var fleet_log := Node.new()
	fleet_log.name = "FleetLog"
	fleet_log.set_script(_FLEET_LOG)
	add_child(fleet_log)
	var drill := Node.new()
	drill.name = "DriveDrill"
	drill.set_script(_DRILL)
	add_child(drill)


func pin_phase(phase: int) -> void:
	_pin_phase = phase
	if phase >= 0:
		_phase = phase
		_phase_left = 30.0
	else:
		_phase_left = 0.35


func _physics_process(delta: float) -> void:
	if _pin_phase >= 0:
		_phase = _pin_phase
		_phase_left = 30.0
	else:
		_phase_left -= delta
		if _phase_left <= 0.0:
			_phase = (_phase + 1) % 4
			if _phase == 0 or _phase == 2:
				_phase_left = GREEN_TIME
			else:
				_phase_left = YELLOW_TIME
	_paint_lamps()
	_trip_wait += delta
	if _trip_wait >= 0.45:
		_trip_wait = 0.0
		_refresh_trips()


func scale_for(car: Node, pos: Vector3, dir: Vector3) -> float:
	var light := _pick(pos, dir, _lights, 2.2)
	var stop := _pick(pos, dir, _stops, 2.2)
	var scale: float = 1.0
	if not light.is_empty():
		scale = minf(scale, _light_scale(Vector2(float(light["along"]), float(light["kind"]))))
	if not stop.is_empty():
		var line: Dictionary = stop["line"] as Dictionary
		scale = minf(scale, _stop_scale(car, float(stop["along"]), dir, _cross_of(line)))
	return scale


func approach(car: Node, pos: Vector3, dir: Vector3) -> Dictionary:
	# Lights and stop signs are visible from 18 m so a car at the speed limit can finish braking before the line.
	var light := _pick(pos, dir, _lights, 7.0, 18.0)
	var stop := _pick(pos, dir, _stops, 7.0, 18.0)
	var light_state := "none"
	var light_along := 999.0
	var stop_word := "none"
	var stop_along := 999.0
	if not light.is_empty():
		light_state = _axis_state(int(light["kind"]))
		light_along = float(light["along"])
	if not stop.is_empty():
		var line: Dictionary = stop["line"] as Dictionary
		stop_along = float(stop["along"])
		stop_word = _stop_word(car, stop_along, dir, _cross_of(line))
	return {
		"light": light_state,
		"light_along": light_along,
		"stop": stop_word,
		"stop_along": stop_along,
	}


func _light_scale(hit: Vector2) -> float:
	var state := _axis_state(int(hit.y))
	if state == "green":
		return 1.0
	if state == "yellow" and hit.x < YELLOW_PASS:
		return 1.0
	return _slow(hit.x)


func _axis_state(kind: int) -> String:
	var ew := kind == 1
	if ew:
		if _phase == 0:
			return "green"
		if _phase == 1:
			return "yellow"
		return "red"
	if _phase == 2:
		return "green"
	if _phase == 3:
		return "yellow"
	return "red"


func _stop_scale(car: Node, along: float, dir: Vector3, cross: Vector2) -> float:
	var word := _stop_word(car, along, dir, cross)
	if word == "go" or word == "force" or word == "none":
		return 1.0
	return _slow(along)


func _cross_of(line: Dictionary) -> Vector2:
	var raw: Variant = line.get("cross", Vector2.ZERO)
	if raw is Vector2:
		return raw
	var spot: Vector3 = line["pos"]
	return Vector2(spot.x, spot.z)


func _box(cross: Vector2) -> Dictionary:
	var key := "%d_%d" % [int(roundf(cross.x)), int(roundf(cross.y))]
	if not _boxes.has(key):
		var fresh: Dictionary = {
			"arrived": {},
			"arrive_dir": {},
			"arrive_turn": {},
			"holder_id": 0,
			"holder_dir": Vector3.ZERO,
			"hold_since": 0,
		}
		_boxes[key] = fresh
	var stored: Variant = _boxes[key]
	if stored is Dictionary:
		return stored
	return {}


func _stop_word(car: Node, along: float, dir: Vector3, cross: Vector2) -> String:
	var box := _box(cross)
	var arrived: Dictionary = box["arrived"] as Dictionary
	var arrive_dir: Dictionary = box["arrive_dir"] as Dictionary
	var arrive_turn: Dictionary = box["arrive_turn"] as Dictionary
	var holder_id: int = int(box["holder_id"])
	var id := car.get_instance_id()
	if along < -0.6:
		if holder_id == id:
			box["holder_id"] = 0
			box["hold_since"] = 0
		arrived.erase(id)
		arrive_dir.erase(id)
		arrive_turn.erase(id)
		return "go"
	# Visible from 18 m. REACH is only 8 m, which is inside the braking distance of a car at the limit.
	if along > 18.0:
		return "none"
	if holder_id != 0 and not _holder_alive(holder_id):
		box["holder_id"] = 0
		box["hold_since"] = 0
		holder_id = 0
	if along < 6.0 and not arrived.has(id) and holder_id != id:
		arrived[id] = Time.get_ticks_msec()
		arrive_dir[id] = dir
		arrive_turn[id] = bool(car.get("drive_turning"))
	holder_id = int(box["holder_id"])
	if holder_id == id:
		return "go"
	if holder_id != 0 and _opposite_clear(car, dir, box):
		return "go"
	if _stalemate(car, along, box):
		return "force"
	var next_id := _earliest(arrived)
	# The brake finishes short of 1.8 m, so a car already waiting in that gap is at the sign.
	if int(box["holder_id"]) == 0 and next_id == id and along < 3.2:
		var shown: Variant = arrived.get(id, Time.get_ticks_msec())
		var waited: int = Time.get_ticks_msec() - int(shown)
		if waited < 450:
			return "wait"
		box["holder_id"] = id
		box["holder_dir"] = dir
		box["hold_since"] = Time.get_ticks_msec()
		arrived.erase(id)
		return "go"
	# Still on the approach. Wait, and brake, until the queue at the line says go.
	return "wait"


func _opposite_clear(car: Node, dir: Vector3, box: Dictionary) -> bool:
	var holder_dir: Vector3 = box["holder_dir"] as Vector3
	if holder_dir.length_squared() < 0.01 or dir.length_squared() < 0.01:
		return false
	if holder_dir.normalized().dot(dir.normalized()) > -0.55:
		return false
	var turning := bool(car.get("drive_turning"))
	if not turning:
		return true
	var holder_id: int = int(box["holder_id"])
	var holder: Object = instance_from_id(holder_id)
	if not (holder is Node):
		return false
	return float((holder as Node).get("drive_intel")) >= 0.55


func _stalemate(car: Node, along: float, box: Dictionary) -> bool:
	var holder_id: int = int(box["holder_id"])
	var hold_since: int = int(box["hold_since"])
	if along > 3.0 or holder_id == 0 or hold_since == 0:
		return false
	if Time.get_ticks_msec() - hold_since < 2500:
		return false
	var holder: Object = instance_from_id(holder_id)
	if not (holder is Node) or holder == car:
		return false
	var mine: float = float(car.get("drive_intel"))
	var theirs: float = float((holder as Node).get("drive_intel"))
	return mine < theirs


func _slow(along: float) -> float:
	if along <= HOLD_AT:
		return 0.0
	if along >= SLOW_FROM:
		return 1.0
	var t := (along - HOLD_AT) / (SLOW_FROM - HOLD_AT)
	return t * t


func _earliest(arrived: Dictionary) -> int:
	var best_id := 0
	var best_t := 2000000000000
	var dead: Array[int]
	for key in arrived.keys():
		var id := int(key)
		var obj: Object = instance_from_id(id)
		if not (obj is Node) or not is_instance_valid(obj):
			dead.append(id)
			continue
		var when := int(arrived[key])
		if when < best_t:
			best_t = when
			best_id = id
	for id in dead:
		arrived.erase(id)
	return best_id


func _holder_alive(holder_id: int) -> bool:
	if holder_id == 0:
		return false
	var obj: Object = instance_from_id(holder_id)
	return obj is Node and is_instance_valid(obj)


func _pick(pos: Vector3, dir: Vector3, lines: Array[Dictionary], lateral_max: float, along_max: float = REACH) -> Dictionary:
	var best_along := 999.0
	var best_kind := 0.0
	var best_line: Dictionary = {}
	var found := false
	for i in lines.size():
		var line: Dictionary = lines[i]
		var axis: Vector3 = line["dir"] as Vector3
		if axis.dot(dir) < 0.75:
			continue
		var spot: Vector3 = line["pos"] as Vector3
		var delta: Vector3 = spot - pos
		delta.y = 0.0
		var along: float = delta.dot(dir)
		if along < RELEASE_AT or along > along_max:
			continue
		var lateral: Vector3 = delta - dir * along
		if lateral.length() > lateral_max:
			continue
		if along < best_along:
			best_along = along
			best_kind = float(line["kind"])
			best_line = line
			found = true
	if not found:
		return {}
	return {"along": best_along, "kind": best_kind, "line": best_line}


func _nearest(pos: Vector3, dir: Vector3, lines: Array[Dictionary], lateral_max: float) -> Vector2:
	var hit := _pick(pos, dir, lines, lateral_max)
	if hit.is_empty():
		return Vector2(-999.0, 0.0)
	return Vector2(float(hit["along"]), float(hit["kind"]))


func _build_lines() -> void:
	# Two interior four-way stops. Corners and the edge junctions have no sign.
	_four_way(150.0, 150.0)
	_four_way(260.0, 150.0)


func _four_way(cx: float, cz: float) -> void:
	# Lane signs match _segment. Eastbound right is +Z. Travel +Z keeps its right at -X.
	var lane: float = GameConstants.LANE_OFF
	var shoulder: float = GameConstants.ROAD_HALF + 1.4
	var back: float = 12.0
	var cross := Vector2(cx, cz)
	var east := Vector3(1.0, 0.0, 0.0)
	var west := Vector3(-1.0, 0.0, 0.0)
	var north := Vector3(0.0, 0.0, 1.0)
	var south := Vector3(0.0, 0.0, -1.0)
	_stop(Vector3(cx - back, CAR_Y, cz + lane), east, cross)
	_sign(Vector3(cx - back, 0.0, cz + shoulder))
	_stop_bar(Vector3(cx - back, 0.05, cz + lane), east)
	_stop(Vector3(cx + back, CAR_Y, cz - lane), west, cross)
	_sign(Vector3(cx + back, 0.0, cz - shoulder))
	_stop_bar(Vector3(cx + back, 0.05, cz - lane), west)
	_stop(Vector3(cx - lane, CAR_Y, cz - back), north, cross)
	_sign(Vector3(cx - shoulder, 0.0, cz - back))
	_stop_bar(Vector3(cx - lane, 0.05, cz - back), north)
	_stop(Vector3(cx + lane, CAR_Y, cz + back), south, cross)
	_sign(Vector3(cx + shoulder, 0.0, cz + back))
	_stop_bar(Vector3(cx + lane, 0.05, cz + back), south)


func _stop_bar(at: Vector3, dir: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	if absf(dir.z) > 0.5:
		box.size = Vector3(2.4, 0.02, 0.18)
	else:
		box.size = Vector3(0.18, 0.02, 2.4)
	mesh.mesh = box
	mesh.position = at
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.95, 0.95, 0.93)
	paint.roughness = 0.8
	mesh.material_override = paint
	add_child(mesh)


func _light(pos: Vector3, dir: Vector3, kind: int) -> void:
	_lights.append({"pos": pos, "dir": dir, "kind": kind})


func _stop(pos: Vector3, dir: Vector3, cross: Vector2 = Vector2.ZERO) -> void:
	_stops.append({"pos": pos, "dir": dir, "kind": 0, "cross": cross})


func _city_kinds() -> PackedStringArray:
	return PackedStringArray([
		"car", "compact", "coupe", "wagon", "minivan", "suv",
		"pickup", "motorcycle", "scooter", "taxi", "limousine", "rv",
		"van", "truck", "flatbed", "dump", "mixer", "utility",
		"sweeper", "garbage", "mail", "delivery", "foodtruck", "tow",
		"bus", "schoolbus", "coach", "ambulance", "fire", "police",
	])


func _is_wide(kind: String) -> bool:
	return kind == "limousine" or kind == "rv" or kind == "truck" or kind == "flatbed" or kind == "dump" or kind == "mixer" or kind == "utility" or kind == "garbage" or kind == "delivery" or kind == "foodtruck" or kind == "tow" or kind == "bus" or kind == "schoolbus" or kind == "coach" or kind == "fire"


func _city_node() -> Node:
	var parent := get_parent()
	if parent != null:
		var direct := parent.get_node_or_null("City")
		if direct != null:
			return direct
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.find_child("City", true, false)


func _bind_generated() -> void:
	var city := _city_node()
	if city == null:
		push_warning("City is missing. Traffic was not placed.")
		return
	_load_controls(city)
	var raw: Variant = city.get_meta("road_drive_edges", [])
	if not (raw is Array):
		push_warning("Generated roads have no drive graph.")
		return
	_build_graph(raw)
	_mark_main()
	_drive_ready = _node_at.size() >= 2
	if not _drive_ready:
		push_warning("Generated roads have no connected lanes.")


func _load_controls(city: Node) -> void:
	_lights.clear()
	_stops.clear()
	var raw: Variant = city.get_meta("road_controls", [])
	if not (raw is Array):
		return
	var rows: Array = raw
	for item in rows:
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		var pos_v: Variant = row["pos"]
		var dir_v: Variant = row["dir"]
		var pos: Vector3 = pos_v
		var dir: Vector3 = dir_v
		var cross := Vector2(float(row["cx"]), float(row["cz"]))
		if str(row["mode"]) == "light":
			_light(pos, dir, int(row["kind"]))
		else:
			_stop(pos, dir, cross)


func _build_graph(edges: Array) -> void:
	_node_at.clear()
	_leave.clear()
	var index: Dictionary = {}
	var seen: Dictionary = {}
	for raw in edges:
		if not (raw is Dictionary):
			continue
		var edge: Dictionary = raw
		var a := Vector2(float(edge["ax"]), float(edge["az"]))
		var b := Vector2(float(edge["bx"]), float(edge["bz"]))
		var ia: int = _node_id(index, a)
		var ib: int = _node_id(index, b)
		if ia == ib:
			continue
		var forward: PackedVector3Array = edge["forward"]
		var back: PackedVector3Array = edge["back"]
		var length: float = float(edge["length"])
		_add_hop(seen, ia, ib, forward, length)
		_add_hop(seen, ib, ia, back, length)


func _node_id(index: Dictionary, at: Vector2) -> int:
	var key := "%d|%d" % [int(round(at.x * 4.0)), int(round(at.y * 4.0))]
	if index.has(key):
		return int(index[key])
	var id: int = _node_at.size()
	index[key] = id
	_node_at.append(at)
	_leave.append([])
	return id


func _add_hop(seen: Dictionary, frm: int, to: int, poly: PackedVector3Array, length: float) -> void:
	if poly.size() < 2:
		return
	var key := "%d|%d" % [frm, to]
	if seen.has(key):
		return
	seen[key] = true
	var outs: Array = _leave[frm]
	outs.append({"to": to, "poly": poly, "length": maxf(length, 0.5)})


func _city_cars() -> void:
	if not _drive_ready:
		push_warning("Generated roads are not ready. No cars were placed.")
		return
	var placed := 0
	while placed < _fleet_target:
		if not _add_city_car():
			break
		placed += 1
	if placed < _fleet_target:
		push_warning("Placed %d of %d cars. The loaded roads ran out of open lane." % [placed, _fleet_target])


func _component_sizes() -> PackedInt32Array:
	var sizes := PackedInt32Array()
	var seen := PackedByteArray()
	seen.resize(_node_at.size())
	seen.fill(0)
	for start in _node_at.size():
		if seen[start] != 0:
			continue
		var count := 0
		var stack: Array[int] = [start]
		seen[start] = 1
		while stack.size() > 0:
			var at: int = stack.pop_back()
			count += 1
			var outs: Array = _leave[at]
			for raw in outs:
				if not (raw is Dictionary):
					continue
				var nxt: int = int((raw as Dictionary)["to"])
				if seen[nxt] != 0:
					continue
				seen[nxt] = 1
				stack.append(nxt)
		sizes.append(count)
	return sizes


func _add_city_car() -> bool:
	var spot: Dictionary = _take_spot()
	if spot.is_empty():
		return false
	var kinds: PackedStringArray = _civilian_kinds()
	if kinds.is_empty():
		return false
	_seq += 1
	var kind: String = kinds[_seq % kinds.size()]
	var at: Vector3 = spot["at"]
	var face: Vector3 = spot["face"]
	var car_name := "City%02d" % _seq
	_car(car_name, _fleet_color(_seq), _kind_speed(kind), PackedVector3Array([at, at + face]), PackedByteArray(), 1, kind, true)
	var car := get_node_or_null(car_name) as AnimatableBody3D
	if car == null:
		return false
	car.park_at(at, face)
	assign_long_trip(car)
	return true


func _civilian_kinds() -> PackedStringArray:
	var out := PackedStringArray()
	for kind in _city_kinds():
		if _emergency_kind(kind):
			continue
		out.append(kind)
	return out


func _emergency_kind(kind: String) -> bool:
	return kind == "police" or kind == "fire" or kind == "ambulance"


func _kind_speed(kind: String) -> float:
	if kind == "motorcycle" or kind == "scooter":
		return 11.0
	if _is_wide(kind):
		return 7.2
	return 9.0


func _fleet_color(n: int) -> Color:
	var hue: float = fmod(float(n) * 0.17 + 0.02, 1.0)
	return Color.from_hsv(hue, 0.62, 0.78)


func _fill_spots() -> void:
	_spots.clear()
	_spot_i = 0
	var avoid := Vector2(22.0, 22.0)
	var soul := get_tree().get_first_node_in_group("soul") as Node3D
	if soul != null:
		avoid = Vector2(soul.global_position.x, soul.global_position.z)
	for node_i in _leave.size():
		if node_i < _in_main.size() and _in_main[node_i] == 0:
			continue
		var outs: Array = _leave[node_i]
		for raw in outs:
			if not (raw is Dictionary):
				continue
			var hop: Dictionary = raw
			var poly: PackedVector3Array = hop["poly"]
			for i in range(1, poly.size()):
				var a: Vector3 = poly[i - 1]
				var b: Vector3 = poly[i]
				var delta := Vector2(b.x - a.x, b.z - a.z)
				var span: float = delta.length()
				if span < 6.0:
					continue
				var face := Vector3(delta.x / span, 0.0, delta.y / span)
				var t: float = 6.0
				while t < span - 2.0:
					var at := Vector3(a.x, CAR_Y, a.z) + face * t
					t += 18.0
					if Vector2(at.x, at.z).distance_to(avoid) <= 16.0:
						continue
					if not _point_on_road(at):
						continue
					_spots.append({"at": at, "face": face})
	var i2 := 0
	while i2 < _spots.size():
		var j: int = randi() % _spots.size()
		var swap: Dictionary = _spots[i2]
		_spots[i2] = _spots[j]
		_spots[j] = swap
		i2 += 1


func _take_spot() -> Dictionary:
	if _spots.is_empty():
		_fill_spots()
	if _spots.is_empty():
		return {}
	var guard := 0
	while guard < _spots.size():
		if _spot_i >= _spots.size():
			_spot_i = 0
		var spot: Dictionary = _spots[_spot_i]
		_spot_i += 1
		guard += 1
		var at: Vector3 = spot["at"]
		var face: Vector3 = spot["face"]
		if _clear_of_cars(at) and _body_fits(at, face):
			return spot
	return {}


func _clear_of_cars(at: Vector3) -> bool:
	for child in get_children():
		if child.get("trip") != true or not (child is Node3D):
			continue
		var body := child as Node3D
		if Vector2(body.global_position.x - at.x, body.global_position.z - at.z).length() < 12.0:
			return false
	return true


func _practice_road_cars() -> void:
	var city := get_tree().current_scene.find_child("City", true, false)
	if city == null or not city.has_meta("road_lane_routes"):
		push_warning("Modular road route is not ready; practice traffic was not placed.")
		return
	var routes: Array = city.get_meta("road_lane_routes")
	if routes.size() < 2:
		return
	var route: PackedVector3Array = routes[0]
	if route.size() < 8:
		return
	var soul := get_tree().get_first_node_in_group("soul") as Node3D
	var center := Vector3.ZERO if soul == null else soul.global_position
	var radius := route[0].distance_to(center)
	var view_target := Vector3(center.x, 0.0, center.z - radius)
	var route_index := 0
	var closest := INF
	for i in route.size():
		var distance := Vector2(route[i].x - view_target.x, route[i].z - view_target.z).length_squared()
		if distance < closest:
			closest = distance
			route_index = i
	var next_index := (route_index + 1) % route.size()
	var face := (route[next_index] - route[route_index]).normalized()
	var at := route[route_index] + Vector3.UP * CAR_Y
	_practice_car("RoadLoopTestCar", Color(1.0, 0.62, 0.06), at, face, 4.5, 0)


func _practice_car(car_name: String, color: Color, at: Vector3, face: Vector3, car_speed: float, lane_index: int) -> void:
	_car(car_name, color, car_speed, PackedVector3Array([at, at + face]), PackedByteArray(), 1, "car", true)
	var car := get_node_or_null(car_name) as AnimatableBody3D
	if car == null:
		return
	car.set("practice_despawn", true)
	car.set("practice_direction", 1.0)
	car.set_meta("road_lane_index", lane_index)
	car.park_at(at, face)
	assign_long_trip(car)


func _practice_trip(car: Node) -> void:
	if not (car is Node3D) or not car.has_method("set_route"):
		return
	var body := car as Node3D
	var city := get_tree().current_scene.find_child("City", true, false)
	if city == null or not city.has_meta("road_lane_routes"):
		return
	var routes: Array = city.get_meta("road_lane_routes")
	var lane_index := int(car.get_meta("road_lane_index", 0))
	if lane_index < 0 or lane_index >= routes.size():
		lane_index = 0
	var loop: PackedVector3Array = routes[lane_index]
	var options: Array = city.get_meta("road_lane_route_options", [])
	if lane_index < options.size() and options[lane_index] is Array and not options[lane_index].is_empty():
		var choices: Array = options[lane_index]
		loop = choices[randi_range(0, choices.size() - 1)]
	if loop.size() < 8:
		return
	var nearest := 0
	var best_distance := INF
	for i in loop.size():
		var distance := body.global_position.distance_squared_to(loop[i] + Vector3.UP * CAR_Y)
		if distance < best_distance:
			best_distance = distance
			nearest = i
	var points := PackedVector3Array([body.global_position])
	for offset in loop.size():
		points.append(loop[(nearest + offset) % loop.size()] + Vector3.UP * CAR_Y)
	points.append(loop[nearest] + Vector3.UP * CAR_Y)
	car.call("set_route", points, PackedByteArray(), 1)
	car.set("route_goal", points.size() - 1)
	car.set("trip", true)
	car.set("drill_lock", false)
	var driver := car.get_node_or_null("Driver") as Node
	if driver != null:
		driver.set("_span_set", false)
		driver.set("_arrival", "")
		driver.set("_done_ids", [])


func _nose_x(car: Node3D) -> float:
	var heading := car.get_node_or_null("Heading") as Node3D
	if heading == null:
		return 1.0
	return -heading.global_transform.basis.x.x


func _loop_car(car_name: String, color: Color, at: Vector3, face: Vector3) -> void:
	var pts := PackedVector3Array()
	pts.append(at)
	pts.append(at + face)
	_car(car_name, color, 7.0, pts, PackedByteArray(), 1, "car", true)
	var car := get_node_or_null(car_name) as AnimatableBody3D
	if car == null:
		return
	car.park_at(at, face)
	assign_long_trip(car)


func _right_loop(y: float) -> PackedVector3Array:
	# Eastbound right lane of Practice Road. A corner arc belongs on the curb side of both centerlines.
	var lane: float = GameConstants.LANE_OFF
	var pts := PackedVector3Array()
	_line(pts, y, Vector3(8.0, y, lane), Vector3(260.0, y, lane), 12.0)
	return pts


func _line(pts: PackedVector3Array, y: float, a: Vector3, b: Vector3, step: float) -> void:
	var span := Vector2(b.x - a.x, b.z - a.z)
	var length: float = span.length()
	var count: int = maxi(1, int(ceil(length / step)))
	for i in count + 1:
		var t: float = float(i) / float(count)
		_add_pt(pts, Vector3(lerpf(a.x, b.x, t), y, lerpf(a.z, b.z, t)))


func _arc(pts: PackedVector3Array, y: float, center: Vector2, leave: Vector2, join: Vector2) -> void:
	var arm := leave - center
	var dest := join - center
	var sweep: float = _clockwise(arm, dest)
	var steps := 6
	for i in steps + 1:
		var turned := _rot_cw(arm, sweep * float(i) / float(steps))
		_add_pt(pts, Vector3(center.x + turned.x, y, center.y + turned.y))


func _clockwise(a: Vector2, b: Vector2) -> float:
	var ccw: float = atan2(a.x * b.y - a.y * b.x, a.dot(b))
	var cw: float = -ccw
	if cw < 0.0:
		cw += TAU
	return cw


func _rot_cw(v: Vector2, ang: float) -> Vector2:
	var c := cos(ang)
	var s := sin(ang)
	return Vector2(v.x * c + v.y * s, -v.x * s + v.y * c)


func _add_pt(pts: PackedVector3Array, at: Vector3) -> void:
	if pts.is_empty() or pts[pts.size() - 1].distance_to(at) > 0.35:
		pts.append(at)


func _bind_routes() -> void:
	var y := CAR_Y
	var none := PackedByteArray()
	_tag("LIGHT", Vector3(0, 4.5, 9))
	_car("LightRed", RED, 6.0, PackedVector3Array([
		Vector3(-16, y, 1.6), Vector3(5, y, 1.6), Vector3(7, y, 0),
		Vector3(5, y, -1.6), Vector3(-16, y, -1.6), Vector3(-18, y, 0),
	]), none, 1)
	_car("LightGreen", GREEN, 6.0, PackedVector3Array([
		Vector3(1.6, y, -16), Vector3(1.6, y, 5), Vector3(0, y, 7),
		Vector3(-1.6, y, 5), Vector3(-1.6, y, -16), Vector3(0, y, -18),
	]), none, 1)
	_tag("STOP", Vector3(24, 4.5, 12))
	_car("StopRed", RED, 5.0, PackedVector3Array([
		Vector3(26.2, y, -8.2), Vector3(26.2, y, 18), Vector3(26.2, y, -8.2),
	]), none, 1)
	_car("StopGreen", GREEN, 5.0, PackedVector3Array([
		Vector3(21.8, y, 16), Vector3(21.8, y, -8.2), Vector3(21.8, y, 16),
	]), none, 1)
	_tag("FOLLOW", Vector3(-32, 3.6, -37))
	_car("FollowRed", RED, 4.4, PackedVector3Array([
		Vector3(-44, y, -37.4), Vector3(-22, y, -37.4), Vector3(-20, y, -40),
		Vector3(-22, y, -42.6), Vector3(-44, y, -42.6), Vector3(-46, y, -40),
	]), none, 1)
	_car("FollowGreen", GREEN, 3.0, PackedVector3Array([
		Vector3(-34, y, -37.4), Vector3(-22, y, -37.4), Vector3(-20, y, -40),
		Vector3(-22, y, -42.6), Vector3(-44, y, -42.6), Vector3(-46, y, -40), Vector3(-44, y, -37.4),
	]), none, 1)
	_tag("LEFT", Vector3(-30, 3.6, -48))
	_car("LeftRed", RED, 5.0, PackedVector3Array([
		Vector3(-38, y, -62), Vector3(-22, y, -62), Vector3(-22, y, -50), Vector3(-38, y, -50),
	]), none, 1)
	_car("LeftGreen", GREEN, 5.0, PackedVector3Array([
		Vector3(-22, y, -50), Vector3(-38, y, -50), Vector3(-38, y, -62), Vector3(-22, y, -62),
	]), none, 1)
	_tag("RIGHT", Vector3(10, 3.6, -48))
	_car("RightRed", RED, 5.0, PackedVector3Array([
		Vector3(4, y, -50), Vector3(16, y, -50), Vector3(16, y, -62), Vector3(4, y, -62),
	]), none, 1)
	_car("RightGreen", GREEN, 5.0, PackedVector3Array([
		Vector3(16, y, -62), Vector3(4, y, -62), Vector3(4, y, -50), Vector3(16, y, -50),
	]), none, 1)
	_tag("U-TURN", Vector3(32, 3.6, -37))
	_car("UTurnRed", RED, 4.6, PackedVector3Array([
		Vector3(26, y, -37.2), Vector3(42, y, -37.2), Vector3(44, y, -40),
		Vector3(42, y, -42.8), Vector3(26, y, -42.8), Vector3(24, y, -40),
	]), none, 1)
	_car("UTurnGreen", GREEN, 4.6, PackedVector3Array([
		Vector3(42, y, -42.8), Vector3(26, y, -42.8), Vector3(24, y, -40),
		Vector3(26, y, -37.2), Vector3(42, y, -37.2), Vector3(44, y, -40),
	]), none, 1)
	_tag("REVERSE", Vector3(32, 3.6, -53))
	_car("ReverseRed", RED, 4.0, PackedVector3Array([
		Vector3(26, y, -55.1), Vector3(38, y, -55.1), Vector3(26, y, -55.1),
	]), PackedByteArray([0, 0, 1]), 1)
	_car("ReverseGreen", GREEN, 4.0, PackedVector3Array([
		Vector3(38, y, -56.9), Vector3(26, y, -56.9), Vector3(38, y, -56.9),
	]), PackedByteArray([0, 1, 0]), 1)


func spawn_unit(unit_name: String, kind: String, color: Color, at: Vector3, unit_speed: float) -> AnimatableBody3D:
	var car := _CAR.instantiate() as AnimatableBody3D
	car.name = unit_name
	car.body_color = color
	car.vehicle_kind = kind
	car.code_three = true
	car.carries_rider = false
	car.brake_miss = 0.0
	car.look_ahead = 8.0
	car.speed = unit_speed
	car.position = at
	car.from_point = at
	car.to_point = at
	add_child(car)
	return car


func _shuttle(car_name: String, kind: String, color: Color, car_speed: float, a: Vector3, b: Vector3) -> void:
	var rev := PackedByteArray([0, 1, 0])
	_car(car_name, color, car_speed, PackedVector3Array([a, b, a]), rev, 1, kind)


func _refresh_trips() -> void:
	for child in get_children():
		if child.get("trip") != true or bool(child.get("drill_lock")):
			continue
		if not child.has_method("route_done") or child.call("route_done") != true:
			continue
		if _practice_scene:
			child.queue_free()
			continue
		_send(child)
	_top_up()


func _top_up() -> void:
	if _practice_scene or not _drive_ready:
		return
	var driving := 0
	for child in get_children():
		if child.get("trip") == true:
			driving += 1
	var added := 0
	while driving < _fleet_target and added < 2:
		if not _add_city_car():
			return
		driving += 1
		added += 1


func assign_long_trip(car: Node) -> void:
	if not car.has_method("set_route"):
		return
	car.set("drill_lock", false)
	car.set("trip", true)
	_send(car)


func _send(car: Node) -> void:
	car.call("ack_route")
	if _practice_scene:
		_practice_trip(car)
		return
	if _drive_ready:
		_send_generated(car)
		return
	var wide: bool = _is_wide(str(car.get("vehicle_kind")))
	var here := _posed_here(car)
	var nose := Vector3(-1.0, 0.0, 0.0)
	if car is Node3D:
		var body := car as Node3D
		var heading := body.get_node_or_null("Heading") as Node3D
		if heading != null:
			nose = -heading.global_transform.basis.x
			nose.y = 0.0
	var lined := PackedVector3Array()
	var pts := PackedVector3Array()
	var tries := 0
	while tries < 6:
		pts = _random_trip(wide, here, false, nose)
		lined = PackedVector3Array()
		lined.append(here)
		for point in pts:
			lined.append(point)
		if lined.size() >= 2 and _poly_len(lined) >= 200.0 and _opens_ahead(lined, nose):
			break
		tries += 1
	if lined.size() < 2:
		return
	car.call("set_route", lined, PackedByteArray(), 1)
	car.set("route_goal", lined.size() - 1)
	var driver := car.get_node_or_null("Driver") as Node
	if driver != null:
		driver.set("_span_set", false)
		driver.set("_arrival", "")


func _send_generated(car: Node) -> void:
	if not (car is Node3D) or not car.has_method("set_route"):
		return
	var body := car as Node3D
	var nose := Vector3(-1.0, 0.0, 0.0)
	var heading := body.get_node_or_null("Heading") as Node3D
	if heading != null:
		nose = -heading.global_transform.basis.x
		nose.y = 0.0
	var origin := _posed_here(car)
	var lined := PackedVector3Array()
	var tries := 0
	while tries < 6:
		lined = _generated_trip(origin, nose)
		if lined.size() >= 2 and _poly_len(lined) >= 80.0 and _opens_ahead(lined, nose):
			break
		tries += 1
	if lined.size() < 2 or _poly_len(lined) < 80.0:
		return
	car.call("set_route", lined, PackedByteArray(), 1)
	car.set("route_goal", lined.size() - 1)
	car.set("trip", true)
	car.set("drill_lock", false)
	var driver := car.get_node_or_null("Driver") as Node
	if driver != null:
		driver.set("_span_set", false)
		driver.set("_arrival", "")
		driver.set("_done_ids", [])


func _posed_here(car: Node) -> Vector3:
	if bool(car.get("have_shove_at")) and car.get("shove_at") is Vector3:
		var pinned: Vector3 = car.get("shove_at")
		car.set("have_shove_at", false)
		return pinned
	if car is Node3D:
		return (car as Node3D).global_position
	return Vector3.ZERO


func _generated_trip(here: Vector3, nose: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var depart: Dictionary = _depart_edge(here, nose)
	if depart.is_empty():
		return pts
	pts = _push_pt(pts, Vector3(here.x, CAR_Y, here.z))
	var suffix: PackedVector3Array = depart["suffix"]
	for point in suffix:
		pts = _push_pt(pts, Vector3(point.x, CAR_Y, point.z))
	var cursor: int = int(depart["to"])
	var guard := 0
	while _poly_len(pts) < 200.0 and guard < 8:
		var extended := false
		var attempt := 0
		while attempt < 6:
			var goal: int = _pick_goal(cursor)
			attempt += 1
			if goal == cursor:
				continue
			var chain: Array[int] = _path_nodes(cursor, goal)
			if chain.size() < 2:
				continue
			var before: float = _poly_len(pts)
			var leg: PackedVector3Array = _poly_along(chain)
			var trial := pts
			for point2 in leg:
				trial = _push_pt(trial, point2)
			if _poly_len(trial) <= before + 1.0:
				continue
			pts = trial
			cursor = chain[chain.size() - 1]
			extended = true
			break
		if not extended:
			break
		guard += 1
	return _seat_trip(pts)


func _mark_main() -> void:
	_in_main = PackedByteArray()
	_in_main.resize(_node_at.size())
	_in_main.fill(0)
	if _node_at.is_empty():
		return
	var sizes: PackedInt32Array = _component_sizes()
	var best := 0
	var best_n := -1
	for i in sizes.size():
		if sizes[i] > best_n:
			best_n = sizes[i]
			best = i
	var seen := PackedByteArray()
	seen.resize(_node_at.size())
	seen.fill(0)
	var found := 0
	for start in _node_at.size():
		if seen[start] != 0:
			continue
		if found == best:
			var stack: Array[int] = [start]
			seen[start] = 1
			_in_main[start] = 1
			while stack.size() > 0:
				var at: int = stack.pop_back()
				var outs: Array = _leave[at]
				for raw in outs:
					if not (raw is Dictionary):
						continue
					var nxt: int = int((raw as Dictionary)["to"])
					if seen[nxt] != 0:
						continue
					seen[nxt] = 1
					_in_main[nxt] = 1
					stack.append(nxt)
			return
		var stack2: Array[int] = [start]
		seen[start] = 1
		while stack2.size() > 0:
			var at2: int = stack2.pop_back()
			var outs2: Array = _leave[at2]
			for raw2 in outs2:
				if not (raw2 is Dictionary):
					continue
				var nxt2: int = int((raw2 as Dictionary)["to"])
				if seen[nxt2] != 0:
					continue
				seen[nxt2] = 1
				stack2.append(nxt2)
		found += 1


func _point_on_road(at: Vector3) -> bool:
	var city := _city_node()
	if city == null or not city.has_method("on_asphalt"):
		return true
	return bool(city.call("on_asphalt", at.x, at.z))


func _body_fits(at: Vector3, face: Vector3) -> bool:
	# The whole body has to sit on asphalt, and the next few meters have to be road.
	# A center point on the chunk rim still left the nose in a building, and that car never moved.
	var city := _city_node()
	if city == null or not city.has_method("on_asphalt"):
		return true
	var fwd := Vector3(face.x, 0.0, face.z)
	if fwd.length_squared() < 0.01:
		return false
	fwd = fwd.normalized()
	var right := Vector3(fwd.z, 0.0, -fwd.x)
	var hx := 3.3
	var hz := 0.9
	var samples: Array[Vector3] = [
		Vector3.ZERO,
		fwd * hx + right * hz,
		fwd * hx - right * hz,
		-fwd * hx + right * hz,
		-fwd * hx - right * hz,
		fwd * 8.0,
		fwd * 8.0 + right * hz,
		fwd * 8.0 - right * hz,
	]
	for offset in samples:
		var spot: Vector3 = at + offset
		if not bool(city.call("on_asphalt", spot.x, spot.z)):
			return false
	return true


func _seat_trip(pts: PackedVector3Array) -> PackedVector3Array:
	var city := _city_node()
	if city == null or not city.has_method("on_asphalt"):
		return pts
	var out := PackedVector3Array()
	for point in pts:
		var at := Vector3(point.x, CAR_Y, point.z)
		if not bool(city.call("on_asphalt", at.x, at.z)):
			at = _pull_asphalt(city, at)
		out = _push_pt(out, at)
	return out


func _pull_asphalt(city: Node, at: Vector3) -> Vector3:
	if not city.has_method("nearest_asphalt"):
		return at
	var raw: Variant = city.call("nearest_asphalt", at.x, at.z)
	if not (raw is Vector3):
		return at
	var edge: Vector3 = raw
	var outward := Vector3(at.x - edge.x, 0.0, at.z - edge.z)
	if outward.length_squared() < 0.04:
		outward = Vector3(1.0, 0.0, 0.0)
	else:
		outward = outward.normalized()
	var walked := 0.4
	while walked < 5.0:
		var probe := Vector3(edge.x, CAR_Y, edge.z) - outward * walked
		if bool(city.call("on_asphalt", probe.x, probe.z)):
			return probe
		walked += 0.35
	return Vector3(edge.x, CAR_Y, edge.z)


func _push_pt(pts: PackedVector3Array, at: Vector3) -> PackedVector3Array:
	if pts.is_empty() or pts[pts.size() - 1].distance_to(at) > 0.35:
		pts.append(at)
	return pts


func _depart_edge(here: Vector3, nose: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_score := 100000.0
	var nose_n := Vector3(nose.x, 0.0, nose.z)
	if nose_n.length_squared() > 0.01:
		nose_n = nose_n.normalized()
	for outs_v in _leave:
		var outs: Array = outs_v
		for raw in outs:
			if not (raw is Dictionary):
				continue
			var hop: Dictionary = raw
			var poly: PackedVector3Array = hop["poly"]
			if poly.size() < 2:
				continue
			for i in range(poly.size() - 1):
				var a: Vector3 = poly[i]
				var b: Vector3 = poly[i + 1]
				var ab := Vector2(b.x - a.x, b.z - a.z)
				var span: float = ab.length()
				if span < 0.2:
					continue
				var rel := Vector2(here.x - a.x, here.z - a.z)
				var t: float = clampf(rel.dot(ab) / (span * span), 0.0, 1.0)
				var closest := Vector2(a.x, a.z) + ab * t
				var gap: float = closest.distance_to(Vector2(here.x, here.z))
				if gap > 7.0:
					continue
				var dir := Vector3(ab.x / span, 0.0, ab.y / span)
				var align := 1.0
				if nose_n.length_squared() > 0.01:
					align = dir.dot(nose_n)
				if align < 0.15:
					continue
				var to_i: int = int(hop["to"])
				var on_main: bool = to_i < _in_main.size() and _in_main[to_i] == 1
				var score: float = gap + (1.0 - align) * 3.0
				if not on_main:
					score += 100.0
				if score >= best_score:
					continue
				best_score = score
				var suffix := PackedVector3Array()
				suffix.append(Vector3(closest.x, 0.0, closest.y))
				for k in range(i + 1, poly.size()):
					suffix.append(poly[k])
				best = {"suffix": suffix, "to": to_i}
	return best


func _pick_goal(start: int) -> int:
	var n: int = _node_at.size()
	if n < 2:
		return start
	var home: bool = start < _in_main.size() and _in_main[start] == 1
	var far := -1
	var any := -1
	var guard := 0
	while guard < 24:
		var pick: int = randi() % n
		guard += 1
		if pick == start:
			continue
		if home and (pick >= _in_main.size() or _in_main[pick] == 0):
			continue
		any = pick
		if _node_at[start].distance_to(_node_at[pick]) > 70.0:
			far = pick
			break
	if far >= 0:
		return far
	if any >= 0:
		return any
	return (start + 1) % n


func _path_nodes(start: int, goal: int) -> Array[int]:
	var none: Array[int] = []
	var count: int = _node_at.size()
	if start < 0 or goal < 0 or start >= count or goal >= count or start == goal:
		return none
	var dist := PackedFloat32Array()
	dist.resize(count)
	dist.fill(1000000.0)
	var prev := PackedInt32Array()
	prev.resize(count)
	prev.fill(-1)
	var seen := PackedByteArray()
	seen.resize(count)
	seen.fill(0)
	dist[start] = 0.0
	var left: int = count
	while left > 0:
		var best := -1
		var best_d := 1000000.0
		for i in count:
			if seen[i] != 0:
				continue
			if dist[i] < best_d:
				best_d = dist[i]
				best = i
		if best < 0:
			break
		seen[best] = 1
		left -= 1
		if best == goal:
			break
		var outs: Array = _leave[best]
		for raw in outs:
			if not (raw is Dictionary):
				continue
			var hop: Dictionary = raw
			var nxt: int = int(hop["to"])
			var alt: float = dist[best] + float(hop["length"])
			if alt < dist[nxt]:
				dist[nxt] = alt
				prev[nxt] = best
	if goal != start and prev[goal] < 0:
		return none
	var chain: Array[int] = []
	var cursor: int = goal
	var guard := 0
	while cursor >= 0 and guard < count + 1:
		chain.append(cursor)
		if cursor == start:
			break
		cursor = prev[cursor]
		guard += 1
	if chain.is_empty() or chain[chain.size() - 1] != start:
		return none
	chain.reverse()
	return chain


func _poly_along(chain: Array[int]) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var prev_dir := Vector3.ZERO
	for i in range(chain.size() - 1):
		var hop: Dictionary = _find_hop(chain[i], chain[i + 1])
		if hop.is_empty():
			continue
		var poly: PackedVector3Array = hop["poly"]
		if poly.size() < 2:
			continue
		var leave := poly[1] - poly[0]
		if prev_dir.length_squared() > 0.01 and float(hop["length"]) >= 12.0:
			for bow in _fillet_pts(_node_at[chain[i]], prev_dir, leave):
				pts = _push_pt(pts, bow)
		for point in poly:
			pts = _push_pt(pts, Vector3(point.x, CAR_Y, point.z))
		prev_dir = poly[poly.size() - 1] - poly[poly.size() - 2]
	return pts


func _find_hop(frm: int, to: int) -> Dictionary:
	if frm < 0 or frm >= _leave.size():
		return {}
	var outs: Array = _leave[frm]
	for raw in outs:
		if not (raw is Dictionary):
			continue
		var hop: Dictionary = raw
		if int(hop["to"]) == to:
			return hop
	return {}


func _fillet_pts(node: Vector2, arrive: Vector3, leave: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array()
	arrive.y = 0.0
	leave.y = 0.0
	if arrive.length_squared() < 0.01 or leave.length_squared() < 0.01:
		return pts
	arrive = arrive.normalized()
	leave = leave.normalized()
	if arrive.dot(leave) > 0.9:
		return pts
	var lane: float = _lane_m()
	var bow := 2.2
	var c := Vector3(node.x, CAR_Y, node.y)
	var ar := Vector3(-arrive.z, 0.0, arrive.x)
	var lr := Vector3(-leave.z, 0.0, leave.x)
	pts.append(c - arrive * bow + ar * lane)
	pts.append(c + ar * lane * 0.55 + lr * lane * 0.55)
	pts.append(c + leave * bow + lr * lane)
	return pts


func _lane_m() -> float:
	var city := _city_node()
	if city != null and city.has_meta("road_lane_m"):
		return float(city.get_meta("road_lane_m"))
	return GameConstants.LANE_OFF


func _opens_ahead(pts: PackedVector3Array, nose: Vector3) -> bool:
	if pts.size() < 2 or nose.length_squared() < 0.01:
		return true
	var leg := pts[1] - pts[0]
	leg.y = 0.0
	if leg.length_squared() < 0.01:
		return true
	return leg.normalized().dot(nose.normalized()) > 0.2


func _junctions(_wide: bool) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for x in GameConstants.LOOP_X:
		for z in GameConstants.LOOP_Z:
			out.append(Vector2(float(x), float(z)))
	return out


func _random_trip(wide: bool, here: Vector3, first: bool, face: Vector3 = Vector3.ZERO) -> PackedVector3Array:
	var spots := _junctions(wide)
	if spots.size() < 2:
		return PackedVector3Array()
	var start := spots[randi() % spots.size()]
	if not first:
		if face.length_squared() > 0.01:
			start = _ahead_junction(here, face, spots)
		else:
			start = _nearest_junction(here, spots)
	var goal := start
	for _try in 8:
		var pick: Vector2 = spots[randi() % spots.size()]
		if start.distance_to(pick) > 110.0:
			goal = pick
			break
	if start.distance_to(goal) < 40.0:
		goal = spots[(randi() + 5) % spots.size()]
	var pts := _build_trip(start, goal, wide)
	var guard := 0
	while _poly_len(pts) < 200.0 and guard < 8:
		var extra: Vector2 = spots[randi() % spots.size()]
		if extra.distance_to(goal) < 40.0:
			guard += 1
			continue
		var more := _build_trip(goal, extra, wide)
		for i in range(1, more.size()):
			pts.append(more[i])
		goal = extra
		guard += 1
	return pts


func _poly_len(pts: PackedVector3Array) -> float:
	var total: float = 0.0
	for i in range(1, pts.size()):
		total += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
	return total


func road_path(a: Vector3, b: Vector3) -> PackedVector3Array:
	var spots := _junctions(false)
	var start := _nearest_junction(a, spots)
	var goal := _nearest_junction(b, spots)
	var pts := _build_trip(start, goal, false)
	var lined := PackedVector3Array()
	lined.append(Vector3(a.x, CAR_Y, a.z))
	for point in pts:
		lined.append(point)
	var gy: float = b.y
	if gy < 0.2:
		gy = CAR_Y
	lined.append(Vector3(b.x, gy, b.z))
	return lined


func _ahead_junction(here: Vector3, face: Vector3, spots: Array[Vector2]) -> Vector2:
	var dir := Vector3(face.x, 0.0, face.z)
	if dir.length_squared() < 0.01:
		return _nearest_junction(here, spots)
	dir = dir.normalized()
	var best: Vector2 = spots[0]
	var best_d := 100000.0
	var found := false
	for spot in spots:
		var rel := Vector3(spot.x - here.x, 0.0, spot.y - here.z)
		var dist: float = rel.length()
		if dist < 12.0 or dist > best_d:
			continue
		if rel.normalized().dot(dir) < 0.25:
			continue
		best_d = dist
		best = spot
		found = true
	if not found:
		return _nearest_junction(here, spots)
	return best


func _nearest_junction(here: Vector3, spots: Array[Vector2]) -> Vector2:
	var best: Vector2 = spots[0]
	var best_d := 100000.0
	for spot in spots:
		var d: float = Vector2(here.x - spot.x, here.z - spot.y).length()
		if d < best_d:
			best_d = d
			best = spot
	return best


func _build_trip(a: Vector2, b: Vector2, wide: bool) -> PackedVector3Array:
	var nodes: Array[Vector2] = []
	nodes.append(a)
	if absf(a.x - b.x) > 2.0 and absf(a.y - b.y) > 2.0:
		var corner := Vector2(b.x, a.y)
		if _bad_ew(a.y, a.x, b.x):
			corner = Vector2(a.x, b.y)
		if _bad_ew(corner.y, a.x, b.x) or _bad_ns(corner.x, a.y, b.y):
			nodes.append(Vector2(a.x, 0.0))
			nodes.append(Vector2(b.x, 0.0))
		else:
			nodes.append(corner)
	nodes.append(b)
	return _stitch(nodes, wide)


func _bad_ew(z: float, x0: float, x1: float) -> bool:
	if absf(z) < 4.0:
		return false
	return minf(x0, x1) < -255.0 and maxf(x0, x1) > -345.0


func _bad_ns(x: float, z0: float, _z1: float) -> bool:
	return x > -345.0 and x < -255.0 and absf(z0) > 8.0


func _stitch(nodes: Array[Vector2], wide: bool) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in range(nodes.size() - 1):
		var seg := _segment(nodes[i], nodes[i + 1], wide)
		for point in seg:
			if pts.is_empty() or pts[pts.size() - 1].distance_to(point) > 3.0:
				pts.append(point)
	return pts


func _shift(pts: PackedVector3Array, salt: int) -> PackedVector3Array:
	if pts.size() < 4:
		return pts
	var hop: int = 1 + (salt % (pts.size() / 2))
	var spun := PackedVector3Array()
	for i in range(hop, pts.size()):
		spun.append(pts[i])
	if spun.size() < 2:
		return pts
	return spun


func _segment(a: Vector2, b: Vector2, _wide: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	var lane: float = GameConstants.LANE_OFF
	# Right-hand lane. Facing +X, right is +Z. Facing +Z, right is -X.
	# (40,40) to (150,40) sits at z = 40 + lane. (150,40) to (150,150) sits at x = 150 - lane.
	if absf(a.x - b.x) >= absf(a.y - b.y):
		var going_east: bool = b.x >= a.x
		var z: float = a.y + lane if going_east else a.y - lane
		var steps: int = maxi(1, int(absf(b.x - a.x) / 48.0))
		for s in steps + 1:
			var t: float = float(s) / float(steps)
			out.append(Vector3(lerpf(a.x, b.x, t), CAR_Y, z))
	else:
		var going_north: bool = b.y >= a.y
		var x: float = a.x - lane if going_north else a.x + lane
		var steps_z: int = maxi(1, int(absf(b.y - a.y) / 48.0))
		for s in steps_z + 1:
			var t2: float = float(s) / float(steps_z)
			out.append(Vector3(x, CAR_Y, lerpf(a.y, b.y, t2)))
	return out


func _car(car_name: String, color: Color, car_speed: float, pts: PackedVector3Array, reverse: PackedByteArray, start_i: int, kind: String = "car", as_trip: bool = false) -> void:
	var car := _CAR.instantiate() as AnimatableBody3D
	car.name = car_name
	car.body_color = color
	car.vehicle_kind = kind
	car.trip = as_trip
	car.speed = car_speed
	car.brake_miss = 0.0
	car.look_ahead = 6.0
	var at: Vector3 = pts[0]
	if start_i > 0 and start_i <= pts.size():
		at = pts[start_i - 1]
	car.position = at
	car.from_point = at
	add_child(car)
	car.set_route(pts, reverse, start_i)
	if pts.size() > 1:
		car.route_goal = pts.size() - 1


func _music() -> void:
	var player := AudioStreamPlayer.new()
	player.name = "Music"
	player.stream = _AUDIO.music()
	player.volume_db = -20.0
	player.autoplay = true
	add_child(player)


func _tag(text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 80
	label.modulate = Color(1, 0.95, 0.72)
	label.outline_modulate = Color(0, 0, 0)
	label.outline_size = 12
	label.position = at
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)


func _build_lamps() -> void:
	_ew_mat = _lamp_mat(Color(0.2, 0.85, 0.25))
	_ns_mat = _lamp_mat(Color(0.85, 0.12, 0.1))
	_pole(Vector3(8.0, 0.0, -(GameConstants.ROAD_HALF + 1.6)), _ew_mat)


func _lamp_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mat.roughness = 0.35
	return mat


func _pole(at: Vector3, mat: StandardMaterial3D) -> void:
	var root := Node3D.new()
	root.position = at
	add_child(root)
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.1
	cyl.height = 2.8
	pole.mesh = cyl
	pole.position = Vector3(0, 1.4, 0)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.13)
	pole.material_override = dark
	root.add_child(pole)
	var head := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.28, 0.7, 0.28)
	head.mesh = box
	head.position = Vector3(0, 2.95, 0)
	head.material_override = mat
	root.add_child(head)


func _paint_lamps() -> void:
	var mats: Dictionary = _signal_mat_map()
	if not mats.is_empty():
		_paint_signal_axis(mats, "ew", _axis_state(1))
		_paint_signal_axis(mats, "ns", _axis_state(2))
		_paint_signal_omnis()
		return
	if _ew_mat == null or _ns_mat == null:
		return
	var ew := _lamp_color(_axis_state(1))
	var ns := _lamp_color(_axis_state(2))
	_ew_mat.albedo_color = ew
	_ew_mat.emission = ew
	_ns_mat.albedo_color = ns
	_ns_mat.emission = ns


func _signal_mat_map() -> Dictionary:
	var city: Node = _city_node()
	if city == null or not city.has_meta("signal_mats"):
		return {}
	var raw: Variant = city.get_meta("signal_mats")
	if raw is Dictionary:
		return raw
	return {}


func _paint_signal_axis(mats: Dictionary, prefix: String, state: String) -> void:
	var lenses: PackedStringArray = PackedStringArray(["red", "yellow", "green"])
	for lens in lenses:
		var key := "%s_%s" % [prefix, lens]
		if not mats.has(key):
			continue
		var mat: Variant = mats[key]
		if not (mat is StandardMaterial3D):
			continue
		var lens_mat: StandardMaterial3D = mat
		lens_mat.emission_energy_multiplier = 2.4 if state == lens else 0.0


func _paint_signal_omnis() -> void:
	for node in get_tree().get_nodes_in_group("signal_lamp"):
		if not (node is OmniLight3D):
			continue
		var lamp := node as OmniLight3D
		var axis: int = int(lamp.get_meta("signal_axis", 0))
		lamp.light_color = _lamp_color(_axis_state(axis))


func _lamp_color(state: String) -> Color:
	if state == "green":
		return Color(0.2, 0.85, 0.25)
	if state == "yellow":
		return Color(0.92, 0.72, 0.12)
	return Color(0.85, 0.12, 0.1)


func _build_signs() -> void:
	_sign(Vector3(17.4, 0, 7.4))
	_sign(Vector3(30.6, 0, 7.4))
	_sign(Vector3(17.4, 0, -7.4))
	_sign(Vector3(30.6, 0, -7.4))


func _sign(at: Vector3) -> void:
	var root := Node3D.new()
	root.position = at
	add_child(root)
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.08
	cyl.height = 1.7
	pole.mesh = cyl
	pole.position = Vector3(0, 0.85, 0)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.15, 0.15, 0.16)
	pole.material_override = dark
	root.add_child(pole)
	var head := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.62, 0.62, 0.06)
	head.mesh = box
	head.position = Vector3(0, 1.7, 0)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.75, 0.08, 0.08)
	red.roughness = 0.45
	head.material_override = red
	root.add_child(head)
	var label := Label3D.new()
	label.name = "StopWord"
	label.text = "STOP"
	label.font_size = 56
	label.modulate = Color(1, 1, 1)
	label.position = Vector3(0, 1.7, 0.05)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)
