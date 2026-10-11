extends RigidBody3D

## A cone or nested cone stack standing in the world (M1, REAL-001 and REAL-005).
## Knockable: a real RigidBody3D, spawned asleep in its rest pose.
## Bottom-heavy: real mass per piece and a custom, low centre of mass.
## Collision: each piece's own CollisionShape3D (the carry/stack shape) is disabled while it
## stands here, and a separate world collider (taper + square base) is used instead.
## The world collider lives in scenes/player/colliders/*_world_collider.tscn so a mesh-based
## "-col" shape can replace it without touching code.
## Car hits: physics decides the push; the velocity it imparts is capped, plus a slight random spin.

const _River := preload("res://scripts/twin_falls_river.gd")
const _COLLIDER_SCENES := {
	0: preload("res://scenes/player/colliders/standard_cone_world_collider.tscn"),
	1: preload("res://scenes/player/colliders/mini_cone_world_collider.tscn"),
}
## Imparted speed cap for a car hit: CAR_HIT_FACTOR x car speed, never above CAR_HIT_MAX.
const CAR_HIT_FACTOR := 1.3
const CAR_HIT_MIN := 2.0
const CAR_HIT_MAX := 12.0
## Random spin added once per car hit, rad/s.
const CAR_SPIN_MIN := 1.0
const CAR_SPIN_MAX := 3.0
## Contact spin is capped too during the hit window, so a hit reads as a knock, not a drill.
const CAR_SPIN_CAP := 10.0
const CAR_HIT_WINDOW_MS := 300
const SOUND_GAP_MS := 120
const THUNK_SPEED := 1.5

var _colliders: Dictionary = {}
var _impact_until := 0
var _impact_cap := 0.0
var _spin_pending := false
var _sound_ms := 0
var _refresh_queued := false
var _settled_once := false
## Downstream unit vector while this stack is touching the river. The force is applied
## above the custom centre of mass so the bottom-heavy stack leans instead of sliding.
var river_flow := Vector3.ZERO
var river_flow_on := false


func _init() -> void:
	collision_layer = 1
	collision_mask = 1
	continuous_cd = true
	can_sleep = true
	contact_monitor = true
	max_contacts_reported = 4
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	add_to_group("stack_target")
	add_to_group("world_cone")
	child_entered_tree.connect(_on_child_entered)
	child_exiting_tree.connect(_on_child_exiting)
	body_entered.connect(_on_body_entered)


func _ready() -> void:
	_refresh_mass()
	sleeping = true


## Called by a car's HitArea (hit_cube._deliver_hit).
func car_impact(travel: Vector3, _hitter: Node = null) -> void:
	var now := Time.get_ticks_msec()
	var fresh := now >= _impact_until
	_impact_cap = clampf(travel.length() * CAR_HIT_FACTOR, CAR_HIT_MIN, CAR_HIT_MAX)
	_impact_until = now + CAR_HIT_WINDOW_MS
	if fresh:
		_spin_pending = true
		sleeping = false


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if river_flow_on and river_flow.length_squared() > 0.0001:
		_river_force(state)
	if Time.get_ticks_msec() >= _impact_until:
		return
	if state.linear_velocity.length() > _impact_cap:
		state.linear_velocity = state.linear_velocity.limit_length(_impact_cap)
	if state.angular_velocity.length() > CAR_SPIN_CAP:
		state.angular_velocity = state.angular_velocity.limit_length(CAR_SPIN_CAP)
	if _spin_pending and state.linear_velocity.length() > 0.2:
		_spin_pending = false
		var axis := Vector3(randf_range(-1.0, 1.0), randf_range(-0.4, 0.4), randf_range(-1.0, 1.0))
		if axis.length_squared() < 0.0001:
			axis = Vector3.RIGHT
		state.angular_velocity += axis.normalized() * randf_range(CAR_SPIN_MIN, CAR_SPIN_MAX)


func _river_force(state: PhysicsDirectBodyState3D) -> void:
	var dir := river_flow
	var hv := Vector3(state.linear_velocity.x, 0.0, state.linear_velocity.z)
	var along := hv.dot(dir)
	var speed := _River.FLOW_SPEED
	if along < speed:
		var accel := minf((speed - along) * 4.0, _River.FLOW_ACCEL)
		var at := state.transform * (center_of_mass + Vector3(0.0, _River.LEAN_ARM, 0.0))
		state.apply_force(dir * mass * accel, at)
	elif along > speed + 0.05:
		state.linear_velocity = Vector3(hv.x, state.linear_velocity.y, hv.z) - dir * (along - speed)


func pieces() -> Array:
	var found: Array = []
	for child in get_children():
		if child.has_method("piece_height") and child is Node3D:
			found.append(child)
	return found


func _on_child_entered(node: Node) -> void:
	if not node.has_method("piece_height"):
		return
	_queue_refresh()


func _on_child_exiting(node: Node) -> void:
	if not _colliders.has(node):
		return
	# The piece leaves (picked up, swapped into): give it back its own shape.
	(node as CollisionShape3D).disabled = false
	for shape in _colliders[node]:
		if is_instance_valid(shape):
			shape.queue_free()
	_colliders.erase(node)
	_queue_refresh()


func _queue_refresh() -> void:
	if _refresh_queued or not is_inside_tree():
		return
	_refresh_queued = true
	_refresh_mass.call_deferred()


func _refresh_mass() -> void:
	_refresh_queued = false
	var total := 0.0
	var moment := Vector3.ZERO
	for item in pieces():
		var piece := item as Node3D
		_fit_collider(piece)
		var kind: int = int(piece.get("piece_type"))
		var kg := _mass_of(kind)
		var com := piece.position + Vector3(0.0, -float(piece.piece_height()) * 0.5 + _com_of(kind), 0.0)
		total += kg
		moment += com * kg
	if total <= 0.0:
		return
	# Setting mass / CoM wakes the body in Jolt; a deferred refresh after spawn (M2: cones
	# are restored by streaming jobs) must not wake a stack that was resting.
	var was_asleep := sleeping
	var changed: bool = absf(mass - total) > 0.0001 or not center_of_mass.is_equal_approx(moment / total)
	if changed:
		mass = total
		center_of_mass = moment / total
	if was_asleep:
		sleeping = true
	if not _settled_once:
		# Spawned in its exact rest pose: start asleep until something touches it.
		_settled_once = true
		sleeping = true


func _fit_collider(piece: Node3D) -> void:
	if _colliders.has(piece):
		return
	var kind: int = int(piece.get("piece_type"))
	if not _COLLIDER_SCENES.has(kind):
		_colliders[piece] = []
		return
	var template := (_COLLIDER_SCENES[kind] as PackedScene).instantiate() as Node3D
	var made: Array = []
	for child in template.get_children():
		if not (child is CollisionShape3D):
			continue
		var src := child as CollisionShape3D
		var shape := CollisionShape3D.new()
		shape.name = "%s_%s" % [piece.name, src.name]
		shape.shape = src.shape
		shape.transform = piece.transform * src.transform
		add_child(shape)
		made.append(shape)
	template.free()
	if not made.is_empty() and piece is CollisionShape3D:
		(piece as CollisionShape3D).disabled = true
	_colliders[piece] = made


func _mass_of(kind: int) -> float:
	match kind:
		1:
			return GameConstants.MINI_MASS_KG
		2:
			return GameConstants.BARREL_MASS_KG
		_:
			return GameConstants.STANDARD_MASS_KG


func _com_of(kind: int) -> float:
	match kind:
		1:
			return GameConstants.MINI_COM_M
		2:
			return GameConstants.BARREL_COM_M
		_:
			return GameConstants.STANDARD_COM_M


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("hitter") or body.is_in_group("vehicle"):
		_play("knock")
		return
	if linear_velocity.length() >= THUNK_SPEED:
		_play("thunk")


func _play(sound: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _sound_ms < SOUND_GAP_MS:
		return
	_sound_ms = now
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.call("play_at", sound, global_position)
