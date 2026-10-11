extends CharacterBody3D

const _River := preload("res://scripts/twin_falls_river.gd")
const GROUND_ACCEL := 64.0
const AIR_ACCEL := 2.5
const DEFAULT_SPEED := 4.5
const DEFAULT_JUMP_SPEED := 3.1
const SQUASH_Y := 0.92
const SQUASH_RETURN := 9.0
const LAND_SPEED := 1.2
const FALL_Y := -4.0
const EDGE_INSET := 1.0
const RESPAWN_INSET := 0.35

var _squash_y := 1.0
var hold_column := false
var ragdoll := false
## City sets this until the spawn sidewalk exists. Physics must not drop the body through the world.
var boot_held := false
## City sidewalks sit near y = 0. Twin Falls turns this off so the canyon (below y = -4) and the map edge stay falls.
@export var recover_falls := true
# Respawn clamp: the loaded chunk's real bounds (City meta "chunk_bounds"), not the disabled Ground box.
var _bounds := Rect2(0.0, 0.0, 500.0, 500.0)
var _bounds_read := false
var max_speed: float = DEFAULT_SPEED
var jump_height: float = 0.49
## Downstream drift set by the river while this stack is touching the water. Zero on land.
var flow_velocity := Vector3.ZERO
var _river_lean := 0.0


func _ready() -> void:
	add_to_group("soul")
	floor_snap_length = 0.2
	var gravity: float = _gravity()
	if gravity > 0.0:
		jump_height = DEFAULT_JUMP_SPEED * DEFAULT_JUMP_SPEED / (2.0 * gravity)


func _physics_process(delta: float) -> void:
	if ragdoll or boot_held:
		return
	var wish := _wish_direction()
	if wish.length_squared() > 0.0004:
		look_at(global_position + wish, Vector3.UP)

	floor_snap_length = 0.0 if hold_column else 0.2
	var accel := GROUND_ACCEL if is_on_floor() else AIR_ACCEL
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target := wish * max_speed
	if flow_velocity.length_squared() > 0.0001:
		target += flow_velocity
	horizontal = horizontal.move_toward(target, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = sqrt(2.0 * _gravity() * maxf(jump_height, 0.0))
		elif velocity.y < 0.0:
			velocity.y = 0.0
	elif hold_column:
		velocity.y = 0.0
	else:
		velocity.y -= _gravity() * delta

	var vy_before := velocity.y
	var was_air := not is_on_floor()
	move_and_slide()
	if was_air and is_on_floor() and vy_before < -LAND_SPEED:
		_squash_y = SQUASH_Y
	_update_squash(delta)
	_recover_if_fallen()
	_apply_river_lean(delta)


## The river sets flow_velocity. This is the stack lean: the column tilts downstream.
func _apply_river_lean(delta: float) -> void:
	var want := 0.0
	if flow_velocity.length_squared() > 0.04:
		want = 1.0
	if want < 0.001 and _river_lean < 0.001:
		return
	_river_lean = move_toward(_river_lean, want, delta * 5.0)
	var yaw := _flat_yaw(global_basis)
	if _river_lean < 0.001 or flow_velocity.length_squared() < 0.0001:
		global_basis = yaw
		return
	var dir := Vector3(flow_velocity.x, 0.0, flow_velocity.z).normalized()
	var axis := Vector3.UP.cross(dir)
	if axis.length_squared() < 0.0001:
		global_basis = yaw
		return
	var h := GameConstants.STANDARD_H
	var stack := get_node_or_null("StackController")
	if stack != null and stack.has_method("get_stack_height"):
		h = maxf(float(stack.call("get_stack_height")), h)
	global_basis = Basis(axis.normalized(), _River.lean_radians(h) * _river_lean) * yaw


func _flat_yaw(from: Basis) -> Basis:
	var back := Vector3(from.z.x, 0.0, from.z.z)
	if back.length_squared() < 0.0001:
		back = Vector3(0.0, 0.0, 1.0)
	back = back.normalized()
	var right := Vector3.UP.cross(back).normalized()
	return Basis(right, Vector3.UP, back)


func _recover_if_fallen() -> void:
	if not recover_falls:
		return
	if global_position.y > FALL_Y:
		return
	global_position = _nearest_pavement()
	velocity = Vector3.ZERO
	var stack := get_node_or_null("StackController")
	if stack != null and stack.has_method("note_respawn"):
		stack.note_respawn()
	LaunchConfig.log_line("pavement")


func _chunk_bounds() -> Rect2:
	# Streaming (M2): the current chunk changes as the player moves, so read it every time.
	var city := get_parent().get_node_or_null("City")
	if city != null and city.has_meta("chunk_bounds"):
		_bounds = city.get_meta("chunk_bounds")
		_bounds_read = true
	return _bounds


func _nearest_pavement() -> Vector3:
	var area := _chunk_bounds().grow(-EDGE_INSET)
	var here := global_position
	here.x = clampf(here.x, area.position.x, area.end.x)
	here.z = clampf(here.z, area.position.y, area.end.y)
	var best := Vector3(here.x, 0.05, here.z)
	var best_d := INF
	# Sidewalks first, so a respawn never lands in a lane. Road pavement is the fallback.
	for group_name in ["sidewalk", "pavement"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is StaticBody3D):
				continue
			var spot := _closest_on_body(node as StaticBody3D, here)
			if not area.has_point(Vector2(spot.x, spot.z)):
				continue
			var dist := Vector2(here.x - spot.x, here.z - spot.z).length()
			if dist < best_d:
				best = spot
				best_d = dist
		if best_d < INF:
			break
	return best


func _closest_on_body(body: StaticBody3D, here: Vector3) -> Vector3:
	if body.has_meta("respawn_boxes"):
		return _closest_on_records(body, body.get_meta("respawn_boxes"), here)
	var best := Vector3(here.x, body.global_position.y + 0.15, here.z)
	var best_d := 100000.0
	var found := false
	for child in body.get_children():
		if not (child is CollisionShape3D):
			continue
		var shape_node := child as CollisionShape3D
		if not (shape_node.shape is BoxShape3D):
			continue
		var spot := _closest_on_box(shape_node, here)
		var dist := Vector2(here.x - spot.x, here.z - spot.z).length()
		if not found or dist < best_d:
			best = spot
			best_d = dist
			found = true
	if found:
		return best
	var center := body.global_position
	var x := clampf(here.x, center.x - 5.0, center.x + 5.0)
	var z := clampf(here.z, center.z - 5.0, center.z + 5.0)
	return Vector3(x, center.y + 0.15, z)


func _closest_on_records(body: StaticBody3D, records: Array, here: Vector3) -> Vector3:
	var best := Vector3(here.x, body.global_position.y + 0.15, here.z)
	var best_d := 100000.0
	var found := false
	var body_xf := body.global_transform
	for rec in records:
		if not (rec is Dictionary):
			continue
		var item: Dictionary = rec
		var size: Vector3 = item["size"]
		var xf: Transform3D = body_xf * (item["xf"] as Transform3D)
		var half := size * 0.5
		var local: Vector3 = xf.affine_inverse() * here
		var ix: float = maxf(half.x - RESPAWN_INSET, 0.0)
		var iz: float = maxf(half.z - RESPAWN_INSET, 0.0)
		var spot := xf * Vector3(clampf(local.x, -ix, ix), half.y, clampf(local.z, -iz, iz)) + Vector3(0.0, 0.05, 0.0)
		var dist := Vector2(here.x - spot.x, here.z - spot.z).length()
		if not found or dist < best_d:
			best = spot
			best_d = dist
			found = true
	if found:
		return best
	var center := body.global_position
	var x := clampf(here.x, center.x - 5.0, center.x + 5.0)
	var z := clampf(here.z, center.z - 5.0, center.z + 5.0)
	return Vector3(x, center.y + 0.15, z)


func _closest_on_box(shape_node: CollisionShape3D, here: Vector3) -> Vector3:
	var box := shape_node.shape as BoxShape3D
	var half := box.size * 0.5
	var xf := shape_node.global_transform
	var local: Vector3 = xf.affine_inverse() * here
	# Stay RESPAWN_INSET inside the box so a sidewalk respawn never sits on the curb line.
	var ix: float = maxf(half.x - RESPAWN_INSET, 0.0)
	var iz: float = maxf(half.z - RESPAWN_INSET, 0.0)
	var x: float = clampf(local.x, -ix, ix)
	var z: float = clampf(local.z, -iz, iz)
	return xf * Vector3(x, half.y, z) + Vector3(0.0, 0.05, 0.0)


func _wish_direction() -> Vector3:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam := get_viewport().get_camera_3d()
	var wish := Vector3(input_dir.x, 0.0, input_dir.y)
	if cam != null:
		var flat_forward := Vector3(cam.global_basis.z.x, 0.0, cam.global_basis.z.z)
		var flat_right := Vector3(cam.global_basis.x.x, 0.0, cam.global_basis.x.z)
		if flat_forward.length_squared() > 0.0001 and flat_right.length_squared() > 0.0001:
			wish = flat_right.normalized() * input_dir.x + flat_forward.normalized() * input_dir.y
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	return wish


func _gravity() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity"))


func _update_squash(delta: float) -> void:
	var blend := 1.0 - exp(-SQUASH_RETURN * delta)
	_squash_y = lerpf(_squash_y, 1.0, blend)
	var piece := _bottom_piece()
	if piece == null:
		return
	var mesh := piece.get_node_or_null("ConeMesh") as MeshInstance3D
	if mesh == null:
		return
	mesh.scale = Vector3(1.0, _squash_y, 1.0)
	var sink: float = float(piece.piece_height()) * 0.5 * (1.0 - _squash_y)
	mesh.position = Vector3(0.0, -sink, 0.0)


func _bottom_piece() -> Node3D:
	var best: Node3D = null
	var best_y := 1000.0
	for child in get_children():
		if not (child is Node3D) or not child.has_method("piece_height"):
			continue
		var piece := child as Node3D
		if piece.position.y < best_y:
			best_y = piece.position.y
			best = piece
	return best
