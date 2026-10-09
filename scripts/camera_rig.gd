extends Node3D

const BOOM_BASE := 2.4
const BOOM_PER_M := 0.55
const LOOK_BIAS := 0.08
const SPRING_MARGIN := 0.3
const MOUSE_SENS := 0.003
const PITCH_MIN := 0.15
const PITCH_MAX := 1.2
# Keyboard look (only with PYLONS_KEYMOUSE=1 or --keymouse), radians per second.
const KEY_YAW_SPEED := 2.2
const KEY_PITCH_SPEED := 1.3

@export var target_path: NodePath

var _target: Node3D
var _camera: Camera3D
var _yaw := 0.0
var _pitch := atan(1.25 / 2.4)


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	_camera = get_node_or_null("Camera3D") as Camera3D
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_place()


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Mouse right turns the view right. Mouse up still looks up.
		_yaw -= motion.relative.x * MOUSE_SENS
		_pitch = clampf(_pitch + motion.relative.y * MOUSE_SENS, PITCH_MIN, PITCH_MAX)


func _physics_process(_delta: float) -> void:
	_place()


func _process(delta: float) -> void:
	if LaunchConfig.keymouse_on() and not get_tree().paused:
		_key_look(delta)
	_place()


func _key_look(delta: float) -> void:
	# Same sense as the mouse: right turns the view right, up looks up.
	var turn := Input.get_axis("km_look_left", "km_look_right")
	var tilt := Input.get_axis("km_look_down", "km_look_up")
	_yaw -= turn * KEY_YAW_SPEED * delta
	_pitch = clampf(_pitch + tilt * KEY_PITCH_SPEED * delta, PITCH_MIN, PITCH_MAX)


func snap() -> void:
	_place()


func look_toward(at: Vector3) -> void:
	if _target == null:
		return
	var from := _target.global_position
	var flat := Vector2(from.x - at.x, from.z - at.z)
	if flat.length_squared() < 0.04:
		return
	flat = flat.normalized()
	_yaw = atan2(flat.x, flat.y)
	_pitch = 0.42
	_place()


func _column_height() -> float:
	if _target != null:
		var stack := _target.get_node_or_null("StackController")
		if stack != null and stack.has_method("get_stack_height"):
			return float(stack.get_stack_height())
	return GameConstants.STANDARD_H


func _place() -> void:
	if _target == null or _camera == null:
		return
	var column_h := _column_height()
	var look := _target.global_position + Vector3(0.0, column_h * 0.5 + LOOK_BIAS, 0.0)
	var boom := BOOM_BASE + BOOM_PER_M * column_h
	var offset := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * boom
	var desired := look + offset
	var cam_pos := desired
	if not _hit_camera():
		cam_pos = _spring(look, desired)
	if cam_pos.distance_squared_to(look) < 0.04:
		cam_pos = look + offset.normalized() * 0.4
	global_position = cam_pos
	_camera.position = Vector3.ZERO
	_camera.look_at(look, Vector3.UP)


func _hit_camera() -> bool:
	if _target != null and _target.get("ragdoll") == true:
		return true
	var tree := get_tree()
	if tree == null:
		return false
	return tree.get_first_node_in_group("hit_tumble") != null


func _spring(look: Vector3, desired: Vector3) -> Vector3:
	var world := get_world_3d()
	if world == null:
		return desired
	var to_cam := desired - look
	if to_cam.length_squared() < 0.0001:
		return desired
	var origin := look + to_cam.normalized() * 0.15
	var query := PhysicsRayQueryParameters3D.create(origin, desired)
	query.collide_with_areas = false
	query.collision_mask = 5
	if _target is CollisionObject3D:
		query.exclude = [(_target as CollisionObject3D).get_rid()]
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return desired
	return hit.position + (look - desired).normalized() * SPRING_MARGIN
