extends CharacterBody3D

## A lean pedestrian (M2): capsule body, box visuals, no face. Walks a sidewalk path and
## reacts to hits by tier (PHYSICS_SPEC_v1 §1). All tunables live in GameConstants.PED_*.
##
## Every hitter goes through take_hit(source, mass, v_rel_vec, point):
## - cars: hit_cube._deliver_hit (kinematic, so the car's speed drives the contact);
## - loose cones, barrels, flung stack pieces and the soul: this body's sensor Area3D
##   (one small area per pedestrian is cheaper than contact monitoring on every cone).

signal reacted(tier: int, amount: float, source: Node)
signal knocked_down(force: float)

enum { WALK, FLINCH, STUMBLE, DOWN, GETUP, FACE }

@export var from_point := Vector3.ZERO
@export var to_point := Vector3.ZERO
@export var speed := GameConstants.PED_WALK_MPS

var points: PackedVector3Array = PackedVector3Array()
var point_index := 0
var home_chunk := Vector2i.ZERO
var state := WALK
var last_tier := 0
var _joined := true
var _toward := true
var _avoid := 0
var _probe: ShapeCast3D
var _sensor: Area3D
var _timer := 0.0
var _stagger := Vector3.ZERO
var _source_at := Vector3.ZERO
var _lock_until := 0.0
var _visual: Node3D
var _rb: RigidBody3D
var _rise_from := Basis.IDENTITY
var _after_getup := 0.0



func _ready() -> void:
	add_to_group("pedestrian")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	floor_snap_length = 0.0
	_visual = get_node_or_null("Visual") as Node3D
	_probe = ShapeCast3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.32
	_probe.shape = sphere
	_probe.collision_mask = 1
	_probe.collide_with_areas = false
	_probe.collide_with_bodies = true
	_probe.enabled = false
	add_child(_probe)
	_probe.top_level = true
	_probe.add_exception(self)
	_sensor = Area3D.new()
	_sensor.name = "HitSensor"
	_sensor.collision_layer = 0
	_sensor.collision_mask = 1
	_sensor.monitorable = false
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = GameConstants.PED_RADIUS_M + 0.12
	cap.height = GameConstants.PED_HEIGHT_M
	shape.shape = cap
	_sensor.add_child(shape)
	add_child(_sensor)
	_sensor.body_entered.connect(_on_sensor)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _physics_process(delta: float) -> void:
	match state:
		WALK:
			_walk(delta)
		FLINCH:
			velocity = Vector3.ZERO
			_timer -= delta
			if _timer <= 0.0:
				_begin_face()
		STUMBLE:
			_timer -= delta
			var k: float = clampf(_timer / GameConstants.PED_STUMBLE_S_MAX, 0.0, 1.0)
			velocity = _stagger * k
			move_and_slide()
			if _timer <= 0.0:
				state = FLINCH
				_timer = GameConstants.PED_STUMBLE_RECOVER_S
		DOWN:
			_timer -= delta
			if _rb != null and is_instance_valid(_rb):
				global_position = _rb.global_position
			if _timer <= 0.0:
				_get_up()
		GETUP:
			_timer -= delta
			var t: float = 1.0 - clampf(_timer / maxf(_after_getup, 0.01), 0.0, 1.0)
			if _visual != null:
				_visual.basis = _rise_from.slerp(Basis.IDENTITY, t)
			if _timer <= 0.0:
				if _visual != null:
					_visual.basis = Basis.IDENTITY
				_begin_face()
		FACE:
			_timer -= delta
			var look := _source_at - global_position
			look.y = 0.0
			if look.length_squared() > 0.01:
				look_at(global_position + look, Vector3.UP)
			if _timer <= 0.0:
				state = WALK


func _begin_face() -> void:
	state = FACE
	_timer = GameConstants.PED_FACE_SOURCE_S


func _walk(delta: float) -> void:
	var target: Vector3 = _goal()
	var flat: Vector3 = target - global_position
	flat.y = 0.0
	if flat.length() < 0.4:
		_arrive()
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
	var feet_y: float = global_position.y - GameConstants.PED_HEIGHT_M * 0.5
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
	return body is StaticBody3D and not body.is_in_group("pavement") and not body.is_in_group("sidewalk")


func _is_cone(body: Node) -> bool:
	if body.is_in_group("stack_target") or body.has_method("piece_height"):
		return true
	for child in body.get_children():
		if child.has_method("piece_height"):
			return true
	return false


# --- Hits ---------------------------------------------------------------------------------

func _on_sensor(body: Node) -> void:
	if body == self or body == _rb or not (body is Node3D):
		return
	# Cars report their own hits (hit_cube), with the car's drive speed.
	if body.is_in_group("hitter") or body.is_in_group("vehicle") or body.is_in_group("pedestrian") or body.is_in_group("ped_ragdoll"):
		return
	var at := (body as Node3D).global_position
	if body.is_in_group("soul"):
		var v: Vector3 = body.get("velocity")
		take_hit(body, 0.0, v - velocity, at)
		return
	if body is RigidBody3D and _is_cone(body):
		var rb := body as RigidBody3D
		take_hit(body, rb.mass, rb.linear_velocity - velocity, at)


## The single entry point for every hitter. `mass` is the hitter's mass in kg (0 = soul,
## vehicles pass their mass but are judged on speed). Returns the tier (0-4).
func take_hit(source: Node, mass: float, v_rel_vec: Vector3, point: Vector3) -> int:
	if state == DOWN or state == GETUP or _now() < _lock_until:
		return 0
	var flat_rel := Vector3(v_rel_vec.x, 0.0, v_rel_vec.z)
	var src_pos := point
	if source is Node3D:
		src_pos = (source as Node3D).global_position
	var normal := global_position - src_pos
	normal.y = 0.0
	if normal.length_squared() < 0.0001:
		normal = flat_rel
	normal = normal.normalized() if normal.length_squared() > 0.0001 else Vector3.RIGHT
	var v_rel: float = maxf(flat_rel.dot(normal), 0.0)
	var dir: Vector3 = flat_rel.normalized() if flat_rel.length_squared() > 0.0001 else normal
	var tier := 0
	var amount := v_rel
	if source != null and (source.is_in_group("hitter") or source.is_in_group("vehicle")):
		# A kinematic car drives the contact at its own speed.
		var v_car: float = flat_rel.length()
		amount = v_car
		if v_car >= GameConstants.PED_CAR_FLING_V:
			tier = 4
		elif v_car >= GameConstants.PED_CAR_KNOCK_V:
			tier = 3
		elif v_car >= GameConstants.PED_CAR_STUMBLE_V:
			tier = 2
		v_rel = v_car
	elif source != null and source.is_in_group("soul"):
		if v_rel >= GameConstants.PED_SOUL_FLINCH_V:
			tier = 1
		if v_rel >= GameConstants.PED_SOUL_STUMBLE_V and _stack_of(source) >= GameConstants.PED_SOUL_STUMBLE_STACK:
			tier = 2
	else:
		var j: float = mass * v_rel
		var feet_y: float = global_position.y - GameConstants.PED_HEIGHT_M * 0.5
		var h: float = point.y - feet_y
		if h > GameConstants.PED_PROJ_TRIP_HIGH_M or h < GameConstants.PED_PROJ_TRIP_LOW_M:
			j *= GameConstants.PED_PROJ_TRIP_MULT
		amount = j
		if j >= GameConstants.PED_PROJ_KNOCK_J and v_rel >= GameConstants.PED_PROJ_KNOCK_V:
			tier = 3
		elif j >= GameConstants.PED_PROJ_STUMBLE_J and v_rel >= GameConstants.PED_PROJ_STUMBLE_V:
			tier = 2
		elif j >= GameConstants.PED_PROJ_FLINCH_J and v_rel >= GameConstants.PED_PROJ_FLINCH_V:
			tier = 1
	last_tier = tier
	if tier == 0:
		return 0
	_source_at = src_pos
	reacted.emit(tier, amount, source)
	match tier:
		1:
			state = FLINCH
			_timer = GameConstants.PED_FLINCH_S
			velocity = Vector3.ZERO
		2:
			state = STUMBLE
			_timer = randf_range(GameConstants.PED_STUMBLE_S_MIN, GameConstants.PED_STUMBLE_S_MAX)
			_stagger = dir * clampf(v_rel * 0.35, 0.6, 1.6)
		_:
			_ragdoll(tier, dir, v_rel, source)
	return tier


func _stack_of(soul: Node) -> int:
	# Carried pieces are the soul's direct children with piece_height (stack_controller).
	var n := 0
	for child in soul.get_children():
		if child.has_method("piece_height"):
			n += 1
	return n


## Legacy entry (M1 callers): a car's travel velocity.
func knock(travel: Vector3, hitter: Node) -> void:
	take_hit(hitter, 1200.0, travel, global_position)


func _ragdoll(tier: int, dir: Vector3, v_in: float, hitter: Node) -> void:
	state = DOWN
	_lock_until = _now() + GameConstants.PED_NO_REESCALATE_S
	var vel: Vector3
	var spin_mag: float
	if tier >= 4:
		var horiz: float = clampf(0.9 * v_in, GameConstants.PED_FLING_H_MIN, GameConstants.PED_SPEED_CAP_MPS)
		var up: float = clampf(0.25 * v_in, GameConstants.PED_FLING_UP_MIN, GameConstants.PED_FLING_UP_MAX)
		vel = dir * horiz + Vector3.UP * up
		spin_mag = randf_range(GameConstants.PED_FLING_SPIN_MIN, GameConstants.PED_SPIN_CAP_RADS)
		_timer = randf_range(GameConstants.PED_FLING_DOWN_S_MIN, GameConstants.PED_FLING_DOWN_S_MAX)
		_after_getup = GameConstants.PED_FLING_GETUP_S
	else:
		vel = dir * (0.8 * minf(v_in, GameConstants.PED_KNOCK_SPEED_MAX)) + Vector3.UP * randf_range(GameConstants.PED_KNOCK_UP_MIN, GameConstants.PED_KNOCK_UP_MAX)
		spin_mag = randf_range(1.0, 3.0)
		_timer = GameConstants.PED_KNOCK_DOWN_S
		_after_getup = GameConstants.PED_KNOCK_GETUP_S
	# Cap: peak speed <= min(1.5 * v_in, 12 m/s); spin <= 6 rad/s on a random axis.
	var cap: float = minf(1.5 * maxf(v_in, 0.1), GameConstants.PED_SPEED_CAP_MPS)
	if vel.length() > cap:
		vel = vel.normalized() * cap
	var axis := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	if axis.length_squared() < 0.01:
		axis = Vector3.RIGHT
	var spin: Vector3 = axis.normalized() * minf(spin_mag, GameConstants.PED_SPIN_CAP_RADS)
	var rb := RigidBody3D.new()
	rb.name = "%s_Ragdoll" % name
	rb.add_to_group("ped_ragdoll")
	rb.set_meta("down_at", Time.get_ticks_usec())
	rb.add_to_group("injured")
	rb.collision_layer = 1
	rb.collision_mask = 1
	rb.mass = GameConstants.PED_MASS_KG
	rb.linear_damp = GameConstants.PED_RAGDOLL_LINEAR_DAMP
	rb.angular_damp = GameConstants.PED_RAGDOLL_ANGULAR_DAMP
	rb.continuous_cd = true
	var mat := PhysicsMaterial.new()
	mat.friction = GameConstants.PED_RAGDOLL_FRICTION
	rb.physics_material_override = mat
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = GameConstants.PED_HEIGHT_M
	capsule.radius = GameConstants.PED_RADIUS_M
	shape.shape = capsule
	rb.add_child(shape)
	get_parent().add_child(rb)
	rb.global_transform = global_transform
	if _visual != null:
		_visual.reparent(rb, true)
	rb.linear_velocity = vel
	rb.angular_velocity = spin
	_rb = rb
	collision_layer = 0
	collision_mask = 0
	_sensor.set_deferred("monitoring", false)
	remove_from_group("pedestrian")
	if hitter is CollisionObject3D:
		var mover := hitter as CollisionObject3D
		rb.add_collision_exception_with(mover)
		mover.add_collision_exception_with(rb)
		get_tree().create_timer(GameConstants.PED_HIT_EXCEPTION_S, false, true).timeout.connect(_drop_exception.bind(rb, mover))
	knocked_down.emit(v_in * GameConstants.PED_MASS_KG)
	# At most PED_MAX_RAGDOLLS simulate; the oldest is frozen first.
	var live: Array = []
	for n in get_tree().get_nodes_in_group("ped_ragdoll"):
		if not (n as RigidBody3D).freeze and not n.is_queued_for_deletion():
			live.append(n)
	live.sort_custom(func(a: Node, b: Node) -> bool: return int(a.get_meta("down_at", 0)) < int(b.get_meta("down_at", 0)))
	while live.size() > GameConstants.PED_MAX_RAGDOLLS:
		(live.pop_front() as RigidBody3D).freeze = true


static func _drop_exception(rb: Variant, mover: Variant) -> void:
	if is_instance_valid(rb) and is_instance_valid(mover):
		(rb as RigidBody3D).remove_collision_exception_with(mover)
		(mover as CollisionObject3D).remove_collision_exception_with(rb)


func _get_up() -> void:
	var at := global_position
	var lying := Basis.IDENTITY
	if _rb != null and is_instance_valid(_rb):
		at = _rb.global_position
		lying = _rb.global_basis
	var feet := _ground_below(at)
	global_position = Vector3(at.x, feet + GameConstants.PED_HEIGHT_M * 0.5, at.z)
	rotation = Vector3.ZERO
	if _visual != null and _rb != null and is_instance_valid(_rb):
		_visual.reparent(self, false)
		_visual.transform = Transform3D.IDENTITY
	_rise_from = lying.orthonormalized()
	if _rb != null and is_instance_valid(_rb):
		_rb.queue_free()
	_rb = null
	collision_layer = 1
	collision_mask = 1
	_sensor.set_deferred("monitoring", true)
	add_to_group("pedestrian")
	# Resume the path from wherever we landed.
	_joined = false
	state = GETUP
	_timer = _after_getup


func _ground_below(at: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at + Vector3.DOWN * 6.0)
	q.exclude = [get_rid()]
	if _rb != null and is_instance_valid(_rb):
		q.exclude = [get_rid(), _rb.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return at.y - GameConstants.PED_HEIGHT_M * 0.5
	return (hit["position"] as Vector3).y


func is_down() -> bool:
	return state == DOWN


func ragdoll_body() -> RigidBody3D:
	return _rb


func _exit_tree() -> void:
	if _rb != null and is_instance_valid(_rb):
		_rb.queue_free()
