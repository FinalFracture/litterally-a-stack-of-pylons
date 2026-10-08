extends Node3D

const WHEEL_R := 0.32
const DOOR_OPEN := 0.95
const DOOR_RATE := 2.2
const STILL_BEFORE_OPEN := 0.45

var paint_material: ShaderMaterial
var _car: AnimatableBody3D
var _sun: Node
var _wheels: Array[Node3D] = []
var _axles: Array[Node3D] = []
var _doors: Array[Node3D] = []
var _door_amount: Array[float] = []
var _head_lights: Array[Light3D] = []
var _tail_lights: Array[Light3D] = []
var _blink_left: Array[Light3D] = []
var _blink_right: Array[Light3D] = []
var _head_mats: Array[StandardMaterial3D] = []
var _tail_mats: Array[StandardMaterial3D] = []
var _blink_left_mats: Array[StandardMaterial3D] = []
var _blink_right_mats: Array[StandardMaterial3D] = []
var _prev_yaw := 0.0
var _have_yaw := false
var _blink_time := 0.0
var _still := 0.0


func bind(paint: ShaderMaterial) -> void:
	paint_material = paint
	var heading: Node3D = get_parent() as Node3D
	if heading != null:
		_car = heading.get_parent() as AnimatableBody3D
	var scene: Node = get_tree().current_scene
	if scene != null:
		_sun = scene.get_node_or_null("DirectionalLight3D")
	_collect(self)


func set_paint(color: Color) -> void:
	if paint_material == null:
		return
	paint_material.set_shader_parameter("paint_color", color)


func _collect(node: Node) -> void:
	if node != self:
		if node.is_in_group("sedan_wheel") and node is Node3D:
			_wheels.append(node as Node3D)
		elif node.is_in_group("sedan_axle") and node is Node3D:
			_axles.append(node as Node3D)
		elif node.is_in_group("sedan_door") and node is Node3D:
			_doors.append(node as Node3D)
			_door_amount.append(0.0)
	for child in node.get_children():
		if child is Light3D and (child.name == "Glow" or child.name == "Beam"):
			_take_light(child as Light3D)
		_collect(child)


func _take_light(light: Light3D) -> void:
	var role := ""
	if light.has_meta("lamp_role"):
		role = str(light.get_meta("lamp_role"))
	elif light.get_parent() is Node and (light.get_parent() as Node).get_node_or_null("Glow") is OmniLight3D:
		var glow: OmniLight3D = (light.get_parent() as Node).get_node("Glow") as OmniLight3D
		if glow.has_meta("lamp_role"):
			role = str(glow.get_meta("lamp_role"))
	var mat: StandardMaterial3D = null
	if light.has_meta("lamp_mat"):
		mat = light.get_meta("lamp_mat") as StandardMaterial3D
	elif light.get_parent() is Node:
		var sibling: Node = (light.get_parent() as Node).get_node_or_null("Glow")
		if sibling is OmniLight3D and sibling.has_meta("lamp_mat"):
			mat = sibling.get_meta("lamp_mat") as StandardMaterial3D
	if role == "head":
		_head_lights.append(light)
		if mat != null and not _head_mats.has(mat):
			_head_mats.append(mat)
	elif role == "tail":
		_tail_lights.append(light)
		if mat != null and not _tail_mats.has(mat):
			_tail_mats.append(mat)
	elif role == "blink_l":
		_blink_left.append(light)
		if mat != null and not _blink_left_mats.has(mat):
			_blink_left_mats.append(mat)
	elif role == "blink_r":
		_blink_right.append(light)
		if mat != null and not _blink_right_mats.has(mat):
			_blink_right_mats.append(mat)


func _physics_process(delta: float) -> void:
	if _car == null:
		var heading: Node3D = get_parent() as Node3D
		if heading != null:
			_car = heading.get_parent() as AnimatableBody3D
	_spin(delta)
	_doors_for(delta)
	_lamps(delta)


func _spin(delta: float) -> void:
	if _car == null:
		return
	var heading: Node3D = get_parent() as Node3D
	if heading == null:
		return
	var nose: Vector3 = -heading.global_transform.basis.x
	if nose.length_squared() < 0.0001:
		return
	nose = nose.normalized()
	var along: float = _car.travel_velocity.dot(nose)
	var turn: float = along / WHEEL_R * delta
	for wheel in _wheels:
		wheel.rotation.z += turn
	for axle in _axles:
		axle.rotation.z += turn


func _doors_for(delta: float) -> void:
	var pace: float = 0.0
	if _car != null:
		pace = _car.travel_velocity.length()
	if pace < 0.35:
		_still += delta
	else:
		_still = 0.0
	var open_front: bool = _still >= STILL_BEFORE_OPEN
	for index in _doors.size():
		var door: Node3D = _doors[index]
		var target: float = 0.0
		if open_front and String(door.name).begins_with("DoorF"):
			target = DOOR_OPEN
		var amount: float = move_toward(_door_amount[index], target, DOOR_RATE * delta)
		_door_amount[index] = amount
		var side: float = door.scale.z
		door.rotation.y = -amount * side


func _lamps(delta: float) -> void:
	var night: bool = _night()
	var head_energy: float = 1.5 if night else 0.0
	var tail_energy: float = 0.65 if night else 0.0
	_set_energy(_head_lights, head_energy)
	_set_mats(_head_mats, 1.8 if night else 0.0)
	_set_energy(_tail_lights, tail_energy)
	_set_mats(_tail_mats, 1.3 if night else 0.0)
	var heading: Node3D = get_parent() as Node3D
	var rate: float = 0.0
	if heading != null:
		var yaw: float = heading.rotation.y
		if _have_yaw:
			rate = angle_difference(_prev_yaw, yaw) / maxf(delta, 0.0001)
		_prev_yaw = yaw
		_have_yaw = true
	_blink_time += delta
	var flash: bool = night and fmod(_blink_time, 0.7) < 0.35
	var left_on: bool = flash and rate < -0.18
	var right_on: bool = flash and rate > 0.18
	_set_energy(_blink_left, 1.6 if left_on else 0.0)
	_set_energy(_blink_right, 1.6 if right_on else 0.0)
	_set_mats(_blink_left_mats, 2.2 if left_on else 0.0)
	_set_mats(_blink_right_mats, 2.2 if right_on else 0.0)


func _night() -> bool:
	if _sun != null and _sun.has_method("sun_up"):
		return not bool(_sun.call("sun_up"))
	return false


func _set_energy(lights: Array[Light3D], energy: float) -> void:
	for light in lights:
		light.light_energy = energy


func _set_mats(mats: Array[StandardMaterial3D], energy: float) -> void:
	for mat in mats:
		mat.emission_energy_multiplier = energy
