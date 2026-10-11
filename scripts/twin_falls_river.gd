extends Node

## Snake River rules for Twin Falls. Water is the water.json centreline, not a collider.
## A loose cone fully under that surface sinks, then returns to the pose it started in.
## A cone that still breaks the surface stays. The player stack, soul included, is one
## object: it respawns only when the whole stack is under. Cones that touch the water
## take a constant downstream speed. The push is a force above the rigid stack's
## centre of mass, so the existing bottom-heavy lean does the tilting.

const FLOW_SPEED := 1.35
const FLOW_ACCEL := 2.5
const LEAN_ARM := 0.16


## Downstream lean while the current pushes, in radians. A short stack barely
## tilts. A taller one leans more, and stops short of falling over.
static func lean_radians(height_m: float) -> float:
	var h := maxf(height_m, GameConstants.STANDARD_H)
	return deg_to_rad(clampf(8.0 + (h - GameConstants.STANDARD_H) * 4.5, 8.0, 18.0))
const SINK_SEC := 0.45
const SINK_SPEED := 1.8
const GRACE_MS := 1600
const CACHE_M := 6.0
const CELL_M := 64.0

var _gen: TwinFallsTerrainGenerator
var _half := 20.0
var _buckets: Dictionary = {}
var _hint_seg: Dictionary = {}
var _hint_at: Dictionary = {}
var _origin: Dictionary = {}
var _grace: Dictionary = {}
var _sinks: Array[Dictionary] = []
var _flowing: Array[RigidBody3D] = []
var _player_sink := 0.0
var _player_under := -1
var _under_since: Dictionary = {}
var _player_layer := 1
var _player_mask := 5
var _scratch := {"d": 9999.0, "y": -6.0, "x": 1.0, "z": 0.0, "seg": -1}


func setup(gen: TwinFallsTerrainGenerator) -> void:
	_gen = gen
	_half = gen.RIVER_HALF_M
	_buckets.clear()
	var pts := gen.water_pts
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var min_x := int(floor(minf(a.x, b.x) / CELL_M)) - 1
		var max_x := int(floor(maxf(a.x, b.x) / CELL_M)) + 1
		var min_z := int(floor(minf(a.z, b.z) / CELL_M)) - 1
		var max_z := int(floor(maxf(a.z, b.z) / CELL_M)) + 1
		for gz in range(min_z, max_z + 1):
			for gx in range(min_x, max_x + 1):
				var key := Vector2i(gx, gz)
				var packed: PackedInt32Array = _buckets.get(key, PackedInt32Array())
				packed.append(i)
				_buckets[key] = packed
	# Lower than the soul (0) and higher than the world (-100), so flow is set
	# before the stack moves and the world can still see holds_player().
	process_physics_priority = -50


func holds_player() -> bool:
	return _player_sink > 0.0


func _physics_process(delta: float) -> void:
	if _gen == null or _gen.water_pts.size() < 2:
		return
	_advance_sinks(delta)
	_flowing = _drop_flow(_flowing)
	var soul := get_tree().get_first_node_in_group("soul") as CharacterBody3D
	if soul != null and not holds_player():
		_touch_player(soul, delta)
	for node in get_tree().get_nodes_in_group("world_cone"):
		if node is RigidBody3D:
			_touch_body(node as RigidBody3D)
	for node in get_tree().get_nodes_in_group("stack_target"):
		if node is RigidBody3D and not node.is_in_group("world_cone"):
			_touch_body(node as RigidBody3D)


func _touch_player(soul: CharacterBody3D, _delta: float) -> void:
	var stack := soul.get_node_or_null("StackController")
	var top_h := GameConstants.STANDARD_H
	if stack != null and stack.has_method("get_stack_height"):
		top_h = maxf(float(stack.call("get_stack_height")), top_h)
	var bottom := soul.global_position.y
	var top := bottom + top_h
	_sample(soul.global_position.x, soul.global_position.z, _hint_of(soul))
	_store_hint(soul)
	if _scratch["d"] > _half:
		soul.flow_velocity = Vector3.ZERO
		return
	var surface := float(_scratch["y"])
	if top < surface - 0.02:
		if _player_under < 0:
			_player_under = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - _player_under >= int(SINK_SEC * 1000.0):
			_begin_player_sink(soul)
		return
	_player_under = -1
	if bottom < surface + 0.05 and top > surface - 0.02:
		soul.flow_velocity = Vector3(float(_scratch["x"]), 0.0, float(_scratch["z"])) * FLOW_SPEED
	else:
		soul.flow_velocity = Vector3.ZERO


func _begin_player_sink(soul: CharacterBody3D) -> void:
	_player_under = -1
	_player_sink = SINK_SEC
	_player_layer = soul.collision_layer
	_player_mask = soul.collision_mask
	soul.collision_layer = 0
	soul.collision_mask = 0
	soul.velocity = Vector3.ZERO
	soul.flow_velocity = Vector3.ZERO
	soul.boot_held = true


func _touch_body(body: RigidBody3D) -> void:
	if not is_instance_valid(body) or _sinking(body):
		return
	var id := body.get_instance_id()
	if int(_grace.get(id, 0)) > Time.get_ticks_msec():
		return
	var span := _span_of(body)
	_sample(body.global_position.x, body.global_position.z, _hint_of(body))
	_store_hint(body)
	var in_ribbon := float(_scratch["d"]) <= _half
	var surface := float(_scratch["y"])
	# Only a dry pose is a home. An underwater first sight must not become the loop point.
	var dry := (not in_ribbon) or span.x >= surface + 0.05
	if dry and not _origin.has(id):
		_origin[id] = body.global_transform
	if not in_ribbon:
		return
	var bottom := span.x
	var top := span.y
	if top < surface - 0.02:
		var since := int(_under_since.get(id, -1))
		if since < 0:
			_under_since[id] = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - since >= int(SINK_SEC * 1000.0):
			_under_since.erase(id)
			_begin_sink(body)
		return
	_under_since.erase(id)
	if bottom < surface + 0.05 and top > surface - 0.02:
		_push_body(body)


func _push_body(body: RigidBody3D) -> void:
	var dir := Vector3(float(_scratch["x"]), 0.0, float(_scratch["z"]))
	if dir.length_squared() < 0.0001:
		return
	if body.is_in_group("world_cone"):
		body.set("river_flow", dir)
		body.set("river_flow_on", true)
		if body.sleeping:
			body.sleeping = false
		_flowing.append(body)
		return
	var hv := Vector3(body.linear_velocity.x, 0.0, body.linear_velocity.z)
	var along := hv.dot(dir)
	if along < FLOW_SPEED:
		along = minf(along + FLOW_ACCEL * 0.016, FLOW_SPEED)
	else:
		along = FLOW_SPEED
	body.linear_velocity = Vector3(dir.x * along, body.linear_velocity.y, dir.z * along)
	if body.sleeping:
		body.sleeping = false


func _begin_sink(body: RigidBody3D) -> void:
	var id := body.get_instance_id()
	var origin := body.global_transform
	if _origin.has(id):
		origin = _origin[id]
	if not _pose_dry(origin):
		origin = _dry_pose(body)
	_sinks.append({
		"body": body,
		"left": SINK_SEC,
		"origin": origin,
		"layer": body.collision_layer,
		"mask": body.collision_mask,
	})
	body.collision_layer = 0
	body.collision_mask = 0
	body.sleeping = false
	if body.is_in_group("world_cone"):
		body.set("river_flow_on", false)


func _pose_dry(xf: Transform3D) -> bool:
	if _gen == null:
		return false
	var p := xf.origin
	var w := _gen.water_nearest(p.x, p.z)
	if w.x <= _half + 0.5:
		return false
	return p.y >= w.y


func _dry_pose(body: RigidBody3D) -> Transform3D:
	var p := body.global_position
	var stand := _gen.dry_ground(p.x, p.z, p.y)
	var ground := stand.y - 0.2
	var feet := -GameConstants.STANDARD_H * 0.5
	var found := false
	for child in body.get_children():
		if not child.has_method("piece_height") or not (child is Node3D):
			continue
		var piece := child as Node3D
		var y := piece.position.y - float(piece.piece_height()) * 0.5
		feet = y if not found else minf(feet, y)
		found = true
	var xf := Transform3D.IDENTITY
	xf.origin = Vector3(stand.x, ground - feet, stand.z)
	return xf


func _sinking(body: RigidBody3D) -> bool:
	for item in _sinks:
		if item["body"] == body:
			return true
	return false


func _advance_sinks(delta: float) -> void:
	if _player_sink > 0.0:
		_player_sink -= delta
		var soul := get_tree().get_first_node_in_group("soul") as CharacterBody3D
		if soul != null:
			soul.global_position.y -= SINK_SPEED * delta
			soul.velocity = Vector3.ZERO
			soul.boot_held = true
		if _player_sink <= 0.0:
			_player_sink = 0.0
			var world := get_parent()
			if world != null and world.has_method("respawn_player"):
				world.call("respawn_player")
			if soul != null:
				soul.collision_layer = _player_layer
				soul.collision_mask = _player_mask
	var keep: Array[Dictionary] = []
	for item in _sinks:
		var body: RigidBody3D = item["body"]
		if body == null or not is_instance_valid(body):
			continue
		var left := float(item["left"]) - delta
		body.global_position.y -= SINK_SPEED * delta
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		if left > 0.0:
			item["left"] = left
			keep.append(item)
			continue
		body.global_transform = item["origin"]
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.collision_layer = int(item["layer"])
		body.collision_mask = int(item["mask"])
		body.sleeping = true
		_grace[body.get_instance_id()] = Time.get_ticks_msec() + GRACE_MS
	_sinks = keep


func _span_of(body: RigidBody3D) -> Vector2:
	var bottom := INF
	var top := -INF
	var found := false
	for child in body.get_children():
		if not child.has_method("piece_height") or not (child is Node3D):
			continue
		var piece := child as Node3D
		var h := float(piece.piece_height())
		bottom = minf(bottom, piece.global_position.y - h * 0.5)
		top = maxf(top, piece.global_position.y + h * 0.5)
		found = true
	if not found:
		bottom = body.global_position.y - 0.23
		top = body.global_position.y + 0.23
	return Vector2(bottom, top)


func _drop_flow(list: Array[RigidBody3D]) -> Array[RigidBody3D]:
	for body in list:
		if is_instance_valid(body) and body.is_in_group("world_cone") and not _sinking(body):
			body.set("river_flow_on", false)
	var empty: Array[RigidBody3D] = []
	return empty


func _hint_of(node: Node) -> int:
	return int(_hint_seg.get(node.get_instance_id(), -1))


func _store_hint(node: Node) -> void:
	var id := node.get_instance_id()
	_hint_seg[id] = int(_scratch["seg"])
	_hint_at[id] = Vector2(node.global_position.x, node.global_position.z)


func _sample(x: float, z: float, hint: int) -> void:
	var n := _gen.water_pts.size() - 1
	if hint >= 0 and hint < n:
		_best_near(x, z, hint, n)
		if float(_scratch["d"]) <= _half + CACHE_M:
			return
	_best_bucket(x, z, n)


func _best_near(x: float, z: float, hint: int, n: int) -> void:
	var best_d := 9999.0
	var best_y := -6.0
	var best_x := 1.0
	var best_z := 0.0
	var best_i := hint
	var pts := _gen.water_pts
	for i in range(maxi(hint - 1, 0), mini(hint + 2, n)):
		var hit := _seg(x, z, pts[i], pts[i + 1])
		if hit.x < best_d:
			best_d = hit.x
			best_y = hit.y
			best_x = hit.z
			best_z = hit.w
			best_i = i
	_scratch["d"] = best_d
	_scratch["y"] = best_y
	_scratch["x"] = best_x
	_scratch["z"] = best_z
	_scratch["seg"] = best_i


func _best_bucket(x: float, z: float, n: int) -> void:
	var best_d := 9999.0
	var best_y := -6.0
	var best_x := 1.0
	var best_z := 0.0
	var best_i := -1
	var pts := _gen.water_pts
	var gx := int(floor(x / CELL_M))
	var gz := int(floor(z / CELL_M))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var packed: PackedInt32Array = _buckets.get(Vector2i(gx + dx, gz + dz), PackedInt32Array())
			for i in packed:
				if i < 0 or i >= n:
					continue
				var hit := _seg(x, z, pts[i], pts[i + 1])
				if hit.x < best_d:
					best_d = hit.x
					best_y = hit.y
					best_x = hit.z
					best_z = hit.w
					best_i = i
	_scratch["d"] = best_d
	_scratch["y"] = best_y
	_scratch["x"] = best_x
	_scratch["z"] = best_z
	_scratch["seg"] = best_i


func _seg(x: float, z: float, a: Vector3, b: Vector3) -> Vector4:
	var abx := b.x - a.x
	var abz := b.z - a.z
	var len2 := abx * abx + abz * abz
	var t := 0.0
	if len2 > 0.0001:
		t = clampf(((x - a.x) * abx + (z - a.z) * abz) / len2, 0.0, 1.0)
	var px := a.x + abx * t
	var pz := a.z + abz * t
	var dx := x - px
	var dz := z - pz
	var dir_x := 1.0
	var dir_z := 0.0
	if len2 > 0.0001:
		var inv := 1.0 / sqrt(len2)
		dir_x = abx * inv
		dir_z = abz * inv
	return Vector4(sqrt(dx * dx + dz * dz), lerpf(a.y, b.y, t), dir_x, dir_z)
