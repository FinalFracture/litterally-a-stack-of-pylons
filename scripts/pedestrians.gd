extends Node3D

const FEET_ROAD := 0.85
const FEET_CURB := 1.05


var _riders := 0
var _pads: Array[Vector3]


func _ready() -> void:
	add_to_group("walker_home")
	var coats: Array[Color] = [
		Color(0.25, 0.32, 0.38),
		Color(0.42, 0.24, 0.22),
		Color(0.22, 0.28, 0.24),
		Color(0.36, 0.34, 0.3),
		Color(0.28, 0.26, 0.4),
	]
	# Sidewalks on the grass, inside the blocks. The z=40 road ends at z=47. The x=150 road ends at x=157.
	var south := PackedVector3Array([
		Vector3(60.0, FEET_ROAD, 52.0),
		Vector3(130.0, FEET_ROAD, 52.0),
		Vector3(130.0, FEET_ROAD, 68.0),
		Vector3(60.0, FEET_ROAD, 68.0),
	])
	var east := PackedVector3Array([
		Vector3(168.0, FEET_ROAD, 70.0),
		Vector3(188.0, FEET_ROAD, 70.0),
		Vector3(188.0, FEET_ROAD, 130.0),
		Vector3(168.0, FEET_ROAD, 130.0),
	])
	_remember(south)
	_remember(east)
	_add("WalkSouth", south, 0, 1.0, coats[0])
	_add("WalkSouth2", south, 2, 0.9, coats[1])
	_add("WalkEast", east, 0, 1.05, coats[2])
	_add("WalkEast2", east, 2, 0.95, coats[3])


func spawn_exit(at: Vector3, _dest: Vector3) -> void:
	_riders += 1
	var pad: Vector3 = _nearest_pad(Vector3(at.x, FEET_ROAD, at.z))
	var nxt: Vector3 = _neighbor(pad)
	var path := PackedVector3Array([pad, nxt])
	var body := _add("Rider%d" % _riders, path, 0, 1.35, Color(0.62, 0.24, 0.2))
	body.global_position = Vector3(at.x, FEET_ROAD, at.z)
	body._joined = false
	body.add_to_group("injured")


func _cross_light() -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(6.1, FEET_CURB, 6.1),
		Vector3(4.0, FEET_ROAD, 4.2),
		Vector3(-4.0, FEET_ROAD, 4.2),
		Vector3(-6.1, FEET_CURB, 6.1),
		Vector3(-4.2, FEET_ROAD, 4.0),
		Vector3(-4.2, FEET_ROAD, -4.0),
		Vector3(-6.1, FEET_CURB, -6.1),
		Vector3(-4.0, FEET_ROAD, -4.2),
		Vector3(4.0, FEET_ROAD, -4.2),
		Vector3(6.1, FEET_CURB, -6.1),
		Vector3(4.2, FEET_ROAD, -4.0),
		Vector3(4.2, FEET_ROAD, 4.0),
	])


func _east_walk() -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(9.0, FEET_CURB, 6.1),
		Vector3(16.0, FEET_CURB, 6.1),
		Vector3(18.9, FEET_CURB, 8.5),
		Vector3(18.9, FEET_CURB, 16.0),
		Vector3(22.0, FEET_ROAD, 18.2),
		Vector3(26.0, FEET_ROAD, 18.2),
		Vector3(29.1, FEET_CURB, 16.0),
		Vector3(29.1, FEET_CURB, 8.5),
		Vector3(33.0, FEET_CURB, 6.1),
		Vector3(38.0, FEET_CURB, 6.1),
		Vector3(30.5, FEET_CURB, 6.1),
		Vector3(26.2, FEET_ROAD, 4.15),
		Vector3(21.8, FEET_ROAD, 4.15),
		Vector3(18.9, FEET_CURB, 6.1),
	])


func _south_west() -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(-34.0, FEET_CURB, -6.1),
		Vector3(-16.0, FEET_CURB, -6.1),
		Vector3(-8.0, FEET_CURB, -6.1),
		Vector3(-6.1, FEET_CURB, -6.1),
		Vector3(-6.1, FEET_CURB, -16.0),
		Vector3(-6.1, FEET_CURB, -30.0),
	])


func _north_walk() -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(6.1, FEET_CURB, 10.0),
		Vector3(6.1, FEET_CURB, 22.0),
		Vector3(6.1, FEET_CURB, 34.0),
	])


func _nearest_pad(at: Vector3) -> Vector3:
	var best := Vector3(6.1, FEET_CURB, 6.1)
	var best_d := 10000.0
	for i in _pads.size():
		var pad: Vector3 = _pads[i]
		var d: float = Vector2(pad.x - at.x, pad.z - at.z).length()
		if d < best_d:
			best_d = d
			best = pad
	return best


func _neighbor(pad: Vector3) -> Vector3:
	var best_i := 0
	var best_d := 10000.0
	for i in _pads.size():
		var d: float = Vector2(_pads[i].x - pad.x, _pads[i].z - pad.z).length()
		if d < best_d:
			best_d = d
			best_i = i
	var nxt: int = (best_i + 1) % _pads.size()
	if _pads[nxt].distance_to(pad) > 12.0 and _pads.size() > 1:
		nxt = (best_i - 1 + _pads.size()) % _pads.size()
	return _pads[nxt]


func _remember(path: PackedVector3Array) -> void:
	for i in path.size():
		_pads.append(path[i])


func _add(node_name: String, path: PackedVector3Array, start: int, walk_speed: float, coat: Color) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 1
	body.set_script(load("res://scripts/pedestrian.gd"))
	var index: int = start % path.size()
	body.points = path
	body.point_index = (index + 1) % path.size()
	body.speed = walk_speed
	body.position = path[index]
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.6
	capsule.radius = 0.28
	shape.shape = capsule
	body.add_child(shape)
	_mesh(body, "Legs", Vector3(0.0, -0.35, 0.0), Vector3(0.36, 0.55, 0.28), Color(0.16, 0.16, 0.18))
	_mesh(body, "Coat", Vector3(0.0, 0.12, 0.0), Vector3(0.48, 0.62, 0.32), coat)
	_mesh(body, "Head", Vector3(0.0, 0.58, -0.12), Vector3(0.26, 0.26, 0.26), Color(0.72, 0.62, 0.52))
	add_child(body)
	return body


func _mesh(parent: Node3D, node_name: String, at: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	mesh.material_override = mat
	parent.add_child(mesh)
