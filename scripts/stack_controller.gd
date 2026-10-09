extends Node

const _JointColumn := preload("res://scripts/joint_column.gd")
const DROP_SPEED := 1.6
const DROP_SPEED_CAP := 2.0
const DROP_SPIN_CAP := 4.0
const SETTLE_SPEED := 1.5
const HIT_SPEED := 2.5
const HIT_FLING := 1.7

var _soul: CharacterBody3D
var _lock_until_ms := 0
var _airborne := true
var _settle_pieces: Array[Node3D] = []
var _settle_y: Array[float] = []
var _drop_bodies: Array[RigidBody3D] = []
var _drop_until: Array[int] = []
var _drop_kicked: Array[bool] = []
var _drop_velocity: Array[Vector3] = []
var _hit_lock_ms := 0
var _seen_stack := false
var _ragdoll_anchor: RigidBody3D
var _ragdoll_until := 0
var _hit_bodies: Array[RigidBody3D] = []
var _hit_hitter: CollisionObject3D
var _keymouse := false


func _ready() -> void:
	_soul = get_parent() as CharacterBody3D
	_keymouse = LaunchConfig.keymouse_on()


func _physics_process(delta: float) -> void:
	if _soul == null:
		return
	if _ragdoll_anchor != null:
		_follow_ragdoll()
		return
	_clamp_drops()
	_settle(delta)
	# Controls canon (M1): Shift = swap, E = drop the top cone and take control of it,
	# left click = add to stack, right click = drop one. Q and R are unbound; F and X are reserved.
	if Input.is_action_just_pressed("hop_top"):
		_hop_off_top()
	if Input.is_action_just_pressed("soul_transfer"):
		_try_swap()
	if _keymouse:
		# Keyboard stand-ins for left/right click. Registered only with PYLONS_KEYMOUSE=1 or --keymouse.
		if Input.is_action_just_pressed("km_take"):
			_try_pickup()
		if Input.is_action_just_pressed("km_drop"):
			_drop_bottom()
	_soul.hold_column = not _settle_pieces.is_empty() and _soul.global_position.y < 0.25
	_check_slide_hit()
	_check_overhead()
	if not _settle_pieces.is_empty():
		return
	var on_floor := _soul.is_on_floor()
	var landed := _airborne and on_floor
	_airborne = not on_floor
	if not landed:
		return
	for i in _soul.get_slide_collision_count():
		var hit := _soul.get_slide_collision(i)
		var collider := hit.get_collider() as Node
		if collider == null or not collider.is_in_group("stack_target"):
			continue
		var piece := _find_piece(collider)
		if piece == null or not _landed_on_top(hit, piece):
			continue
		_try_stack(collider)
		return


func get_stack_height() -> float:
	var pieces := _pieces()
	if pieces.is_empty():
		return 0.0
	var centers: Array = _centers_for(pieces)
	var last: Node = pieces[pieces.size() - 1]
	return float(centers[centers.size() - 1]) + float(last.piece_height()) * 0.5


func next_drop_name() -> String:
	var pieces: Array = _pieces()
	if pieces.is_empty():
		return "none"
	var top: Node = pieces[pieces.size() - 1]
	var height: float = float(top.piece_height())
	if height > 0.75:
		return "barrel"
	if height < 0.38:
		return "mini"
	return "standard"


func _centers_for(pieces: Array) -> Array:
	# A piece nests only into the same kind below it (standard in standard, mini in mini).
	# Any other pair sits on top, so a mixed stack never sinks below the piece under it
	# or below the ground (REAL-002: a barrel on a cone used to end 0.16 m under ground).
	var centers: Array[float] = []
	var cursor_top := 0.0
	var prev_bottom := 0.0
	for i in pieces.size():
		var piece: Node = pieces[i]
		var height: float = float(piece.piece_height())
		var bottom := 0.0
		if i > 0 and _nests_into(pieces[i - 1], piece):
			bottom = maxf(cursor_top - (height - float(piece.piece_extra())), prev_bottom)
		elif i > 0:
			bottom = cursor_top
		var center: float = bottom + height * 0.5
		centers.append(center)
		cursor_top = bottom + height
		prev_bottom = bottom
	return centers


func _nests_into(below: Node, above: Node) -> bool:
	if not (below.has_method("can_receive_nest") and below.can_receive_nest()):
		return false
	return below.get("piece_type") == above.get("piece_type")


func _landed_on_top(hit: KinematicCollision3D, piece: Node) -> bool:
	if hit.get_normal().dot(Vector3.UP) < 0.85:
		return false
	var top_y: float = piece.global_position.y + float(piece.piece_height()) * 0.5
	return hit.get_position().y >= top_y - 0.06


func _pieces() -> Array:
	var found: Array = []
	for child in _soul.get_children():
		if child.has_method("piece_height"):
			found.append(child)
	found.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.position.y < b.position.y)
	return found


func _try_stack(wrapper: Node) -> void:
	if wrapper == null or not is_instance_valid(wrapper):
		return
	if Time.get_ticks_msec() < _lock_until_ms:
		return
	var piece := _find_piece(wrapper)
	if piece == null or piece.get_parent() == _soul:
		return
	if not piece.is_upright():
		_refuse()
		return
	_attach(piece as Node3D, wrapper, true)


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index != MOUSE_BUTTON_LEFT and button.button_index != MOUSE_BUTTON_RIGHT:
		return
	if _soul == null or _ragdoll_anchor != null or get_tree().paused:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if button.button_index == MOUSE_BUTTON_RIGHT:
		_drop_bottom()
		return
	_try_pickup()


func _try_pickup() -> void:
	if Time.get_ticks_msec() < _lock_until_ms:
		return
	var found: Array = _nearest_adjacent()
	if found.is_empty():
		return
	var wrapper := found[0] as Node
	var pieces: Array = _column_pieces(wrapper)
	if pieces.is_empty():
		return
	for item in pieces:
		var piece := item as Node3D
		if piece == null or not piece.is_upright():
			_refuse()
			return
	_attach_many(pieces, wrapper)


func _column_pieces(wrapper: Node) -> Array:
	var pieces: Array = []
	if wrapper.has_method("piece_height") and wrapper is Node3D and wrapper.get_parent() != _soul:
		pieces.append(wrapper)
	for child in wrapper.get_children():
		if child.has_method("piece_height") and child is Node3D and (child as Node).get_parent() != _soul:
			pieces.append(child)
	pieces.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.position.y < b.position.y)
	return pieces


func _attach_many(pieces: Array, wrapper: Node) -> void:
	var trial: Array = []
	for owned in _pieces():
		trial.append(owned)
	for item in pieces:
		trial.append(item)
	var centers: Array = _centers_for(trial)
	for i in trial.size():
		var item := trial[i] as Node3D
		item.reparent(_soul, false)
		item.position = Vector3(0.0, float(centers[i]), 0.0)
		item.rotation = Vector3.ZERO
	if wrapper != _soul and is_instance_valid(wrapper) and not _has_piece(wrapper):
		if wrapper is CollisionObject3D:
			_soul.remove_collision_exception_with(wrapper)
		wrapper.queue_free()
	_sfx("click")
	if not _seen_stack:
		_seen_stack = true
		_portrait("stack")


func _nearest_adjacent() -> Array:
	var look := _body_facing()
	if look.length_squared() < 0.0001:
		return []
	var best: Node3D = null
	var best_wrap: Node = null
	var best_d := 1.2
	for node in get_tree().get_nodes_in_group("stack_target"):
		if not (node is Node):
			continue
		var wrapper := node as Node
		var candidates: Array = []
		if wrapper.has_method("piece_height") and wrapper is Node3D:
			candidates.append(wrapper)
		for child in wrapper.get_children():
			if child.has_method("piece_height") and child is Node3D:
				candidates.append(child)
		for item in candidates:
			var piece := item as Node3D
			if piece.get_parent() == _soul:
				continue
			var dx: float = piece.global_position.x - _soul.global_position.x
			var dz: float = piece.global_position.z - _soul.global_position.z
			var horiz: float = Vector2(dx, dz).length()
			var feet_y: float = piece.global_position.y - float(piece.piece_height()) * 0.5
			if absf(feet_y - _soul.global_position.y) > 1.15:
				continue
			if horiz > 1.2 or horiz < 0.04:
				continue
			var toward := Vector3(dx, 0.0, dz).normalized()
			if look.dot(toward) < 0.94:
				continue
			if horiz < best_d:
				best_d = horiz
				best = piece
				best_wrap = wrapper
	if best == null:
		return []
	return [best_wrap, best]


func _attach(piece: Node3D, wrapper: Node, on_bottom: bool) -> void:
	var trial: Array = []
	if on_bottom:
		trial.append(piece)
	for owned in _pieces():
		trial.append(owned)
	if not on_bottom:
		trial.append(piece)
	var centers: Array = _centers_for(trial)
	if on_bottom:
		var feet_y: float = piece.global_position.y - float(piece.piece_height()) * 0.5
		_soul.global_position = Vector3(piece.global_position.x, feet_y, piece.global_position.z)
		_soul.velocity = Vector3.ZERO
	for i in trial.size():
		var item := trial[i] as Node3D
		item.reparent(_soul, false)
		item.position = Vector3(0.0, float(centers[i]), 0.0)
		item.rotation = Vector3.ZERO
	if wrapper != _soul and is_instance_valid(wrapper) and not _has_piece(wrapper):
		if wrapper is CollisionObject3D:
			_soul.remove_collision_exception_with(wrapper)
		wrapper.queue_free()
	_sfx("click")
	if not _seen_stack:
		_seen_stack = true
		_portrait("stack")


func _try_swap() -> void:
	var aim := _aim_cone()
	if aim.is_empty():
		_sfx("dull_click")
		return
	var wrapper := aim[0] as Node
	var anchor := aim[1] as Node3D
	var taken := _pieces_from(wrapper, anchor)
	if taken.is_empty():
		_sfx("dull_click")
		return
	var feet_y: float = anchor.global_position.y - float(anchor.piece_height()) * 0.5
	var feet := Vector3(anchor.global_position.x, feet_y, anchor.global_position.z)
	_deposit_column()
	_soul.global_position = feet
	_soul.velocity = Vector3.ZERO
	_pack_onto_soul(taken)
	_release_wrapper(wrapper)
	var rig := _soul.get_parent().get_node_or_null("CameraRig")
	if rig != null and rig.has_method("snap"):
		rig.snap()
	_sfx("thunk")
	_portrait("swap")


func _body_facing() -> Vector3:
	var face := Vector3(-_soul.global_basis.z.x, 0.0, -_soul.global_basis.z.z)
	if face.length_squared() < 0.0004:
		return Vector3.ZERO
	return face.normalized()


func _look_flat() -> Vector3:
	var cam := _soul.get_viewport().get_camera_3d()
	var look := Vector3(0.0, 0.0, -1.0)
	if cam != null:
		look = Vector3(-cam.global_basis.z.x, 0.0, -cam.global_basis.z.z)
	if look.length_squared() < 0.0004:
		return Vector3.ZERO
	return look.normalized()


func _aim_cone() -> Array:
	var world := _soul.get_world_3d()
	if world == null:
		return []
	var dir := Vector3(0.0, 0.0, -1.0)
	var cam := _soul.get_viewport().get_camera_3d()
	if cam != null:
		dir = Vector3(-cam.global_basis.z.x, 0.0, -cam.global_basis.z.z)
	elif _soul.global_basis.z.length_squared() > 0.0001:
		dir = Vector3(-_soul.global_basis.z.x, 0.0, -_soul.global_basis.z.z)
	if dir.length_squared() < 0.0001:
		return []
	dir = dir.normalized()
	var origin := _soul.global_position + Vector3(0.0, 0.28, 0.0)
	var cast := ShapeCast3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.28
	cast.shape = sphere
	cast.target_position = dir * GameConstants.SWAP_RANGE
	cast.collision_mask = 1
	cast.collide_with_areas = false
	cast.collide_with_bodies = true
	_soul.get_parent().add_child(cast)
	cast.global_transform = Transform3D(Basis.IDENTITY, origin)
	cast.add_exception(_soul)
	cast.force_shapecast_update()
	var best: Node = null
	var best_point := Vector3.ZERO
	var best_d := GameConstants.SWAP_RANGE + 1.0
	for i in cast.get_collision_count():
		var collider := cast.get_collider(i) as Node
		if collider == null or not collider.is_in_group("stack_target"):
			continue
		var point := cast.get_collision_point(i)
		var dist := origin.distance_to(point)
		if dist < best_d:
			best_d = dist
			best = collider
			best_point = point
	cast.queue_free()
	if best == null:
		return []
	var anchor := _piece_near(best, best_point.y)
	if anchor == null:
		return []
	return [best, anchor]


func _piece_near(wrapper: Node, hit_y: float) -> Node3D:
	if wrapper.has_method("piece_height") and wrapper is Node3D:
		return wrapper as Node3D
	var best: Node3D = null
	var best_dy := 1000.0
	for child in wrapper.get_children():
		if not child.has_method("piece_height") or not (child is Node3D):
			continue
		var piece := child as Node3D
		var half: float = float(piece.piece_height()) * 0.5
		var center_y: float = piece.global_position.y
		if hit_y >= center_y - half - 0.05 and hit_y <= center_y + half + 0.05:
			return piece
		var dy := absf(center_y - hit_y)
		if best == null or dy < best_dy:
			best = piece
			best_dy = dy
	return best


func _pieces_from(wrapper: Node, anchor: Node3D) -> Array:
	var taken: Array = []
	var floor_y := anchor.position.y - 0.02
	for child in wrapper.get_children():
		if child == anchor or (child.has_method("piece_height") and child is Node3D and (child as Node3D).position.y >= floor_y):
			taken.append(child)
	if taken.is_empty():
		taken.append(anchor)
	taken.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.position.y < b.position.y)
	return taken


func _pack_onto_soul(taken: Array) -> void:
	var centers: Array = _centers_for(taken)
	for i in taken.size():
		var piece := taken[i] as Node3D
		piece.reparent(_soul, false)
		piece.position = Vector3(0.0, float(centers[i]), 0.0)
		piece.rotation = Vector3.ZERO


func _deposit_column() -> void:
	var pieces := _pieces()
	if pieces.is_empty():
		return
	if pieces.size() == 1:
		_spawn_loose(pieces[0] as Node3D, Vector3.ZERO, false)
		return
	var column := _JointColumn.new()
	column.build(pieces, _soul.get_parent())
	for rb in column.bodies():
		_soul.add_collision_exception_with(rb)
		_drop_bodies.append(rb)
		_drop_until.append(Time.get_ticks_msec() + 300)
		_drop_kicked.append(true)
		_drop_velocity.append(Vector3.ZERO)


func _release_wrapper(wrapper: Node) -> void:
	if wrapper == null or wrapper == _soul or not is_instance_valid(wrapper):
		return
	if _has_piece(wrapper):
		return
	if wrapper is CollisionObject3D:
		_soul.remove_collision_exception_with(wrapper)
	wrapper.queue_free()


func _has_piece(wrapper: Node) -> bool:
	if wrapper.has_method("piece_height"):
		return true
	for child in wrapper.get_children():
		if child.has_method("piece_height"):
			return true
	return false


func _facing() -> Vector3:
	var hop := Vector3(-_soul.global_basis.z.x, 0.0, -_soul.global_basis.z.z)
	if hop.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, -1.0)
	return hop.normalized()


func _hop_off_top() -> void:
	var pieces := _pieces()
	if pieces.size() <= 1:
		_sfx("dull_click")
		return
	var top := pieces[pieces.size() - 1] as Node3D
	var feet_y: float = top.global_position.y - float(top.piece_height()) * 0.5
	var feet := Vector3(top.global_position.x, feet_y, top.global_position.z)
	var hop := _facing()
	var holder := Node3D.new()
	_soul.get_parent().add_child(holder)
	top.reparent(holder, true)
	_deposit_column()
	if not _drop_until.is_empty():
		_drop_until[_drop_until.size() - 1] = Time.get_ticks_msec() + 500
	_soul.global_position = feet
	_soul.velocity = hop * 2.2 + Vector3.UP * 3.1
	top.reparent(_soul, false)
	top.position = Vector3(0.0, float(top.piece_height()) * 0.5, 0.0)
	top.rotation = Vector3.ZERO
	holder.queue_free()
	_sfx("thunk")


func _drop_bottom() -> void:
	var pieces := _pieces()
	if pieces.size() <= 1:
		_sfx("dull_click")
		return
	var piece := pieces[0] as Node3D
	_spawn_loose(piece, _drop_back() * DROP_SPEED, true)
	_queue_settle()
	_sfx("thunk")


func receive_hit(travel: Vector3, hitter: Node = null) -> void:
	if _ragdoll_anchor != null:
		return
	if Time.get_ticks_msec() < _hit_lock_ms:
		return
	if travel.length() < HIT_SPEED:
		return
	var push := Vector3(travel.x, 0.0, travel.z)
	if push.length_squared() < 0.0001:
		return
	_hit_lock_ms = Time.get_ticks_msec() + 800
	_shatter(push.normalized(), minf(travel.length(), 8.0), hitter)


func _check_slide_hit() -> void:
	for i in _soul.get_slide_collision_count():
		var hit := _soul.get_slide_collision(i)
		var collider := hit.get_collider() as Node
		if collider == null or not collider.is_in_group("hitter"):
			continue
		if hit.get_normal().dot(Vector3.UP) > 0.65:
			continue
		var travel := Vector3.ZERO
		if "travel_velocity" in collider:
			travel = collider.travel_velocity
		if travel.length() < HIT_SPEED:
			continue
		receive_hit(travel, collider)
		return


func give_top_piece() -> Node3D:
	var pieces := _pieces()
	if pieces.size() < 2:
		return null
	var top := pieces[pieces.size() - 1] as Node3D
	top.reparent(_soul.get_parent(), true)
	_queue_settle()
	return top


func _check_overhead() -> void:
	if _ragdoll_anchor != null:
		return
	if Time.get_ticks_msec() < _hit_lock_ms:
		return
	var height: float = get_stack_height()
	if height < 1.15:
		return
	var world := _soul.get_world_3d()
	if world == null:
		return
	var origin := _soul.global_position + Vector3(0.0, 0.25, 0.0)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3(0.0, height, 0.0))
	query.collision_mask = 1
	query.exclude = [_soul.get_rid()]
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider := hit.get("collider") as Node
	if collider == null or not collider.is_in_group("overhead"):
		return
	var push := Vector3(_soul.velocity.x, 0.0, _soul.velocity.z)
	if push.length() < 0.6:
		push = _look_flat()
	if push.length() < 0.2:
		push = Vector3(0.0, 0.0, -1.0)
	_hit_lock_ms = Time.get_ticks_msec() + 800
	_shatter(push.normalized(), 3.2, collider)


func _shatter(push: Vector3, speed: float, hitter: Node) -> void:
	var pieces := _pieces()
	if pieces.is_empty():
		return
	_soul.collision_layer = 0
	_soul.collision_mask = 0
	_soul.velocity = Vector3.ZERO
	if hitter is CollisionObject3D:
		_hit_hitter = hitter as CollisionObject3D
		_soul.add_collision_exception_with(_hit_hitter)
		_hit_hitter.add_collision_exception_with(_soul)
	_hit_bodies.clear()
	var anchor: RigidBody3D
	for i in pieces.size():
		var fling: Vector3 = _JointColumn.hit_fling(push, speed, i)
		var rb := _make_hit_body(pieces[i] as Node3D, fling, hitter, push * (0.32 * float(i)))
		_hit_bodies.append(rb)
		if i == 0:
			anchor = rb
	_begin_ragdoll(anchor)
	_sfx("knock")
	_portrait("hit")


func _make_hit_body(piece: Node3D, fling: Vector3, hitter: Node, nudge: Vector3) -> RigidBody3D:
	var mesh := piece.get_node_or_null("ConeMesh") as MeshInstance3D
	if mesh != null:
		mesh.scale = Vector3.ONE
		mesh.position = Vector3.ZERO
	var rb := RigidBody3D.new()
	rb.add_to_group("stack_target")
	rb.collision_layer = 1
	rb.collision_mask = 1
	rb.mass = 0.55
	rb.linear_damp = 0.05
	rb.angular_damp = 0.35
	rb.continuous_cd = true
	rb.lock_rotation = false
	_soul.get_parent().add_child(rb)
	rb.global_transform = piece.global_transform
	piece.reparent(rb, true)
	_JointColumn.detach_from_hitter(rb, piece, hitter, fling)
	rb.global_position += nudge
	rb.sleeping = false
	rb.linear_velocity = fling
	rb.angular_velocity = Vector3(2.6, 1.2, 1.8)
	_JointColumn.commit_motion(rb)
	_soul.add_collision_exception_with(rb)
	return rb


func _begin_ragdoll(anchor: RigidBody3D) -> void:
	_ragdoll_anchor = anchor
	_ragdoll_until = Time.get_ticks_msec() + 900
	_soul.ragdoll = true
	_soul.collision_layer = 0
	_soul.collision_mask = 0
	_soul.velocity = Vector3.ZERO
	_follow_ragdoll()


func _follow_ragdoll() -> void:
	if not is_instance_valid(_ragdoll_anchor):
		_end_ragdoll()
		return
	var piece := _piece_on(_ragdoll_anchor)
	if piece == null:
		_end_ragdoll()
		return
	var height: float = float(piece.piece_height())
	_soul.global_position = _ragdoll_anchor.global_position - Vector3(0.0, height * 0.5, 0.0)
	_soul.velocity = Vector3.ZERO
	if _soul.global_position.y < -4.0:
		_end_ragdoll()
		return
	var slow := _ragdoll_anchor.linear_velocity.length() < 0.85
	if Time.get_ticks_msec() > _ragdoll_until and slow:
		_end_ragdoll()


func _end_ragdoll() -> void:
	_soul.ragdoll = false
	_release_hit_exceptions()
	_soul.collision_layer = 1
	_soul.collision_mask = 5
	if is_instance_valid(_ragdoll_anchor):
		var piece := _piece_on(_ragdoll_anchor)
		if piece != null:
			var height: float = float(piece.piece_height())
			var feet := _ragdoll_anchor.global_position - Vector3(0.0, height * 0.5, 0.0)
			piece.reparent(_soul, false)
			piece.position = Vector3(0.0, height * 0.5, 0.0)
			piece.rotation = Vector3.ZERO
			_soul.global_position = feet
		_ragdoll_anchor.queue_free()
	_ragdoll_anchor = null
	_soul.velocity = Vector3.ZERO


func _release_hit_exceptions() -> void:
	var mover := _hit_hitter
	for body in _hit_bodies:
		if not is_instance_valid(body):
			continue
		_soul.remove_collision_exception_with(body)
		if mover != null and is_instance_valid(mover):
			body.remove_collision_exception_with(mover)
			mover.remove_collision_exception_with(body)
	if mover != null and is_instance_valid(mover):
		_soul.remove_collision_exception_with(mover)
		mover.remove_collision_exception_with(_soul)
	_hit_hitter = null
	_hit_bodies.clear()


func _piece_on(body: Node) -> Node3D:
	for child in body.get_children():
		if child.has_method("piece_height") and child is Node3D:
			return child as Node3D
	return null


func _release_chunk(chunk: Array, velocity: Vector3) -> void:
	if chunk.size() == 1:
		_spawn_loose(chunk[0] as Node3D, velocity, false)
		return
	var column := _JointColumn.new()
	column.build(chunk, _soul.get_parent())
	for rb in column.bodies():
		rb.linear_velocity = velocity
		_soul.add_collision_exception_with(rb)
		_drop_bodies.append(rb)
		_drop_until.append(Time.get_ticks_msec() + 450)
		_drop_kicked.append(true)
		_drop_velocity.append(velocity)


func _spawn_loose(piece: Node3D, velocity: Vector3, keep_upright: bool) -> void:
	var mesh := piece.get_node_or_null("ConeMesh") as MeshInstance3D
	if mesh != null:
		mesh.scale = Vector3.ONE
		mesh.position = Vector3.ZERO
	var rb := RigidBody3D.new()
	rb.add_to_group("stack_target")
	rb.collision_layer = 1
	rb.collision_mask = 1
	rb.mass = 0.6
	rb.linear_damp = 1.2
	rb.angular_damp = 2.5
	rb.continuous_cd = true
	rb.lock_rotation = keep_upright
	var parent := _soul.get_parent()
	parent.add_child(rb)
	rb.global_transform = piece.global_transform
	piece.reparent(rb, true)
	rb.can_sleep = false
	rb.sleeping = false
	rb.linear_velocity = velocity
	if not keep_upright:
		rb.angular_velocity = Vector3(1.2, 0.4, 0.2)
	_soul.add_collision_exception_with(rb)
	_drop_bodies.append(rb)
	_drop_until.append(Time.get_ticks_msec() + 450)
	_drop_kicked.append(false)
	_drop_velocity.append(velocity)


func _queue_settle() -> void:
	_settle_pieces.clear()
	_settle_y.clear()
	var pieces := _pieces()
	var centers: Array = _centers_for(pieces)
	for i in pieces.size():
		_settle_pieces.append(pieces[i] as Node3D)
		_settle_y.append(float(centers[i]))


func _settle(delta: float) -> void:
	if _settle_pieces.is_empty():
		return
	var step := SETTLE_SPEED * delta
	var done := true
	for i in _settle_pieces.size():
		var piece := _settle_pieces[i]
		if not is_instance_valid(piece):
			continue
		var dy: float = _settle_y[i] - piece.position.y
		if absf(dy) > 0.001:
			done = false
			piece.position.y += clampf(dy, -step, step)
	if _soul.velocity.y < -3.5:
		_soul.velocity.y = -3.5
	if _soul.velocity.y > 1.5:
		_soul.velocity.y = 1.5
	if done:
		_settle_pieces.clear()
		_settle_y.clear()


func _drop_back() -> Vector3:
	var back := _soul.global_basis.z
	back.y = 0.0
	if back.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, 1.0)
	return back.normalized()


func _clamp_drops() -> void:
	var now := Time.get_ticks_msec()
	var keep_bodies: Array[RigidBody3D] = []
	var keep_until: Array[int] = []
	var keep_kicked: Array[bool] = []
	var keep_velocity: Array[Vector3] = []
	for i in _drop_bodies.size():
		var rb := _drop_bodies[i]
		if not is_instance_valid(rb):
			continue
		if not _drop_kicked[i] and rb.linear_velocity.length() < 0.2:
			rb.sleeping = false
			rb.linear_velocity = _drop_velocity[i]
		if not _drop_kicked[i]:
			_drop_kicked[i] = true
		if rb.linear_velocity.length() > DROP_SPEED_CAP:
			rb.linear_velocity = rb.linear_velocity.limit_length(DROP_SPEED_CAP)
		if rb.angular_velocity.length() > DROP_SPIN_CAP:
			rb.angular_velocity = rb.angular_velocity.limit_length(DROP_SPIN_CAP)
		if now >= _drop_until[i]:
			rb.lock_rotation = false
			rb.can_sleep = true
			_soul.remove_collision_exception_with(rb)
			continue
		keep_bodies.append(rb)
		keep_until.append(_drop_until[i])
		keep_kicked.append(_drop_kicked[i])
		keep_velocity.append(_drop_velocity[i])
	_drop_bodies = keep_bodies
	_drop_until = keep_until
	_drop_kicked = keep_kicked
	_drop_velocity = keep_velocity


func _find_piece(wrapper: Node) -> Node:
	if wrapper.has_method("piece_height"):
		return wrapper
	var best: Node = null
	var best_y := -1000.0
	for child in wrapper.get_children():
		if not child.has_method("piece_height") or not (child is Node3D):
			continue
		var y: float = (child as Node3D).global_position.y
		if best == null or y > best_y:
			best = child
			best_y = y
	return best


func _portrait(_trigger: String) -> void:
	return


func note_respawn() -> void:
	_portrait("respawn")


func _sfx(sound: String) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and _soul != null:
		sfx.call("play_at", sound, _soul.global_position)


func _refuse() -> void:
	_lock_until_ms = Time.get_ticks_msec() + 400
	_sfx("knock")
