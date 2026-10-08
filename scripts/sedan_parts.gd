extends RefCounted

# Numbers match the photo loft. Nose is local -X.
# Tire contact is WHEEL_Y - WHEEL_R = -0.60.
const HALF_W := 0.63
const DOOR_F_X := -0.4957
const DOOR_F_Y := -0.4226
const DOOR_R_X := 0.274
const DOOR_R_Y := -0.4163
const WHEEL_R := 0.32
const WHEEL_Y := -0.28
const TRACK := 0.67
const AXLE_F := -1.1324
const AXLE_R := 1.0072

const _BODY := preload("res://Models/sedan/body.glb")
const _DOOR_F := preload("res://Models/sedan/door_front.glb")
const _DOOR_R := preload("res://Models/sedan/door_rear.glb")
const _GLASS := preload("res://Models/sedan/windshield.glb")
const _WHEEL := preload("res://Models/sedan/wheel.glb")
const _AXLE := preload("res://Models/sedan/axle.glb")
const _FLANK := preload("res://Models/sedan/flank.png")
const _DRIVE := preload("res://scripts/sedan_drive.gd")
const _PAINT := preload("res://shaders/sedan_paint.gdshader")
const _GLASS_SHADER := preload("res://shaders/sedan_glass.gdshader")


static func assemble(heading: Node3D, paint: Color) -> Node3D:
	var rig := Node3D.new()
	rig.name = "SedanRig"
	rig.set_script(_DRIVE)
	heading.add_child(rig)
	var paint_mat := ShaderMaterial.new()
	paint_mat.shader = _PAINT
	paint_mat.set_shader_parameter("paint_color", paint)
	paint_mat.set_shader_parameter("flank_tex", _FLANK)
	paint_mat.set_shader_parameter("use_photo", true)
	var glass_mat := ShaderMaterial.new()
	glass_mat.shader = _GLASS_SHADER
	var shell := _BODY.instantiate() as Node3D
	shell.name = "BodyShell"
	shell.add_to_group("sedan_body")
	rig.add_child(shell)
	_retint(shell, paint_mat, glass_mat)
	var shield := _GLASS.instantiate() as Node3D
	shield.name = "Windshield"
	shield.add_to_group("sedan_glass")
	rig.add_child(shield)
	_retint(shield, paint_mat, glass_mat)
	_axle(rig, "AxleF", AXLE_F)
	_axle(rig, "AxleR", AXLE_R)
	_wheel(rig, "WheelFL", AXLE_F, TRACK)
	_wheel(rig, "WheelFR", AXLE_F, -TRACK)
	_wheel(rig, "WheelRL", AXLE_R, TRACK)
	_wheel(rig, "WheelRR", AXLE_R, -TRACK)
	_door(rig, "DoorFL", _DOOR_F, DOOR_F_X, DOOR_F_Y, HALF_W, paint_mat, glass_mat)
	_door(rig, "DoorFR", _DOOR_F, DOOR_F_X, DOOR_F_Y, -HALF_W, paint_mat, glass_mat)
	_door(rig, "DoorRL", _DOOR_R, DOOR_R_X, DOOR_R_Y, HALF_W, paint_mat, glass_mat)
	_door(rig, "DoorRR", _DOOR_R, DOOR_R_X, DOOR_R_Y, -HALF_W, paint_mat, glass_mat)
	if rig.has_method("bind"):
		rig.call("bind", paint_mat)
	return rig


static func _axle(rig: Node3D, node_name: String, axle_x: float) -> void:
	var axle := _AXLE.instantiate() as Node3D
	axle.name = node_name
	axle.position = Vector3(axle_x, WHEEL_Y, 0.0)
	axle.add_to_group("sedan_axle")
	rig.add_child(axle)


static func _wheel(rig: Node3D, node_name: String, axle_x: float, z: float) -> void:
	var wheel := _WHEEL.instantiate() as Node3D
	wheel.name = node_name
	wheel.position = Vector3(axle_x, WHEEL_Y, z)
	wheel.add_to_group("sedan_wheel")
	rig.add_child(wheel)


static func _door(rig: Node3D, node_name: String, packed: PackedScene, hinge_x: float, hinge_y: float, z: float, paint_mat: ShaderMaterial, glass_mat: ShaderMaterial) -> void:
	var door := packed.instantiate() as Node3D
	door.name = node_name
	door.position = Vector3(hinge_x, hinge_y, z)
	if z < 0.0:
		door.scale = Vector3(1.0, 1.0, -1.0)
	door.add_to_group("sedan_door")
	rig.add_child(door)
	_retint(door, paint_mat, glass_mat)


static func _retint(root: Node, paint_mat: ShaderMaterial, glass_mat: ShaderMaterial) -> void:
	if root is MeshInstance3D:
		var mesh_node := root as MeshInstance3D
		var role := _role(String(mesh_node.name))
		if role == "Paint":
			_override_all(mesh_node, paint_mat)
		elif role == "Glass":
			_override_all(mesh_node, glass_mat)
		elif role == "LampHead":
			_lamp(mesh_node, "head")
		elif role == "LampTail":
			_lamp(mesh_node, "tail")
		elif role == "BlinkL":
			_lamp(mesh_node, "blink_l")
		elif role == "BlinkR":
			_lamp(mesh_node, "blink_r")
	for child in root.get_children():
		_retint(child, paint_mat, glass_mat)


static func _role(node_name: String) -> String:
	if node_name.begins_with("Paint"):
		return "Paint"
	if node_name.begins_with("Glass"):
		return "Glass"
	if node_name.begins_with("LampHead"):
		return "LampHead"
	if node_name.begins_with("LampTail"):
		return "LampTail"
	if node_name == "BlinkFL" or node_name == "BlinkRL" or node_name.begins_with("BlinkFL") or node_name.begins_with("BlinkRL"):
		return "BlinkL"
	if node_name == "BlinkFR" or node_name == "BlinkRR" or node_name.begins_with("BlinkFR") or node_name.begins_with("BlinkRR"):
		return "BlinkR"
	return ""


static func _override_all(mesh_node: MeshInstance3D, mat: Material) -> void:
	var mesh := mesh_node.mesh
	if mesh == null:
		return
	var count: int = mesh.get_surface_count()
	for index in count:
		mesh_node.set_surface_override_material(index, mat)


static func _lamp(mesh_node: MeshInstance3D, role: String) -> void:
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.28
	mat.emission_enabled = true
	if role == "head":
		mat.albedo_color = Color(0.95, 0.93, 0.86)
		mat.emission = Color(1.0, 0.96, 0.84)
	elif role == "tail":
		mat.albedo_color = Color(0.55, 0.02, 0.02)
		mat.emission = Color(0.85, 0.02, 0.02)
	else:
		mat.albedo_color = Color(0.85, 0.42, 0.05)
		mat.emission = Color(1.0, 0.52, 0.06)
	mat.emission_energy_multiplier = 0.0
	mesh_node.material_override = mat
	var glow := OmniLight3D.new()
	glow.name = "Glow"
	var box: AABB = mesh_node.get_aabb()
	glow.position = box.get_center()
	glow.light_color = mat.emission
	glow.shadow_enabled = false
	glow.light_energy = 0.0
	if role == "head":
		glow.omni_range = 11.0
		var spot := SpotLight3D.new()
		spot.name = "Beam"
		spot.position = box.get_center()
		# SpotLight looks along local -Z. +PI/2 yaws that axis onto car -X (the nose).
		spot.rotation = Vector3(0.0, PI * 0.5, 0.0)
		spot.light_color = mat.emission
		spot.shadow_enabled = false
		spot.spot_range = 16.0
		spot.spot_angle = deg_to_rad(26.0)
		spot.light_energy = 0.0
		mesh_node.add_child(spot)
	elif role == "tail":
		glow.omni_range = 3.2
	else:
		glow.omni_range = 4.0
	glow.set_meta("lamp_role", role)
	glow.set_meta("lamp_mat", mat)
	mesh_node.add_child(glow)
