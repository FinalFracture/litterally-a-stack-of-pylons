extends Node3D

const RANGE := 140.0

var _soul: Node3D
var _tiles: Array[Node3D] = []


func _ready() -> void:
	_soul = get_parent().get_node("SoulBody") as Node3D
	_build()
	for child in get_children():
		if child is Node3D:
			_tiles.append(child)
	_refresh()


func _physics_process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if _soul == null:
		return
	for tile in _tiles:
		var near := tile.global_position.distance_to(_soul.global_position) <= RANGE
		tile.visible = near
		tile.process_mode = Node.PROCESS_MODE_INHERIT if near else Node.PROCESS_MODE_DISABLED


func _build() -> void:
	return
	var ring: Array[Vector3] = [
		Vector3(58, 0, 18),
		Vector3(62, 0, -10),
		Vector3(-58, 0, 24),
		Vector3(-60, 0, -16),
		Vector3(16, 0, 58),
		Vector3(-12, 0, 62),
		Vector3(20, 0, -58),
		Vector3(-18, 0, -60),
	]
	for i in ring.size():
		var tall: float = 12.0 + float(i % 4) * 4.0
		var tint := Color(0.55, 0.5, 0.46).lerp(Color(0.4, 0.38, 0.42), float(i) * 0.08)
		var spot: Vector3 = ring[i]
		_tower(self, Vector3(spot.x, tall * 0.5, spot.z), Vector3(6.0, tall, 5.0), tint)


func _road(at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "Road"
	body.position = at
	body.add_to_group("pavement")
	add_child(body)
	_box(body, Vector3(16, 0.2, 10), Color(0.33, 0.34, 0.36))


func _tower(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = at
	parent.add_child(body)
	_box(body, size, color)
	var band := MeshInstance3D.new()
	var glass := BoxMesh.new()
	glass.size = Vector3(size.x * 0.62, size.y * 0.18, 0.08)
	band.mesh = glass
	band.position = Vector3(0.0, size.y * 0.08, size.z * 0.5 + 0.02)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.2, 0.26)
	band.material_override = mat
	body.add_child(band)


func _box(body: StaticBody3D, size: Vector3, color: Color) -> void:
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
