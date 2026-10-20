extends Node3D

## One road on the seed-20261008 height field, seamed with strategy 11:
## a 2 m flat shoulder, then a 4 m linear blend. No junction disks.
## Open scenes/road_strategy_lab.tscn and press F6.

const SEED := 20261008
const FIELD_STEP := 8.0
const CHUNK_M := 500.0
const ROAD_HALF := 4.0
const BENCH_M := 2.0
const BLEND_M := 4.0
const STEP_M := 1.0
const GRID_N := 501
const CELL_M := 40.0
const CURVE_M := 3.0
const MACRO_SIGMA_M := 80.0
const MACRO_AMP_M := 0.42
const MESO_SIGMA_M := 24.0
const MESO_AMP_M := 0.0859
const _SALT_MACRO := 11
const _SALT_MESO := 29
const _SALT_PAIR := 8191

var _ox0 := 0
var _oz0 := 0
var _fnx := 0
var _fnz := 0
var _field := PackedFloat32Array()
var _segs: Array[Dictionary] = []
var _bins: Dictionary = {}
var _controls: Array[Vector2] = []
var _body: CharacterBody3D
var _rig: Node3D
var _hud: Label
var _spawn := Vector3(18.0, 1.0, 70.0)
var _ground_mat: StandardMaterial3D
var _stripe_mat: StandardMaterial3D


func _ready() -> void:
	_make_materials()
	_add_lighting()
	_build_seed_field()
	_build_network()
	var crosses := _count_crossings()
	var built := _build_ground()
	_add_stripe()
	_add_labels()
	_add_player()
	var mark := "PASS" if bool(built["pass"]) else "FAIL"
	var line := "strategy 11 bench+short  above %d  gap %d  grade %.2f  spill %.2f  crossings %d  %s" % [int(built["above"]), int(built["gap"]), float(built["grade"]), float(built["spill"]), crosses, mark]
	_add_hud(line)
	print("ROAD_LAB_DONE")
	print(line)


func _make_materials() -> void:
	_ground_mat = StandardMaterial3D.new()
	_ground_mat.vertex_color_use_as_albedo = true
	_ground_mat.roughness = 1.0
	_ground_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_ground_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_stripe_mat = StandardMaterial3D.new()
	_stripe_mat.albedo_color = Color(0.92, 0.78, 0.22)
	_stripe_mat.roughness = 1.0
	_stripe_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_stripe_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func _add_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = false
	add_child(sun)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.62, 0.74, 0.86)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.7, 0.64)
	environment.ambient_light_energy = 0.55
	env.environment = environment
	add_child(env)


func _on_line(dist: float, offset: float) -> Vector3:
	var rad := deg_to_rad(-30.0)
	return Vector3(400.0 + cos(rad) * dist, offset, 340.0 + sin(rad) * dist)


func _ray(angle_deg: float, dist: float, offset: float) -> Vector3:
	var rad := deg_to_rad(angle_deg)
	return Vector3(400.0 + cos(rad) * dist, offset, 340.0 + sin(rad) * dist)


func _build_network() -> void:
	# x, height offset above the seeded ground, z.
	# The junction is a straight spine crossed by a north-south road, a
	# northeast diagonal, and a short southeast fork. Offsets match at the
	# junction so the gore is not a step.
	var split := Vector3(300, 1.2, 270)
	var tee := Vector3(230, 0.8, 230)
	var merge: Vector3 = _on_line(-170.0, -0.7)
	var junction: Vector3 = _on_line(0.0, -1.2)
	var south_bend := Vector3(455, 1.0, 210)
	var y_point := Vector3(340, 0.5, 80)
	_curve([
		Vector3(48, 0.0, 70),
		Vector3(125, 0.8, 125),
		Vector3(190, 1.6, 55),
		Vector3(270, 2.6, 145),
		Vector3(330, 2.0, 210),
		split,
		tee,
		Vector3(145, 0.3, 300),
		Vector3(185, -0.2, 370),
		merge,
		_on_line(-110.0, -0.95),
		_on_line(-55.0, -1.2),
		junction,
		_on_line(55.0, -1.2),
		_on_line(100.0, -0.4),
		south_bend,
		Vector3(490, 1.6, 150),
		Vector3(430, 1.1, 100),
		y_point,
	])
	_curve([
		split,
		Vector3(365, 0.6, 305),
		Vector3(330, 0.0, 345),
		merge,
	])
	_curve([
		tee,
		Vector3(60, 0.2, 155),
	])
	_curve([
		_ray(90.0, 130.0, 0.2),
		_ray(90.0, 55.0, -1.2),
		junction,
		_ray(270.0, 55.0, -1.2),
		_ray(270.0, 130.0, 0.2),
	])
	_curve([
		_ray(35.0, 95.0, 0.0),
		_ray(35.0, 50.0, -1.2),
		junction,
	])
	_curve([
		junction,
		_ray(-60.0, 36.0, -1.2),
		_ray(-60.0, 72.0, 0.1),
	])
	_curve([
		y_point,
		Vector3(230, 0.0, 35),
	])
	_curve([
		y_point,
		Vector3(430, 0.9, 35),
	])
	_curve([
		south_bend,
		Vector3(400, 1.4, 150),
	])


func _curve(controls: Array) -> void:
	var n := controls.size()
	if n < 2:
		return
	for item in controls:
		var control: Vector3 = item
		_controls.append(Vector2(control.x, control.z))
	var ext: Array[Vector3] = []
	ext.append(controls[0])
	for item in controls:
		ext.append(item)
	ext.append(controls[n - 1])
	var pts: Array[Vector3] = []
	for i in range(1, n):
		var p0: Vector3 = ext[i - 1]
		var p1: Vector3 = ext[i]
		var p2: Vector3 = ext[i + 1]
		var p3: Vector3 = ext[i + 2]
		var chord := Vector2(p2.x - p1.x, p2.z - p1.z).length()
		var steps := maxi(int(ceil(chord / CURVE_M)), 1)
		for s in steps:
			pts.append(_catmull(p0, p1, p2, p3, float(s) / float(steps)))
	pts.append(controls[n - 1])
	var prev: Vector3 = pts[0]
	var prev_y := _sample_field(prev.x, prev.z) + prev.y
	for j in range(1, pts.size()):
		var cur: Vector3 = pts[j]
		var cur_y := _sample_field(cur.x, cur.z) + cur.y
		if Vector2(prev.x, prev.z).distance_to(Vector2(cur.x, cur.z)) > 0.05:
			_add_segment(Vector2(prev.x, prev.z), Vector2(cur.x, cur.z), prev_y, cur_y)
		prev = cur
		prev_y = cur_y


func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	var x := 0.5 * ((2.0 * p1.x) + (-p0.x + p2.x) * t + (2.0 * p0.x - 5.0 * p1.x + 4.0 * p2.x - p3.x) * t2 + (-p0.x + 3.0 * p1.x - 3.0 * p2.x + p3.x) * t3)
	var off := 0.5 * ((2.0 * p1.y) + (-p0.y + p2.y) * t + (2.0 * p0.y - 5.0 * p1.y + 4.0 * p2.y - p3.y) * t2 + (-p0.y + 3.0 * p1.y - 3.0 * p2.y + p3.y) * t3)
	var z := 0.5 * ((2.0 * p1.z) + (-p0.z + p2.z) * t + (2.0 * p0.z - 5.0 * p1.z + 4.0 * p2.z - p3.z) * t2 + (-p0.z + 3.0 * p1.z - 3.0 * p2.z + p3.z) * t3)
	return Vector3(x, off, z)


func _add_segment(a: Vector2, b: Vector2, y0: float, y1: float) -> void:
	var idx := _segs.size()
	_segs.append({"a": a, "b": b, "y0": y0, "y1": y1})
	var pad := ROAD_HALF + BENCH_M + BLEND_M + 2.0
	var min_x := int(floor((minf(a.x, b.x) - pad) / CELL_M))
	var max_x := int(floor((maxf(a.x, b.x) + pad) / CELL_M))
	var min_z := int(floor((minf(a.y, b.y) - pad) / CELL_M))
	var max_z := int(floor((maxf(a.y, b.y) + pad) / CELL_M))
	for iz in range(min_z, max_z + 1):
		for ix in range(min_x, max_x + 1):
			var key := ix * 1024 + iz
			if not _bins.has(key):
				_bins[key] = []
			var bucket: Array = _bins[key]
			bucket.append(idx)


func _road_at(x: float, z: float) -> Vector2:
	var key := int(floor(x / CELL_M)) * 1024 + int(floor(z / CELL_M))
	if not _bins.has(key):
		return Vector2(1.0e9, 0.0)
	var bucket: Array = _bins[key]
	var p := Vector2(x, z)
	var best_d := 1.0e9
	var best_y := 0.0
	var w_sum := 0.0
	var y_sum := 0.0
	var influence := ROAD_HALF + BENCH_M + BLEND_M
	for item in bucket:
		var segment: Dictionary = _segs[int(item)]
		var a: Vector2 = segment["a"]
		var b: Vector2 = segment["b"]
		var hit := _closest(a, b, p)
		var y := lerpf(float(segment["y0"]), float(segment["y1"]), hit.y)
		if hit.x < best_d:
			best_d = hit.x
			best_y = y
		if hit.x < influence:
			var w := influence - hit.x
			w = w * w
			w_sum += w
			y_sum += w * y
	var road_y := best_y
	if w_sum > 0.0:
		road_y = y_sum / w_sum
	return Vector2(best_d, road_y)


func _closest(a: Vector2, b: Vector2, p: Vector2) -> Vector2:
	var ab := b - a
	var den := ab.length_squared()
	if den < 0.0001:
		return Vector2(p.distance_to(a), 0.0)
	var t := clampf((p - a).dot(ab) / den, 0.0, 1.0)
	return Vector2(p.distance_to(a + ab * t), t)


func _sculpt(x: float, z: float) -> float:
	var original := _sample_field(x, z)
	var hit := _road_at(x, z)
	if hit.x > ROAD_HALF + BENCH_M + BLEND_M:
		return original
	if hit.x <= ROAD_HALF:
		return hit.y
	var outer := hit.x - ROAD_HALF
	if outer <= BENCH_M:
		return hit.y
	var blend_t := clampf((outer - BENCH_M) / BLEND_M, 0.0, 1.0)
	return lerpf(hit.y, original, blend_t)


func _build_ground() -> Dictionary:
	var count := GRID_N * GRID_N
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var dist_a := PackedFloat32Array()
	vertices.resize(count)
	colors.resize(count)
	dist_a.resize(count)
	var above := 0
	var gap := 0
	var spill := 0.0
	for gz in GRID_N:
		var z := float(gz) * STEP_M
		for gx in GRID_N:
			var x := float(gx) * STEP_M
			var h := _sculpt(x, z)
			var i := gz * GRID_N + gx
			vertices[i] = Vector3(x, h, z)
			var hit := _road_at(x, z)
			dist_a[i] = hit.x
			var original := _sample_field(x, z)
			colors[i] = _vertex_color(h, original, hit)
			if hit.x <= ROAD_HALF:
				if h > hit.y + 0.08:
					above += 1
				elif h < hit.y - 0.15:
					gap += 1
			elif hit.x > ROAD_HALF + BENCH_M + BLEND_M + 1.0:
				spill = maxf(spill, absf(h - original))
	var grade := 0.0
	var influence := ROAD_HALF + BENCH_M + BLEND_M
	for gz2 in GRID_N:
		for gx2 in GRID_N:
			var i2 := gz2 * GRID_N + gx2
			if gx2 + 1 < GRID_N:
				grade = maxf(grade, _pair_grade(vertices, dist_a, i2, i2 + 1, influence))
			if gz2 + 1 < GRID_N:
				grade = maxf(grade, _pair_grade(vertices, dist_a, i2, i2 + GRID_N, influence))
	var indices := PackedInt32Array()
	indices.resize((GRID_N - 1) * (GRID_N - 1) * 6)
	var index_at := 0
	for gz3 in GRID_N - 1:
		for gx3 in GRID_N - 1:
			var a := gz3 * GRID_N + gx3
			var b := a + GRID_N
			var c := a + 1
			var d := b + 1
			indices[index_at] = a
			indices[index_at + 1] = c
			indices[index_at + 2] = b
			indices[index_at + 3] = c
			indices[index_at + 4] = d
			indices[index_at + 5] = b
			index_at += 6
	var mesh := _array_mesh(vertices, indices, _normals(vertices), colors)
	_add_collision_mesh(self, mesh, _ground_mat, "SculptedGround")
	var passed := above == 0 and gap == 0 and grade <= 0.90 and spill < 0.05
	return {"above": above, "gap": gap, "grade": grade, "spill": spill, "pass": passed}


func _vertex_color(h: float, original: float, hit: Vector2) -> Color:
	if hit.x <= ROAD_HALF:
		if h > hit.y + 0.08:
			return Color(0.62, 0.22, 0.16)
		if h < hit.y - 0.15:
			return Color(0.25, 0.36, 0.58)
		return Color(0.13, 0.13, 0.14)
	if h > original + 0.1:
		return Color(0.55, 0.48, 0.32)
	if h < original - 0.1:
		return Color(0.32, 0.28, 0.24)
	return Color(0.45, 0.38, 0.28)


func _pair_grade(vertices: PackedVector3Array, dist_a: PackedFloat32Array, i: int, j: int, influence: float) -> float:
	if minf(dist_a[i], dist_a[j]) > influence:
		return 0.0
	return absf(vertices[i].y - vertices[j].y) / STEP_M


func _normals(vertices: PackedVector3Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for gz in GRID_N:
		for gx in GRID_N:
			var i := gz * GRID_N + gx
			var left: float = vertices[gz * GRID_N + maxi(gx - 1, 0)].y
			var right: float = vertices[gz * GRID_N + mini(gx + 1, GRID_N - 1)].y
			var near: float = vertices[maxi(gz - 1, 0) * GRID_N + gx].y
			var far: float = vertices[mini(gz + 1, GRID_N - 1) * GRID_N + gx].y
			normals[i] = Vector3(left - right, 2.0 * STEP_M, near - far).normalized()
	return normals


func _array_mesh(vertices: PackedVector3Array, indices: PackedInt32Array, normals: PackedVector3Array, colors: PackedColorArray) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_collision_mesh(parent: Node3D, mesh: ArrayMesh, material: Material, node_name: String) -> void:
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.mesh = mesh
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)
	var body := StaticBody3D.new()
	body.name = node_name + "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var trimesh: ConcavePolygonShape3D = mesh.create_trimesh_shape() as ConcavePolygonShape3D
	if trimesh != null:
		trimesh.backface_collision = true
	shape.shape = trimesh
	body.add_child(shape)
	parent.add_child(body)


func _add_stripe() -> void:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var half := 0.16
	for segment in _segs:
		var a: Vector2 = segment["a"]
		var b: Vector2 = segment["b"]
		var delta := b - a
		var length := delta.length()
		if length < 0.01:
			continue
		var side := Vector2(delta.y, -delta.x).normalized() * half
		var y0 := float(segment["y0"]) + 0.04
		var y1 := float(segment["y1"]) + 0.04
		var first := vertices.size()
		vertices.append(Vector3(a.x + side.x, y0, a.y + side.y))
		vertices.append(Vector3(a.x - side.x, y0, a.y - side.y))
		vertices.append(Vector3(b.x + side.x, y1, b.y + side.y))
		vertices.append(Vector3(b.x - side.x, y1, b.y - side.y))
		indices.append_array(PackedInt32Array([first, first + 1, first + 2, first + 1, first + 3, first + 2]))
	if vertices.is_empty():
		return
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	var colors := PackedColorArray()
	colors.resize(vertices.size())
	colors.fill(Color(0.92, 0.78, 0.22))
	var mesh := _array_mesh(vertices, indices, normals, colors)
	var visual := MeshInstance3D.new()
	visual.name = "CenterStripe"
	visual.mesh = mesh
	visual.material_override = _stripe_mat
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)


func _add_labels() -> void:
	var merge: Vector3 = _on_line(-170.0, -0.7)
	var junction: Vector3 = _on_line(0.0, -1.2)
	_mark(Vector2(48, 70), 0.0, "START")
	_mark(Vector2(190, 55), 1.6, "S")
	_mark(Vector2(270, 145), 2.6, "CLIMB")
	_mark(Vector2(300, 270), 1.2, "SPLIT")
	_mark(Vector2(230, 230), 0.8, "T")
	_mark(Vector2(145, 300), 0.3, "HAIRPIN")
	_mark(Vector2(merge.x, merge.z), -0.7, "MERGE")
	_mark(Vector2(junction.x, junction.z), -1.2, "JUNCTION")
	_mark(Vector2(455, 210), 1.0, "CLIMB")
	_mark(Vector2(340, 80), 0.5, "Y")


func _mark(at: Vector2, offset: float, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = Vector3(at.x, _sample_field(at.x, at.y) + offset + 2.2, at.y)
	label.font_size = 42
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.96, 0.94, 0.86)
	label.outline_size = 8
	label.outline_modulate = Color(0.05, 0.04, 0.03)
	add_child(label)


func _count_crossings() -> int:
	var nodes := _shared_nodes()
	var count := 0
	for i in _segs.size():
		var sa: Dictionary = _segs[i]
		var a: Vector2 = sa["a"]
		var b: Vector2 = sa["b"]
		for j in range(i + 1, _segs.size()):
			var sb: Dictionary = _segs[j]
			var c: Vector2 = sb["a"]
			var d: Vector2 = sb["b"]
			if _shares_end(a, b, c, d):
				continue
			if not _proper_cross(a, b, c, d):
				continue
			if _near_node(_cross_at(a, b, c, d), nodes, 14.0):
				continue
			count += 1
	return count


func _shared_nodes() -> Array[Vector2]:
	var nodes: Array[Vector2] = []
	for i in _controls.size():
		var a: Vector2 = _controls[i]
		var dup := false
		for j in range(i + 1, _controls.size()):
			var other: Vector2 = _controls[j]
			if a.distance_to(other) < 0.6:
				dup = true
				break
		if not dup:
			continue
		if _near_node(a, nodes, 0.6):
			continue
		nodes.append(a)
	return nodes


func _near_node(pt: Vector2, nodes: Array[Vector2], radius: float) -> bool:
	for node in nodes:
		if node.distance_to(pt) <= radius:
			return true
	return false


func _cross_at(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Vector2:
	var r := b - a
	var s := d - c
	var den := r.x * s.y - r.y * s.x
	if absf(den) < 0.0001:
		return (a + b) * 0.5
	var t := ((c.x - a.x) * s.y - (c.y - a.y) * s.x) / den
	return a + r * t


func _shares_end(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	return a.distance_to(c) < 0.25 or a.distance_to(d) < 0.25 or b.distance_to(c) < 0.25 or b.distance_to(d) < 0.25


func _proper_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab_c := _orient(a, b, c)
	var ab_d := _orient(a, b, d)
	var cd_a := _orient(c, d, a)
	var cd_b := _orient(c, d, b)
	return ab_c * ab_d < 0.0 and cd_a * cd_b < 0.0


func _orient(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)


func _add_player() -> void:
	var ground := _sample_field(_spawn.x, _spawn.z)
	_spawn.y = ground + 0.4
	_body = CharacterBody3D.new()
	_body.name = "SoulBody"
	_body.set_script(load("res://scripts/soul_body.gd"))
	_body.recover_falls = false
	_body.collision_layer = 1
	_body.collision_mask = 1
	_body.floor_max_angle = deg_to_rad(45.0)
	_body.position = _spawn
	var stack := Node.new()
	stack.name = "StackController"
	stack.set_script(load("res://scripts/stack_controller.gd"))
	_body.add_child(stack)
	var cone_scene: PackedScene = load("res://scenes/player/standard_cone.tscn") as PackedScene
	if cone_scene != null:
		var cone: Node3D = cone_scene.instantiate() as Node3D
		cone.position = Vector3(0.0, 0.2286, 0.0)
		_body.add_child(cone)
	add_child(_body)
	_rig = Node3D.new()
	_rig.name = "CameraRig"
	_rig.set_script(load("res://scripts/camera_rig.gd"))
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = 70.0
	camera.current = true
	_rig.add_child(camera)
	_rig.set("target_path", NodePath("../SoulBody"))
	add_child(_rig)
	if _rig.has_method("look_toward"):
		_rig.call("look_toward", Vector3(125.0, _spawn.y, 125.0))


func _add_hud(line: String) -> void:
	var layer := CanvasLayer.new()
	layer.name = "StrategyHud"
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16.0, 12.0)
	_hud.add_theme_font_size_override("font_size", 16)
	_hud.add_theme_color_override("font_color", Color(0.96, 0.94, 0.88))
	_hud.add_theme_color_override("font_shadow_color", Color(0.02, 0.02, 0.02, 0.9))
	_hud.add_theme_constant_override("shadow_offset_x", 1)
	_hud.add_theme_constant_override("shadow_offset_y", 1)
	_hud.text = "ROAD LAB  strategy 11 only\n2 m flat shoulder, then a 4 m blend. No junction disk.\nS-curve, hairpins, bypass, T, six-leg junction, Y.\nWASD slide    mouse look    R restart    Esc frees the mouse\n" + line
	layer.add_child(_hud)


func _physics_process(_delta: float) -> void:
	if _body == null:
		return
	if _body.global_position.y >= -8.0:
		return
	_body.global_position = _spawn
	_body.velocity = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or _body == null:
		return
	if key.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if key.keycode != KEY_R:
		return
	_body.global_position = _spawn
	_body.velocity = Vector3.ZERO
	if _rig != null and _rig.has_method("look_toward"):
		_rig.call("look_toward", Vector3(125.0, _spawn.y, 125.0))


func _build_seed_field() -> void:
	var x0 := -1
	var x1 := 64
	var z0 := -1
	var z1 := 64
	var skirt := int(ceil(3.0 * MACRO_SIGMA_M / FIELD_STEP))
	_ox0 = x0 - skirt
	_oz0 = z0 - skirt
	_fnx = x1 - x0 + 1 + skirt * 2
	_fnz = z1 - z0 + 1 + skirt * 2
	var macro_k := _make_kernel(MACRO_SIGMA_M)
	var meso_k := _make_kernel(MESO_SIGMA_M)
	var macro := _fill_octave(_ox0, _oz0, _fnx, _fnz, macro_k, _kernel_rms(macro_k), _SALT_MACRO)
	var meso := _fill_octave(_ox0, _oz0, _fnx, _fnz, meso_k, _kernel_rms(meso_k), _SALT_MESO)
	_field.resize(_fnx * _fnz)
	for i in _field.size():
		_field[i] = MACRO_AMP_M * macro[i] + MESO_AMP_M * meso[i]


func _sample_field(x: float, z: float) -> float:
	var gx := clampf(x / FIELD_STEP - float(_ox0), 0.0, float(_fnx - 1))
	var gz := clampf(z / FIELD_STEP - float(_oz0), 0.0, float(_fnz - 1))
	var x0 := int(floor(gx))
	var z0 := int(floor(gz))
	var x1 := mini(x0 + 1, _fnx - 1)
	var z1 := mini(z0 + 1, _fnz - 1)
	var tx := gx - float(x0)
	var tz := gz - float(z0)
	var h00 := _field[z0 * _fnx + x0]
	var h10 := _field[z0 * _fnx + x1]
	var h01 := _field[z1 * _fnx + x0]
	var h11 := _field[z1 * _fnx + x1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func _make_kernel(sigma_m: float) -> PackedFloat32Array:
	var sigma_cells := sigma_m / FIELD_STEP
	var radius := int(ceil(3.0 * sigma_cells))
	var n := radius * 2 + 1
	var weights := PackedFloat32Array()
	weights.resize(n)
	var sum := 0.0
	for i in n:
		var k := i - radius
		var g := exp(-0.5 * float(k) * float(k) / (sigma_cells * sigma_cells))
		weights[i] = g
		sum += g
	for j in n:
		weights[j] = weights[j] / sum
	return weights


func _kernel_rms(kernel: PackedFloat32Array) -> float:
	var sum_sq := 0.0
	var n := kernel.size()
	for dz in n:
		var kz := kernel[dz]
		for dx in n:
			var w := kernel[dx] * kz
			sum_sq += w * w
	return sqrt(sum_sq)


func _fill_octave(ox0: int, oz0: int, nx: int, nz: int, kernel: PackedFloat32Array, rms: float, salt: int) -> PackedFloat32Array:
	var radius := kernel.size() >> 1
	var noise_x0 := ox0 - radius
	var noise_z0 := oz0 - radius
	var noise_nx := nx + radius * 2
	var noise_nz := nz + radius * 2
	var noise := PackedFloat32Array()
	noise.resize(noise_nx * noise_nz)
	for z in noise_nz:
		var iz := noise_z0 + z
		var row_i := z * noise_nx
		for x in noise_nx:
			noise[row_i + x] = _gaussian(noise_x0 + x, iz, salt)
	var horiz := PackedFloat32Array()
	horiz.resize(noise_nz * nx)
	var ks := kernel.size()
	for z2 in noise_nz:
		var base := z2 * noise_nx
		var dest := z2 * nx
		for x2 in nx:
			var acc := 0.0
			for k in ks:
				acc += kernel[k] * noise[base + x2 + k]
			horiz[dest + x2] = acc
	var out := PackedFloat32Array()
	out.resize(nx * nz)
	var inv_rms := 1.0 / rms
	for z3 in nz:
		var dest_row := z3 * nx
		for x3 in nx:
			var acc2 := 0.0
			for k2 in ks:
				acc2 += kernel[k2] * horiz[(z3 + k2) * nx + x3]
			out[dest_row + x3] = acc2 * inv_rms
	return out


func _gaussian(ix: int, iz: int, salt: int) -> float:
	var u1 := _unit(_hash(ix, iz, salt))
	var u2 := _unit(_hash(ix, iz, salt + _SALT_PAIR))
	return sqrt(-2.0 * log(u1)) * cos(TAU * u2)


func _unit(h: int) -> float:
	return (float(h) + 1.0) / 4294967297.0


func _hash(ix: int, iz: int, salt: int) -> int:
	var n := _u32(SEED)
	n = _u32(n + _u32(ix * 374761393))
	n = _u32(n + _u32(iz * 668265263))
	n = _u32(n + _u32(salt * 1442695041))
	n = _u32((n ^ (n >> 16)) * 0x7feb352d)
	n = _u32((n ^ (n >> 15)) * 0x846ca68b)
	return _u32(n ^ (n >> 16))


func _u32(n: int) -> int:
	return n & 0xffffffff
