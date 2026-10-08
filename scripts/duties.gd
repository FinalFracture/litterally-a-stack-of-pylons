extends Node

const _CONE := preload("res://scenes/player/standard_cone.tscn")

var _dept := ""
var _text := ""
var _mode := ""
var _at := Vector3.ZERO
var _need := 1
var _radius := 5.0
var _height := 1.0
var _tracked: Array[Node3D]
var _marker: MeshInstance3D
var _index := -1
var _wait := 5.0
var _banner := ""
var _banner_left := 0.0
var _npc: Node3D
var _cargo: Node3D
var _npc_goal := Vector3.ZERO
var _npc_phase := ""
var _npc_wait := 12.0
var _role := ""
var _props: Array[Node3D]
var _helping_clear := false


func dept_name() -> String:
	if _banner_left > 0.0:
		return "CITY DISPATCH"
	return _dept


func task_text() -> String:
	if _banner_left > 0.0:
		return _banner
	return _text


func job_point() -> Vector3:
	if _mode == "":
		return Vector3(99999.0, 0.0, 0.0)
	return _at


func task_progress() -> String:
	if _mode == "clear":
		return "left  %d" % _alive()
	if _mode == "place":
		return "set  %d / %d" % [_nearby(false), _need]
	if _mode == "bring":
		return "height  %.1f / %.1f" % [_player_height(), _height]
	return ""


func _process(delta: float) -> void:
	if _banner_left > 0.0:
		_banner_left -= delta
		if _banner_left <= 0.0:
			_wait = 2.0
	elif _mode == "":
		_wait -= delta
		if _wait <= 0.0:
			_roll()
	else:
		_check()
	_npc_wait -= delta
	if _npc == null and _npc_wait <= 0.0:
		_npc_wait = randf_range(18.0, 36.0)
		if randf() < 0.62:
			_start_npc()
	_step_npc(delta)


func _roll() -> void:
	var pick := randi() % 16
	if pick == _index:
		pick = (pick + 5) % 16
	_index = pick
	_clear_job()
	_apply(pick)


func _apply(index: int) -> void:
	_height = 1.0
	if index == 0:
		_job("LAW ENFORCEMENT", "Cones are in the Hall Avenue lanes north of the hall. Clear them.", "clear", Vector3(2.2, 0.0, 48.0), 4, 7.0)
		_spawn_cluster(4, 1.4)
	elif index == 1:
		_job("LAW ENFORCEMENT", "Post three cones on the sidewalk by the police station.", "place", Vector3(102.0, 0.0, 16.0), 3, 4.5)
	elif index == 2:
		_job("LAW ENFORCEMENT", "Bring a stack at least 1.2 m tall back to the hall plaza.", "bring", Vector3(32.0, 0.0, 16.0), 1, 6.0)
		_height = 1.2
	elif index == 3:
		_job("PARKS AND RECREATION", "Cones were left on the park lawn. Pick them up.", "clear", Vector3(-40.0, 0.0, -200.0), 4, 8.0)
		_spawn_cluster(4, 1.8)
	elif index == 4:
		_job("PARKS AND RECREATION", "Set three cones beside the park bench.", "place", Vector3(-36.0, 0.0, -150.0), 3, 4.0)
	elif index == 5:
		_job("PARKS AND RECREATION", "Stand in the park with a stack at least 1.6 m tall.", "bring", Vector3(24.0, 0.0, -168.0), 1, 6.0)
		_height = 1.6
	elif index == 6:
		_job("CONSTRUCTION", "Lay four cones on the bridge shoulder.", "place", Vector3(-228.0, 0.0, 8.2), 4, 4.5)
	elif index == 7:
		_job("CONSTRUCTION", "Deliver a stack at least 2 m tall to the bridge crew.", "bring", Vector3(-228.0, 0.0, 9.0), 1, 6.0)
		_height = 2.0
	elif index == 8:
		_job("CONSTRUCTION", "Cones are sitting in the eastbound lane. Clear them.", "clear", Vector3(48.0, 0.0, -2.4), 3, 6.0)
		_spawn_cluster(3, 1.2)
	elif index == 9:
		_job("PUBLIC HEALTH", "Cones are blocking the ambulance bay. Clear them.", "clear", Vector3(-248.2, 0.0, 36.0), 3, 5.0)
		_spawn_cluster(3, 1.2)
	elif index == 10:
		_job("PUBLIC HEALTH", "Mark the hospital bay with two cones.", "place", Vector3(-248.2, 0.0, 50.0), 2, 4.0)
	elif index == 11:
		_job("PUBLIC HEALTH", "Report to the hospital entrance with a stack at least 1 m tall.", "bring", Vector3(-200.0, 0.0, 18.0), 1, 7.0)
		_height = 1.0
	elif index == 12:
		_job("CONSTRUCTION", "A crew is pouring cement on the shoulder. Block the patch with four cones.", "place", Vector3(64.0, 0.0, -8.4), 4, 4.2)
		_prop_patch(Vector3(64.0, 0.04, -8.4), Vector3(6.0, 0.04, 2.4), Color(0.45, 0.45, 0.46))
	elif index == 13:
		_job("LAW ENFORCEMENT", "Traffic accident at Oak and Diner. Divert the lane with four cones.", "place", Vector3(-86.0, 0.0, -96.0), 4, 5.0)
		_prop_box(Vector3(-74.0, 0.6, -84.0), Vector3(2.4, 1.2, 1.2), Color(0.15, 0.16, 0.18))
		_prop_box(Vector3(-78.0, 0.55, -88.0), Vector3(2.2, 1.1, 1.15), Color(0.35, 0.12, 0.1))
	elif index == 14:
		_job("PARKS AND RECREATION", "Rope off the playground. Set four cones around the swings.", "place", Vector3(-30.0, 0.0, -208.0), 4, 6.0)
	else:
		_job("PUBLIC HEALTH", "The drop-off lane is open. Line the bay with three cones.", "place", Vector3(-244.0, 0.0, 42.0), 3, 4.5)
	if _mode != "clear":
		_mark()


func _job(dept: String, text: String, mode: String, at: Vector3, need: int, radius: float) -> void:
	_dept = dept
	_text = text
	_mode = mode
	_at = at
	_need = need
	_radius = radius


func _check() -> void:
	var done := false
	if _mode == "clear":
		done = _alive() == 0
	elif _mode == "place":
		done = _nearby(false) >= _need
	elif _mode == "bring":
		var soul := get_tree().get_first_node_in_group("soul") as Node3D
		done = soul != null and soul.global_position.distance_to(_at) <= _radius and _player_height() + 0.05 >= _height
	if done:
		_banner = "Job closed.  " + _dept
		_banner_left = 3.5
		_clear_job()


func _spawn_cluster(count: int, gap: float) -> void:
	for i in count:
		var at := _at + Vector3(float(i) * gap, 0.0, 0.4)
		_tracked.append(_spawn_cone(at))


func _spawn_cone(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 1
	body.add_to_group("stack_target")
	body.add_to_group("duty_cone")
	get_parent().add_child(body)
	var piece := _CONE.instantiate() as Node3D
	body.add_child(piece)
	piece.position = Vector3(0.0, 0.2286, 0.0)
	return body


func _mark() -> void:
	_marker = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.7
	cyl.bottom_radius = 0.7
	cyl.height = 0.05
	_marker.mesh = cyl
	_marker.position = _at + Vector3(0.0, 0.08, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.62, 0.16)
	mat.emission_enabled = true
	mat.emission = Color(0.95, 0.5, 0.1)
	mat.emission_energy_multiplier = 0.6
	_marker.material_override = mat
	get_parent().add_child(_marker)


func _clear_job() -> void:
	_mode = ""
	for body in _tracked:
		if is_instance_valid(body):
			body.queue_free()
	_tracked.clear()
	if _marker != null and is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null
	for prop in _props:
		if is_instance_valid(prop):
			prop.queue_free()
	_props.clear()


func _alive() -> int:
	var n := 0
	for body in _tracked:
		if is_instance_valid(body):
			n += 1
	return n


func _nearby(include_player: bool) -> int:
	var n := 0
	var soul := get_tree().get_first_node_in_group("soul")
	for node in get_tree().get_nodes_in_group("stack_target"):
		if not (node is Node3D):
			continue
		var body := node as Node3D
		if not include_player and soul != null and body == soul:
			continue
		if body.global_position.distance_to(_at) <= _radius:
			n += 1
	return n


func _player_height() -> float:
	var soul := get_tree().get_first_node_in_group("soul") as Node
	if soul == null:
		return 0.0
	var stack := soul.get_node_or_null("StackController")
	if stack == null or not stack.has_method("get_stack_height"):
		return 0.0
	return float(stack.call("get_stack_height"))


func _start_npc() -> void:
	if _mode != "place" and _mode != "clear":
		return
	var soul := get_tree().get_first_node_in_group("soul") as Node3D
	if soul == null:
		return
	_helping_clear = _mode == "clear"
	if _dept.begins_with("LAW"):
		_role = "officer"
	elif _dept.begins_with("PARKS"):
		_role = "grounds"
	elif _dept.begins_with("CONSTRUCTION"):
		_role = "crew"
	else:
		_role = "paramedic"
	var coat := Color(0.12, 0.2, 0.45)
	if _role == "paramedic":
		coat = Color(0.9, 0.9, 0.88)
	elif _role == "crew":
		coat = Color(0.9, 0.48, 0.1)
	elif _role == "grounds":
		coat = Color(0.2, 0.42, 0.24)
	var spawn := _sidewalk_near(_at if _helping_clear else soul.global_position)
	_npc = _person(spawn, coat)
	if _helping_clear:
		var spill := _tracked_cone()
		if spill == null:
			_npc.queue_free()
			_npc = null
			return
		_npc_phase = "to_cone"
		_cargo = spill
		_npc_goal = spill.global_position
	elif _stack_count() >= 2:
		_npc_phase = "to_player"
		_npc_goal = soul.global_position
	else:
		var loose := _loose_cone(soul.global_position)
		if loose == null:
			_npc.queue_free()
			_npc = null
			return
		_npc_phase = "to_cone"
		_cargo = loose
		_npc_goal = loose.global_position


func _step_npc(delta: float) -> void:
	if _npc == null or not is_instance_valid(_npc):
		_npc = null
		return
	var soul := get_tree().get_first_node_in_group("soul") as Node3D
	if _npc_phase == "to_player" and soul != null:
		_npc_goal = soul.global_position
	elif _npc_phase == "to_cone" and _cargo != null and is_instance_valid(_cargo):
		_npc_goal = _cargo.global_position
	var flat := Vector3(_npc_goal.x, _npc.global_position.y, _npc_goal.z)
	var step := _npc.global_position.move_toward(flat, 2.1 * delta)
	if _inside_block(step.x, step.z):
		var side := Vector3(-(flat.z - _npc.global_position.z), 0.0, flat.x - _npc.global_position.x).normalized()
		var around := _npc.global_position + side * 2.1 * delta
		if not _inside_block(around.x, around.z):
			step = around
		else:
			step = _npc.global_position
	if _npc is CharacterBody3D:
		var body := _npc as CharacterBody3D
		var wish := step - body.global_position
		body.velocity = Vector3(wish.x / maxf(delta, 0.001), 0.0, wish.z / maxf(delta, 0.001))
		body.move_and_slide()
	else:
		_npc.global_position = step
	if _cargo != null and is_instance_valid(_cargo) and _npc_phase == "haul":
		_cargo.global_position = _npc.global_position + Vector3(0.55, 0.0, 0.2)
	if _npc.global_position.distance_to(flat) > 1.7:
		return
	if _npc_phase == "to_cone" or _npc_phase == "to_player":
		if _npc_phase == "to_player":
			_take_from_player()
		_npc_phase = "haul"
		if _helping_clear:
			_npc_goal = Vector3(18.0, 0.0, 14.0)
		else:
			_npc_goal = _at
	elif _npc_phase == "haul":
		if _helping_clear and _cargo != null and is_instance_valid(_cargo):
			_tracked.erase(_cargo)
			_cargo.queue_free()
		_cargo = null
		_npc.queue_free()
		_npc = null
		_npc_phase = ""
		_helping_clear = false


func _take_from_player() -> void:
	var soul := get_tree().get_first_node_in_group("soul") as Node
	if soul == null:
		return
	var stack := soul.get_node_or_null("StackController")
	if stack == null or not stack.has_method("give_top_piece"):
		return
	var piece: Node3D = stack.call("give_top_piece") as Node3D
	if piece == null:
		return
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 1
	body.add_to_group("stack_target")
	get_parent().add_child(body)
	piece.reparent(body, false)
	piece.position = Vector3(0.0, 0.2286, 0.0)
	piece.rotation = Vector3.ZERO
	body.global_position = _npc.global_position
	_cargo = body


func _loose_cone(at: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := 36.0
	var soul := get_tree().get_first_node_in_group("soul")
	for node in get_tree().get_nodes_in_group("stack_target"):
		if not (node is Node3D) or node == soul:
			continue
		var body := node as Node3D
		if body is CharacterBody3D:
			continue
		var gap: float = body.global_position.distance_to(at)
		if gap < best_d:
			best_d = gap
			best = body
	return best


func _stack_count() -> int:
	var soul := get_tree().get_first_node_in_group("soul") as Node
	if soul == null:
		return 0
	var n := 0
	for child in soul.get_children():
		if child.has_method("piece_height"):
			n += 1
	return n


func _person(at: Vector3, coat: Color) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.position = Vector3(at.x, 0.9, at.z)
	body.collision_layer = 1
	body.collision_mask = 1
	get_parent().add_child(body)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.5
	shape.shape = capsule
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.24
	cap.height = 1.5
	mesh.mesh = cap
	var mat := StandardMaterial3D.new()
	mat.albedo_color = coat
	mesh.material_override = mat
	body.add_child(mesh)
	return body


func _tracked_cone() -> Node3D:
	for body in _tracked:
		if is_instance_valid(body):
			return body
	return null


func _sidewalk_near(at: Vector3) -> Vector3:
	var offsets := PackedVector3Array([
		Vector3(12, 0, 0), Vector3(-12, 0, 0), Vector3(0, 0, 12), Vector3(0, 0, -12),
		Vector3(8, 0, 8), Vector3(-8, 0, 8), Vector3(8, 0, -8), Vector3(-8, 0, -8),
	])
	for offset in offsets:
		var spot := at + offset
		if not _inside_block(spot.x, spot.z):
			return spot
	return at + Vector3(14.0, 0.0, 0.0)


func _inside_block(x: float, z: float) -> bool:
	var host: Node3D = get_parent() as Node3D
	if host == null:
		return false
	var world: World3D = host.get_world_3d()
	if world == null:
		return false
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 1.4, 0.5)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = box
	params.transform = Transform3D(Basis.IDENTITY, Vector3(x, 1.0, z))
	params.collision_mask = 1
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var hits: Array = world.direct_space_state.intersect_shape(params, 6)
	for found in hits:
		var hit: Dictionary = found
		var body := hit.get("collider") as Node
		if body is StaticBody3D and not body.is_in_group("pavement"):
			return true
	return false


func _prop_patch(at: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	get_parent().add_child(mesh)
	_props.append(mesh)


func _prop_box(at: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 1
	get_parent().add_child(body)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var solid := BoxShape3D.new()
	solid.size = size
	shape.shape = solid
	body.add_child(shape)
	_props.append(body)
