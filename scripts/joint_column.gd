extends Node3D

const CLEAR_SKIN := 0.5
const TUMBLE_SLOW := 0.85

var _body: RigidBody3D
var _split := false
var _loose: Array[RigidBody3D] = []
var _hitter: CollisionObject3D
var _tumble_until := 0
var _tumble_cap := 0


func build(pieces: Array, parent: Node) -> void:
	parent.add_child(self)
	_body = RigidBody3D.new()
	_body.add_to_group("stack_target")
	_body.collision_layer = 1
	_body.collision_mask = 1
	_body.mass = 0.6 * float(pieces.size())
	_body.linear_damp = 0.6
	_body.angular_damp = 1.2
	_body.continuous_cd = true
	_body.lock_rotation = false
	add_child(_body)
	var anchor := pieces[0] as Node3D
	_body.global_transform = anchor.global_transform
	for piece in pieces:
		var mesh_piece := piece as Node3D
		var mesh := mesh_piece.get_node_or_null("ConeMesh") as MeshInstance3D
		if mesh != null:
			mesh.scale = Vector3.ONE
			mesh.position = Vector3.ZERO
		mesh_piece.reparent(_body, true)
	_body.sleeping = false


func _loose_piece(piece: Node3D, fling: Vector3, hitter: Node, nudge: Vector3) -> RigidBody3D:
	var loose := RigidBody3D.new()
	loose.add_to_group("stack_target")
	loose.collision_layer = 1
	loose.collision_mask = 1
	loose.mass = 0.55
	loose.linear_damp = 0.05
	loose.angular_damp = 0.4
	loose.continuous_cd = true
	loose.lock_rotation = false
	add_child(loose)
	loose.global_transform = piece.global_transform
	piece.reparent(loose, true)
	detach_from_hitter(loose, piece, hitter, fling)
	loose.global_position += nudge
	loose.sleeping = false
	loose.linear_velocity = fling
	loose.angular_velocity = Vector3(3.0, 1.4, 2.2)
	commit_motion(loose)
	return loose


func bodies() -> Array[RigidBody3D]:
	var found: Array[RigidBody3D] = []
	if _body != null and is_instance_valid(_body):
		found.append(_body)
	return found


func _physics_process(_delta: float) -> void:
	if _split:
		_watch_tumble()
		return
	if _body == null or not is_instance_valid(_body):
		return
	var upright := _body.global_basis.y.normalized().dot(Vector3.UP)
	if upright < 0.45:
		var shove := _body.linear_velocity
		if shove.length() < 1.0:
			shove = Vector3(1.5, 0.0, 0.0)
		break_from_hit(shove)


func break_from_hit(travel: Vector3, hitter: Node = null) -> void:
	if _split or _body == null or not is_instance_valid(_body):
		return
	var min_speed: float = 2.5 if hitter != null else 1.0
	if travel.length() < min_speed:
		return
	_split = true
	var push := Vector3(travel.x, 0.0, travel.z)
	if push.length_squared() < 0.0001:
		push = Vector3(1.0, 0.0, 0.0)
	push = push.normalized()
	var speed := minf(travel.length(), 8.0)
	var parts: Array[Node3D] = []
	for child in _body.get_children():
		if child.has_method("piece_height") and child is Node3D:
			parts.append(child)
	parts.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.position.y < b.position.y)
	_body.collision_layer = 0
	_body.collision_mask = 0
	_body.linear_velocity = Vector3.ZERO
	_body.angular_velocity = Vector3.ZERO
	for i in parts.size():
		var fling := hit_fling(push, speed, i)
		var loose := _loose_piece(parts[i], fling, hitter, push * (0.32 * float(i)))
		_loose.append(loose)
	_body.queue_free()
	_body = null
	if hitter is CollisionObject3D:
		_hitter = hitter as CollisionObject3D
		add_to_group("hit_tumble")
		_tumble_until = Time.get_ticks_msec() + 900
		_tumble_cap = Time.get_ticks_msec() + 4000


func _watch_tumble() -> void:
	if not is_in_group("hit_tumble"):
		return
	var now := Time.get_ticks_msec()
	if now < _tumble_until:
		return
	var moving := false
	if now < _tumble_cap:
		for body in _loose:
			if is_instance_valid(body) and body.linear_velocity.length() >= TUMBLE_SLOW:
				moving = true
				break
	if moving:
		return
	if _hitter != null and is_instance_valid(_hitter):
		for body in _loose:
			if not is_instance_valid(body):
				continue
			body.remove_collision_exception_with(_hitter)
			_hitter.remove_collision_exception_with(body)
	_hitter = null
	remove_from_group("hit_tumble")


static func hit_fling(push: Vector3, speed: float, index: int) -> Vector3:
	var side := Vector3(-push.z, 0.0, push.x)
	var sign: float = 1.0 if (index % 2) == 0 else -1.0
	var side_speed: float = sign * (2.05 + 0.38 * float(index))
	var lift: float = 1.7 + 0.3 * float(index)
	return push * speed + side * side_speed + Vector3.UP * lift


# A kinematic mover shoves every body that still overlaps it, including bodies spawned this frame.
static func detach_from_hitter(body: RigidBody3D, piece: Node3D, hitter: Node, push: Vector3) -> void:
	if not (hitter is CollisionObject3D):
		return
	var mover := hitter as CollisionObject3D
	body.add_collision_exception_with(mover)
	mover.add_collision_exception_with(body)
	var radius: float = _piece_radius(piece)
	var away := Vector3(push.x, 0.0, push.z)
	if away.length_squared() < 0.0001:
		away = Vector3(1.0, 0.0, 0.0)
	away = away.normalized()
	var box := _solid_aabb(mover)
	body.global_position = _past_leading_face(body.global_position, radius, box, away)


static func commit_motion(body: RigidBody3D) -> void:
	var rid := body.get_rid()
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, body.linear_velocity)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, body.angular_velocity)


static func _piece_radius(piece: Node3D) -> float:
	var shape_node := piece as CollisionShape3D
	if shape_node != null and shape_node.shape is CylinderShape3D:
		return (shape_node.shape as CylinderShape3D).radius
	return GameConstants.BASE_R


static func _solid_aabb(hitter: Node3D) -> AABB:
	var found := false
	var box := AABB()
	for child in hitter.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null or not (shape_node.shape is BoxShape3D):
			continue
		var solid := shape_node.shape as BoxShape3D
		var half := solid.size * 0.5
		var xf := shape_node.global_transform
		var signs: Array[float] = [-1.0, 1.0]
		for sx in signs:
			for sy in signs:
				for sz in signs:
					var corner: Vector3 = xf * Vector3(half.x * sx, half.y * sy, half.z * sz)
					if not found:
						box = AABB(corner, Vector3.ZERO)
						found = true
					else:
						box = box.expand(corner)
	return box


static func _past_leading_face(center: Vector3, radius: float, box: AABB, push: Vector3) -> Vector3:
	if box.size.length_squared() < 0.0001:
		return center
	var dir := Vector3(push.x, 0.0, push.z)
	if dir.length_squared() < 0.0001:
		dir = Vector3(1.0, 0.0, 0.0)
	dir = dir.normalized()
	var end := box.position + box.size
	var face_x: float = end.x if dir.x >= 0.0 else box.position.x
	var face_z: float = end.z if dir.z >= 0.0 else box.position.z
	var lead: float = Vector3(face_x, 0.0, face_z).dot(dir)
	var here: float = Vector3(center.x, 0.0, center.z).dot(dir)
	var want: float = lead + radius + CLEAR_SKIN
	if here >= want:
		return center
	return center + dir * (want - here)
