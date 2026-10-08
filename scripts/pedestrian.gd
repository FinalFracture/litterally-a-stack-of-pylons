extends CharacterBody3D

@export var from_point := Vector3.ZERO
@export var to_point := Vector3.ZERO
@export var speed := 1.2

var points: PackedVector3Array = PackedVector3Array()
var point_index := 0
var _joined := true
var _toward := true
var _down := false
var _avoid := 0
var _probe: ShapeCast3D


func _ready() -> void:
	add_to_group("pedestrian")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	floor_snap_length = 0.0
	_probe = ShapeCast3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.32
	_probe.shape = sphere
	_probe.collision_mask = 1
	_probe.collide_with_areas = false
	_probe.collide_with_bodies = true
	_probe.enabled = true
	add_child(_probe)
	_probe.top_level = true
	_probe.add_exception(self)


func _physics_process(delta: float) -> void:
	if _down:
		return
	var target: Vector3 = _goal()
	var flat: Vector3 = target - global_position
	flat.y = 0.0
	if flat.length() < 0.4:
		_arrive()
		global_position.y = target.y
		return
	var dir := flat.normalized()
	var wish := _around_cones(dir)
	if wish.length_squared() < 0.01:
		velocity = Vector3.ZERO
		return
	velocity = Vector3(wish.x * speed, 0.0, wish.z * speed)
	move_and_slide()
	global_position.y = move_toward(global_position.y, target.y, delta * 1.4)
	look_at(global_position + wish, Vector3.UP)


func _goal() -> Vector3:
	if points.size() >= 2:
		return points[point_index]
	if _toward:
		return to_point
	return from_point


func _arrive() -> void:
	_avoid = 0
	if points.size() >= 2:
		if not _joined:
			_joined = true
			point_index = 0
			return
		point_index = (point_index + 1) % points.size()
		return
	_toward = not _toward


func _around_cones(dir: Vector3) -> Vector3:
	if not _cone_ahead(dir, 1.15):
		_avoid = 0
		return dir
	var side := Vector3(-dir.z, 0.0, dir.x)
	var left_open := not _cone_ahead((dir - side).normalized(), 1.05) and not _cone_ahead(-side, 0.65)
	var right_open := not _cone_ahead((dir + side).normalized(), 1.05) and not _cone_ahead(side, 0.65)
	if _avoid < 0 and not left_open:
		_avoid = 0
	if _avoid > 0 and not right_open:
		_avoid = 0
	if _avoid == 0:
		if left_open and not right_open:
			_avoid = -1
		elif right_open and not left_open:
			_avoid = 1
		elif left_open and right_open:
			_avoid = -1 if randf() < 0.5 else 1
	if _avoid < 0:
		return (dir * 0.4 - side).normalized()
	if _avoid > 0:
		return (dir * 0.4 + side).normalized()
	return Vector3.ZERO


func _cone_ahead(dir: Vector3, dist: float) -> bool:
	if _probe == null:
		return false
	var feet_y: float = global_position.y - 0.8
	var origin := Vector3(global_position.x, feet_y + 0.36, global_position.z)
	_probe.global_transform = Transform3D(Basis.IDENTITY, origin)
	_probe.target_position = dir * dist
	_probe.force_shapecast_update()
	for i in _probe.get_collision_count():
		var hit := _probe.get_collider(i) as Node
		if hit != null and hit != self and (_is_cone(hit) or _is_solid(hit)):
			return true
	return false


func _is_solid(body: Node) -> bool:
	return body is StaticBody3D and not body.is_in_group("pavement")


func _is_cone(body: Node) -> bool:
	if body.is_in_group("stack_target") or body.has_method("piece_height"):
		return true
	for child in body.get_children():
		if child.has_method("piece_height"):
			return true
	return false


func knock(travel: Vector3, hitter: Node) -> void:
	if _down:
		return
	if travel.length() < 1.2:
		return
	_down = true
	remove_from_group("pedestrian")
	collision_layer = 0
	collision_mask = 0
	var rb := RigidBody3D.new()
	rb.collision_layer = 1
	rb.collision_mask = 1
	rb.mass = 1.1
	rb.linear_damp = 0.2
	rb.angular_damp = 0.45
	rb.continuous_cd = true
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.6
	capsule.radius = 0.28
	shape.shape = capsule
	rb.add_child(shape)
	get_parent().add_child(rb)
	rb.global_transform = global_transform
	for child in get_children():
		if child is MeshInstance3D:
			child.reparent(rb, true)
	var push := Vector3(travel.x, 0.0, travel.z)
	if push.length_squared() < 0.0001:
		push = Vector3(1.0, 0.0, 0.0)
	push = push.normalized()
	var fling: float = minf(travel.length(), 7.0)
	rb.add_to_group("injured")
	rb.linear_velocity = push * fling + Vector3.UP * 1.15
	rb.angular_velocity = Vector3(1.4, 0.5, 1.1)
	if hitter is CollisionObject3D:
		var mover := hitter as CollisionObject3D
		rb.add_collision_exception_with(mover)
		mover.add_collision_exception_with(rb)
	queue_free()
