extends AnimatableBody3D

@export var from_point := Vector3(-7.0, 0.5, 3.2)
@export var to_point := Vector3(7.0, 0.5, 3.2)
@export var speed := 5.0
@export var look_ahead := 0.0
@export var brake_miss := 0.3
@export var wrecker := false
@export var carries_rider := true
@export var body_color := Color(0.18, 0.22, 0.28)
@export var vehicle_kind := "car"
@export var code_three := false
@export var nose_len := 3.6

const BRAKE_FROM := 3.4
const STOP_GAP := 0.7

var travel_velocity := Vector3.ZERO
var _toward_end := true
var _placed := false
var _last_position := Vector3.ZERO
var _have_last := false
var _cruise := 0.0
var _brake_roll := -1
var _wrecked := false
var _ahead_shape: BoxShape3D
var _tow: RigidBody3D
var _exit := Vector3.ZERO
var _route: PackedVector3Array = PackedVector3Array()
var _back: PackedByteArray = PackedByteArray()
var _route_i := 0
var _aim_point := Vector3.ZERO
var _heading: Node3D
var _drive: PackedVector3Array = PackedVector3Array()
var _drive_i := 0
var _route_from_drive := false
var held := false
var trip := false
var arrived := false
var practice_despawn := false
var practice_direction := 0.0
var route_goal := -1
var pulled_off := false
var left_asphalt := false
var escape_sign := 1.0
var backing_out := false
var drive_intel := 0.5
var drive_agg := 0.5
var drive_base_agg := 0.5
var drive_turning := false
var drive_note := ""
var drive_sight: Dictionary = {}
var drill_lock := false
var _driver: Node
var _half := Vector3(1.3, 0.62, 0.65)
var _box_center := Vector3.ZERO
var _pass_bias := 0.0
var _pass_lock := 0
var _stuck: float = 0.0
var _wall_fails := 0
var _crawl_t: float = 0.0
var _crawl_at := Vector3.ZERO
var _have_crawl := false
var _creep_on := false
var _ease_at := Vector3.ZERO
var _ease_until := 0.0
var _ease_sent := false
var shove_mark := ""
var have_shove_at := false
var shove_at := Vector3.ZERO
var _solid_shape: BoxShape3D
var _engine: AudioStreamPlayer3D
var _siren: AudioStreamPlayer3D
var _touch_paint := false
var _ground_check_time := 0.0
var _saved_aim := Vector3.ZERO
var _saved_speed := 0.0
var _have_saved := false
var _yaw_frame := -1
var _yaw_left := 0.0
const _AUDIO := preload("res://scripts/ambience.gd")
const _KIND_SCENE: Dictionary = {
	"police": preload("res://Models/police_car.glb"),
	"car": preload("res://Models/car.glb"),
	"compact": preload("res://Models/compact.glb"),
	"coupe": preload("res://Models/coupe.glb"),
	"wagon": preload("res://Models/wagon.glb"),
	"minivan": preload("res://Models/minivan.glb"),
	"suv": preload("res://Models/suv.glb"),
	"pickup": preload("res://Models/pickup.glb"),
	"motorcycle": preload("res://Models/motorcycle.glb"),
	"scooter": preload("res://Models/scooter.glb"),
	"taxi": preload("res://Models/taxi.glb"),
	"limousine": preload("res://Models/limousine.glb"),
	"rv": preload("res://Models/rv.glb"),
	"van": preload("res://Models/van.glb"),
	"truck": preload("res://Models/truck.glb"),
	"flatbed": preload("res://Models/flatbed.glb"),
	"dump": preload("res://Models/dump.glb"),
	"mixer": preload("res://Models/mixer.glb"),
	"utility": preload("res://Models/utility.glb"),
	"sweeper": preload("res://Models/sweeper.glb"),
	"garbage": preload("res://Models/garbage.glb"),
	"mail": preload("res://Models/mail.glb"),
	"delivery": preload("res://Models/delivery.glb"),
	"foodtruck": preload("res://Models/foodtruck.glb"),
	"tow": preload("res://Models/tow.glb"),
	"bus": preload("res://Models/bus.glb"),
	"schoolbus": preload("res://Models/schoolbus.glb"),
	"coach": preload("res://Models/coach.glb"),
	"ambulance": preload("res://Models/ambulance.glb"),
	"fire": preload("res://Models/fire.glb"),
}
const _SedanParts := preload("res://scripts/sedan_parts.gd")
const WALL_STUCK := 1.6
const SCAN_HITS := 32
const _AI_MID := 75.0
const _AI_FAR := 140.0


func _ready() -> void:
	var area := get_node_or_null("HitArea") as Area3D
	if area != null and not area.body_entered.is_connected(_on_body_entered):
		area.body_entered.connect(_on_body_entered)
	if look_ahead > 0.5:
		_ahead_shape = BoxShape3D.new()
	_heading = Node3D.new()
	_heading.name = "Heading"
	add_child(_heading)
	var meshes: Array[MeshInstance3D] = []
	for child in get_children():
		if child is MeshInstance3D:
			meshes.append(child)
	for mesh in meshes:
		mesh.reparent(_heading, true)
	_paint_body()
	_apply_kind()
	_add_sounds()
	_solid_shape = BoxShape3D.new()
	_solid_shape.size = _half * 2.0 + Vector3(0.2, 0.0, 0.2)
	_driver = preload("res://scripts/driver.gd").new()
	_driver.name = "Driver"
	add_child(_driver)


func _physics_process(delta: float) -> void:
	var seen := global_position
	var stepped := Vector3.ZERO
	if _have_last:
		stepped = (seen - _last_position) / maxf(delta, 0.0001)
	if not _placed:
		global_position = from_point
		_placed = true
		_last_position = global_position
		_have_last = true
		return
	if _wrecked:
		return
	_ground_check_time -= delta
	if _ground_check_time <= 0.0:
		_ground_check_time = 0.12
		if not _has_ground_support():
			_fall_from_road()
			return
	var patrol := _steer_target()
	var aim: Vector3 = patrol
	var on_patrol := true
	if wrecker:
		aim = _wrecker_aim(patrol)
		patrol = aim
		on_patrol = _tow == null and _nearest_wreck() == null
	var use_driver := _driver != null and look_ahead > 0.5 and not held
	var cruise: float = speed
	if use_driver and _driver.has_method("note_progress"):
		_driver.call("note_progress", self, delta)
	if held:
		cruise = 0.0
	elif use_driver and _think_now():
		var plan: Dictionary = _driver.plan(self, delta, aim)
		var planned: Variant = plan.get("aim", aim)
		if planned is Vector3:
			aim = planned
		cruise = float(plan.get("speed", speed))
		_saved_aim = aim
		_saved_speed = cruise
		_have_saved = true
	elif use_driver and _have_saved:
		aim = _saved_aim
		if _driver != null and _driver.has_method("roll_speed"):
			cruise = float(_driver.call("roll_speed", delta))
			_saved_speed = cruise
		else:
			cruise = _saved_speed
	else:
		aim = _apply_pass(aim)
		if look_ahead > 0.5:
			cruise = _choose_speed()
	_aim_point = aim
	_cruise = cruise
	var drill := get_tree().get_first_node_in_group("drive_drill")
	if drill != null and drill.has_method("allow_motion"):
		var allowed: Variant = drill.call("allow_motion", self)
		if allowed is bool and not bool(allowed):
			cruise = 0.0
			_cruise = 0.0
	if held:
		_stuck = 0.0
	var previous := global_position
	var wish: Vector3 = previous.move_toward(aim, cruise * delta)
	var face_dir: Vector3 = wish - previous
	if face_dir.length_squared() < 0.0004:
		face_dir = aim - previous
	var yaw_before := 0.0
	if _heading != null:
		yaw_before = _heading.rotation.y
	var creep_dir := Vector3.ZERO
	if use_driver and _creep_on and not backing_out:
		if _driver_wedged() and _ease_at.length_squared() > 0.01:
			var out := _ease_at - previous
			out.y = 0.0
			if out.length_squared() > 0.04 and out.normalized().dot(_shove_nose()) > 0.15:
				face_dir = out
		elif not _driver_leaving():
			creep_dir = _choose_creep_dir(previous, aim, delta)
			if creep_dir.length_squared() > 0.01 and creep_dir.dot(_shove_nose()) > 0.55:
				face_dir = creep_dir
	_aim_heading(face_dir)
	var next: Vector3 = _fit_city(previous, wish, delta)
	next = _clear_cones(previous, next)
	var moved: Vector3 = next - previous
	if moved.length_squared() > 0.0004:
		var agree := true
		if face_dir.length_squared() > 0.0004:
			agree = moved.normalized().dot(face_dir.normalized()) > 0.2
		if agree:
			_aim_heading(moved)
	var body_fwd := face_dir
	if _heading != null:
		body_fwd = -_heading.global_transform.basis.x
	next = _keep_car_on_asphalt(next, body_fwd)
	if use_driver and _should_creep(previous, next):
		if creep_dir.length_squared() < 0.01:
			creep_dir = _choose_creep_dir(previous, aim, delta)
		var crept := previous
		if creep_dir.length_squared() > 0.01:
			crept = _drive_unstick(previous, creep_dir, delta, _offroad_unstick())
		if crept.distance_squared_to(previous) > 0.0004:
			next = crept
			_creep_on = true
		else:
			var pushed := previous
			if _hits_wall(previous):
				pushed = _separate(previous, delta)
			if pushed.distance_squared_to(previous) > 0.0004:
				next = pushed
				_creep_on = true
			else:
				_creep_on = true
				if _wall_fails < 1 and not _driver_leaving() and _driver != null and _driver.has_method("recover"):
					_driver.call("recover", self)
					_wall_fails = 1
				elif _driver_wedged():
					var eased := _ease_out(previous, delta, yaw_before)
					if eased.distance_squared_to(previous) > 0.0004:
						next = eased
	elif next.distance_squared_to(previous) > 0.0004:
		_creep_on = false
		_wall_fails = 0
		_ease_at = Vector3.ZERO
		_ease_sent = false
	moved = next - previous
	global_position = next
	if not use_driver and on_patrol and next.distance_to(patrol) <= 0.45:
		_advance_steer()
		_stuck = 0.0
	elif not use_driver and _stuck >= WALL_STUCK:
		_skip_forward()
		_stuck = 0.0
	# A curb correction is not driving speed. Counting it made a 0.6 m nudge look like 36 m/s and wrecked both cars.
	var intended := (wish - previous) / maxf(delta, 0.0001)
	var scripted := (next - previous) / maxf(delta, 0.0001)
	if scripted.length() > intended.length() + 1.5:
		scripted = intended
	travel_velocity = scripted if scripted.length() >= stepped.length() else stepped
	_last_position = next
	_have_last = true
	_watch_crawl(delta)
	if travel_velocity.length() >= 2.5:
		_touch_overlaps()
	elif not held:
		_keep_clear()
	_paint_test()
	_hum()


func _think_now() -> bool:
	if wrecker or code_three:
		return true
	if _driver != null and _driver.has_method("needs_tick") and bool(_driver.call("needs_tick")):
		return true
	var soul := get_tree().get_first_node_in_group("soul") as Node3D
	if soul == null:
		return true
	var dx: float = global_position.x - soul.global_position.x
	var dz: float = global_position.z - soul.global_position.z
	var dist_sq: float = dx * dx + dz * dz
	var stride := 1
	if dist_sq > _AI_FAR * _AI_FAR:
		stride = 8
	elif dist_sq > _AI_MID * _AI_MID:
		stride = 3
	if stride == 1:
		return true
	return (Engine.get_physics_frames() + get_instance_id()) % stride == 0


func set_route(points: PackedVector3Array, reverse: PackedByteArray, start_i: int) -> void:
	arrived = false
	_route = points
	_back = reverse
	_route_i = start_i
	if points.size() == 0:
		return
	var at: Vector3 = points[0]
	if start_i > 0 and start_i <= points.size():
		at = points[start_i - 1]
	from_point = at
	to_point = points[_route_i % points.size()]
	global_position = at


func is_backing() -> bool:
	return _backing()


func _backing() -> bool:
	if backing_out:
		return true
	if _route_i < 0 or _route_i >= _back.size():
		return false
	return _back[_route_i] != 0


func set_drive(points: PackedVector3Array) -> void:
	_drive = points
	_drive_i = 0
	if points.size() < 2:
		return
	# The driver steers from _route. Leaving the polyline only in _drive made the crew aim 4 m along the nose and leave the map.
	arrived = false
	trip = false
	_route = points
	_back = PackedByteArray()
	_route_i = 0
	route_goal = points.size() - 1
	_route_from_drive = true
	var driver := get_node_or_null("Driver")
	if driver != null and driver.has_method("adopt_drive"):
		driver.call("adopt_drive")


func clear_drive() -> void:
	_drive = PackedVector3Array()
	_drive_i = 0
	if not _route_from_drive:
		return
	_route = PackedVector3Array()
	_back = PackedByteArray()
	_route_i = 0
	route_goal = -1
	arrived = false
	_route_from_drive = false


func has_assigned_drive() -> bool:
	return _route_from_drive and _route.size() >= 2


func has_tow() -> bool:
	return _tow != null and is_instance_valid(_tow)


func release_tow() -> RigidBody3D:
	var cargo := _tow
	_tow = null
	return cargo


func _steer_target() -> Vector3:
	if _drive.size() > 0:
		return _drive_point()
	if _route.size() >= 2:
		return _route[_route_i]
	if _toward_end:
		return to_point
	return from_point


func route_done() -> bool:
	return arrived


func ack_route() -> void:
	arrived = false


func mark_arrived() -> void:
	arrived = true


func route_points() -> PackedVector3Array:
	return _route


func route_cursor() -> int:
	return _route_i


func set_route_cursor(index: int) -> void:
	if _route.is_empty():
		return
	_route_i = clampi(index, 0, _route.size() - 1)


func _advance_steer() -> void:
	if _route.size() >= 2:
		if trip and _route_i >= _route.size() - 1:
			arrived = true
			return
		_route_i += 1
		if _route_i >= _route.size():
			_route_i = 0
		return
	_toward_end = not _toward_end


func _skip_forward() -> void:
	if _drive.size() > 0:
		if _drive_i < _drive.size() - 1:
			_drive_i += 1
		return
	_advance_steer()


func park_at(at: Vector3, face: Vector3) -> void:
	global_position = at
	_last_position = at
	_have_last = true
	_placed = true
	travel_velocity = Vector3.ZERO
	_aim_heading(face, true)


func _aim_heading(dir: Vector3, snap: bool = false) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return
	flat = flat.normalized()
	if _backing():
		flat = -flat
	# Nose is local -X. The body yaw is reset by sync_to_physics, so the solid box turns with the meshes.
	var yaw: float = atan2(flat.z, -flat.x)
	# A one-frame reversal is a flip, and reversing is supposed to keep the nose. Turn at about 160 deg/s.
	if not snap and _heading != null:
		var frame := Engine.get_physics_frames()
		if frame != _yaw_frame:
			_yaw_frame = frame
			_yaw_left = 2.8 * maxf(get_physics_process_delta_time(), 0.016)
		var turn := wrapf(yaw - _heading.rotation.y, -PI, PI)
		var step := clampf(turn, -_yaw_left, _yaw_left)
		_yaw_left -= absf(step)
		yaw = _heading.rotation.y + step
	if _heading != null:
		_heading.rotation.y = yaw
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node != null:
		shape_node.rotation = Vector3(0.0, yaw, 0.0)
	var area := get_node_or_null("HitArea") as Area3D
	if area != null:
		area.rotation = Vector3(0.0, yaw, 0.0)


func _keep_car_on_asphalt(at: Vector3, travel: Vector3) -> Vector3:
	# Explicit pull-offs and shoulder maneuvers are allowed to leave the pavement;
	# the curb-corner rule is for ordinary driving and turns.
	if bool(get("pulled_off")) or bool(get("left_asphalt")):
		return at
	var traffic := get_tree().get_first_node_in_group("traffic")
	var main := traffic.get_parent() if traffic != null else null
	var city := main.get_node_or_null("City") if main != null else null
	if city == null or not city.has_method("on_asphalt") or travel.length_squared() < 0.0001:
		return at
	var fwd := Vector3(travel.x, 0.0, travel.z).normalized()
	var right := Vector3(fwd.z, 0.0, -fwd.x)
	# The original point is the closest candidate. Skip the search when it already fits.
	if _corners_on_asphalt(city, at, fwd, right):
		return at
	var best := at
	var best_d := INF
	for ring in range(1, 7):
		for ix in range(-ring, ring + 1):
			for iz in range(-ring, ring + 1):
				if maxi(absi(ix), absi(iz)) != ring:
					continue
				var candidate: Vector3 = at + Vector3(float(ix) * 0.2, 0.0, float(iz) * 0.2)
				if not _corners_on_asphalt(city, candidate, fwd, right):
					continue
				var distance: float = Vector2(candidate.x - at.x, candidate.z - at.z).length_squared()
				if distance < best_d:
					best = candidate
					best_d = distance
	if best_d == INF:
		return at
	var pull := best - at
	var span := pull.length()
	var cap := maxf(2.2 * get_physics_process_delta_time(), 0.02)
	if span > cap:
		return at + pull * (cap / span)
	return best


func _near_hitter(at: Vector3, reach: float = 4.0) -> bool:
	var limit := reach * reach
	for node in get_tree().get_nodes_in_group("hitter"):
		if node == self or not (node is Node3D):
			continue
		var other := node as Node3D
		var dx: float = other.global_position.x - at.x
		var dz: float = other.global_position.z - at.z
		if dx * dx + dz * dz < limit:
			return true
	return false


func _watch_crawl(delta: float) -> void:
	# travel_velocity stays high when a wall slide cancels the step, so the clock is net displacement.
	if not _have_crawl:
		_have_crawl = true
		_crawl_at = global_position
	var moved := Vector2(global_position.x - _crawl_at.x, global_position.z - _crawl_at.z).length()
	var trying := _cruise >= 0.8 or _driver_leaving()
	if not trying or moved >= 1.6:
		_crawl_t = 0.0
		_crawl_at = global_position
		return
	_crawl_t += delta


func _driver_leaving() -> bool:
	return _driver != null and _driver.has_method("leaving") and bool(_driver.call("leaving"))


func _shove_nose() -> Vector3:
	var nose := _flat_aim()
	if _heading != null:
		nose = -_heading.global_transform.basis.x
		nose.y = 0.0
	if nose.length_squared() < 0.01:
		nose = Vector3(-1.0, 0.0, 0.0)
	return nose.normalized()


func _motion_agrees(from: Vector3, to: Vector3) -> bool:
	var moved := to - from
	moved.y = 0.0
	if moved.length_squared() < 0.0001:
		return false
	var dot := moved.normalized().dot(_shove_nose())
	if backing_out or _backing():
		return dot < -0.15
	return dot > 0.35


func _should_creep(previous: Vector3, next: Vector3) -> bool:
	if held:
		return false
	var trying := _cruise >= 0.8 or _driver_leaving()
	if not trying and _stuck < 0.45:
		return false
	if _hits_wall(previous):
		return true
	if next.distance_squared_to(previous) > 0.00015:
		return false
	if _stuck >= 0.45:
		return true
	if not _have_crawl:
		return false
	var moved := Vector2(previous.x - _crawl_at.x, previous.z - _crawl_at.z).length()
	return (_crawl_t >= 0.9 and moved < 0.35) or (_crawl_t >= 2.6 and moved < 0.9)


func _driver_wedged() -> bool:
	return _driver != null and _driver.has_method("wedged") and bool(_driver.call("wedged"))


func _offroad_unstick() -> bool:
	return bool(left_asphalt) or _driver_leaving() or _driver_wedged()


func _choose_creep_dir(previous: Vector3, aim: Vector3, delta: float) -> Vector3:
	var nose := _shove_nose()
	var right := Vector3(nose.z, 0.0, -nose.x)
	var allow := _offroad_unstick()
	var dirs: Array[Vector3] = []
	if backing_out:
		dirs.append(-nose)
		dirs.append((-nose + right * 0.45).normalized())
		dirs.append((-nose - right * 0.45).normalized())
	else:
		var aim_flat := aim - previous
		aim_flat.y = 0.0
		if aim_flat.length_squared() > 0.04 and aim_flat.normalized().dot(nose) > 0.45:
			dirs.append(aim_flat.normalized())
		dirs.append(nose)
		dirs.append((nose + right * 0.45).normalized())
		dirs.append((nose - right * 0.45).normalized())
		if allow:
			dirs.append(-nose)
	var dist := minf(2.2 * delta, 0.32)
	for dir in dirs:
		var at := previous + dir * dist
		at.y = previous.y
		if _step_ok(at, allow):
			return dir
	return Vector3.ZERO


func _drive_unstick(previous: Vector3, dir: Vector3, delta: float, allow_offroad: bool) -> Vector3:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return previous
	flat = flat.normalized()
	var nose := _shove_nose()
	var dot := flat.dot(nose)
	var travel := Vector3.ZERO
	if dot > 0.55:
		travel = flat
	elif dot < -0.55:
		travel = -nose
	else:
		return previous
	var dist := minf(2.2 * delta, 0.32)
	var at := previous + travel * dist
	at.y = previous.y
	if _step_ok(at, allow_offroad):
		return at
	return previous


func _separate(previous: Vector3, delta: float, prefer: Vector3 = Vector3.ZERO) -> Vector3:
	# The body is already in the wall. Inch toward the nearest open cell. A longer hop is the teleport.
	var nose := _shove_nose()
	var right := Vector3(nose.z, 0.0, -nose.x)
	var embedded := _hits_wall(previous)
	var dirs: Array[Vector3] = []
	var preferred := Vector3(prefer.x, 0.0, prefer.z)
	if preferred.length_squared() > 0.01:
		dirs.append(preferred.normalized())
	dirs.append(-nose)
	dirs.append(nose)
	dirs.append(right)
	dirs.append(-right)
	dirs.append((-nose + right * 0.6).normalized())
	dirs.append((-nose - right * 0.6).normalized())
	dirs.append((nose + right * 0.6).normalized())
	dirs.append((nose - right * 0.6).normalized())
	var best_dir := Vector3.ZERO
	var best_reach := 20.0
	for dir in dirs:
		for reach in [0.45, 1.0, 2.0, 4.0, 7.0, 12.0]:
			var probe := previous + dir * float(reach)
			probe.y = previous.y
			if _hits_wall(probe):
				continue
			if float(reach) < best_reach:
				best_reach = float(reach)
				best_dir = dir
			break
	if best_dir.length_squared() < 0.01:
		return previous
	var step := minf(best_reach, minf(2.2 * delta, 0.32))
	var at := previous + best_dir * step
	at.y = previous.y
	# A wedged body may still be inside the wall. Keep inching toward the opening.
	if not embedded and not _driver_wedged() and _hits_wall(at):
		return previous
	return at


func _step_ok(at: Vector3, allow_offroad: bool) -> bool:
	if _hits_wall(at):
		return false
	if _near_hitter(at, 1.55):
		return false
	if allow_offroad:
		return true
	var fwd := _shove_nose()
	var right := Vector3(fwd.z, 0.0, -fwd.x)
	return _slide_supported(at, fwd, right)


func _ease_out(previous: Vector3, delta: float, yaw_before: float) -> Vector3:
	if _ease_at.length_squared() > 0.01 and previous.distance_squared_to(_ease_at) < 1.44 and not _hits_wall(previous):
		if not _ease_sent:
			_ease_sent = true
			# set_route reads the body pose. sync_to_physics still has the wedge, and that put the car back.
			have_shove_at = true
			shove_at = previous
			if _driver != null and _driver.has_method("nudged"):
				_driver.call("nudged")
		return previous
	var now := float(Time.get_ticks_msec()) * 0.001
	if _ease_at.length_squared() < 0.01 or now >= _ease_until:
		var found := _nearest_clear(previous)
		if found.length_squared() < 0.01:
			return _separate(previous, delta)
		_ease_at = found
		_ease_until = now + 0.75
	var dir := _ease_at - previous
	dir.y = 0.0
	if dir.length_squared() < 0.04:
		return previous
	var flat := dir.normalized()
	var nose := _shove_nose()
	if absf(flat.dot(nose)) <= 0.55 and not backing_out:
		# The blocked aim already spent this frame's turn. Put that back and turn toward the open road.
		if _heading != null:
			_heading.rotation.y = yaw_before
		_yaw_frame = -1
		_aim_heading(flat)
		return _separate(previous, delta, flat)
	var driven := _drive_unstick(previous, flat, delta, true)
	if driven.distance_squared_to(previous) > 0.0004:
		return driven
	return _separate(previous, delta, flat)


func _nearest_clear(here: Vector3) -> Vector3:
	var nose := _shove_nose()
	var right := Vector3(nose.z, 0.0, -nose.x)
	var best := Vector3.ZERO
	var best_d := 16.5
	var fallback := Vector3.ZERO
	var fallback_d := 16.5
	var spots: Array[Vector3] = []
	var axes: Array[Vector3] = [
		nose, -nose, right, -right,
		(nose + right).normalized(), (nose - right).normalized(),
		(-nose + right).normalized(), (-nose - right).normalized(),
	]
	for reach in [2.0, 4.0, 7.0, 11.0, 15.0]:
		for dir in axes:
			var spot := here + dir * float(reach)
			spot.y = here.y
			spots.append(spot)
	var city := _city_node()
	if city != null and city.has_method("nearest_asphalt"):
		var raw: Variant = city.call("nearest_asphalt", here.x, here.z)
		if raw is Vector3:
			var edge := raw as Vector3
			edge.y = here.y
			var inward := edge - here
			inward.y = 0.0
			if inward.length() < 0.4:
				inward = -right
			inward = inward.normalized()
			for depth in [2.5, 5.0]:
				var lane := edge + inward * float(depth)
				lane.y = here.y
				spots.append(lane)
	for spot in spots:
		var rel := spot - here
		rel.y = 0.0
		var dist := rel.length()
		if dist < 1.4 or dist >= best_d:
			continue
		if not _point_on_road(spot) or _near_hitter(spot, 1.2):
			continue
		if dist < fallback_d:
			fallback = spot
			fallback_d = dist
		var face := nose
		if rel.normalized().dot(nose) < -0.5:
			face = -nose
		if _box_hits(spot, face, 1.0):
			continue
		best = spot
		best_d = dist
	if best.length_squared() < 0.01:
		return fallback
	return best


func _point_on_road(at: Vector3) -> bool:
	var city := _city_node()
	if city == null or not city.has_method("on_asphalt"):
		return true
	return bool(city.call("on_asphalt", at.x, at.z))


func _city_node() -> Node:
	var traffic := get_tree().get_first_node_in_group("traffic")
	var main := traffic.get_parent() if traffic != null else null
	if main == null:
		return null
	return main.get_node_or_null("City")


func _box_hits(at: Vector3, face: Vector3, scale: float = 1.0) -> bool:
	if _solid_shape == null:
		return false
	var world: World3D = get_world_3d()
	if world == null:
		return false
	var flat := Vector3(face.x, 0.0, face.z)
	if flat.length_squared() < 0.01:
		return _hits_wall(at)
	flat = flat.normalized()
	var yaw: float = atan2(flat.z, -flat.x)
	var basis := Basis(Vector3.UP, yaw)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _solid_shape
	if scale < 0.99:
		var small := _solid_shape.duplicate() as BoxShape3D
		small.size = _solid_shape.size * scale
		params.shape = small
	var center := at
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node != null:
		center = at + Vector3(0.0, shape_node.position.y, 0.0)
	params.transform = Transform3D(basis, center)
	params.collision_mask = 1
	params.collide_with_bodies = true
	params.collide_with_areas = false
	params.exclude = [get_rid()]
	var hits: Array = world.direct_space_state.intersect_shape(params, 8)
	for found in hits:
		var hit: Dictionary = found
		var body := hit.get("collider") as Node
		if _blocks_car(body):
			return true
	return false


func _slide_supported(at: Vector3, fwd: Vector3, right: Vector3) -> bool:
	var traffic := get_tree().get_first_node_in_group("traffic")
	var main := traffic.get_parent() if traffic != null else null
	var city := main.get_node_or_null("City") if main != null else null
	if city == null or not city.has_method("on_asphalt"):
		return true
	return _corners_on_asphalt(city, at, fwd, right)


func _corners_on_asphalt(city: Node, at: Vector3, fwd: Vector3, right: Vector3) -> bool:
	for offset in [
		fwd * _half.x + right * _half.z,
		fwd * _half.x - right * _half.z,
		-fwd * _half.x + right * _half.z,
		-fwd * _half.x - right * _half.z,
	]:
		var corner: Vector3 = at + offset
		if not bool(city.call("on_asphalt", corner.x, corner.z)):
			return false
	return true


func _fit_city(previous: Vector3, desired: Vector3, delta: float) -> Vector3:
	if previous.distance_squared_to(desired) < 0.0000001:
		return desired
	if not _hits_wall(desired):
		_stuck = 0.0
		return desired
	var x_only := Vector3(desired.x, desired.y, previous.z)
	var z_only := Vector3(previous.x, desired.y, desired.z)
	var aim := _aim_point
	var best := previous
	var best_d: float = previous.distance_squared_to(aim)
	if x_only.distance_squared_to(previous) > 0.0000001 and not _hits_wall(x_only) and _motion_agrees(previous, x_only):
		var dx: float = x_only.distance_squared_to(aim)
		if dx < best_d:
			best = x_only
			best_d = dx
	if z_only.distance_squared_to(previous) > 0.0000001 and not _hits_wall(z_only) and _motion_agrees(previous, z_only):
		var dz: float = z_only.distance_squared_to(aim)
		if dz < best_d:
			best = z_only
	if best.distance_squared_to(previous) < 0.0000001:
		_stuck += delta
	else:
		_stuck = 0.0
	return best


func _hits_wall(at: Vector3) -> bool:
	if _solid_shape == null:
		return false
	var world: World3D = get_world_3d()
	if world == null:
		return false
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _solid_shape
	var basis := global_transform.basis
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	var center := at
	if shape_node != null:
		basis = shape_node.global_transform.basis
		center = at + Vector3(0.0, shape_node.position.y, 0.0)
	params.transform = Transform3D(basis, center)
	params.collision_mask = 1
	params.collide_with_bodies = true
	params.collide_with_areas = false
	params.exclude = [get_rid()]
	var hits: Array = world.direct_space_state.intersect_shape(params, 16)
	for found in hits:
		var hit: Dictionary = found
		var body := hit.get("collider") as Node
		if _blocks_car(body):
			return true
	return false


func _blocks_car(body: Node) -> bool:
	if body == null or body == self or not (body is StaticBody3D):
		return false
	if body is AnimatableBody3D:
		return false
	if body.is_in_group("hitter") or body.is_in_group("vehicle") or body.is_in_group("soul") or body.is_in_group("pedestrian"):
		return false
	if body.is_in_group("pavement") or body.is_in_group("stack_target") or body.is_in_group("overhead"):
		return false
	if _is_cone_body(body):
		return false
	var shape_node := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node != null and shape_node.shape is BoxShape3D:
		var tall: float = (shape_node.shape as BoxShape3D).size.y
		if tall < 0.5:
			return false
	return true


func _paint_body() -> void:
	var mesh := find_child("Body", true, false) as MeshInstance3D
	if mesh == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mat.roughness = 0.65
	mesh.material_override = mat


func _choose_speed() -> float:
	var cap: float = speed * minf(_signal_scale(), _yield_scale())
	var gap: float = _blocker_gap()
	if gap < 0.0:
		_brake_roll = -1
		return cap
	# Some approaches miss the brake and hit anyway. Signals still hold.
	if _brake_roll < 0:
		_brake_roll = 1 if randf() < brake_miss else 0
	if _brake_roll == 1:
		return cap
	if gap <= STOP_GAP:
		if _pass_bias != 0.0:
			return cap * 0.5
		return 0.0
	if gap >= BRAKE_FROM:
		return cap
	var t: float = (gap - STOP_GAP) / (BRAKE_FROM - STOP_GAP)
	return cap * t * t


func _signal_scale() -> float:
	if code_three and not wrecker:
		return 1.0
	var node: Node = get_tree().get_first_node_in_group("traffic")
	if node == null or not node.has_method("scale_for"):
		return 1.0
	var aim: Vector3 = _flat_aim()
	if aim.length_squared() < 0.0001:
		return 1.0
	return float(node.scale_for(self, global_position, aim.normalized()))


func _yield_scale() -> float:
	var aim := _flat_aim()
	if aim.length_squared() < 0.0001:
		return 1.0
	var dir := aim.normalized()
	var worst := 1.0
	worst = minf(worst, _yield_group(get_tree().get_nodes_in_group("hitter"), dir))
	worst = minf(worst, _yield_group(get_tree().get_nodes_in_group("pedestrian"), dir))
	var soul := get_tree().get_first_node_in_group("soul") as Node3D
	if soul != null and not _sedan_skips_player():
		worst = minf(worst, _yield_one(soul, dir))
	return worst


func _yield_group(nodes: Array, dir: Vector3) -> float:
	var worst := 1.0
	for node in nodes:
		if node is Node3D:
			worst = minf(worst, _yield_one(node as Node3D, dir))
	return worst


func _yield_one(other: Node3D, dir: Vector3) -> float:
	if other == self or not is_instance_valid(other):
		return 1.0
	var rel := other.global_position - global_position
	rel.y = 0.0
	var along: float = rel.dot(dir)
	if along < 2.0 or along > 16.0:
		return 1.0
	var lat := rel - dir * along
	var side: float = lat.length()
	if side < 1.4 or side > 14.0:
		return 1.0
	var their := _flat_velocity(other)
	if their.length() < 0.6:
		return 1.0
	var toward := -lat / side
	if their.normalized().dot(toward) < 0.45:
		return 1.0
	var pace: float = maxf(_cruise, speed * 0.35)
	var their_time: float = side / their.length()
	var our_time: float = along / pace
	if their_time > our_time + 0.35:
		return 1.0
	if along <= 3.2:
		return 0.0
	var blend: float = (along - 3.2) / 12.8
	return blend * blend


func _flat_velocity(body: Node3D) -> Vector3:
	var travel: Variant = body.get("travel_velocity")
	var flat := Vector3.ZERO
	if travel is Vector3:
		flat = travel as Vector3
	elif body is CharacterBody3D:
		flat = (body as CharacterBody3D).velocity
	flat.y = 0.0
	return flat


func _flat_aim() -> Vector3:
	var aim: Vector3 = _aim_point - global_position
	aim.y = 0.0
	return aim


func _blocker_gap() -> float:
	if _ahead_shape == null:
		return -1.0
	var world := get_world_3d()
	if world == null:
		return -1.0
	var aim := _flat_aim()
	if aim.length_squared() < 0.0001:
		return -1.0
	var dir := aim.normalized()
	var reach: float = look_ahead
	_ahead_shape.size = Vector3(2.4, 1.3, reach)
	var mid := global_position + dir * (1.6 + reach * 0.5)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _ahead_shape
	params.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), mid)
	params.collision_mask = 1
	params.collide_with_bodies = true
	params.collide_with_areas = false
	params.exclude = [get_rid()]
	var best := -1.0
	var hits: Array = world.direct_space_state.intersect_shape(params, SCAN_HITS)
	for found in hits:
		var hit: Dictionary = found
		var body := hit.get("collider") as Node
		if body == null or body == self or not _is_brake_target(body):
			continue
		var nose: float = 1.3
		if body.is_in_group("hitter") or body.is_in_group("vehicle"):
			nose = nose_len
		var along: float = (body.global_position - global_position).dot(dir) - nose
		if along < 0.2:
			continue
		if best < 0.0 or along < best:
			best = along
	return best


func _sedan_skips_player() -> bool:
	return vehicle_kind == "car" and not wrecker


func _paint_test() -> void:
	if not _sedan_skips_player() or _heading == null:
		return
	var area := get_node_or_null("HitArea") as Area3D
	var touching := false
	if area != null:
		var bodies: Array = area.get_overlapping_bodies()
		for body in bodies:
			if body is Node and _is_player_body(body as Node):
				touching = true
				break
	if touching and not _touch_paint:
		_roll_paint()
	_touch_paint = touching


func _roll_paint() -> void:
	var rig: Node = _heading.get_node_or_null("SedanRig")
	if rig == null or not rig.has_method("set_paint"):
		return
	var next := Color.from_hsv(randf(), randf_range(0.55, 0.92), randf_range(0.42, 0.92))
	var gap := Vector3(next.r - body_color.r, next.g - body_color.g, next.b - body_color.b)
	if gap.length() < 0.18:
		next = Color.from_hsv(randf(), 0.8, 0.75)
	body_color = next
	rig.call("set_paint", next)


func _is_player_body(body: Node) -> bool:
	if body.is_in_group("soul"):
		return true
	var parent := body.get_parent()
	return parent != null and parent.is_in_group("soul")


func _is_brake_target(body: Node) -> bool:
	if body.is_in_group("hitter"):
		return true
	if body.is_in_group("vehicle") and not wrecker:
		return true
	if (code_three or wrecker) and body.is_in_group("stack_target"):
		return false
	if _sedan_skips_player() and _is_player_body(body):
		return false
	if body.is_in_group("soul") or body.is_in_group("pedestrian") or body.is_in_group("stack_target"):
		return true
	var parent := body.get_parent()
	return parent != null and parent.is_in_group("pedestrian")


func _touch_overlaps() -> void:
	var area := get_node_or_null("HitArea") as Area3D
	if area == null:
		return
	var bodies: Array = area.get_overlapping_bodies()
	for body in bodies:
		if body is Node and _is_soft(body as Node):
			_deliver_hit(body as Node)
	if _wrecked:
		return
	for body in bodies:
		if body is Node and not _is_soft(body as Node):
			_deliver_hit(body as Node)


func _on_body_entered(body: Node) -> void:
	_deliver_hit(body)


func _deliver_hit(body: Node) -> void:
	if _wrecked or body == null or body == self:
		return
	if wrecker and body.has_method("become_wreck"):
		_bump_aside(body)
		return
	if body.is_in_group("hitter") or body.is_in_group("vehicle"):
		_crash_with(body)
		return
	if body.is_in_group("pedestrian") and body.has_method("knock"):
		body.knock(travel_velocity, self)
		return
	if body.is_in_group("soul"):
		if _feet_on_roof(body):
			return
		var stack := body.get_node_or_null("StackController")
		if stack != null and stack.has_method("receive_hit"):
			stack.receive_hit(travel_velocity, self)
		return
	var column := body.get_parent()
	if column != null and column.has_method("break_from_hit"):
		column.break_from_hit(travel_velocity, self)


func _crash_with(body: Node) -> void:
	if code_three or _wrecked or pulled_off or body == self:
		return
	var my_vel := travel_velocity
	var their_vel := Vector3.ZERO
	if body is RigidBody3D:
		their_vel = (body as RigidBody3D).linear_velocity
	elif body.get("travel_velocity") is Vector3:
		their_vel = body.get("travel_velocity") as Vector3
	var rel: float = (my_vel - their_vel).length()
	var smash: float = rel * (_kind_mass(self) + _kind_mass(body)) * 0.08
	# A bumper touch while going around a wreck, or while stopping for a light, is not a crash.
	# Below this, both cars keep their route. Above it, they stop where they are.
	if smash < 8.0:
		return
	var other := body as Node3D
	if other == null:
		return
	_stop_at_impact()
	if body.has_method("stop_at_impact"):
		body.stop_at_impact()


func _stop_at_impact() -> void:
	if _wrecked or wrecker or code_three:
		return
	_wrecked = true
	travel_velocity = Vector3.ZERO
	_cruise = 0.0
	# Keep the stopped vehicle in both collision and traffic sight. It stays
	# exactly where the impact left it and remains a solid obstacle.


func pull_off() -> void:
	if wrecker or code_three or _wrecked or pulled_off:
		return
	pulled_off = true
	_spill_rider(global_position, travel_velocity)


func _kind_mass(body: Node) -> float:
	var kind := str(body.get("vehicle_kind"))
	if kind == "motorcycle" or kind == "scooter":
		return 1.1
	if kind == "bus" or kind == "truck" or kind == "coach" or kind == "fire" or kind == "schoolbus" or kind == "dump" or kind == "mixer":
		return 9.0
	return 4.5


func _wrecker_aim(patrol: Vector3) -> Vector3:
	if _tow != null and not is_instance_valid(_tow):
		_tow = null
	elif _tow != null:
		_drag_tow()
	elif _tow == null:
		var wreck := _nearest_wreck()
		if wreck != null:
			var spot := wreck.global_position
			var dist: float = Vector2(global_position.x - spot.x, global_position.z - spot.z).length()
			if dist < 2.7:
				_hook(wreck)
	if _drive.size() > 0:
		return _drive_point()
	if _tow != null:
		return _exit
	return patrol


func _nearest_wreck() -> RigidBody3D:
	var best: RigidBody3D = null
	var best_d := 10000.0
	for node in get_tree().get_nodes_in_group("vehicle"):
		if not (node is RigidBody3D):
			continue
		var wreck := node as RigidBody3D
		var gap: float = global_position.distance_to(wreck.global_position)
		if gap < best_d:
			best_d = gap
			best = wreck
	return best


func _hook(wreck: RigidBody3D) -> void:
	if _tow != null or not is_instance_valid(wreck):
		return
	_tow = wreck
	wreck.remove_from_group("vehicle")
	wreck.freeze = true
	wreck.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	wreck.collision_layer = 0
	wreck.collision_mask = 0
	_exit = Vector3(-392.0, global_position.y, 36.0)


func _drag_tow() -> void:
	if _tow == null or not is_instance_valid(_tow):
		return
	var dir: Vector3 = _exit - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3(0.0, 0.0, 1.0)
	dir = dir.normalized()
	_tow.global_position = global_position - dir * 3.6
	_tow.global_position.y = 0.45
	_tow.look_at(_tow.global_position + dir, Vector3.UP)


func _bump_aside(body: Node) -> void:
	if not body.has_method("become_wreck"):
		return
	var their_vel := Vector3.ZERO
	if body.get("travel_velocity") is Vector3:
		their_vel = body.get("travel_velocity") as Vector3
	var other := body as Node3D
	if other == null:
		return
	var away: Vector3 = other.global_position - global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3(1.0, 0.0, 0.0)
	body.become_wreck(their_vel, away.normalized() * 0.55)


func become_wreck(vel: Vector3, nudge: Vector3) -> void:
	if wrecker or code_three or _wrecked:
		return
	_wrecked = true
	remove_from_group("hitter")
	global_position += nudge
	var rb := _make_rigid_vehicle(vel, 2.2, 5.0)
	var parent := get_parent()
	parent.add_child(rb)
	rb.global_transform = global_transform
	_copy_vehicle_shape_and_model(rb)
	var spin := nudge.cross(Vector3.UP)
	if spin.length_squared() < 0.001:
		spin = Vector3(0.3, 0.2, 0.4)
	rb.angular_velocity = spin.normalized() * clampf(vel.length() * 0.08, 0.35, 1.5)
	_finish_vehicle_conversion(rb, vel, true)


func _fall_from_road() -> void:
	if _wrecked:
		return
	_wrecked = true
	remove_from_group("hitter")
	var rb := _make_rigid_vehicle(travel_velocity, 0.35, 0.6)
	var parent := get_parent()
	parent.add_child(rb)
	rb.global_transform = global_transform
	_copy_vehicle_shape_and_model(rb)
	rb.angular_velocity = Vector3.ZERO
	_finish_vehicle_conversion(rb, travel_velocity, false)


func _make_rigid_vehicle(vel: Vector3, linear_friction: float, angular_friction: float) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.collision_layer = 1
	rb.collision_mask = 1
	rb.mass = _kind_mass(self)
	rb.linear_damp = linear_friction
	rb.angular_damp = angular_friction
	rb.continuous_cd = true
	rb.can_sleep = true
	var material := PhysicsMaterial.new()
	material.friction = 1.25
	material.rough = true
	material.bounce = 0.0
	rb.physics_material_override = material
	rb.add_to_group("vehicle")
	rb.linear_velocity = vel
	return rb


func _copy_vehicle_shape_and_model(rb: RigidBody3D) -> void:
	var old_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if old_shape != null and old_shape.shape != null:
		var inst := CollisionShape3D.new()
		inst.shape = old_shape.shape.duplicate()
		inst.transform = old_shape.transform
		rb.add_child(inst)
	if _heading != null and is_instance_valid(_heading):
		_heading.reparent(rb, true)
	else:
		var meshes: Array[MeshInstance3D] = []
		for child in get_children():
			if child is MeshInstance3D:
				meshes.append(child)
		for mesh in meshes:
			mesh.reparent(rb, true)


func _finish_vehicle_conversion(rb: RigidBody3D, vel: Vector3, report_crash: bool) -> void:
	_spill_rider(rb.global_position, vel)
	if report_crash:
		_eject(rb)
		var desk := get_tree().get_first_node_in_group("dispatch")
		if desk != null and desk.has_method("note_crash"):
			desk.note_crash(rb.global_position)
	if _engine != null:
		_engine.stop()
	queue_free()


func _has_ground_support() -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.8, global_position - Vector3.UP * 3.5, 1)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider: Object = hit.get("collider")
	if collider is Node and (collider as Node).is_in_group("vehicle"):
		return false
	return collider is StaticBody3D or (collider is Node and (collider as Node).is_in_group("pavement"))


func _spill_rider(at: Vector3, vel: Vector3) -> void:
	if not carries_rider:
		return
	var home := get_tree().get_first_node_in_group("walker_home")
	if home == null or not home.has_method("spawn_exit"):
		return
	var side: Vector3 = vel.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = Vector3(1.0, 0.0, 0.0)
	side = side.normalized()
	if (at + side).length_squared() < (at - side).length_squared():
		side = -side
	var feet := Vector3(at.x, 0.85, at.z) + side * 1.9
	home.spawn_exit(feet, feet + side * 6.0)


func _drive_point() -> Vector3:
	if _drive_i >= _drive.size():
		_drive_i = _drive.size() - 1
	var pt: Vector3 = _drive[_drive_i]
	var gap: float = Vector2(global_position.x - pt.x, global_position.z - pt.z).length()
	if gap < 3.0 and _drive_i < _drive.size() - 1:
		_drive_i += 1
		pt = _drive[_drive_i]
	return pt


func _apply_pass(aim: Vector3) -> Vector3:
	if held:
		_pass_bias = 0.0
		return aim
	var flat := aim - global_position
	flat.y = 0.0
	if flat.length() < 1.0:
		return aim
	var dir := flat.normalized()
	var side := Vector3(-dir.z, 0.0, dir.x)
	var blocker := _ahead_body(dir)
	var now := Time.get_ticks_msec()
	if blocker == null:
		if now > _pass_lock:
			_pass_bias = 0.0
		elif _pass_bias != 0.0:
			return aim + side * _pass_bias * 2.7
		return aim
	if _is_cone_body(blocker) and not code_three and not wrecker:
		_pass_bias = 0.0
		return aim
	if not _is_stopped(blocker) and not (blocker is StaticBody3D):
		return aim
	if _pass_bias == 0.0 or now > _pass_lock:
		if _side_clear(dir, side):
			_pass_bias = 1.0
		elif _side_clear(dir, -side):
			_pass_bias = -1.0
		else:
			_pass_bias = 0.0
		_pass_lock = now + 1800
	if _pass_bias == 0.0:
		return aim
	return aim + side * _pass_bias * 2.7


func _ahead_body(dir: Vector3) -> Node:
	var world := get_world_3d()
	if world == null:
		return null
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 1.3, 7.0)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = box
	params.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), global_position + dir * 5.0)
	params.collision_mask = 1
	params.collide_with_bodies = true
	params.collide_with_areas = false
	params.exclude = [get_rid()]
	var hits: Array = world.direct_space_state.intersect_shape(params, SCAN_HITS)
	var best: Node = null
	var best_along := 1000.0
	for found in hits:
		var hit: Dictionary = found
		var body := hit.get("collider") as Node
		if body == null or body == self or body.is_in_group("pavement"):
			continue
		if body is StaticBody3D and not _is_cone_body(body):
			continue
		var along: float = ((body as Node3D).global_position - global_position).dot(dir)
		if along < 0.4:
			continue
		if along < best_along:
			best_along = along
			best = body
	return best


func _side_clear(dir: Vector3, side: Vector3) -> bool:
	var world := get_world_3d()
	if world == null:
		return false
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 1.4, 6.0)
	var mid := global_position + side * 2.7 + dir * 4.5
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = box
	params.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), mid)
	params.collision_mask = 1
	params.collide_with_bodies = true
	params.collide_with_areas = false
	params.exclude = [get_rid()]
	var hits: Array = world.direct_space_state.intersect_shape(params, SCAN_HITS)
	for found in hits:
		var hit: Dictionary = found
		var body := hit.get("collider") as Node
		if body == null or body == self or body.is_in_group("pavement"):
			continue
		if _is_cone_body(body) and (code_three or wrecker):
			continue
		return false
	return true


func _clear_cones(from: Vector3, at: Vector3) -> Vector3:
	var world := get_world_3d()
	if world == null:
		return at
	var shape := SphereShape3D.new()
	var reach := 0.9
	shape.radius = reach
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), at + Vector3(0.0, 0.45, 0.0))
	params.collision_mask = 1
	params.collide_with_bodies = true
	params.collide_with_areas = false
	params.exclude = [get_rid()]
	var hits: Array = world.direct_space_state.intersect_shape(params, 8)
	var out := at
	var step := at - from
	step.y = 0.0
	for found in hits:
		var hit: Dictionary = found
		var body := hit.get("collider") as Node
		if body == null or not (body is Node3D) or not _is_cone_body(body):
			continue
		var away: Vector3 = out - (body as Node3D).global_position
		away.y = 0.0
		var dist: float = away.length()
		if dist >= reach:
			continue
		if dist < 0.0001:
			away = Vector3(0.0, 0.0, 1.0)
			dist = 0.0001
		var push_dir := away.normalized()
		# A shove back along the step bounced the car off the same cone every frame.
		if step.length_squared() > 0.0001 and push_dir.dot(step.normalized()) < -0.2:
			var side := Vector3(step.z, 0.0, -step.x).normalized()
			if side.dot(push_dir) < 0.0:
				side = -side
			push_dir = side
		out += push_dir * (reach - dist)
	return out


func _is_cone_body(body: Node) -> bool:
	if body.is_in_group("stack_target") or body.has_method("piece_height"):
		return true
	var parent := body.get_parent()
	return parent != null and parent.is_in_group("stack_target")


func _is_stopped(body: Node) -> bool:
	if body is StaticBody3D:
		return true
	if body is RigidBody3D:
		return (body as RigidBody3D).linear_velocity.length() < 1.3
	var travel: Variant = body.get("travel_velocity")
	if travel is Vector3:
		return (travel as Vector3).length() < 1.3
	return true


func _police_siren() -> AudioStream:
	var clip := load("res://Sounds_Music/police_siren.mp3") as AudioStreamMP3
	if clip == null:
		return _AUDIO.siren()
	clip.loop = true
	return clip


func _feet_on_roof(body: Node) -> bool:
	if not (body is Node3D):
		return false
	var who := body as Node3D
	return who.global_position.y > global_position.y + _box_center.y + _half.y - 0.25


func _is_soft(body: Node) -> bool:
	if body.is_in_group("soul") or body.is_in_group("pedestrian") or body.is_in_group("stack_target") or body.is_in_group("injured"):
		return true
	var parent := body.get_parent()
	return parent != null and parent.has_method("break_from_hit")


func _keep_clear() -> void:
	var soul := get_tree().get_first_node_in_group("soul") as Node3D
	if soul == null or bool(soul.get("ragdoll")):
		return
	_shove_if_inside(self, soul, _half)


func _eject(host: Node3D) -> void:
	var world := host.get_world_3d()
	if world == null:
		return
	var box := BoxShape3D.new()
	box.size = _half * 2.0 + Vector3(0.5, 1.4, 0.5)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = box
	params.transform = _solid_xf(host)
	params.collision_mask = 1
	params.collide_with_bodies = true
	params.collide_with_areas = false
	if host is CollisionObject3D:
		params.exclude = [(host as CollisionObject3D).get_rid()]
	var hits: Array = world.direct_space_state.intersect_shape(params, 12)
	for found in hits:
		var hit: Dictionary = found
		var body := hit.get("collider") as Node3D
		if body != null:
			_shove_if_inside(host, body, _half)


func _solid_xf(host: Node3D) -> Transform3D:
	var shape_node := host.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node != null:
		return Transform3D(shape_node.global_transform.basis, host.global_position + Vector3(0.0, shape_node.position.y, 0.0))
	return host.global_transform


func _shove_if_inside(host: Node3D, body: Node3D, half: Vector3) -> void:
	if body == host or body.is_in_group("vehicle") or body.is_in_group("hitter"):
		return
	if not _is_soft(body):
		return
	if body.is_in_group("soul") and bool(body.get("ragdoll")):
		return
	if body.is_in_group("soul") and body.global_position.y > host.global_position.y + half.y - 0.25:
		return
	var local: Vector3 = _solid_xf(host).affine_inverse() * body.global_position
	if absf(local.x) > half.x + 0.15 or absf(local.z) > half.z + 0.15:
		return
	var use_x := absf(local.x) / maxf(half.x, 0.1) >= absf(local.z) / maxf(half.z, 0.1)
	if use_x:
		var sx: float = 1.0 if local.x >= 0.0 else -1.0
		local.x = sx * (half.x + 0.7)
	else:
		var sz: float = 1.0 if local.z >= 0.0 else -1.0
		local.z = sz * (half.z + 0.7)
	var world: Vector3 = _solid_xf(host) * local
	body.global_position = Vector3(world.x, body.global_position.y, world.z)
	if body is RigidBody3D:
		var rb := body as RigidBody3D
		PhysicsServer3D.body_set_state(rb.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, rb.global_transform)


func _apply_kind() -> void:
	_keep_nose_len()
	var body_mesh := _heading.get_node_or_null("Body") as MeshInstance3D
	var cabin := _heading.get_node_or_null("Cabin") as MeshInstance3D
	if wrecker:
		# Wreckers share this script with kind "car" but keep their own cab mesh.
		_resize_body(Vector3(2.6, 1.25, 1.3), Vector3.ZERO)
		return
	if vehicle_kind == "car" and body_mesh != null:
		body_mesh.visible = false
		if cabin != null:
			cabin.visible = false
		var rig: Node3D = _SedanParts.assemble(_heading, body_color)
		if rig != null:
			var bounds: AABB = _kind_bounds(rig)
			_resize_body(bounds.size, bounds.get_center())
		return
	if body_mesh != null and _KIND_SCENE.has(vehicle_kind):
		_mount_kind_mesh(body_mesh, cabin)
		return
	_apply_box_kind(body_mesh, cabin)


func _keep_nose_len() -> void:
	if vehicle_kind == "bus":
		nose_len = 5.6
	elif vehicle_kind == "truck":
		nose_len = 4.6
	elif vehicle_kind == "fire":
		nose_len = 4.8
	elif vehicle_kind == "van" or vehicle_kind == "ambulance":
		nose_len = 3.9
	elif vehicle_kind == "motorcycle":
		nose_len = 2.2


func _apply_box_kind(body_mesh: MeshInstance3D, cabin: MeshInstance3D) -> void:
	var size := Vector3(2.6, 1.25, 1.3)
	if vehicle_kind == "bus":
		size = Vector3(6.4, 1.7, 1.5)
		_resize_mesh(body_mesh, Vector3(6.2, 1.35, 1.45), Vector3(0.3, 0.1, 0.0))
		_resize_mesh(cabin, Vector3(1.5, 0.7, 1.35), Vector3(-2.2, 0.85, 0.0))
	elif vehicle_kind == "truck":
		size = Vector3(4.8, 1.55, 1.45)
		_resize_mesh(body_mesh, Vector3(2.8, 0.7, 1.4), Vector3(0.7, 0.15, 0.0))
		_resize_mesh(cabin, Vector3(1.5, 1.1, 1.35), Vector3(-1.4, 0.55, 0.0))
	elif vehicle_kind == "fire":
		size = Vector3(5.2, 1.65, 1.5)
		_resize_mesh(body_mesh, Vector3(3.2, 0.9, 1.4), Vector3(0.6, 0.25, 0.0))
		_resize_mesh(cabin, Vector3(1.6, 1.15, 1.4), Vector3(-1.5, 0.6, 0.0))
		_bar(Color(0.9, 0.15, 0.1), Vector3(0.4, 1.15, 0.0), Vector3(2.4, 0.12, 0.12))
	elif vehicle_kind == "van" or vehicle_kind == "ambulance":
		size = Vector3(3.3, 1.55, 1.4)
		_resize_mesh(body_mesh, Vector3(3.1, 1.2, 1.35), Vector3(0.1, 0.2, 0.0))
		_resize_mesh(cabin, Vector3(1.2, 0.45, 1.25), Vector3(-0.9, 0.85, 0.0))
		if vehicle_kind == "ambulance":
			_bar(Color(0.85, 0.12, 0.1), Vector3(0.2, 0.95, 0.0), Vector3(0.7, 0.16, 0.16))
	elif vehicle_kind == "motorcycle":
		size = Vector3(1.7, 0.9, 0.55)
		_resize_mesh(body_mesh, Vector3(1.5, 0.35, 0.28), Vector3(0.0, 0.15, 0.0))
		if cabin != null:
			cabin.visible = false
	_resize_body(size, Vector3.ZERO)


# Hood of every fleet mesh is local -X, the same nose the box cars use.
func _mount_kind_mesh(body_mesh: MeshInstance3D, cabin: MeshInstance3D) -> void:
	if body_mesh != null:
		body_mesh.visible = false
	if cabin != null:
		cabin.visible = false
	var packed: PackedScene = _KIND_SCENE[vehicle_kind] as PackedScene
	if packed == null:
		return
	var rig: Node3D = packed.instantiate() as Node3D
	if rig == null:
		return
	rig.name = "KindMesh"
	_heading.add_child(rig)
	var bounds: AABB = _kind_bounds(rig)
	_resize_body(bounds.size, bounds.get_center())


func _kind_bounds(root: Node3D) -> AABB:
	var merged: AABB = AABB()
	var started := false
	var pending: Array[Node] = [root]
	while pending.size() > 0:
		var node: Node = pending.pop_back()
		var child_count: int = node.get_child_count()
		for index in child_count:
			pending.append(node.get_child(index))
		if node is MeshInstance3D:
			var mesh_node := node as MeshInstance3D
			var box: AABB = mesh_node.get_aabb()
			var to_heading: Transform3D = _transform_under_heading(mesh_node)
			var corner_i := 0
			while corner_i < 8:
				var local := Vector3(
					box.position.x + box.size.x * float(corner_i & 1),
					box.position.y + box.size.y * float((corner_i >> 1) & 1),
					box.position.z + box.size.z * float((corner_i >> 2) & 1)
				)
				var point: Vector3 = to_heading * local
				if not started:
					merged = AABB(point, Vector3.ZERO)
					started = true
				else:
					merged = merged.expand(point)
				corner_i += 1
	if not started:
		return AABB(Vector3(-1.3, -0.62, -0.65), Vector3(2.6, 1.25, 1.3))
	return merged


func _transform_under_heading(mesh_node: Node3D) -> Transform3D:
	var xf: Transform3D = Transform3D.IDENTITY
	var cursor: Node = mesh_node
	while cursor != null and cursor != _heading:
		if cursor is Node3D:
			xf = (cursor as Node3D).transform * xf
		cursor = cursor.get_parent()
	return xf


func _resize_body(size: Vector3, center: Vector3) -> void:
	_half = size * 0.5
	_box_center = Vector3(0.0, center.y, 0.0)
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node != null and shape_node.shape is BoxShape3D:
		var box := shape_node.shape.duplicate() as BoxShape3D
		box.size = size
		shape_node.shape = box
		shape_node.position = _box_center
	var area := get_node_or_null("HitArea/CollisionShape3D") as CollisionShape3D
	if area != null and area.shape is BoxShape3D:
		var hitbox := area.shape.duplicate() as BoxShape3D
		hitbox.size = size + Vector3(0.3, 0.2, 0.25)
		area.shape = hitbox
		area.position = _box_center


func _resize_mesh(mesh: MeshInstance3D, size: Vector3, at: Vector3) -> void:
	if mesh == null or not (mesh.mesh is BoxMesh):
		return
	var box := mesh.mesh.duplicate() as BoxMesh
	box.size = size
	mesh.mesh = box
	mesh.position = at


func _bar(color: Color, at: Vector3, size: Vector3) -> void:
	if _heading == null:
		return
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.6
	mesh.material_override = mat
	_heading.add_child(mesh)


func _add_sounds() -> void:
	_engine = AudioStreamPlayer3D.new()
	_engine.stream = _AUDIO.engine()
	_engine.volume_db = -24.0
	_engine.max_distance = 32.0
	_engine.unit_size = 7.0
	_engine.autoplay = true
	add_child(_engine)
	if code_three:
		_siren = AudioStreamPlayer3D.new()
		if vehicle_kind == "police":
			_siren.stream = _police_siren()
		else:
			_siren.stream = _AUDIO.siren()
		_siren.volume_db = -12.0
		_siren.max_distance = 90.0
		_siren.unit_size = 12.0
		_siren.autoplay = true
		_siren.finished.connect(_siren.play)
		add_child(_siren)


func _hum() -> void:
	if _engine == null:
		return
	var pace: float = clampf(travel_velocity.length() / maxf(speed, 0.1), 0.2, 1.35)
	_engine.pitch_scale = 0.7 + pace * 0.65
	_engine.volume_db = -26.0 + pace * 6.0
