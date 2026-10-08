extends CharacterBody3D

const GROUND_ACCEL := 64.0
const AIR_ACCEL := 2.5
const DEFAULT_SPEED := 4.5
const DEFAULT_JUMP_SPEED := 3.1
const SQUASH_Y := 0.92
const SQUASH_RETURN := 9.0
const LAND_SPEED := 1.2
const FALL_Y := -4.0
const EDGE_INSET := 1.0

var _squash_y := 1.0
var hold_column := false
var ragdoll := false
var _map_half := 32.0
var max_speed: float = DEFAULT_SPEED
var jump_height: float = 0.49


func _ready() -> void:
	add_to_group("soul")
	floor_snap_length = 0.2
	var gravity: float = _gravity()
	if gravity > 0.0:
		jump_height = DEFAULT_JUMP_SPEED * DEFAULT_JUMP_SPEED / (2.0 * gravity)
	var shape_node := get_parent().get_node_or_null("Ground/CollisionShape3D") as CollisionShape3D
	if shape_node != null and shape_node.shape is BoxShape3D:
		var box := shape_node.shape as BoxShape3D
		_map_half = minf(box.size.x, box.size.z) * 0.5


func _physics_process(delta: float) -> void:
	if ragdoll:
		return
	var wish := _wish_direction()
	if wish.length_squared() > 0.0004:
		look_at(global_position + wish, Vector3.UP)

	floor_snap_length = 0.0 if hold_column else 0.2
	var accel := GROUND_ACCEL if is_on_floor() else AIR_ACCEL
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(wish * max_speed, accel * delta)
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


func _recover_if_fallen() -> void:
	if global_position.y > FALL_Y:
		return
	global_position = _nearest_pavement()
	velocity = Vector3.ZERO
	var stack := get_node_or_null("StackController")
	if stack != null and stack.has_method("note_respawn"):
		stack.note_respawn()
	print("pavement")


func _nearest_pavement() -> Vector3:
	var limit := _map_half - EDGE_INSET
	var here := global_position
	var best := Vector3(clampf(here.x, -limit, limit), 0.05, clampf(here.z, -limit, limit))
	var best_d := Vector2(here.x - best.x, here.z - best.z).length()
	for node in get_tree().get_nodes_in_group("pavement"):
		if not (node is StaticBody3D):
			continue
		var spot := _closest_on_body(node as StaticBody3D, here)
		var dist := Vector2(here.x - spot.x, here.z - spot.z).length()
		if dist < best_d:
			best = spot
			best_d = dist
	return best


func _closest_on_body(body: StaticBody3D, here: Vector3) -> Vector3:
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


func _closest_on_box(shape_node: CollisionShape3D, here: Vector3) -> Vector3:
	var box := shape_node.shape as BoxShape3D
	var half := box.size * 0.5
	var xf := shape_node.global_transform
	var local: Vector3 = xf.affine_inverse() * here
	var x: float = clampf(local.x, -half.x, half.x)
	var z: float = clampf(local.z, -half.z, half.z)
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
