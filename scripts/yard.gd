extends Node3D

const _STANDARD := preload("res://scenes/player/standard_cone.tscn")
const _MINI := preload("res://scenes/player/mini_cone.tscn")
const _BARREL := preload("res://scenes/player/barrel.tscn")

const _CONES: Array = [
	["standard", Vector3(-14, 0, 12)],
	["standard", Vector3(-12, 0, 32)],
	["standard", Vector3(-36, 0, 14)],
	["standard", Vector3(-10, 0, 20)],
	["standard", Vector3(-34, 0, 36)],
	["standard", Vector3(12, 0, 10)],
	["standard", Vector3(16, 0, 28)],
	["standard", Vector3(-30, 0, -10)],
	["mini", Vector3(-16, 0, 15)],
	["mini", Vector3(-28, 0, 34)],
	["mini", Vector3(14, 0, 12)],
	["mini", Vector3(-32, 0, -16)],
	["barrel", Vector3(-20, 0, 11)],
	["barrel", Vector3(-38, 0, 30)],
	["barrel", Vector3(-28, 0, -22)],
]

const _DRESSING: Array = [
	["crate", Vector3(-13, 0, 11)],
	["crate", Vector3(-36, 0, 33)],
	["post", Vector3(-11, 0, 18)],
	["post", Vector3(-15, 0, 30)],
	["post", Vector3(-38, 0, 16)],
	["crate", Vector3(18, 0, 11)],
	["post", Vector3(22, 0, 10)],
	["post", Vector3(-26, 0, -12)],
	["crate", Vector3(-36, 0, -20)],
	["post", Vector3(-12, 0, -24)],
]


func _ready() -> void:
	pass


func _build_block() -> void:
	_add_box(self, "Block", Vector3(12, 4, -8), Vector3(8, 8, 6), Color(0.56, 0.5, 0.44))
	var block := get_node("Block") as StaticBody3D
	var band := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(5.4, 1.8, 0.08)
	band.mesh = box
	band.position = Vector3(0.0, 0.6, 3.06)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.2, 0.26)
	band.material_override = mat
	block.add_child(band)


func _build_overpass() -> void:
	var overpass := Node3D.new()
	overpass.name = "Overpass"
	add_child(overpass)
	var concrete := Color(0.38, 0.39, 0.42)
	_add_box(overpass, "Deck", Vector3(0, 2.6, 24), Vector3(18, 0.5, 3.4), concrete)
	_add_box(overpass, "PierWest", Vector3(-8.4, 1.15, 24), Vector3(1.3, 2.3, 3.2), concrete)
	_add_box(overpass, "PierEast", Vector3(8.4, 1.15, 24), Vector3(1.3, 2.3, 3.2), concrete)


func _add_cone(parent: Node, kind: String, at: Vector3) -> void:
	var scene: PackedScene = _STANDARD
	var center_y := 0.2286
	if kind == "mini":
		scene = _MINI
		center_y = 0.1524
	elif kind == "barrel":
		scene = _BARREL
		center_y = 0.5
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 1
	body.add_to_group("stack_target")
	parent.add_child(body)
	var piece := scene.instantiate()
	body.add_child(piece)
	piece.position = Vector3(0, center_y, 0)


func _add_dressing(parent: Node, kind: String, at: Vector3) -> void:
	if kind == "crate":
		_add_box(parent, "Crate", at + Vector3(0, 0.4, 0), Vector3(0.8, 0.8, 0.8), Color(0.42, 0.36, 0.28))
	else:
		_add_box(parent, "Post", at + Vector3(0, 0.45, 0), Vector3(0.28, 0.9, 0.28), Color(0.55, 0.55, 0.52))


func _add_box(parent: Node, node_name: String, at: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 1
	parent.add_child(body)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
