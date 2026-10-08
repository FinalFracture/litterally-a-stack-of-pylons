extends Node3D


func _ready() -> void:
	pass


func _van() -> void:
	var van := Node3D.new()
	van.name = "Van"
	van.position = Vector3(-36, 0, -16)
	add_child(van)
	_box(van, Vector3(0, 0.7, 0), Vector3(2.4, 1.4, 1.3), Color(0.2, 0.24, 0.22))
	_box(van, Vector3(0.15, 1.55, 0), Vector3(1.3, 0.7, 1.2), Color(0.55, 0.62, 0.6))


func _gallery() -> void:
	var gallery := Node3D.new()
	gallery.name = "Gallery"
	gallery.position = Vector3(-16, 0, 36)
	add_child(gallery)
	for i in 3:
		_box(gallery, Vector3(float(i) * 1.6, 0.35, 0), Vector3(0.7, 0.7, 0.7), Color(0.5, 0.5, 0.52))


func _cement() -> void:
	var cement := Node3D.new()
	cement.name = "WetCement"
	cement.position = Vector3(-24, 0, 16)
	add_child(cement)
	_box(cement, Vector3(0, 0.02, 0), Vector3(3.2, 0.04, 2.4), Color(0.45, 0.45, 0.47))
	var sign := Label3D.new()
	sign.text = "WET CEMENT"
	sign.position = Vector3(0, 0.9, -1.4)
	sign.font_size = 48
	sign.pixel_size = 0.004
	sign.modulate = Color(0.9, 0.9, 0.85)
	cement.add_child(sign)


func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = at
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
