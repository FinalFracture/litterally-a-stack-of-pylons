extends Node3D


const DROP := Vector3(-392.0, 0.7, 36.0)
const CRUSH := Vector3(-392.0, 0.7, 20.0)
const EMERGENCY_RESPONSE_ENABLED := false

var _haul: Dictionary = {}


func _ready() -> void:
	if not EMERGENCY_RESPONSE_ENABLED:
		return
	var desk := Node.new()
	desk.name = "Emergency"
	desk.set_script(load("res://scripts/emergency.gd"))
	get_parent().add_child.call_deferred(desk)


func _physics_process(delta: float) -> void:
	for child in get_children():
		if not child.has_method("set_drive"):
			continue
		var truck := child as Node3D
		if bool(truck.call("has_tow")):
			if not bool(_haul.get(truck.name, false)):
				_haul[truck.name] = true
				truck.call("set_drive", _route(truck.global_position, DROP))
			if truck.global_position.distance_to(DROP) < 5.0:
				_drop(truck)
		else:
			_haul[truck.name] = false
			var wreck := _nearest(truck.global_position)
			var key := "%s-go" % truck.name
			if wreck != null:
				if str(_haul.get(key, "")) != str(wreck.get_instance_id()):
					_haul[key] = wreck.get_instance_id()
					truck.call("set_drive", _route(truck.global_position, wreck.global_position))
			elif _haul.has(key):
				_haul.erase(key)
				truck.call("clear_drive")
	_belt(delta)


func _nearest(at: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := 800.0
	for node in get_tree().get_nodes_in_group("vehicle"):
		if not (node is RigidBody3D):
			continue
		var wreck := node as Node3D
		var gap: float = Vector2(wreck.global_position.x - at.x, wreck.global_position.z - at.z).length()
		if gap < best_d:
			best_d = gap
			best = wreck
	return best


func _drop(truck: Node) -> void:
	var cargo: RigidBody3D = truck.call("release_tow") as RigidBody3D
	truck.call("clear_drive")
	_haul[truck.name] = false
	if cargo == null or not is_instance_valid(cargo):
		return
	cargo.freeze = false
	cargo.collision_layer = 1
	cargo.collision_mask = 1
	cargo.global_position = DROP
	cargo.linear_velocity = Vector3(0.0, 0.0, -2.2)
	cargo.add_to_group("belt_load")


func _belt(delta: float) -> void:
	var done: Array[Node] = []
	for node in get_tree().get_nodes_in_group("belt_load"):
		if not (node is RigidBody3D):
			continue
		var body := node as RigidBody3D
		body.global_position += Vector3(0.0, 0.0, -3.2 * delta)
		body.global_position.x = DROP.x
		body.linear_velocity = Vector3(0.0, 0.0, -3.2)
		if body.global_position.z < CRUSH.z:
			done.append(body)
	for body in done:
		body.queue_free()


func _route(a: Vector3, b: Vector3) -> PackedVector3Array:
	var desk := get_parent().get_node_or_null("Emergency")
	if desk != null and desk.has_method("_route"):
		return desk._route(a, b)
	var line := PackedVector3Array()
	line.append(a)
	line.append(b)
	return line


func _yard() -> void:
	_box("Belt", Vector3(-392.0, 0.35, 28.0), Vector3(1.6, 0.2, 16.0), Color(0.22, 0.22, 0.24))
	_box("Compactor", Vector3(-392.0, 1.6, 18.0), Vector3(4.2, 3.2, 4.4), Color(0.18, 0.16, 0.15))
	for i in 5:
		var roll := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.18
		cyl.bottom_radius = 0.18
		cyl.height = 1.5
		roll.mesh = cyl
		roll.position = Vector3(-392.0, 0.5, 40.0 - float(i) * 3.2)
		roll.rotation.z = PI * 0.5
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.32, 0.28)
		roll.material_override = mat
		add_child(roll)


func _truck(node_name: String, from_point: Vector3, to_point: Vector3) -> void:
	var body := AnimatableBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 1
	body.sync_to_physics = true
	body.add_to_group("hitter")
	body.set_script(load("res://scripts/hit_cube.gd"))
	body.wrecker = true
	body.carries_rider = false
	body.look_ahead = 6.0
	body.brake_miss = 0.0
	body.speed = 7.0
	body.from_point = from_point
	body.to_point = to_point
	body.position = from_point
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.1, 1.2, 1.35)
	shape.shape = box
	body.add_child(shape)
	_mesh(body, "Bed", Vector3(0.35, -0.1, 0.0), Vector3(2.2, 0.45, 1.3), Color(0.86, 0.62, 0.1))
	_mesh(body, "Cab", Vector3(-0.85, 0.28, 0.0), Vector3(1.15, 0.85, 1.25), Color(0.92, 0.72, 0.12))
	_mesh(body, "Bar", Vector3(-0.85, 0.82, 0.0), Vector3(0.7, 0.16, 0.7), Color(0.75, 0.18, 0.12))
	var area := Area3D.new()
	area.name = "HitArea"
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitorable = false
	var area_shape := CollisionShape3D.new()
	var area_box := BoxShape3D.new()
	area_box.size = Vector3(3.4, 1.5, 1.7)
	area_shape.shape = area_box
	area.add_child(area_shape)
	body.add_child(area)
	add_child(body)


func _box(node_name: String, at: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	mesh.material_override = mat
	add_child(mesh)


func _mesh(parent: Node3D, node_name: String, at: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.55
	mesh.material_override = mat
	parent.add_child(mesh)
