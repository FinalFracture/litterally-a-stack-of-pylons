extends RefCounted

## Retired. city.gd builds the seeded network in road_network.gd.
## This file stretched straight slabs to close a loop and is not called.
## Seeded closed two-way road built from the supplied, port-matched STL pieces.
## Straight slabs are scaled along local X only. No-stretch turn pieces keep
## their authored proportions and are only rotated or mirrored.
const TARGET_TOTAL_LANE_LENGTH_M := 1000.0
const REFERENCE_BOX_M := 237.5
const BOX_SHRINK := 0.70
const MAX_BOX_M := REFERENCE_BOX_M * BOX_SHRINK
const MAX_PENETRATION_MM := 3.0
const ROAD_Y := 0.025
const LANE_WIDTH_MM := 72.0
const LANE_CENTER_GAP_MM := 80.0
const LANE_GAP_MM := LANE_CENTER_GAP_MM - LANE_WIDTH_MM
const MILLIMETERS_TO_METERS := 3.66 / LANE_WIDTH_MM
const STRAIGHT_SOURCE_MIN_X := -2109.9255
const STRAIGHT_SOURCE_CENTER_Y := 1206.1213
const INSIDE_TURN_ENTRY := Vector2(-1365.9255, 1206.1213)
const INSIDE_TURN_EXIT := Vector2(-1249.9255, 1322.1213)
const OUTSIDE_TURN_ENTRY := Vector2(-301.9255, 1206.1213)
const OUTSIDE_TURN_EXIT := Vector2(-105.9255, 1010.1213)
const INSIDE_TURN_RADIUS_MM := 116.0
const OUTSIDE_TURN_RADIUS_MM := 196.0
const ROAD_EDGE_EXTENT_MM := 44.0
const CURVE_ROUTE_SAMPLES := 24
const ROAD_ASSET_DIR := "res://Models/road_segments/"
const ASPHALT_TEXTURE := "res://materials/asphalt_02/textures/asphalt_02_diff_2k.jpg"
const CENTER_LINE_TEXTURE := "res://materials/asphalt_tile_yellow_stripe_dotted.png"
const EDGE_LINE_TEXTURE := "res://materials/asphalt_tile_white_stripe_full.png"
const SOLID_YELLOW_TEXTURE := "res://materials/asphalt_tile_yellow_stripe_full.png"

const STRAIGHT_SLAB := ROAD_ASSET_DIR + "single_lane_slab.stl"
const STRAIGHT_STRIPE := ROAD_ASSET_DIR + "single_lane_stripe.stl"
const INSIDE_TURN_SLAB := ROAD_ASSET_DIR + "turn_90_inside_lane_slab_no_stretch.stl"
const INSIDE_TURN_STRIPE := ROAD_ASSET_DIR + "turn_90_inside_stripe_no_stretch.stl"
const OUTSIDE_TURN_SLAB := ROAD_ASSET_DIR + "turn_90_outside_lane_slab_no_stretch.stl"
const OUTSIDE_TURN_STRIPE := ROAD_ASSET_DIR + "turn_90_outside_stripe_no_stretch.stl"
const OUTSIDE_EDGE_STRIPE := ROAD_ASSET_DIR + "turn_90_outside_lane_outside_stripe_no_stretch.stl"

var _source_triangle_cache: Dictionary = {}
var _piece_definitions: Array[Dictionary] = []
var _route_forward: Array[PackedVector2Array] = []
var _total_centerline_length_mm := 0.0
var _layout_closed := false
var _turn_ports_aligned := true
var _layout_closure_delta := Vector2.ZERO
var _asphalt_material: StandardMaterial3D
var _yellow_dash_material: StandardMaterial3D
var _yellow_solid_material: StandardMaterial3D
var _white_material: StandardMaterial3D


func build(city: Node3D, center: Vector3, requested_seed := 0) -> void:
	var seed_rng := RandomNumberGenerator.new()
	if requested_seed == 0:
		seed_rng.randomize()
	else:
		seed_rng.seed = requested_seed
	var seed := seed_rng.seed
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var has_chicane := rng.randf() < 0.55
	var depth_mm := rng.randf_range(520.0, 640.0) if has_chicane else 0.0
	var bypass_mm := rng.randf_range(650.0, 780.0) if has_chicane else 0.0
	var turn_count := 8 if has_chicane else 4
	var turn_pair_length_mm := (PI * 0.5) * (INSIDE_TURN_RADIUS_MM + OUTSIDE_TURN_RADIUS_MM)
	var closure_compensation_mm := 1248.0 if has_chicane else 0.0
	var straight_sum_mm := (TARGET_TOTAL_LANE_LENGTH_M / MILLIMETERS_TO_METERS - turn_pair_length_mm * turn_count - 4.0 * depth_mm + closure_compensation_mm) / 4.0
	var x_share := rng.randf_range(0.68, 0.72) if has_chicane else rng.randf_range(0.56, 0.66)
	var straight_x_mm := straight_sum_mm * x_share
	var straight_z_mm := straight_sum_mm - straight_x_mm
	if has_chicane and straight_x_mm - 624.0 - bypass_mm < 850.0:
		straight_x_mm = 624.0 + bypass_mm + 900.0
		straight_z_mm = straight_sum_mm - straight_x_mm

	# Correct small tessellation and floating-point residuals against the centerline
	# length calculated from the actual pieces and closed route, without changing
	# any turn module's scale.
	for _fit_pass in 3:
		_build_layout(straight_x_mm, straight_z_mm, depth_mm, bypass_mm, has_chicane)
		var length_error_m := TARGET_TOTAL_LANE_LENGTH_M - _total_centerline_length_mm * MILLIMETERS_TO_METERS
		straight_x_mm += length_error_m / (4.0 * MILLIMETERS_TO_METERS)

	_build_layout(straight_x_mm, straight_z_mm, depth_mm, bypass_mm, has_chicane)
	var forward_a: PackedVector2Array = _route_forward[0]
	var forward_b: PackedVector2Array = _route_forward[1]
	if not _turn_ports_aligned:
		push_error("Seed %d produced turn ports that do not line up with their straight slabs; road generation was cancelled." % seed)
		return
	if not _layout_closed:
		push_error("Seed %d produced an open loop (chicane=%s, residual=%s mm, points=%d/%d); road generation was cancelled." % [seed, str(has_chicane), str(_layout_closure_delta), forward_a.size(), forward_b.size()])
		return
	if not _validate_piece_placements(_piece_definitions):
		push_error("Seed %d produced road pieces overlapping by more than 3 mm; road generation was cancelled." % seed)
		return

	var bounds := _route_bounds_mm([forward_a, forward_b])
	var box_size_m := Vector2(bounds.size.x, bounds.size.y) * MILLIMETERS_TO_METERS
	if maxf(box_size_m.x, box_size_m.y) > MAX_BOX_M + 0.01:
		push_error("Seed %d produced a %.2f m x %.2f m box, over the %.2f m limit." % [seed, box_size_m.x, box_size_m.y, MAX_BOX_M])
		return

	_create_materials()
	var shift_mm := -bounds.position - bounds.size * 0.5
	var root := Node3D.new()
	root.name = "SeededProvidedPieceRoad"
	root.position = center + Vector3(shift_mm.x * MILLIMETERS_TO_METERS, 0.0, shift_mm.y * MILLIMETERS_TO_METERS)
	root.set_meta("road_seed", seed)
	city.add_child(root)

	for piece_index in _piece_definitions.size():
		var definition: Dictionary = _piece_definitions[piece_index]
		var style: String = definition["style"]
		var material := _material_for_style(style)
		_add_piece_node(root, definition, piece_index, material)

	var route_a := _to_world_route(forward_a, center, shift_mm)
	var reversed_b := forward_b.duplicate()
	reversed_b.reverse()
	var route_b := _to_world_route(reversed_b, center, shift_mm)
	_register_route(city, route_a)
	_register_route(city, route_b)
	city.call("register_road_route", route_a)
	city.set_meta("road_lane_routes", [route_a, route_b])
	city.set_meta("road_lane_route_options", [[route_a], [route_b]])
	city.set_meta("road_total_lane_length_m", _total_centerline_length_mm * MILLIMETERS_TO_METERS)
	city.set_meta("road_lane_length_m", [
		_route_length_m(forward_a),
		_route_length_m(forward_b),
	])
	city.set_meta("road_network_length_m", _total_centerline_length_mm * MILLIMETERS_TO_METERS)
	city.set_meta("road_seed", seed)
	city.set_meta("road_bounding_box_limit_m", MAX_BOX_M)
	city.set_meta("road_bounding_box_m", box_size_m)
	city.set_meta("road_lane_gap_m", LANE_GAP_MM * MILLIMETERS_TO_METERS)
	city.set_meta("road_overlap_tolerance_m", MAX_PENETRATION_MM * MILLIMETERS_TO_METERS)
	city.set_meta("road_chicane_enabled", has_chicane)
	city.set_meta("road_piece_source", "Models/road_segments STL")
	LaunchConfig.log_line("Generated modular road seed: %d | %.1f m total | box %.1f x %.1f m | chicane %s" % [seed, _total_centerline_length_mm * MILLIMETERS_TO_METERS, box_size_m.x, box_size_m.y, str(has_chicane)])


func _build_layout(straight_x_mm: float, straight_z_mm: float, depth_mm: float, bypass_mm: float, has_chicane: bool) -> void:
	_piece_definitions.clear()
	_route_forward.clear()
	_route_forward.append(PackedVector2Array())
	_route_forward.append(PackedVector2Array())
	_total_centerline_length_mm = 0.0
	_layout_closed = false
	_turn_ports_aligned = true
	_layout_closure_delta = Vector2.ZERO

	var cursor := Vector2.ZERO
	var direction := 0 # 0=east, 1=south, 2=west, 3=north in source asset space.
	var start := cursor
	var start_turn := _append_turn(cursor, direction, true)
	cursor = start_turn["exit_a"]
	direction = int(start_turn["direction_after"])
	_append_straight(cursor, direction, straight_z_mm)
	cursor += _direction_vector(direction) * straight_z_mm

	var turn := _append_turn(cursor, direction, true)
	cursor = turn["exit_a"]
	direction = int(turn["direction_after"])
	_append_straight(cursor, direction, straight_x_mm)
	cursor += _direction_vector(direction) * straight_x_mm

	turn = _append_turn(cursor, direction, true)
	cursor = turn["exit_a"]
	direction = int(turn["direction_after"])
	_append_straight(cursor, direction, straight_z_mm)
	cursor += _direction_vector(direction) * straight_z_mm

	turn = _append_turn(cursor, direction, true)
	cursor = turn["exit_a"]
	direction = int(turn["direction_after"])

	if has_chicane:
		var extra_turn_x_advance := 2.0 * (INSIDE_TURN_RADIUS_MM + OUTSIDE_TURN_RADIUS_MM)
		var side_straight_total := straight_x_mm - extra_turn_x_advance
		var first_run := (side_straight_total - bypass_mm) * 0.5
		if first_run <= 420.0:
			first_run = 420.0
		_append_straight(cursor, direction, first_run)
		cursor += _direction_vector(direction) * first_run

		turn = _append_turn(cursor, direction, true)
		cursor = turn["exit_a"]
		direction = int(turn["direction_after"])
		_append_straight(cursor, direction, depth_mm)
		cursor += _direction_vector(direction) * depth_mm

		turn = _append_turn(cursor, direction, false)
		cursor = turn["exit_a"]
		direction = int(turn["direction_after"])
		_append_straight(cursor, direction, bypass_mm)
		cursor += _direction_vector(direction) * bypass_mm

		turn = _append_turn(cursor, direction, false)
		cursor = turn["exit_a"]
		direction = int(turn["direction_after"])
		_append_straight(cursor, direction, depth_mm)
		cursor += _direction_vector(direction) * depth_mm

		turn = _append_turn(cursor, direction, true)
		cursor = turn["exit_a"]
		direction = int(turn["direction_after"])
		var required_final_run := (start - cursor).dot(_direction_vector(direction))
		var lateral_error := absf((start - cursor).dot(_left_normal(direction)))
		if lateral_error > 0.01 or required_final_run <= 420.0:
			_layout_closure_delta = Vector2(required_final_run, lateral_error)
			_piece_definitions.clear()
			return
		_append_straight(cursor, direction, required_final_run)
		cursor += _direction_vector(direction) * required_final_run
	else:
		_append_straight(cursor, direction, straight_x_mm)
		cursor += _direction_vector(direction) * straight_x_mm

	var route_b_start := start + _left_normal(0) * LANE_CENTER_GAP_MM
	var route_b_end := cursor + _left_normal(direction) * LANE_CENTER_GAP_MM
	_layout_closure_delta = cursor - start
	_layout_closed = cursor.distance_to(start) <= 0.01 and route_b_end.distance_to(route_b_start) <= 0.01
	if _layout_closed:
		for lane_index in 2:
			var points: PackedVector2Array = _route_forward[lane_index]
			if points.size() > 1 and points[points.size() - 1].distance_to(points[0]) <= 0.01:
				points.remove_at(points.size() - 1)
				_route_forward[lane_index] = points


func _append_turn(entry_a: Vector2, direction: int, turn_right: bool) -> Dictionary:
	var left := _left_normal(direction)
	var entry_b := entry_a + left * LANE_CENTER_GAP_MM
	var angle := _direction_angle(direction)
	var inside_asset := turn_right
	var lane_a_path := INSIDE_TURN_SLAB if inside_asset else OUTSIDE_TURN_SLAB
	var lane_b_path := OUTSIDE_TURN_SLAB if inside_asset else INSIDE_TURN_SLAB
	var lane_a_stripe := INSIDE_TURN_STRIPE if inside_asset else OUTSIDE_TURN_STRIPE
	var lane_b_stripe := OUTSIDE_TURN_STRIPE if inside_asset else INSIDE_TURN_STRIPE
	var lane_a_entry := INSIDE_TURN_ENTRY if inside_asset else OUTSIDE_TURN_ENTRY
	var lane_b_entry := OUTSIDE_TURN_ENTRY if inside_asset else INSIDE_TURN_ENTRY
	var lane_a_exit := INSIDE_TURN_EXIT if inside_asset else OUTSIDE_TURN_EXIT
	var lane_b_exit := OUTSIDE_TURN_EXIT if inside_asset else INSIDE_TURN_EXIT
	var mirror_a := true
	# The inside piece already turns left in its authored orientation; only the
	# outside turn needs mirroring on a left-hand bend.
	var mirror_b := false

	_append_asset(lane_a_path, "asphalt_turn", lane_a_entry, entry_a, angle, mirror_a, 0.0, "RoadTurnA", 0)
	_append_asset(lane_a_stripe, "yellow_solid", lane_a_entry, entry_a, angle, mirror_a, 0.0, "TurnStripeA", 0)
	_append_asset(lane_b_path, "asphalt_turn", lane_b_entry, entry_b, angle, mirror_b, 0.0, "RoadTurnB", 1)
	_append_asset(lane_b_stripe, "yellow_solid", lane_b_entry, entry_b, angle, mirror_b, 0.0, "TurnStripeB", 1)
	if not inside_asset:
		_append_asset(OUTSIDE_EDGE_STRIPE, "white", lane_b_entry, entry_b, angle, mirror_b, 0.0, "TurnOutsideEdgeB", 1)

	var radius_a := INSIDE_TURN_RADIUS_MM if inside_asset else OUTSIDE_TURN_RADIUS_MM
	var radius_b := OUTSIDE_TURN_RADIUS_MM if inside_asset else INSIDE_TURN_RADIUS_MM
	var turn_sign := -1.0 if turn_right else 1.0
	var exit_a := _asset_turn_exit(entry_a, lane_a_entry, lane_a_exit, mirror_a, angle)
	var exit_b := _asset_turn_exit(entry_b, lane_b_entry, lane_b_exit, mirror_b, angle)
	var expected_exit_a := _turn_exit_point(entry_a, direction, turn_right, radius_a)
	var expected_exit_b := _turn_exit_point(entry_b, direction, turn_right, radius_b)
	if exit_a.distance_to(expected_exit_a) > 0.01 or exit_b.distance_to(expected_exit_b) > 0.01:
		_turn_ports_aligned = false
	var exit_direction := (direction + (1 if turn_right else 3)) % 4
	if exit_b.distance_to(exit_a + _left_normal(exit_direction) * LANE_CENTER_GAP_MM) > 0.01:
		_turn_ports_aligned = false
	if _route_forward[0].is_empty():
		_append_route_point(0, entry_a)
		_append_route_point(1, entry_b)
	for sample_index in range(1, CURVE_ROUTE_SAMPLES + 1):
		var angle_delta := turn_sign * (PI * 0.5) * float(sample_index) / float(CURVE_ROUTE_SAMPLES)
		var center_a := _turn_center(entry_a, direction, turn_right, radius_a)
		var center_b := _turn_center(entry_b, direction, turn_right, radius_b)
		_append_route_point(0, center_a + (entry_a - center_a).rotated(angle_delta))
		_append_route_point(1, center_b + (entry_b - center_b).rotated(angle_delta))
	_total_centerline_length_mm += (radius_a + radius_b) * (PI * 0.5)
	return {"exit_a": exit_a, "exit_b": exit_b, "direction_after": exit_direction}


func _append_straight(start_a: Vector2, direction: int, length_mm: float) -> void:
	if length_mm <= 0.0:
		return
	var forward := _direction_vector(direction)
	var left := _left_normal(direction)
	var start_b := start_a + left * LANE_CENTER_GAP_MM
	var angle := _direction_angle(direction)
	_append_asset(STRAIGHT_SLAB, "asphalt_straight", Vector2(STRAIGHT_SOURCE_MIN_X, STRAIGHT_SOURCE_CENTER_Y), start_a, angle, false, length_mm, "RoadStraightA", 0)
	_append_asset(STRAIGHT_STRIPE, "yellow_dash", Vector2(STRAIGHT_SOURCE_MIN_X, STRAIGHT_SOURCE_CENTER_Y), start_a, angle, false, length_mm, "CenterStripeA", 0)
	_append_asset(STRAIGHT_SLAB, "asphalt_straight", Vector2(STRAIGHT_SOURCE_MIN_X, STRAIGHT_SOURCE_CENTER_Y), start_b, angle, false, length_mm, "RoadStraightB", 1)
	_append_asset(STRAIGHT_STRIPE, "white", Vector2(STRAIGHT_SOURCE_MIN_X, STRAIGHT_SOURCE_CENTER_Y), start_b, angle, false, length_mm, "OuterStripeB", 1)
	for lane_index in 2:
		var points: PackedVector2Array = _route_forward[lane_index]
		var lane_start: Vector2 = start_a if lane_index == 0 else start_b
		if points.is_empty():
			points.append(lane_start)
		var sample_count := maxi(1, ceili(length_mm / 100.0))
		for sample_index in range(1, sample_count + 1):
			var point: Vector2 = lane_start + forward * length_mm * float(sample_index) / float(sample_count)
			if points[points.size() - 1].distance_to(point) > 0.001:
				points.append(point)
		_route_forward[lane_index] = points
	_total_centerline_length_mm += length_mm * 2.0


func _append_asset(path: String, style: String, source_anchor: Vector2, target_anchor: Vector2, angle: float, mirror_y: bool, stretch_length_mm: float, node_prefix: String, lane_index: int) -> void:
	_piece_definitions.append({
		"path": path,
		"style": style,
		"source_anchor": source_anchor,
		"target_anchor": target_anchor,
		"angle": angle,
		"mirror_y": mirror_y,
		"stretch_length_mm": stretch_length_mm,
		"node_prefix": "%s_%02d" % [node_prefix, _piece_definitions.size()],
		"lane_index": lane_index,
	})


func _add_piece_node(root: Node3D, definition: Dictionary, index: int, material: Material) -> void:
	var path: String = definition["path"]
	var vertices: PackedVector3Array = _source_triangles(path)
	if vertices.is_empty():
		return
	var local_vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var angle: float = definition["angle"]
	var mirror_y: bool = definition["mirror_y"]
	var stretch_length: float = definition["stretch_length_mm"]
	var target: Vector2 = definition["target_anchor"]
	var style: String = definition["style"]
	var stripe_direction := Vector2(cos(angle), sin(angle))
	var stripe_lateral := Vector2(-stripe_direction.y, stripe_direction.x)
	for vertex_index in vertices.size():
		var source: Vector3 = vertices[vertex_index]
		var local_mm := _piece_local_point(definition, Vector2(source.x, source.y))
		local_vertices.append(Vector3(local_mm.x * MILLIMETERS_TO_METERS, ROAD_Y + _surface_lift(style), local_mm.y * MILLIMETERS_TO_METERS))
		normals.append(Vector3.UP)
		uvs.append(_piece_uv(style, local_mm, stripe_direction, stripe_lateral))
		indices.append(vertex_index)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = local_vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, material)
	var body := StaticBody3D.new()
	body.name = "%s_%03d" % [String(definition["node_prefix"]), index]
	body.position = Vector3(target.x * MILLIMETERS_TO_METERS, 0.0, target.y * MILLIMETERS_TO_METERS)
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("road_lane_index", int(definition["lane_index"]))
	body.set_meta("road_piece_kind", "surface" if style.begins_with("asphalt") else "marking")
	body.set_meta("road_piece_style", style)
	body.set_meta("road_source_mesh", path)
	root.add_child(body)
	var visual := MeshInstance3D.new()
	visual.name = "ProvidedRoadPiece"
	visual.mesh = mesh
	body.add_child(visual)
	if style.begins_with("asphalt"):
		var collision := CollisionShape3D.new()
		collision.shape = mesh.create_trimesh_shape()
		body.add_child(collision)
	else:
		body.collision_layer = 0


func _piece_local_point(definition: Dictionary, source: Vector2) -> Vector2:
	var local: Vector2
	var stretch_length: float = definition["stretch_length_mm"]
	if stretch_length > 0.0:
		var along := (source.x - STRAIGHT_SOURCE_MIN_X) * stretch_length / LANE_WIDTH_MM
		var across := source.y - STRAIGHT_SOURCE_CENTER_Y
		local = Vector2(along, across)
	else:
		local = source - definition["source_anchor"]
		if bool(definition["mirror_y"]):
			local.y = -local.y
	return local.rotated(float(definition["angle"]))


func _piece_uv(style: String, local_mm: Vector2, stripe_direction: Vector2, stripe_lateral: Vector2) -> Vector2:
	if style == "yellow_dash":
		var along_m := local_mm.dot(stripe_direction) * MILLIMETERS_TO_METERS
		var across_m := local_mm.dot(stripe_lateral) * MILLIMETERS_TO_METERS
		return Vector2(along_m / 4.0, 0.04 + clampf((across_m / 0.406) * 0.14, 0.0, 0.14))
	return Vector2(local_mm.x, local_mm.y) * MILLIMETERS_TO_METERS * 0.5


func _surface_lift(style: String) -> float:
	if style == "yellow_dash" or style == "yellow_solid" or style == "white":
		return 0.006
	return 0.0


func _create_materials() -> void:
	_asphalt_material = _texture_material(ASPHALT_TEXTURE, Color(1.0, 1.0, 1.0), 0.96)
	_yellow_dash_material = _texture_material(CENTER_LINE_TEXTURE, Color.WHITE, 0.9)
	_yellow_solid_material = _texture_material(SOLID_YELLOW_TEXTURE, Color.WHITE, 0.9)
	_white_material = _texture_material(EDGE_LINE_TEXTURE, Color.WHITE, 0.9)


func _material_for_style(style: String) -> Material:
	if style == "yellow_dash":
		return _yellow_dash_material
	if style == "yellow_solid":
		return _yellow_solid_material
	if style == "white":
		return _white_material
	return _asphalt_material


func _texture_material(texture_path: String, tint: Color, roughness_value: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.albedo_texture = load(texture_path) as Texture2D
	material.roughness = roughness_value
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.uv1_scale = Vector3.ONE
	return material


func _source_triangles(path: String) -> PackedVector3Array:
	if _source_triangle_cache.has(path):
		return _source_triangle_cache[path]
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 84:
		push_error("Could not read supplied road STL: %s" % path)
		return PackedVector3Array()
	file.get_buffer(80)
	var triangle_count := file.get_32()
	var vertices := PackedVector3Array()
	for _triangle in triangle_count:
		# STL stores one normal, then three vertices, then a two-byte attribute.
		file.get_float()
		file.get_float()
		file.get_float()
		vertices.append(Vector3(file.get_float(), file.get_float(), file.get_float()))
		vertices.append(Vector3(file.get_float(), file.get_float(), file.get_float()))
		vertices.append(Vector3(file.get_float(), file.get_float(), file.get_float()))
		file.get_16()
	_source_triangle_cache[path] = vertices
	return vertices


func _validate_piece_placements(definitions: Array[Dictionary]) -> bool:
	var road_pieces: Array[Dictionary] = []
	for definition in definitions:
		if not String(definition["style"]).begins_with("asphalt"):
			continue
		var triangles := _triangles_for_definition(definition)
		if triangles.is_empty():
			push_error("Missing road surface triangles for %s." % String(definition["path"]))
			return false
		var bounds := _triangle_bounds(triangles)
		for prior in road_pieces:
			var prior_bounds: Rect2 = prior["bounds"]
			if not _bounds_overlap_with_tolerance(bounds, prior_bounds, MAX_PENETRATION_MM):
				continue
			var overlap := _piece_overlap_depth(triangles, prior["triangles"])
			if overlap > MAX_PENETRATION_MM:
				push_warning("Road asset placement rejected: %s at %s against %s at %s overlaps by %.2f mm." % [String(definition["node_prefix"]), str(definition["target_anchor"]), String(prior["node_prefix"]), str(prior["target_anchor"]), overlap])
				return false
		road_pieces.append({"path": definition["path"], "node_prefix": definition["node_prefix"], "target_anchor": definition["target_anchor"], "triangles": triangles, "bounds": bounds})
	return true


func _triangles_for_definition(definition: Dictionary) -> Array[PackedVector2Array]:
	var source: PackedVector3Array = _source_triangles(String(definition["path"]))
	var result: Array[PackedVector2Array] = []
	for i in range(0, source.size(), 3):
		var triangle := PackedVector2Array()
		for vertex_index in range(i, mini(i + 3, source.size())):
			var vertex: Vector3 = source[vertex_index]
			triangle.append(_piece_local_point(definition, Vector2(vertex.x, vertex.y)) + definition["target_anchor"])
		if triangle.size() == 3:
			result.append(triangle)
	return result


func _triangle_bounds(triangles: Array[PackedVector2Array]) -> Rect2:
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for triangle in triangles:
		for point in triangle:
			min_x = minf(min_x, point.x)
			min_y = minf(min_y, point.y)
			max_x = maxf(max_x, point.x)
			max_y = maxf(max_y, point.y)
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)


func _bounds_overlap_with_tolerance(a: Rect2, b: Rect2, tolerance: float) -> bool:
	return a.position.x <= b.end.x + tolerance and b.position.x <= a.end.x + tolerance and a.position.y <= b.end.y + tolerance and b.position.y <= a.end.y + tolerance


func _piece_overlap_depth(a: Array[PackedVector2Array], b: Array[PackedVector2Array]) -> float:
	var maximum_overlap := 0.0
	for triangle_a in a:
		for triangle_b in b:
			if not _triangle_bounds_overlap(triangle_a, triangle_b):
				continue
			maximum_overlap = maxf(maximum_overlap, _triangle_overlap_depth(triangle_a, triangle_b))
			if maximum_overlap > MAX_PENETRATION_MM:
				return maximum_overlap
	return maximum_overlap


func _triangle_bounds_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	var min_ax := INF
	var min_ay := INF
	var max_ax := -INF
	var max_ay := -INF
	var min_bx := INF
	var min_by := INF
	var max_bx := -INF
	var max_by := -INF
	for point in a:
		min_ax = minf(min_ax, point.x)
		min_ay = minf(min_ay, point.y)
		max_ax = maxf(max_ax, point.x)
		max_ay = maxf(max_ay, point.y)
	for point in b:
		min_bx = minf(min_bx, point.x)
		min_by = minf(min_by, point.y)
		max_bx = maxf(max_bx, point.x)
		max_by = maxf(max_by, point.y)
	return min_ax <= max_bx + MAX_PENETRATION_MM and min_bx <= max_ax + MAX_PENETRATION_MM and min_ay <= max_by + MAX_PENETRATION_MM and min_by <= max_ay + MAX_PENETRATION_MM


func _triangle_overlap_depth(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var minimum_overlap := INF
	for polygon_index in 2:
		var polygon: PackedVector2Array = a if polygon_index == 0 else b
		for edge_index in 3:
			var edge: Vector2 = polygon[(edge_index + 1) % 3] - polygon[edge_index]
			if edge.length_squared() < 0.000001:
				continue
			var axis := Vector2(-edge.y, edge.x).normalized()
			var min_a := INF
			var max_a := -INF
			var min_b := INF
			var max_b := -INF
			for point in a:
				var projection := point.dot(axis)
				min_a = minf(min_a, projection)
				max_a = maxf(max_a, projection)
			for point in b:
				var projection := point.dot(axis)
				min_b = minf(min_b, projection)
				max_b = maxf(max_b, projection)
			var overlap := minf(max_a, max_b) - maxf(min_a, min_b)
			if overlap <= 0.0:
				return 0.0
			minimum_overlap = minf(minimum_overlap, overlap)
	return minimum_overlap


func _route_bounds_mm(routes: Array[PackedVector2Array]) -> Rect2:
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for route in routes:
		for point in route:
			min_x = minf(min_x, point.x)
			min_y = minf(min_y, point.y)
			max_x = maxf(max_x, point.x)
			max_y = maxf(max_y, point.y)
	return Rect2(min_x - ROAD_EDGE_EXTENT_MM, min_y - ROAD_EDGE_EXTENT_MM, max_x - min_x + ROAD_EDGE_EXTENT_MM * 2.0, max_y - min_y + ROAD_EDGE_EXTENT_MM * 2.0)


func _append_route_point(lane_index: int, point: Vector2) -> void:
	var route: PackedVector2Array = _route_forward[lane_index]
	if route.is_empty() or route[route.size() - 1].distance_to(point) > 0.001:
		route.append(point)
	_route_forward[lane_index] = route


func _turn_center(entry: Vector2, direction: int, turn_right: bool, radius: float) -> Vector2:
	var left := _left_normal(direction)
	return entry - left * radius if turn_right else entry + left * radius


func _turn_exit_point(entry: Vector2, direction: int, turn_right: bool, radius: float) -> Vector2:
	var center := _turn_center(entry, direction, turn_right, radius)
	var sign := -1.0 if turn_right else 1.0
	return center + (entry - center).rotated(sign * PI * 0.5)


func _asset_turn_exit(target_entry: Vector2, source_entry: Vector2, source_exit: Vector2, mirror_y: bool, angle: float) -> Vector2:
	var delta := source_exit - source_entry
	if mirror_y:
		delta.y = -delta.y
	return target_entry + delta.rotated(angle)


func _direction_vector(direction: int) -> Vector2:
	match posmod(direction, 4):
		0: return Vector2.RIGHT
		1: return Vector2(0.0, -1.0)
		2: return Vector2.LEFT
		_: return Vector2(0.0, 1.0)


func _left_normal(direction: int) -> Vector2:
	var forward := _direction_vector(direction)
	return Vector2(-forward.y, forward.x)


func _direction_angle(direction: int) -> float:
	return -PI * 0.5 * float(posmod(direction, 4))


func _route_length_m(route: PackedVector2Array) -> float:
	var length_mm := 0.0
	for i in range(route.size() - 1):
		length_mm += route[i].distance_to(route[i + 1])
	if route.size() > 2:
		length_mm += route[route.size() - 1].distance_to(route[0])
	return length_mm * MILLIMETERS_TO_METERS


func _to_world_route(route: PackedVector2Array, center: Vector3, shift_mm: Vector2) -> PackedVector3Array:
	var result := PackedVector3Array()
	for point in route:
		var shifted := point + shift_mm
		result.append(Vector3(center.x + shifted.x * MILLIMETERS_TO_METERS, center.y, center.z + shifted.y * MILLIMETERS_TO_METERS))
	return result


func _register_route(city: Node3D, path: PackedVector3Array) -> void:
	for i in path.size():
		var next_i := (i + 1) % path.size()
		var a := path[i]
		var b := path[next_i]
		city.call("register_road_segment", a, b)
		var pad := LANE_WIDTH_MM * MILLIMETERS_TO_METERS * 0.5
		city.call("register_road_surface", Rect2(minf(a.x, b.x) - pad, minf(a.z, b.z) - pad, absf(a.x - b.x) + pad * 2.0, absf(a.z - b.z) + pad * 2.0))
