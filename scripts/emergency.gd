extends Node

const Y := 0.65
const BAY := Vector3(-248.2, 0.65, 40.0)

var _busy := false
var _phase := "idle"
var _wait := 0.0
var _units: Array[Node3D]
var _hurt: Node3D
var _gurney: Node3D
var _medics: Array[Node3D]
var _crash := Vector3.ZERO
var _phase_time: float = 0.0


func _ready() -> void:
	add_to_group("dispatch")


func note_crash(at: Vector3) -> void:
	if _busy:
		return
	_busy = true
	_crash = at
	_phase = "enroute"
	_wait = 0.0
	_phase_time = 0.0
	_hurt = _nearest_hurt(at)
	var traffic: Node = get_tree().get_first_node_in_group("traffic")
	if traffic == null or not traffic.has_method("spawn_unit"):
		_busy = false
		return
	var police: Node3D = traffic.call("spawn_unit", "CrewPolice", "police", Color(0.1, 0.16, 0.42), Vector3(81.8, Y, 36.0), 11.0) as Node3D
	var fire: Node3D = traffic.call("spawn_unit", "CrewFire", "fire", Color(0.75, 0.12, 0.08), Vector3(-248.2, Y, 22.0), 10.0) as Node3D
	var ambulance: Node3D = traffic.call("spawn_unit", "CrewAmbulance", "ambulance", Color(0.9, 0.9, 0.88), Vector3(-248.2, Y, 52.0), 12.0) as Node3D
	_units.clear()
	_units.append(police)
	_units.append(fire)
	_units.append(ambulance)
	police.call("set_drive", _route(police.global_position, at + Vector3(8.0, 0.0, 4.0)))
	fire.call("set_drive", _route(fire.global_position, at + Vector3(-8.0, 0.0, 4.0)))
	ambulance.call("set_drive", _route(ambulance.global_position, at + Vector3(0.0, 0.0, 8.0)))


func _process(delta: float) -> void:
	if not _busy:
		return
	_phase_time += delta
	if _phase == "enroute":
		if _arrived():
			_hold(true)
			_phase = "scene"
			_phase_time = 0.0
			_wait = 0.0
			if _hurt != null and is_instance_valid(_hurt):
				_begin_load()
			else:
				_wait = 0.0
				_phase = "leave"
		elif _phase_time > 36.0:
			_finish()
			return
	elif _phase == "scene":
		_wait += delta
		_step_load(delta)
		if _wait > 7.5:
			_load_patient()
			_phase = "hospital"
			_phase_time = 0.0
			_send_home()
	elif _phase == "leave":
		_wait += delta
		if _wait > 4.0:
			_send_home()
			_phase = "hospital"
			_phase_time = 0.0
	elif _phase == "hospital":
		var ambulance := _unit(2)
		if ambulance == null or ambulance.global_position.distance_to(BAY) < 6.0 or _phase_time > 36.0:
			_finish()


func _begin_load() -> void:
	var ambulance := _unit(2)
	if ambulance == null:
		return
	_gurney = _gurney_mesh(ambulance.global_position + Vector3(1.6, 0.0, 0.4))
	var medic_a := _medic(_gurney.global_position + Vector3(-0.6, 0.0, 0.4), Color(0.85, 0.88, 0.9))
	var medic_b := _medic(_gurney.global_position + Vector3(0.6, 0.0, -0.4), Color(0.75, 0.82, 0.8))
	_medics.clear()
	_medics.append(medic_a)
	_medics.append(medic_b)


func _step_load(delta: float) -> void:
	if _gurney == null or _hurt == null or not is_instance_valid(_hurt):
		return
	var goal := _hurt.global_position
	goal.y = 0.35
	_gurney.global_position = _gurney.global_position.move_toward(goal, 2.2 * delta)
	for medic in _medics:
		if medic == null:
			continue
		var side: float = 0.7 if medic == _medics[0] else -0.7
		var beside := goal + Vector3(side, 0.0, 0.0)
		medic.global_position = medic.global_position.move_toward(beside + Vector3(0.0, 0.9, 0.0), 2.4 * delta)


func _load_patient() -> void:
	var ambulance := _unit(2)
	if ambulance == null or _hurt == null or not is_instance_valid(_hurt):
		_free_crew_props()
		return
	if _hurt is RigidBody3D:
		(_hurt as RigidBody3D).freeze = true
	if _hurt is CollisionObject3D:
		(_hurt as CollisionObject3D).collision_layer = 0
		(_hurt as CollisionObject3D).collision_mask = 0
	_hurt.reparent(ambulance)
	_hurt.position = Vector3(0.4, 0.4, 0.0)
	_hurt.visible = false
	if _gurney != null:
		_gurney.reparent(ambulance)
		_gurney.visible = false
	for medic in _medics:
		if medic != null:
			medic.reparent(ambulance)
			medic.visible = false


func _send_home() -> void:
	_hold(false)
	var police := _unit(0)
	var fire := _unit(1)
	var ambulance := _unit(2)
	if police != null:
		police.call("set_drive", _route(police.global_position, Vector3(81.8, Y, 70.0)))
	if fire != null:
		fire.call("set_drive", _route(fire.global_position, Vector3(-248.2, Y, 70.0)))
	if ambulance != null:
		ambulance.call("set_drive", _route(ambulance.global_position, BAY))


func _finish() -> void:
	_free_crew_props()
	for unit in _units:
		if unit != null and is_instance_valid(unit):
			unit.queue_free()
	_units.clear()
	_hurt = null
	_busy = false
	_phase = "idle"


func _free_crew_props() -> void:
	if _gurney != null and is_instance_valid(_gurney) and _gurney.get_parent() == self:
		_gurney.queue_free()
	_gurney = null
	for medic in _medics:
		if medic != null and is_instance_valid(medic) and medic.get_parent() == self:
			medic.queue_free()
	_medics.clear()


func _arrived() -> bool:
	for unit in _units:
		if unit == null or not is_instance_valid(unit):
			continue
		if unit.global_position.distance_to(_crash) > 18.0:
			return false
	return not _units.is_empty()


func _hold(parked: bool) -> void:
	for unit in _units:
		if unit != null and is_instance_valid(unit):
			unit.set("held", parked)


func _unit(index: int) -> Node3D:
	if index >= _units.size():
		return null
	var unit := _units[index]
	if unit == null or not is_instance_valid(unit):
		return null
	return unit


func _nearest_hurt(at: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := 28.0
	for node in get_tree().get_nodes_in_group("injured"):
		if not (node is Node3D):
			continue
		var body := node as Node3D
		var gap: float = Vector2(body.global_position.x - at.x, body.global_position.z - at.z).length()
		if gap < best_d:
			best_d = gap
			best = body
	return best


func _medic(at: Vector3, coat: Color) -> Node3D:
	var body := Node3D.new()
	body.position = at
	add_child(body)
	var mesh := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.22
	cap.height = 1.5
	mesh.mesh = cap
	mesh.position = Vector3(0.0, 0.75, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = coat
	mesh.material_override = mat
	body.add_child(mesh)
	return body


func _gurney_mesh(at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = at
	add_child(root)
	var bed := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.55, 0.08, 1.7)
	bed.mesh = box
	bed.position = Vector3(0.0, 0.55, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.82, 0.84, 0.86)
	bed.material_override = mat
	root.add_child(bed)
	var leg := MeshInstance3D.new()
	var post := BoxMesh.new()
	post.size = Vector3(0.5, 0.5, 0.08)
	leg.mesh = post
	leg.position = Vector3(0.0, 0.28, 0.5)
	leg.material_override = mat
	root.add_child(leg)
	return root


func _route(a: Vector3, b: Vector3) -> PackedVector3Array:
	var traffic: Node = get_tree().get_first_node_in_group("traffic")
	if traffic != null and traffic.has_method("road_path"):
		return traffic.call("road_path", a, b)
	var start := _snap(a)
	var goal := _snap(b)
	var out := PackedVector3Array()
	out.append(start)
	if _same_road(start, goal):
		out.append(goal)
		return _bridge_safe(out)
	var corner := Vector3(start.x, Y, goal.z)
	if _crosses_river(start, corner) or _crosses_river(corner, goal):
		corner = Vector3(goal.x, Y, start.z)
	out.append(corner)
	out.append(goal)
	return _bridge_safe(out)


func _bridge_safe(points: PackedVector3Array) -> PackedVector3Array:
	var safe := PackedVector3Array()
	for i in range(points.size() - 1):
		safe.append(points[i])
		if _crosses_river(points[i], points[i + 1]):
			safe.append(Vector3(points[i].x, Y, 2.2))
			safe.append(Vector3(points[i + 1].x, Y, 2.2))
	if points.size() > 0:
		safe.append(points[points.size() - 1])
	return safe


func _same_road(a: Vector3, b: Vector3) -> bool:
	return absf(a.x - b.x) < 2.0 or absf(a.z - b.z) < 2.0


func _crosses_river(a: Vector3, b: Vector3) -> bool:
	if absf(a.z) < 8.0 and absf(b.z) < 8.0:
		return false
	var lo: float = minf(a.x, b.x)
	var hi: float = maxf(a.x, b.x)
	return lo < -260.0 and hi > -340.0


func _snap(p: Vector3) -> Vector3:
	var best := Vector3(2.2, Y, p.z)
	var best_d := absf(p.x - 2.2)
	var bridge := Vector3(p.x, Y, 2.2)
	var bridge_d := absf(p.z - 2.2)
	if bridge_d < best_d:
		best = bridge
		best_d = bridge_d
	var xs: Array[float] = [-450.0, -360.0, -250.0, -160.0, -80.0, 80.0, 160.0, 250.0, 340.0, 430.0]
	var zs: Array[float] = [-450.0, -360.0, -270.0, -180.0, -90.0, 90.0, 180.0, 270.0, 360.0, 450.0]
	for x in xs:
		var lane: float = x + 1.7
		var d: float = absf(p.x - lane)
		if d < best_d and not (lane > -340.0 and lane < -260.0):
			best = Vector3(lane, Y, p.z)
			best_d = d
	for z in zs:
		var lane_z: float = z + 1.7
		var dz: float = absf(p.z - lane_z)
		if dz < best_d:
			best = Vector3(p.x, Y, lane_z)
			best_d = dz
	if best.x > -340.0 and best.x < -260.0 and absf(best.z) > 8.0:
		best.x = -248.2
	return best
