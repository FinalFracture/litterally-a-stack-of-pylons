extends RefCounted

## District mesh for the loaded chunk.
## Each chunk keeps one or two main arteries. Parallel arteries leave a local street between them.
## A median opens only on a main-artery gap long enough for the flare. Collectors stay two-lane.
## Each chunk grows 2-5 districts. Alley, radial, strips, court, and campus
## each use a different street plan. Corners use the turn module.
## A 4-way module is used only when every mouth meets another road.
## Gravel fills the stripe footprints, so a dirt road has no line channel.
## Where gravel meets asphalt, the paint on that shared edge is left off.
## Dirt shoulders blend that gravel into the rocky ground. Stripes stay off.
## Paved roads wear the sidewalk pieces. Outside corners use the corner slab. Lamps sit past that walk.
## Grass fills only the blocks between roads. A block that meets a sidewalk
## rises to that walk, and the buildings stand on it.
## Street lamps, signal masts, stop signs, speed signs, and parking barriers
## use the decoration pieces. Artery medians use the planter tiles and round caps.

const _Layout = preload("res://scripts/road_chunk_layout.gd")

const UNIT := 3.66 / 72.0
const TILE := 72.0 * UNIT
const CROSS := 168.0 * UNIT
const HALF := 84.0 * UNIT
const TURN := 156.0 * UNIT
const LANE := 40.0 * UNIT
const ROAD_Y := 0.025
const MARK_Y := 0.036
const ARTERIAL_TILES := 26
const DIRT_CROSS := 144.0 * UNIT
const DIRT_HALF := 72.0 * UNIT
const MIN_SPLIT_TILES := 14
const SPLIT_LEAD := 2
const SPLIT_RUN := 6
const TAPER_TILES := 2
const TAPER_U := 144.0
const SIDEWALK := 3.4
const WALK_X0 := 172.66067505
const WALK_Y0 := -10.07819843
const TURN_CX := 515.66064453125
const TURN_CY := 151.54977416992188
const FLARE_X0 := 1290.66064453125
const FLARE_Y0 := 117.22077178955078
const CORNER_AX := -1821.925537109375
const CORNER_AY := 1082.121337890625
const CORNER_ALONG := 78.0 * UNIT
const WALK_W := 54.0 * UNIT
const WALK_TOP := ROAD_Y + 6.0 * UNIT
const SIDE_LIFT := 0.001
const SHOULDER_U := 20.0
const SPAWN_CLEAR := 18.0
const STACK_CAP := 36
const STACK_GAP := 28.0
const STACK_END := 7.0
const STACK_SPAWN := 14.0
const LOT_THICK := 0.55
const SIGN_SCALE := 0.001
const STL_DIR := "res://Models/road_segments/"
const DECOR_DIR := "res://Models/road_decorations/"
const STRAIGHT_X0 := -2109.925537109375
const STRAIGHT_Y0 := 1206.121337890625
const INSIDE_X0 := -1365.925537109375
const INSIDE_Y0 := 1206.121337890625
const OUTSIDE_X0 := -301.925537109375
const OUTSIDE_Y0 := 1206.121337890625
const CROSS_X0 := -1821.925537109375
const CROSS_Y0 := 1166.121337890625
const SPLIT_X0 := -145.92550659179688
const SPLIT_Y0 := 2.121323823928833

var _mesh: Dictionary = {}
var _xf: Dictionary = {}
var _boxes: Array[Dictionary] = []
var _blocks: Array[Dictionary] = []
var _medians: Array[Dictionary] = []
var _used_glb := false
var _tiles := 0
var _turns := 0
var _crossings := 0
var _splits := 0
var _rects := 0
var _clash := 0
var _joint_error := 0.0
var _asphalt_mat: StandardMaterial3D
var _gravel_mat: StandardMaterial3D
var _concrete_mat: StandardMaterial3D
var _dirt_straight_mat: Material
var _dirt_turn_mat: Material
var _dirt_cross_mat: Material
var _yellow_mat: StandardMaterial3D
var _white_mat: StandardMaterial3D
var _wall_mats: Array[StandardMaterial3D] = []
var _curb_mat: StandardMaterial3D
var _plant_mat: StandardMaterial3D
var _trunk_mat: StandardMaterial3D
var _canopy_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D
var _ground_mat: Material
var _part_mats: Dictionary = {}
var _segments: Array[Dictionary] = []
var _rects_pending: Array[Dictionary] = []
var _stack_sites: Array[Dictionary] = []
var _portals: Array[Dictionary] = []
var _portal_keys: Dictionary = {}
var _rng: RandomNumberGenerator
var _lattice: Dictionary = {}
var _split_key: Dictionary = {}
var _split_run: Dictionary = {}
var _artery_x: Dictionary = {}
var _artery_z: Dictionary = {}
var _artery_count := 0
var _artery_mode := 0
var _station_x: Dictionary = {}
var _station_z: Dictionary = {}
var _span_tiles_x: Dictionary = {}
var _span_tiles_z: Dictionary = {}
var _open: Dictionary = {}
var _gap_seen: Dictionary = {}
var _world_seed := 0
var _index_x0 := 0
var _index_x1 := 0
var _index_z0 := 0
var _index_z1 := 0
var _span_min := 0.0
var _span_max := 0.0
var _closed := 0
var _parks := 0
var _portal_gaps := 0
var _open_edges := 0
var _weak_chunks := 0
var _tour: PackedVector3Array = PackedVector3Array()
var _tour_back: PackedVector3Array = PackedVector3Array()
var _tour_alt: PackedVector3Array = PackedVector3Array()
var _tour_alt_back: PackedVector3Array = PackedVector3Array()
var _split_spans: Array[Dictionary] = []
var _controls: Array[Dictionary] = []
var _cross_points: Array[Vector2] = []
var _run := 0.0
var _clear_at := Vector2.ZERO
var _clear_ok := true
var _paint_count := 0
var _district_label := ""
var _district_count := 0
var _dirt_centers: Array[Vector2] = []
var _mouths: Array[Dictionary] = []
var _asphalt_lips: Array[Dictionary] = []
var _dirt_caps: Array[Dictionary] = []
var _paint_edges: Array[Dictionary] = []
var _bare: Array[Dictionary] = []
var _decors: Array[Dictionary] = []
var _surfaces: Array[Dictionary] = []
var _median_tiles: Array[Dictionary] = []
var _overlap_pairs := 0
var _overlap_worst: float = 0.0
var _lamp_locals: Array[Vector3] = []
var _signal_arm_y: float = 8.6
var _signal_glow_local := Vector3(0.0, -0.4, 0.0)
var _signal_mats: Dictionary = {}
var _walk_boxes: Array[Dictionary] = []
var _aprons: Array[Dictionary] = []
var _paved_crosses: Array[Vector2] = []
var _mouth_corners: Array[Rect2] = []
var _walk_corners: Array[Dictionary] = []
var _tri_cache: Dictionary = {}
var _split_profile: PackedVector2Array = PackedVector2Array()
var _cut_walks: Array[Dictionary] = []
var _walks: Array[Rect2] = []
var _lots: Array[Dictionary] = []
var _turn_specs: Array[Dictionary] = []
var _flare_specs: Array[Dictionary] = []
var _walk_straight := 0
var _walk_turns := 0
var _walk_flares := 0
var _empty_mouths := 0
var _bare_count := 0


func build(city: Node3D, center: Vector3, requested_seed: int = 0) -> void:
	var seed: int = _roll_seed(requested_seed)
	_reset_build(center)
	_world_seed = seed
	if not _load_modules():
		push_error("Road modules failed to load. No city was built.")
		return
	_make_materials()
	var home: Vector2i = _Layout.chunk_of(center.x, center.z)
	var window: Array[Vector2i] = _Layout.active_window(home)
	_prepare_plan(seed, window)
	for chunk in window:
		var cell: Vector2i = chunk
		_build_chunk(seed, cell, cell == home)
	_audit_links(window)
	_drop_bare_paint()
	_audit_mouths()
	_audit_arteries(home, window)
	_plan_lots(center)
	_lift_blocks()
	_plan_decor()
	_gap_sidewalks()
	_plan_median_tiles()
	_audit_overlaps(seed)
	_spawn(city)
	_register_route(city)
	_publish_cone_stacks(city)
	var straight_size := Vector3.ZERO
	var split_size := Vector3.ZERO
	var dirt_straight := Vector3.ZERO
	var dirt_cross := Vector3.ZERO
	if _mesh.has("straight_asphalt"):
		straight_size = (_mesh["straight_asphalt"] as Mesh).get_aabb().size
	if _mesh.has("split_asphalt"):
		split_size = (_mesh["split_asphalt"] as Mesh).get_aabb().size
	if _mesh.has("straight_dirt"):
		dirt_straight = (_mesh["straight_dirt"] as Mesh).get_aabb().size
	if _mesh.has("cross_dirt"):
		dirt_cross = (_mesh["cross_dirt"] as Mesh).get_aabb().size
	var edges: PackedStringArray = _edge_names()
	city.set_meta("road_seed", seed)
	city.set_meta("road_home_length_m", _run)
	city.set_meta("road_min_length_m", _run)
	city.set_meta("road_max_length_m", _run)
	city.set_meta("road_chunk_lengths", [_run])
	city.set_meta("road_tile_count", _tiles)
	city.set_meta("road_turn_count", _turns)
	city.set_meta("road_crossing_count", _crossings)
	city.set_meta("road_split_count", _splits)
	city.set_meta("road_portal_count", _portals.size())
	city.set_meta("road_portal_edges", edges)
	city.set_meta("road_portals", _portals.duplicate())
	city.set_meta("road_portal_gaps", _portal_gaps)
	city.set_meta("road_open_edges", _open_edges)
	city.set_meta("road_weak_chunks", _weak_chunks)
	city.set_meta("road_building_count", _blocks.size())
	city.set_meta("road_building_clash", _clash)
	city.set_meta("road_spawn_clear", _clear_ok)
	city.set_meta("road_joint_error", _joint_error)
	city.set_meta("road_split_size", split_size)
	city.set_meta("road_rect_count", _rects)
	city.set_meta("road_chunk_m", _Layout.CHUNK_SIZE_M)
	city.set_meta("road_chunk_count", window.size())
	city.set_meta("road_pitch_m", (_span_min + _span_max) * 0.5)
	city.set_meta("road_span_min_m", _span_min)
	city.set_meta("road_span_max_m", _span_max)
	city.set_meta("road_gap_kinds", _gap_seen.size())
	city.set_meta("road_closed_count", _closed)
	city.set_meta("road_park_count", _parks)
	city.set_meta("road_lane_m", LANE)
	city.set_meta("road_used_glb", _used_glb)
	city.set_meta("road_straight_size", straight_size)
	city.set_meta("road_piece_source", "Models/road_modules")
	city.set_meta("road_district", _district_label)
	city.set_meta("road_district_count", _district_count)
	city.set_meta("road_surface", "mixed")
	city.set_meta("road_dirt_straight_size", dirt_straight)
	city.set_meta("road_dirt_cross_size", dirt_cross)
	city.set_meta("road_paint_count", _paint_count)
	city.set_meta("road_junctions", _cross_points.duplicate())
	_publish_drive(city)
	city.set_meta("road_home_chicanes", _closed)
	city.set_meta("road_empty_mouths", _empty_mouths)
	city.set_meta("road_bare_seams", _bare_count)
	city.set_meta("road_median_count", _medians.size())
	city.set_meta("road_decor_count", _decors.size())
	city.set_meta("road_artery_count", _artery_count)
	city.set_meta("road_artery_mode", _artery_mode)
	city.set_meta("road_walk_straight", _walk_straight)
	city.set_meta("road_walk_turns", _walk_turns)
	city.set_meta("road_walk_flares", _walk_flares)
	city.set_meta("road_walk_boxes", _walk_boxes.size())
	city.set_meta("road_lot_count", _lots.size())
	city.set_meta("road_overlap_pairs", _overlap_pairs)
	city.set_meta("road_overlap_worst", _overlap_worst)
	city.set_meta("signal_mats", _signal_mats)
	city.set_meta("street_bulb_mat", _part_mats.get("bulbs_industrial", null))
	LaunchConfig.log_line("District mesh seed %d | %d districts %s | arteries %d mode %d | span %.0f m | %d crossings | %d turns | %d closed | %d buildings | paint %d | bare %d | medians %d | decor %d | walks %d/%d/%d | lots %d | empty %d | joint %.3f m | overlaps %d worst %.3f | %d chunks" % [seed, _district_count, _district_label, _artery_count, _artery_mode, _span_min, _crossings, _turns, _closed, _blocks.size(), _paint_count, _bare_count, _medians.size(), _decors.size(), _walk_straight, _walk_turns, _walk_flares, _lots.size(), _empty_mouths, _joint_error, _overlap_pairs, _overlap_worst, window.size()])


func _reset_build(center: Vector3) -> void:
	_xf.clear()
	_boxes.clear()
	_blocks.clear()
	_medians.clear()
	_segments.clear()
	_rects_pending.clear()
	_portals.clear()
	_portal_keys.clear()
	_lattice.clear()
	_split_key.clear()
	_split_run.clear()
	_artery_x.clear()
	_artery_z.clear()
	_artery_count = 0
	_artery_mode = 0
	_station_x.clear()
	_station_z.clear()
	_span_tiles_x.clear()
	_span_tiles_z.clear()
	_open.clear()
	_gap_seen.clear()
	_world_seed = 0
	_index_x0 = 0
	_index_x1 = 0
	_index_z0 = 0
	_index_z1 = 0
	_span_min = 100000.0
	_span_max = 0.0
	_closed = 0
	_parks = 0
	_portal_gaps = 0
	_open_edges = 0
	_weak_chunks = 0
	_tiles = 0
	_turns = 0
	_crossings = 0
	_splits = 0
	_rects = 0
	_clash = 0
	_joint_error = 0.0
	_run = 0.0
	_clear_ok = true
	_paint_count = 0
	_district_label = ""
	_district_count = 0
	_dirt_centers.clear()
	_mouths.clear()
	_asphalt_lips.clear()
	_dirt_caps.clear()
	_paint_edges.clear()
	_bare.clear()
	_decors.clear()
	_surfaces.clear()
	_median_tiles.clear()
	_overlap_pairs = 0
	_overlap_worst = 0.0
	_lamp_locals.clear()
	_walk_boxes.clear()
	_aprons.clear()
	_paved_crosses.clear()
	_mouth_corners.clear()
	_walk_corners.clear()
	_tri_cache.clear()
	_cut_walks.clear()
	_walks.clear()
	_lots.clear()
	_walk_straight = 0
	_walk_turns = 0
	_walk_flares = 0
	_empty_mouths = 0
	_bare_count = 0
	_clear_at = Vector2(center.x, center.z)
	_tour = PackedVector3Array()
	_tour_back = PackedVector3Array()
	_tour_alt = PackedVector3Array()
	_tour_alt_back = PackedVector3Array()
	_split_spans.clear()
	_controls.clear()
	_cross_points.clear()


func _roll_seed(requested_seed: int) -> int:
	if requested_seed != 0:
		return requested_seed
	var roller := RandomNumberGenerator.new()
	var seed: int = 0
	while seed == 0:
		roller.randomize()
		seed = roller.seed
	return seed


func _chunk_seed(world_seed: int, chunk: Vector2i) -> int:
	var n: int = world_seed & 0x7fffffff
	n = (n * 1103515245 + chunk.x * 12345 + 12345) & 0x7fffffff
	n = (n * 1103515245 + chunk.y * 67890 + 67890) & 0x7fffffff
	if n == 0:
		n = 1
	return n


func _mix(n: int) -> int:
	var x: int = n & 0x7fffffff
	x = (x * 1103515245 + 12345) & 0x7fffffff
	if x == 0:
		x = 1
	return x


func _axis_phase(world_seed: int, axis: int) -> float:
	var h: int = _mix(world_seed + 17 + axis * 91)
	return float(h % 10000) / 10000.0 * 90.0


func _span_m(tiles: int) -> float:
	return CROSS + float(tiles) * TILE


func _gap_tiles(_world_seed: int, _axis: int, _index: int) -> int:
	return ARTERIAL_TILES


func _note_span(tiles: int) -> void:
	var span: float = _span_m(tiles)
	if span < _span_min:
		_span_min = span
	if span > _span_max:
		_span_max = span
	_gap_seen[tiles] = true


func _prepare_plan(world_seed: int, window: Array[Vector2i]) -> void:
	var min_x: float = 1000000.0
	var max_x: float = -1000000.0
	var min_z: float = 1000000.0
	var max_z: float = -1000000.0
	for chunk in window:
		var origin: Vector2 = _Layout.chunk_origin(chunk)
		min_x = minf(min_x, origin.x)
		max_x = maxf(max_x, origin.x + _Layout.CHUNK_SIZE_M)
		min_z = minf(min_z, origin.y)
		max_z = maxf(max_z, origin.y + _Layout.CHUNK_SIZE_M)
	_fill_axis(world_seed, 0, min_x - 200.0, max_x + 200.0)
	_fill_axis(world_seed, 1, min_z - 200.0, max_z + 200.0)
	_plan_arteries(world_seed)


func _fill_axis(world_seed: int, axis: int, low: float, high: float) -> void:
	var stations: Dictionary = {}
	var gaps: Dictionary = {}
	var phase: float = _axis_phase(world_seed, axis)
	var index: int = 0
	var cursor: float = phase
	stations[0] = cursor
	var guard: int = 0
	while cursor < high and guard < 500:
		var tiles: int = _gap_tiles(world_seed, axis, index)
		gaps[index] = tiles
		_note_span(tiles)
		cursor += _span_m(tiles)
		index += 1
		stations[index] = cursor
		guard += 1
	var hi: int = index
	index = 0
	cursor = phase
	guard = 0
	while cursor > low and guard < 500:
		var back: int = index - 1
		var tiles_back: int = _gap_tiles(world_seed, axis, back)
		gaps[back] = tiles_back
		_note_span(tiles_back)
		cursor -= _span_m(tiles_back)
		index = back
		stations[index] = cursor
		guard += 1
	if axis == 0:
		_station_x = stations
		_span_tiles_x = gaps
		_index_x0 = index
		_index_x1 = hi
	else:
		_station_z = stations
		_span_tiles_z = gaps
		_index_z0 = index
		_index_z1 = hi


func _gap_of(axis: int, index: int) -> int:
	if axis == 0:
		return int(_span_tiles_x[index])
	return int(_span_tiles_z[index])


func _crossing(i: int, j: int) -> Vector2:
	return Vector2(float(_station_x[i]), float(_station_z[j]))


func _segment_crosses_border(i: int, j: int, axis: int) -> bool:
	var a: Vector2 = _crossing(i, j)
	var b: Vector2 = _crossing(i + 1, j) if axis == 0 else _crossing(i, j + 1)
	var size: float = _Layout.CHUNK_SIZE_M
	if axis == 0:
		return int(floor(a.x / size)) != int(floor((b.x - 0.01) / size))
	return int(floor(a.y / size)) != int(floor((b.y - 0.01) / size))


func _segment_open(_world_seed: int, _i: int, _j: int, _axis: int) -> bool:
	return true


func _arms(world_seed: int, i: int, j: int) -> int:
	var count := 0
	if i > _index_x0 and _segment_open(world_seed, i - 1, j, 0):
		count += 1
	if i < _index_x1 and _segment_open(world_seed, i, j, 0):
		count += 1
	if j > _index_z0 and _segment_open(world_seed, i, j - 1, 1):
		count += 1
	if j < _index_z1 and _segment_open(world_seed, i, j, 1):
		count += 1
	return count


func _run_tiles(total: int) -> int:
	return total - SPLIT_LEAD - TAPER_TILES - TAPER_TILES - SPLIT_LEAD


func _plan_arteries(world_seed: int) -> void:
	# 0 one east-west, 1 one north-south, 2 one of each, 3 two east-west, 4 two north-south.
	var mode: int = posmod(_mix(world_seed + 404), 5)
	_artery_mode = mode
	var east_west: int = 0
	var north_south: int = 0
	if mode == 0:
		east_west = 1
	elif mode == 1:
		north_south = 1
	elif mode == 2:
		east_west = 1
		north_south = 1
	elif mode == 3:
		east_west = 2
	else:
		north_south = 2
	if east_west > 0:
		_choose_axis_arteries(1, east_west, world_seed)
	if north_south > 0:
		_choose_axis_arteries(0, north_south, world_seed)
	_mark_artery_medians()


func _choose_axis_arteries(axis: int, want: int, world_seed: int) -> void:
	var bands: Dictionary = {}
	var i0: int = _index_x0 if axis == 0 else _index_z0
	var i1: int = _index_x1 if axis == 0 else _index_z1
	for index in range(i0, i1 + 1):
		var pos: float = float(_station_x[index]) if axis == 0 else float(_station_z[index])
		var band: int = _Layout.chunk_of(pos, 0.0).x if axis == 0 else _Layout.chunk_of(0.0, pos).y
		if not bands.has(band):
			bands[band] = []
		(bands[band] as Array).append(index)
	for band_key in bands.keys():
		var lines: Array = bands[band_key]
		var salt: int = _mix(world_seed + axis * 9176 + int(band_key) * 131 + want * 17)
		var picked: Array[int] = _pick_spaced(lines, want, salt)
		for line in picked:
			if axis == 0:
				_artery_x[line] = true
			else:
				_artery_z[line] = true


func _pick_spaced(lines: Array, want: int, salt: int) -> Array[int]:
	var chosen: Array[int] = []
	var n: int = lines.size()
	if n <= 0 or want <= 0:
		return chosen
	if want == 1 or n < 3:
		chosen.append(int(lines[posmod(salt, n)]))
		return chosen
	var pairs: Array[Vector2i] = []
	for a in range(n):
		for b in range(a + 1, n):
			if b - a < 2:
				continue
			pairs.append(Vector2i(a, b))
	if pairs.is_empty():
		chosen.append(int(lines[posmod(salt, n)]))
		return chosen
	var pair: Vector2i = pairs[posmod(salt, pairs.size())]
	chosen.append(int(lines[pair.x]))
	chosen.append(int(lines[pair.y]))
	return chosen


func _mark_artery_medians() -> void:
	for key in _artery_z.keys():
		var j: int = int(key)
		for i in range(_index_x0, _index_x1):
			_mark_artery_gap(0, i, j)
	for key2 in _artery_x.keys():
		var i2: int = int(key2)
		for j2 in range(_index_z0, _index_z1):
			_mark_artery_gap(1, i2, j2)


func _mark_artery_gap(axis: int, i: int, j: int) -> void:
	var tiles: int = _gap_of(axis, i if axis == 0 else j)
	if tiles < MIN_SPLIT_TILES:
		return
	var run_tiles: int = _run_tiles(tiles)
	if run_tiles < 4:
		return
	var split_key := "%d|%d|%d" % [axis, i, j]
	_split_key[split_key] = true
	_split_run[split_key] = run_tiles


func _is_main_segment(axis: int, i: int, j: int) -> bool:
	if axis == 0:
		return _artery_z.has(j)
	return _artery_x.has(i)


func _arteries_in(chunk: Vector2i) -> int:
	var count := 0
	for key in _artery_x.keys():
		var i: int = int(key)
		var x: float = float(_station_x[i])
		if _Layout.chunk_of(x, 0.0).x == chunk.x:
			count += 1
	for key2 in _artery_z.keys():
		var j: int = int(key2)
		var z: float = float(_station_z[j])
		if _Layout.chunk_of(0.0, z).y == chunk.y:
			count += 1
	return count


func _median_on_artery(mid: Vector3) -> bool:
	for key in _artery_x.keys():
		var x: float = float(_station_x[int(key)])
		if absf(mid.x - x) < 2.0:
			return true
	for key2 in _artery_z.keys():
		var z: float = float(_station_z[int(key2)])
		if absf(mid.z - z) < 2.0:
			return true
	return false


func _audit_arteries(home: Vector2i, window: Array[Vector2i]) -> void:
	for chunk in window:
		var count: int = _arteries_in(chunk)
		if count < 1 or count > 2:
			push_error("Chunk %s has %d main arteries." % [str(chunk), count])
			_joint_error = maxf(_joint_error, 5.0)
	_artery_count = _arteries_in(home)
	for spec in _medians:
		var mid: Vector3 = spec["mid"]
		if _median_on_artery(mid):
			continue
		push_error("Median at (%.1f, %.1f) is not on a main artery." % [mid.x, mid.z])
		_joint_error = maxf(_joint_error, 5.0)


func _build_chunk(world_seed: int, chunk: Vector2i, record: bool) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = _chunk_seed(world_seed, chunk)
	for j in range(_index_z0, _index_z1 + 1):
		for i in range(_index_x0, _index_x1 + 1):
			if _arms(world_seed, i, j) <= 0:
				continue
			var center: Vector2 = _crossing(i, j)
			_lattice["%d|%d" % [i, j]] = center
			if _Layout.chunk_of(center.x, center.y) == chunk:
				_place_cross(chunk, center, false, _ns_name(i))
	for j3 in range(_index_z0, _index_z1):
		for i3 in range(_index_x0, _index_x1):
			_emit_segment(chunk, i3, j3, 0)
	for j4 in range(_index_z0, _index_z1):
		for i4 in range(_index_x0, _index_x1 + 1):
			_emit_segment(chunk, i4, j4, 1)
	_emit_districts(chunk)
	if record:
		_build_tours(chunk)
		if _tour.size() < 8:
			_fallback_tour(chunk)


func _emit_districts(chunk: Vector2i) -> void:
	var cells: Array[Vector2i] = []
	for j in range(_index_z0, _index_z1):
		for i in range(_index_x0, _index_x1):
			if not _lattice.has("%d|%d" % [i, j]):
				continue
			if not _lattice.has("%d|%d" % [i + 1, j]):
				continue
			if not _lattice.has("%d|%d" % [i, j + 1]):
				continue
			if not _lattice.has("%d|%d" % [i + 1, j + 1]):
				continue
			var sw: Vector2 = _crossing(i, j)
			var ne: Vector2 = _crossing(i + 1, j + 1)
			var lot_c := Vector2((sw.x + ne.x) * 0.5, (sw.y + ne.y) * 0.5)
			if _Layout.chunk_of(lot_c.x, lot_c.y) != chunk:
				continue
			if not _check_cell(i, j):
				continue
			cells.append(Vector2i(i, j))
	if cells.size() < 2:
		push_error("Chunk %s has %d arterial cells. Districts need at least 2." % [str(chunk), cells.size()])
	var count: int = 2 + posmod(_mix(_world_seed + chunk.x * 17 + chunk.y * 31 + 501), 4)
	if count > cells.size():
		count = cells.size()
	if count > 5:
		count = 5
	var picked: PackedStringArray = _pick_types(count)
	_district_count = picked.size()
	_district_label = "+".join(picked)
	var seeds: Array[Vector2i] = _spread_seeds(cells, picked.size())
	for cell in cells:
		var here: Vector2i = cell
		var which: int = _nearest_seed(here, seeds)
		var kind: String = picked[which]
		_emit_cell(chunk, here, kind)


func _check_cell(i: int, j: int) -> bool:
	var sw: Vector2 = _crossing(i, j)
	var ne: Vector2 = _crossing(i + 1, j + 1)
	var origin := Vector2(sw.x + HALF, sw.y + HALF)
	var far := Vector2(ne.x - HALF, ne.y - HALF)
	var want: float = float(ARTERIAL_TILES) * TILE
	var err_x: float = absf((far.x - origin.x) - want)
	var err_z: float = absf((far.y - origin.y) - want)
	if err_x > _joint_error:
		_joint_error = err_x
	if err_z > _joint_error:
		_joint_error = err_z
	if err_x > 0.05 or err_z > 0.05:
		push_error("Arterial cell %d,%d is not %d tiles (%.3f, %.3f)." % [i, j, ARTERIAL_TILES, far.x - origin.x, far.y - origin.y])
		return false
	return true


func _pick_types(count: int) -> PackedStringArray:
	var pool: Array[String] = ["alley", "radial", "strips", "court", "campus"]
	for i in range(pool.size() - 1, 0, -1):
		var swap_at: int = _rng.randi_range(0, i)
		var swap: String = pool[i]
		pool[i] = pool[swap_at]
		pool[swap_at] = swap
	var out := PackedStringArray()
	var take: int = mini(count, pool.size())
	for k in take:
		out.append(pool[k])
	return out


func _spread_seeds(cells: Array[Vector2i], count: int) -> Array[Vector2i]:
	var seeds: Array[Vector2i] = []
	if cells.is_empty() or count <= 0:
		return seeds
	var first: int = _rng.randi_range(0, cells.size() - 1)
	seeds.append(cells[first])
	while seeds.size() < count:
		var best_i := 0
		var best_d := -1
		for i in cells.size():
			var dist := 1000000
			for s in seeds.size():
				var seed: Vector2i = seeds[s]
				var dx: int = cells[i].x - seed.x
				var dy: int = cells[i].y - seed.y
				var here: int = dx * dx + dy * dy
				if here < dist:
					dist = here
			if dist > best_d:
				best_d = dist
				best_i = i
		if best_d <= 0:
			break
		seeds.append(cells[best_i])
	return seeds


func _nearest_seed(cell: Vector2i, seeds: Array[Vector2i]) -> int:
	var best := 0
	var best_d := 1000000
	for s in seeds.size():
		var seed: Vector2i = seeds[s]
		var dx: int = cell.x - seed.x
		var dy: int = cell.y - seed.y
		var dist: int = dx * dx + dy * dy
		if dist < best_d:
			best_d = dist
			best = s
	return best


func _emit_cell(chunk: Vector2i, cell: Vector2i, kind: String) -> void:
	_dirt_centers.clear()
	var sw: Vector2 = _crossing(cell.x, cell.y)
	var origin := Vector2(sw.x + HALF, sw.y + HALF)
	if kind == "alley":
		_emit_alley(chunk, origin)
	elif kind == "radial":
		_emit_radial(chunk, origin)
	elif kind == "strips":
		_emit_strips(chunk, origin)
	elif kind == "court":
		_emit_court(chunk, origin)
	else:
		_emit_campus(chunk, origin)


func _road_spans(lines: Array[int]) -> Array[Vector2i]:
	var spans: Array[Vector2i] = []
	var cursor := 0
	for line_v in lines:
		var line: int = int(line_v)
		if line > cursor:
			spans.append(Vector2i(cursor, line))
		cursor = line + 2
	if cursor < ARTERIAL_TILES:
		spans.append(Vector2i(cursor, ARTERIAL_TILES))
	return spans


func _cross_n(chunk: Vector2i, origin: Vector2, nx: int, nz: int, road_name: String) -> void:
	var center := Vector2(origin.x + float(nx) * TILE + DIRT_HALF, origin.y + float(nz) * TILE + DIRT_HALF)
	_place_cross(chunk, center, true, road_name)
	_dirt_centers.append(center)


func _run_x(chunk: Vector2i, origin: Vector2, z_line: int, x0: int, x1: int, dirt: bool, road_name: String) -> void:
	var count: int = x1 - x0
	if count <= 0:
		return
	var lateral: float = origin.y + float(z_line) * TILE + DIRT_HALF
	var mouth := Vector3(origin.x + float(x0) * TILE, 0.0, lateral)
	_emit_bi(chunk, mouth, 0.0, count, road_name, dirt)
	if dirt:
		var end := Vector3(origin.x + float(x1) * TILE, 0.0, lateral)
		_bind_end(mouth, true, x0 == 0)
		_bind_end(end, true, x1 == ARTERIAL_TILES)


func _run_z(chunk: Vector2i, origin: Vector2, x_line: int, z0: int, z1: int, dirt: bool, road_name: String) -> void:
	var count: int = z1 - z0
	if count <= 0:
		return
	var lateral: float = origin.x + float(x_line) * TILE + DIRT_HALF
	var mouth := Vector3(lateral, 0.0, origin.y + float(z0) * TILE)
	_emit_bi(chunk, mouth, PI * 0.5, count, road_name, dirt)
	if dirt:
		var end := Vector3(lateral, 0.0, origin.y + float(z1) * TILE)
		_bind_end(mouth, false, z0 == 0)
		_bind_end(end, false, z1 == ARTERIAL_TILES)


func _bind_end(point: Vector3, along_x: bool, on_rim: bool) -> void:
	if on_rim:
		return
	var best: float = 1000.0
	var face_pt := point
	for c in _dirt_centers:
		var center: Vector2 = c
		if along_x:
			if absf(center.y - point.z) > 0.2:
				continue
			var west: float = center.x - DIRT_HALF
			var east: float = center.x + DIRT_HALF
			var face_x: float = west if absf(point.x - west) <= absf(point.x - east) else east
			var gap: float = absf(point.x - face_x)
			if gap < best:
				best = gap
				face_pt = Vector3(face_x, 0.0, center.y)
		else:
			if absf(center.x - point.x) > 0.2:
				continue
			var south: float = center.y - DIRT_HALF
			var north: float = center.y + DIRT_HALF
			var face_z: float = south if absf(point.z - south) <= absf(point.z - north) else north
			var gap_z: float = absf(point.z - face_z)
			if gap_z < best:
				best = gap_z
				face_pt = Vector3(center.x, 0.0, face_z)
	if best < 50.0:
		_note_joint(point, face_pt)
	if best > 1.0 and not on_rim:
		if best >= 50.0:
			_joint_error = maxf(_joint_error, 5.0)
		push_error("Dirt run missed its crossing at (%.2f, %.2f)." % [point.x, point.z])


func _note_joint(got: Vector3, want: Vector3) -> void:
	var gap: float = got.distance_to(want)
	if gap > _joint_error:
		_joint_error = gap


func _fill_span(chunk: Vector2i, origin: Vector2, x0: int, x1: int, z0: int, z1: int, inset: float, style: int) -> void:
	_fill_lot(chunk, origin.x + float(x0) * TILE + inset, origin.y + float(z0) * TILE + inset, origin.x + float(x1) * TILE - inset, origin.y + float(z1) * TILE - inset, style)


func _emit_alley(chunk: Vector2i, origin: Vector2) -> void:
	var x_parts: Array[int] = _split_tiles(19)
	var z_parts: Array[int] = _split_tiles(19)
	var xs: PackedFloat32Array = _station_chain(x_parts[0], [x_parts[1], x_parts[2]])
	var zs: PackedFloat32Array = _station_chain(z_parts[0], [z_parts[1], z_parts[2]])
	var cell: float = float(ARTERIAL_TILES) * TILE
	for xi in xs.size():
		for zi in zs.size():
			_place_cross(chunk, origin + Vector2(xs[xi], zs[zi]), true, "Alley")
	for zi2 in zs.size():
		var z: float = zs[zi2]
		_run_between(chunk, origin + Vector2(0.0, z), origin + Vector2(xs[0] - HALF, z), true, "Alley")
		_run_between(chunk, origin + Vector2(xs[0] + HALF, z), origin + Vector2(xs[1] - HALF, z), true, "Alley")
		_run_between(chunk, origin + Vector2(xs[1] + HALF, z), origin + Vector2(xs[2] - HALF, z), true, "Alley")
		_run_between(chunk, origin + Vector2(xs[2] + HALF, z), origin + Vector2(cell, z), true, "Alley")
	for xi2 in xs.size():
		var x: float = xs[xi2]
		_run_between(chunk, origin + Vector2(x, 0.0), origin + Vector2(x, zs[0] - HALF), true, "Alley")
		_run_between(chunk, origin + Vector2(x, zs[0] + HALF), origin + Vector2(x, zs[1] - HALF), true, "Alley")
		_run_between(chunk, origin + Vector2(x, zs[1] + HALF), origin + Vector2(x, zs[2] - HALF), true, "Alley")
		_run_between(chunk, origin + Vector2(x, zs[2] + HALF), origin + Vector2(x, cell), true, "Alley")
	_fill_grid(chunk, origin, xs, zs, cell, 5)


func _emit_radial(chunk: Vector2i, origin: Vector2) -> void:
	var bend_tiles := 4
	var k: int = _rng.randi_range(2, 7)
	var leg: float = TURN + HALF + float(bend_tiles) * TILE
	var side: float = leg * 2.0
	var cell: float = float(ARTERIAL_TILES) * TILE
	var x_w: float = float(k) * TILE + HALF
	var z_s: float = x_w
	var x_e: float = x_w + side
	var z_n: float = z_s + side
	var mid_x: float = (x_w + x_e) * 0.5
	var mid_z: float = (z_s + z_n) * 0.5
	var sw := origin + Vector2(x_w, z_s)
	var se := origin + Vector2(x_e, z_s)
	var ne := origin + Vector2(x_e, z_n)
	var nw := origin + Vector2(x_w, z_n)
	var south := origin + Vector2(mid_x, z_s)
	var north := origin + Vector2(mid_x, z_n)
	var east := origin + Vector2(x_e, mid_z)
	var west := origin + Vector2(x_w, mid_z)
	var center := origin + Vector2(mid_x, mid_z)
	var east_dir := Vector2(1.0, 0.0)
	var north_dir := Vector2(0.0, 1.0)
	_place_cross(chunk, center, true, "Radial")
	_place_cross(chunk, south, true, "Radial")
	_place_cross(chunk, north, true, "Radial")
	_place_cross(chunk, east, true, "Radial")
	_place_cross(chunk, west, true, "Radial")
	_place_turn(chunk, sw, -east_dir, north_dir, true, "Radial")
	_place_turn(chunk, se, east_dir, north_dir, true, "Radial")
	_place_turn(chunk, ne, north_dir, -east_dir, true, "Radial")
	_place_turn(chunk, nw, -east_dir, -north_dir, true, "Radial")
	_run_between(chunk, sw + east_dir * TURN, south - east_dir * HALF, true, "Radial")
	_run_between(chunk, south + east_dir * HALF, se - east_dir * TURN, true, "Radial")
	_run_between(chunk, se + north_dir * TURN, east - north_dir * HALF, true, "Radial")
	_run_between(chunk, east + north_dir * HALF, ne - north_dir * TURN, true, "Radial")
	_run_between(chunk, ne - east_dir * TURN, north + east_dir * HALF, true, "Radial")
	_run_between(chunk, north - east_dir * HALF, nw + east_dir * TURN, true, "Radial")
	_run_between(chunk, nw - north_dir * TURN, west + north_dir * HALF, true, "Radial")
	_run_between(chunk, west - north_dir * HALF, sw + north_dir * TURN, true, "Radial")
	_run_between(chunk, south + north_dir * HALF, center - north_dir * HALF, true, "Radial")
	_run_between(chunk, center + north_dir * HALF, north - north_dir * HALF, true, "Radial")
	_run_between(chunk, west + east_dir * HALF, center - east_dir * HALF, true, "Radial")
	_run_between(chunk, center + east_dir * HALF, east - east_dir * HALF, true, "Radial")
	_run_between(chunk, origin + Vector2(mid_x, 0.0), south - north_dir * HALF, true, "Radial")
	_run_between(chunk, north + north_dir * HALF, origin + Vector2(mid_x, cell), true, "Radial")
	_run_between(chunk, origin + Vector2(0.0, mid_z), west - east_dir * HALF, true, "Radial")
	_run_between(chunk, east + east_dir * HALF, origin + Vector2(cell, mid_z), true, "Radial")
	var pad: float = HALF + _inset_for(5)
	_fill_lot(chunk, sw.x + pad, sw.y + pad, center.x - pad, center.y - pad, 5)
	_fill_lot(chunk, center.x + pad, sw.y + pad, se.x - pad, center.y - pad, 5)
	_fill_lot(chunk, sw.x + pad, center.y + pad, center.x - pad, nw.y - pad, 5)
	_fill_lot(chunk, center.x + pad, center.y + pad, se.x - pad, ne.y - pad, 5)


func _emit_strips(chunk: Vector2i, origin: Vector2) -> void:
	var swap: bool = _rng.randf() < 0.5
	var gaps: Array[int] = [4, 7]
	if _rng.randf() < 0.5:
		gaps = [7, 4]
	var lead := 4
	var cell: float = float(ARTERIAL_TILES) * TILE
	var xs: PackedFloat32Array = _cross_chain(gaps, lead)
	var ys: PackedFloat32Array = _cross_chain(gaps, lead)
	for yi in ys.size():
		for xi in xs.size():
			_place_cross(chunk, _map_pt(Vector2(xs[xi], ys[yi]), origin, swap), false, "Strip")
	for yi2 in ys.size():
		var y: float = ys[yi2]
		_run_between(chunk, _map_pt(Vector2(0.0, y), origin, swap), _map_pt(Vector2(xs[0] - HALF, y), origin, swap), false, "Strip")
		for gap_i in range(xs.size() - 1):
			_run_between(chunk, _map_pt(Vector2(xs[gap_i] + HALF, y), origin, swap), _map_pt(Vector2(xs[gap_i + 1] - HALF, y), origin, swap), false, "Strip")
		var last_x: float = xs[xs.size() - 1]
		_run_between(chunk, _map_pt(Vector2(last_x + HALF, y), origin, swap), _map_pt(Vector2(cell, y), origin, swap), false, "Strip")
	for xi2 in xs.size():
		var x: float = xs[xi2]
		_run_between(chunk, _map_pt(Vector2(x, 0.0), origin, swap), _map_pt(Vector2(x, ys[0] - HALF), origin, swap), false, "Strip")
		for gap_j in range(ys.size() - 1):
			_run_between(chunk, _map_pt(Vector2(x, ys[gap_j] + HALF), origin, swap), _map_pt(Vector2(x, ys[gap_j + 1] - HALF), origin, swap), false, "Strip")
		var last_y: float = ys[ys.size() - 1]
		_run_between(chunk, _map_pt(Vector2(x, last_y + HALF), origin, swap), _map_pt(Vector2(x, cell), origin, swap), false, "Strip")
	var inset: float = _inset_for(5) + 2.4
	for gy in range(ys.size() - 1):
		for gx in range(xs.size() - 1):
			_fill_mapped(chunk, origin, xs[gx] + HALF + inset, ys[gy] + HALF + inset, xs[gx + 1] - HALF - inset, ys[gy + 1] - HALF - inset, swap, 5)


func _cross_chain(gaps: Array[int], lead: int) -> PackedFloat32Array:
	var cursor: float = float(lead) * TILE + HALF
	var out := PackedFloat32Array()
	out.append(cursor)
	for gap in gaps:
		cursor += CROSS + float(gap) * TILE
		out.append(cursor)
	return out


func _emit_court(chunk: Vector2i, origin: Vector2) -> void:
	var mouth: int = _rng.randi_range(0, 3)
	var spur_tiles := 4
	var straight_tiles := 14
	var side: float = 2.0 * TURN + float(straight_tiles) * TILE
	var cell: float = float(ARTERIAL_TILES) * TILE
	var pivot := Vector2(cell * 0.5, cell * 0.5)
	var xw: float = float(spur_tiles) * TILE + HALF
	var zs: float = (cell - side) * 0.5
	var east_dir: Vector2 = _turn_ccw(Vector2(1.0, 0.0), mouth)
	var north_dir: Vector2 = _turn_ccw(Vector2(0.0, 1.0), mouth)
	var sw: Vector2 = origin + _spin_about(Vector2(xw, zs), pivot, mouth)
	var se: Vector2 = origin + _spin_about(Vector2(xw + side, zs), pivot, mouth)
	var nw: Vector2 = origin + _spin_about(Vector2(xw, zs + side), pivot, mouth)
	var ne: Vector2 = origin + _spin_about(Vector2(xw + side, zs + side), pivot, mouth)
	_place_turn(chunk, sw, -north_dir, east_dir, true, "Court")
	_place_turn(chunk, se, east_dir, north_dir, true, "Court")
	_place_turn(chunk, ne, north_dir, -east_dir, true, "Court")
	_place_turn(chunk, nw, -east_dir, -north_dir, true, "Court")
	_run_between(chunk, sw + east_dir * TURN, se - east_dir * TURN, true, "Court")
	_run_between(chunk, se + north_dir * TURN, ne - north_dir * TURN, true, "Court")
	_run_between(chunk, ne - east_dir * TURN, nw + east_dir * TURN, true, "Court")
	_run_between(chunk, nw - north_dir * TURN, sw + north_dir * TURN, true, "Court")
	var mid_z: float = zs + side * 0.5
	var spur_a: Vector2 = origin + _spin_about(Vector2(0.0, mid_z), pivot, mouth)
	var spur_b: Vector2 = origin + _spin_about(Vector2(float(spur_tiles) * TILE, mid_z), pivot, mouth)
	_run_between(chunk, spur_a, spur_b, true, "Court")
	var pad: float = HALF + _inset_for(0)
	var x0: float = minf(minf(sw.x, se.x), minf(ne.x, nw.x)) + pad
	var z0: float = minf(minf(sw.y, se.y), minf(ne.y, nw.y)) + pad
	var x1: float = maxf(maxf(sw.x, se.x), maxf(ne.x, nw.x)) - pad
	var z1: float = maxf(maxf(sw.y, se.y), maxf(ne.y, nw.y)) - pad
	_fill_lot(chunk, x0, z0, x1, z1, 0)


func _split_tiles(total: int) -> Array[int]:
	var remain: int = total
	var parts: Array[int] = []
	for i in 3:
		var min_left: int = 2 * (3 - i)
		var hi: int = remain - min_left
		var lo := 2
		if hi >= 4:
			lo = 3
		if hi < lo:
			lo = hi
		var pick: int = lo
		if hi > lo:
			pick = _rng.randi_range(lo, hi)
		parts.append(pick)
		remain -= pick
	parts.append(remain)
	return parts


func _station_chain(lead: int, gaps: Array[int]) -> PackedFloat32Array:
	var cursor: float = HALF + float(lead) * TILE
	var out := PackedFloat32Array()
	out.append(cursor)
	for gap in gaps:
		cursor += CROSS + float(gap) * TILE
		out.append(cursor)
	return out


func _fill_grid(chunk: Vector2i, origin: Vector2, xs: PackedFloat32Array, zs: PackedFloat32Array, cell: float, style: int) -> void:
	var inset: float = _inset_for(style)
	var x_marks: PackedFloat32Array = PackedFloat32Array([0.0])
	x_marks.append_array(xs)
	x_marks.append(cell)
	var z_marks: PackedFloat32Array = PackedFloat32Array([0.0])
	z_marks.append_array(zs)
	z_marks.append(cell)
	for zi in range(z_marks.size() - 1):
		for xi in range(x_marks.size() - 1):
			var left: float = x_marks[xi]
			var right: float = x_marks[xi + 1]
			var bottom: float = z_marks[zi]
			var top: float = z_marks[zi + 1]
			if xi > 0:
				left += HALF
			if xi < x_marks.size() - 2:
				right -= HALF
			if zi > 0:
				bottom += HALF
			if zi < z_marks.size() - 2:
				top -= HALF
			_fill_lot(chunk, origin.x + left + inset, origin.y + bottom + inset, origin.x + right - inset, origin.y + top - inset, style)


func _map_pt(local: Vector2, origin: Vector2, swap: bool) -> Vector2:
	if swap:
		return origin + Vector2(local.y, local.x)
	return origin + local


func _map_dir(dir: Vector2, swap: bool) -> Vector2:
	if swap:
		return Vector2(dir.y, dir.x)
	return dir


func _fill_mapped(chunk: Vector2i, origin: Vector2, x0: float, z0: float, x1: float, z1: float, swap: bool, style: int) -> void:
	var a: Vector2 = _map_pt(Vector2(x0, z0), origin, swap)
	var b: Vector2 = _map_pt(Vector2(x1, z1), origin, swap)
	_fill_lot(chunk, minf(a.x, b.x), minf(a.y, b.y), maxf(a.x, b.x), maxf(a.y, b.y), style)


func _turn_ccw(dir: Vector2, steps: int) -> Vector2:
	var spun: Vector2 = dir
	var n: int = posmod(steps, 4)
	for _step in n:
		spun = Vector2(-spun.y, spun.x)
	return spun


func _spin_about(point: Vector2, pivot: Vector2, steps: int) -> Vector2:
	return pivot + _turn_ccw(point - pivot, steps)


func _run_between(chunk: Vector2i, start: Vector2, end: Vector2, dirt: bool, road_name: String) -> void:
	start = _pull_from_split(start, end, dirt)
	end = _pull_from_split(end, start, dirt)
	var delta: Vector2 = end - start
	var length: float = delta.length()
	if length < 0.05:
		return
	var tiles_f: float = length / TILE
	var count: int = int(round(tiles_f))
	var err: float = absf(length - float(count) * TILE)
	if err > 0.04 or count <= 0:
		push_error("Road run from (%.2f, %.2f) is %.3f tiles." % [start.x, start.y, tiles_f])
		_joint_error = maxf(_joint_error, maxf(err, 0.05))
		return
	var angle: float = atan2(delta.y, delta.x)
	var mouth := Vector3(start.x, 0.0, start.y)
	_emit_bi(chunk, mouth, angle, count, road_name, dirt)


func _place_turn(chunk: Vector2i, corner: Vector2, approach: Vector2, depart: Vector2, dirt: bool, road_name: String) -> void:
	var left: Vector2 = Vector2(-approach.y, approach.x)
	var mirror: bool = depart.dot(left) < 0.0
	var entry: Vector2 = corner - approach * TURN
	var exit_at: Vector2 = corner + depart * TURN
	var angle: float = atan2(approach.y, approach.x)
	var at := Vector3(entry.x, 0.0, entry.y)
	var kind: String = "turn_dirt" if dirt else "turn_asphalt"
	if not _mesh.has(kind):
		push_error("Turn module is missing.")
		_joint_error = maxf(_joint_error, 5.0)
		return
	_put(chunk, at, angle, kind, mirror)
	if not dirt:
		_put(chunk, at, angle, "turn_yellow", mirror)
		_put(chunk, at, angle, "turn_white", mirror)
		_put(chunk, at, angle, "walk_turn", mirror)
		_place_walk_specs(chunk, at, angle, mirror, _turn_specs)
		_walk_turns += 1
	_turns += 1
	var mid_in := Vector3(corner.x - approach.x * TURN * 0.5, 0.0, corner.y - approach.y * TURN * 0.5)
	var mid_out := Vector3(corner.x + depart.x * TURN * 0.5, 0.0, corner.y + depart.y * TURN * 0.5)
	_add_box(chunk, mid_in, angle, TURN, CROSS)
	_add_box(chunk, mid_out, atan2(depart.y, depart.x), TURN, CROSS)
	_remember_arm(entry, corner, road_name)
	_remember_arm(corner, exit_at, road_name)
	var road_kind: String = _kind_for(road_name)
	_segments.append({
		"from": Vector3(entry.x, 0.0, entry.y),
		"to": Vector3(corner.x, 0.0, corner.y),
		"name": road_name,
		"kind": road_kind,
	})
	_segments.append({
		"from": Vector3(corner.x, 0.0, corner.y),
		"to": Vector3(exit_at.x, 0.0, exit_at.y),
		"name": road_name,
		"kind": road_kind,
	})


func _remember_arm(a: Vector2, b: Vector2, road_name: String) -> void:
	var delta: Vector2 = b - a
	if delta.length_squared() < 0.0001:
		return
	var dir: Vector2 = delta.normalized()
	var side := Vector3(-dir.y, 0.0, dir.x) * HALF
	var a3 := Vector3(a.x, 0.0, a.y)
	var b3 := Vector3(b.x, 0.0, b.y)
	_remember_rect(_bounds4(a3 + side, a3 - side, b3 + side, b3 - side), road_name)


func _kind_for(road_name: String) -> String:
	if road_name == "Alley":
		return "alley"
	if road_name == "Radial":
		return "radial"
	if road_name == "Strip":
		return "strips"
	if road_name == "Court":
		return "court"
	return ""


func _emit_campus(chunk: Vector2i, origin: Vector2) -> void:
	var mid: int = ARTERIAL_TILES / 2
	var park_i: int = _rng.randi_range(0, 3)
	var quads: Array[Vector2i] = [Vector2i(0, mid), Vector2i(mid, ARTERIAL_TILES)]
	var q := 0
	var inset: float = _inset_for(3)
	for gz in quads:
		for gx in quads:
			var gap_x: Vector2i = gx
			var gap_z: Vector2i = gz
			if q == park_i:
				_parks += 1
			else:
				_fill_span(chunk, origin, gap_x.x, gap_x.y, gap_z.x, gap_z.y, inset, 3)
			q += 1


func _rank(world_seed: int, axis: int, i: int, j: int) -> int:
	var n: int = _mix(world_seed + axis * 10007 + i * 97 + j * 131)
	return n


func _deep(chunk: Vector2i, x: float, z: float) -> bool:
	var origin: Vector2 = _Layout.chunk_origin(chunk)
	var span: float = _Layout.CHUNK_SIZE_M
	var margin: float = HALF + 8.0
	if x < origin.x + margin or x > origin.x + span - margin:
		return false
	if z < origin.y + margin or z > origin.y + span - margin:
		return false
	return true


func _place_cross(chunk: Vector2i, center: Vector2, dirt: bool = false, road_name: String = "") -> void:
	var label: String = road_name
	if label == "":
		label = _ns_name(0)
	var west := Vector3(center.x - HALF, 0.0, center.y)
	if dirt:
		_put(chunk, west, 0.0, "cross_dirt", false)
		_note_box_edges(center, false)
	else:
		_put(chunk, west, 0.0, "cross_asphalt", false)
		_note_box_edges(center, true)
		_put_cross_paint(chunk, west)
	var mid := Vector3(center.x, 0.0, center.y)
	_add_box(chunk, mid, 0.0, CROSS, CROSS)
	_remember_rect(_square(center.x, center.y, HALF, HALF), label)
	_note_mouths(center)
	_cross_points.append(center)
	if not dirt:
		_paved_crosses.append(center)
	_crossings += 1


func _emit_segment(chunk: Vector2i, i: int, j: int, axis: int) -> void:
	var horizontal: bool = axis == 0
	if horizontal and i >= _index_x1:
		return
	if not horizontal and j >= _index_z1:
		return
	var owns_near: bool = _Layout.chunk_of(_crossing(i, j).x, _crossing(i, j).y) == chunk
	if not _segment_open(_world_seed, i, j, axis):
		if owns_near:
			_closed += 1
		return
	var center: Vector2 = _crossing(i, j)
	var far_center: Vector2 = _crossing(i + 1, j) if horizontal else _crossing(i, j + 1)
	var tiles: int = _gap_of(axis, i if horizontal else j)
	var dir := Vector3.RIGHT if horizontal else Vector3(0.0, 0.0, 1.0)
	var angle: float = 0.0 if horizontal else PI * 0.5
	var mouth := Vector3(center.x, 0.0, center.y) + dir * HALF
	var owned := 0
	var outside := 0
	var first := -1
	var last := -1
	for t in tiles:
		var at: Vector3 = mouth + dir * (TILE * float(t))
		if _Layout.chunk_of(at.x, at.z) == chunk:
			owned += 1
			if first < 0:
				first = t
			last = t
		else:
			outside += 1
	var owns_far: bool = _Layout.chunk_of(far_center.x, far_center.y) == chunk
	if owned == 0 and not owns_near and not owns_far:
		return
	var from := Vector3(center.x, 0.0, center.y)
	var to := Vector3(far_center.x, 0.0, far_center.y)
	var road_name: String = _ew_name(j) if horizontal else _ns_name(i)
	var road_kind: String = "arterial" if _is_main_segment(axis, i, j) else "street"
	if owns_near:
		_segments.append({"from": from, "to": to, "name": road_name, "kind": road_kind})
	_note_portals(chunk, from, to)
	if owned > 0 and outside > 0:
		_run += TILE * float(owned)
	if owned == 0:
		return
	var split: bool = _split_key.has("%d|%d|%d" % [axis, i, j]) and outside == 0
	if split:
		_emit_split(chunk, mouth, angle, tiles)
		_run += TILE * float(tiles)
		return
	if first < 0:
		return
	var slice: Vector3 = mouth + dir * (TILE * float(first))
	_emit_bi(chunk, slice, angle, last - first + 1, road_name)
	if outside == 0:
		_run += TILE * float(tiles)


func _emit_bi(chunk: Vector2i, mouth: Vector3, angle: float, count: int, road_name: String, dirt: bool = false) -> void:
	if count <= 0:
		return
	var dir: Vector3 = _dir(angle)
	var road_kind: String = "straight_dirt" if dirt else "straight_asphalt"
	for t in count:
		var at: Vector3 = mouth + dir * (TILE * float(t))
		_put(chunk, at, angle, road_kind, false)
		if not dirt:
			_put(chunk, at, angle, "straight_yellow", false)
			_put_edge(chunk, at, angle, 1.0)
			_put_edge(chunk, at, angle, -1.0)
			_put(chunk, at, angle, "walk_straight", false)
			_put(chunk, at, angle, "walk_straight_neg", false)
			_walk_straight += 1
		_tiles += 1
	var length: float = TILE * float(count)
	var end: Vector3 = mouth + dir * length
	var width: float = CROSS
	var half_w: float = HALF
	_add_box(chunk, mouth + dir * (length * 0.5), angle, length, width)
	if not dirt:
		_add_straight_walks(chunk, mouth, angle, length)
	_remember_rect(_road_rect(mouth, end, angle, half_w), road_name)
	if dirt:
		_note_cap(mouth, angle)
		_note_cap(end, angle)
	else:
		_note_lips(mouth, end, angle)
	_note_map_run(mouth, end, road_name, dirt)


func _note_map_run(mouth: Vector3, end: Vector3, road_name: String, _dirt: bool) -> void:
	var kind := ""
	if road_name == "Alley":
		kind = "alley"
	elif road_name == "Radial":
		kind = "radial"
	elif road_name == "Strip":
		kind = "strips"
	elif road_name == "Court":
		kind = "court"
	if kind == "":
		return
	var delta: Vector3 = end - mouth
	if delta.length_squared() < 0.25:
		return
	var dir: Vector3 = delta.normalized()
	var extra: float = HALF
	_segments.append({
		"from": mouth - dir * extra,
		"to": end + dir * extra,
		"drive_from": mouth,
		"drive_to": end,
		"name": road_name,
		"kind": kind,
	})


func _emit_split(chunk: Vector2i, mouth: Vector3, angle: float, total: int) -> void:
	var dir: Vector3 = _dir(angle)
	var right: Vector3 = _right(angle)
	var lead: float = float(SPLIT_LEAD) * TILE
	var taper: float = float(TAPER_TILES) * TILE
	var run_tiles: int = _run_tiles(total)
	if run_tiles < 4:
		_emit_bi(chunk, mouth, angle, total, "Split")
		return
	_splits += 1
	_split_spans.append({
		"origin": mouth,
		"dir": dir,
		"length": TILE * float(total),
		"run_tiles": run_tiles,
	})
	var run: float = float(run_tiles) * TILE
	var lane_m: float = 80.0 * UNIT
	_emit_bi(chunk, mouth, angle, SPLIT_LEAD, "Split")
	var narrow: Vector3 = mouth + dir * lead
	_put(chunk, narrow, angle, "split_asphalt", false)
	_put(chunk, narrow, angle, "split_yellow", false)
	_put(chunk, narrow, angle, "split_white", false)
	_put(chunk, narrow, angle, "split_asphalt", true)
	_put(chunk, narrow, angle, "split_yellow", true)
	_put(chunk, narrow, angle, "split_white", true)
	_put_flare_walks(chunk, narrow, angle)
	_lay_taper_boxes(chunk, narrow, angle, right)
	_lay_taper_boxes(chunk, narrow, angle, -right)
	_remember_rect(_band_rect(narrow, dir, taper, 116.0 * UNIT), "Split")
	var lane_at: Vector3 = mouth + dir * (lead + taper)
	_emit_lane(chunk, lane_at + right * lane_m, angle, run_tiles)
	_emit_lane(chunk, lane_at - right * lane_m, angle, run_tiles)
	_emit_wide_walks(chunk, lane_at, angle, run_tiles)
	var merge_narrow: Vector3 = mouth + dir * (lead + taper + run + taper)
	var back: float = angle + PI
	_put(chunk, merge_narrow, back, "split_asphalt", true)
	_put(chunk, merge_narrow, back, "split_yellow", true)
	_put(chunk, merge_narrow, back, "split_white", true)
	_put(chunk, merge_narrow, back, "split_asphalt", false)
	_put(chunk, merge_narrow, back, "split_yellow", false)
	_put(chunk, merge_narrow, back, "split_white", false)
	_put_flare_walks(chunk, merge_narrow, back)
	var merge_wide: Vector3 = merge_narrow - dir * taper
	var back_right: Vector3 = _right(back)
	_lay_taper_boxes(chunk, merge_narrow, back, back_right)
	_lay_taper_boxes(chunk, merge_narrow, back, -back_right)
	_remember_rect(_band_rect(merge_wide, dir, taper, 116.0 * UNIT), "Split")
	var tail_tiles: int = total - SPLIT_LEAD - TAPER_TILES - run_tiles - TAPER_TILES
	if tail_tiles != SPLIT_LEAD:
		push_error("Lane split must be symmetric so the return lane meets the flare.")
	_emit_bi(chunk, merge_narrow, angle, tail_tiles, "Split")
	var med_tiles: int = run_tiles - 2
	if med_tiles >= 2:
		var med_len: float = float(med_tiles) * TILE
		var margin: float = (run - med_len) * 0.5
		var med_start: Vector3 = lane_at + dir * margin
		_medians.append({
			"chunk": chunk,
			"start": med_start,
			"mid": med_start + dir * (med_len * 0.5),
			"angle": angle,
			"length": med_len,
			"width": 80.0 * UNIT,
			"height": 12.0 * UNIT,
			"tiles": med_tiles,
		})
	var lane_end: Vector3 = lane_at + right * lane_m + dir * run
	var merge_lane: Vector3 = merge_wide + right * lane_m
	var gap: float = lane_end.distance_to(merge_lane)
	if gap > _joint_error:
		_joint_error = gap


func _emit_lane(chunk: Vector2i, mouth: Vector3, angle: float, count: int) -> void:
	var dir: Vector3 = _dir(angle)
	for t in count:
		var at: Vector3 = mouth + dir * (TILE * float(t))
		_put(chunk, at, angle, "lane_asphalt", false)
		_put(chunk, at, angle, "lane_white", false)
		_tiles += 1
	var length: float = TILE * float(count)
	var end: Vector3 = mouth + dir * length
	var width: float = 80.0 * UNIT
	_add_box(chunk, mouth + dir * (length * 0.5), angle, length, width)
	_remember_rect(_road_rect(mouth, end, angle, width * 0.5), "Split")


func _lay_taper_boxes(chunk: Vector2i, origin: Vector3, angle: float, side: Vector3) -> void:
	var dir: Vector3 = _dir(angle)
	var slices := 6
	var taper_len: float = float(TAPER_TILES) * TILE
	for s in slices:
		var f0: float = taper_len * float(s) / float(slices)
		var f1: float = taper_len * float(s + 1) / float(slices)
		var outer_m: float = _profile_outer((f0 + f1) * 0.5) - 0.04
		if outer_m < TILE * 0.5:
			outer_m = TILE * 0.5
		var center: Vector3 = origin + dir * ((f0 + f1) * 0.5) + side * (outer_m * 0.5)
		_add_box(chunk, center, angle, f1 - f0, outer_m)


func _taper_outer(forward_u: float) -> float:
	if forward_u <= 72.0:
		return lerpf(76.0, 90.0, forward_u / 72.0)
	var t: float = clampf((forward_u - 72.0) / 72.0, 0.0, 1.0)
	return lerpf(90.0, 116.0, t)


func _shift_z(src: PackedVector3Array, dz: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for v in src:
		out.append(Vector3(v.x, v.y, v.z + dz))
	return out


func _emit_wide_walks(chunk: Vector2i, lane_at: Vector3, angle: float, run_tiles: int) -> void:
	if run_tiles <= 0:
		return
	var dir: Vector3 = _dir(angle)
	var right: Vector3 = _right(angle)
	for t in run_tiles:
		var at: Vector3 = lane_at + dir * (TILE * float(t))
		_put(chunk, at, angle, "walk_wide", false)
		_put(chunk, at, angle, "walk_wide_neg", false)
	var length: float = TILE * float(run_tiles)
	var mid: Vector3 = lane_at + dir * (length * 0.5)
	var lateral: float = 116.0 * UNIT + WALK_W * 0.5
	_add_walk_box(chunk, mid + right * lateral, angle, length, WALK_W)
	_add_walk_box(chunk, mid - right * lateral, angle, length, WALK_W)


func _pull_from_split(point: Vector2, other: Vector2, dirt: bool) -> Vector2:
	var half_w: float = HALF
	if not dirt:
		half_w = _paved_width() * 0.5
	var flank: Dictionary = _split_flank(point, half_w)
	if flank.is_empty():
		return point
	var delta: Vector2 = other - point
	var length: float = delta.length()
	if length < TILE:
		return point
	var dir: Vector2 = delta / length
	var sign: float = float(flank["sign"])
	var away: float = dir.x * float(flank["rx"]) * sign + dir.y * float(flank["rz"]) * sign
	if away < 0.7:
		return point
	var inset: float = float(flank["edge"]) - float(flank["lat"])
	if inset < 0.15:
		return point
	var clear: float = inset + WALK_W + 0.08
	var tiles_need: int = int(ceil(clear / TILE))
	if tiles_need < 1:
		tiles_need = 1
	var tiles_fit: int = int(floor((length + 0.05) / TILE)) - 1
	if tiles_fit < 1:
		return point
	if tiles_need > tiles_fit:
		tiles_need = tiles_fit
	var pull: float = float(tiles_need) * TILE
	var tile_at: Vector2 = point + dir * pull
	_note_apron(point, tile_at, dir, flank, dirt, half_w, pull, inset)
	return tile_at


func _split_flank(point: Vector2, half_w: float) -> Dictionary:
	var best: Dictionary = {}
	var best_gap: float = 0.85
	for span in _split_spans:
		var origin: Vector3 = span["origin"]
		var travel: Vector3 = span["dir"]
		var along: float = (point.x - origin.x) * travel.x + (point.y - origin.z) * travel.z
		var outer: float = _span_outer(along, half_w, int(span["run_tiles"]))
		if outer <= HALF + 0.2:
			continue
		var right: Vector3 = _right_of(travel)
		var lateral: float = (point.x - origin.x) * right.x + (point.y - origin.z) * right.z
		var gap: float = absf(absf(lateral) - HALF)
		if gap >= best_gap:
			continue
		best_gap = gap
		var sign: float = 1.0
		if lateral < 0.0:
			sign = -1.0
		best = {
			"edge": outer,
			"lat": absf(lateral),
			"sign": sign,
			"rx": right.x,
			"rz": right.z,
			"origin": origin,
			"dir": travel,
			"along": along,
			"run_tiles": int(span["run_tiles"]),
		}
	return best


func _span_outer(along: float, half_w: float, run_tiles: int) -> float:
	var worst: float = 0.0
	var steps := 8
	for s in steps + 1:
		var t: float = along - half_w + (2.0 * half_w) * float(s) / float(steps)
		worst = maxf(worst, _split_outer(t, run_tiles))
	return worst


func _split_outer(along: float, run_tiles: int) -> float:
	var lead: float = float(SPLIT_LEAD) * TILE
	var taper: float = float(TAPER_TILES) * TILE
	var run: float = float(run_tiles) * TILE
	var open_end: float = lead + taper
	var run_end: float = open_end + run
	var close_end: float = run_end + taper
	if along < lead or along > close_end:
		return HALF
	if along < open_end:
		return _profile_outer(along - lead)
	if along < run_end:
		return 116.0 * UNIT
	return _profile_outer(close_end - along)


func _note_apron(point: Vector2, tile_at: Vector2, road_dir: Vector2, flank: Dictionary, dirt: bool, half_w: float, pull: float, inset: float) -> void:
	var verts: PackedVector3Array = _apron_verts(point, tile_at, flank, half_w)
	if verts.size() < 3:
		return
	var angle: float = atan2(road_dir.y, road_dir.x)
	var at := Vector3(point.x, 0.0, point.y)
	var to := Vector3(tile_at.x, 0.0, tile_at.y)
	var cover: float = maxf(pull, inset + WALK_W + 0.35)
	var gap_to: Vector3 = at + _dir(angle) * cover
	var gap: Rect2 = _road_rect(at, gap_to, angle, half_w)
	var rect: Rect2 = _verts_rect(verts)
	var mid := Vector3((point.x + tile_at.x) * 0.5, 0.0, (point.y + tile_at.y) * 0.5)
	var chunk: Vector2i = _Layout.chunk_of(mid.x, mid.z)
	var flat := PackedVector2Array()
	for v in verts:
		flat.append(Vector2(v.x, v.z))
	_aprons.append({
		"chunk": chunk,
		"mid": mid,
		"angle": angle,
		"length": pull,
		"width": half_w * 2.0,
		"dirt": dirt,
		"rect": rect,
		"gap": gap,
		"verts": verts,
		"flat": flat,
	})
	_add_box(chunk, mid, angle, pull, half_w * 2.0)
	_remember_rect(_road_rect(at, to, angle, half_w), "Apron")


func _apron_verts(point: Vector2, tile_at: Vector2, flank: Dictionary, half_w: float) -> PackedVector3Array:
	var travel: Vector3 = flank["dir"]
	var run_tiles: int = int(flank["run_tiles"])
	var along0: float = float(flank["along"])
	var rx: float = float(flank["rx"])
	var rz: float = float(flank["rz"])
	var sign: float = float(flank["sign"])
	var lat: float = float(flank["lat"])
	var signed: float = sign * lat
	var center := Vector2(point.x - rx * signed, point.y - rz * signed)
	var side := Vector2(rx * sign, rz * sign)
	var artery := Vector2(travel.x, travel.z)
	var steps := 12
	var verts := PackedVector3Array()
	var prev_in := Vector2.ZERO
	var prev_out := Vector2.ZERO
	var pad: float = 0.03
	for s in steps + 1:
		var u: float = -1.0 + 2.0 * float(s) / float(steps)
		var along: float = along0 + u * half_w
		var outer: float = _split_outer(along, run_tiles) + pad
		var inner := center + artery * (u * half_w) + side * outer
		var outer_pt := tile_at + artery * (u * half_w)
		if s > 0:
			var y: float = ROAD_Y
			_tri_up(verts, Vector3(prev_in.x, y, prev_in.y), Vector3(inner.x, y, inner.y), Vector3(outer_pt.x, y, outer_pt.y))
			_tri_up(verts, Vector3(prev_in.x, y, prev_in.y), Vector3(outer_pt.x, y, outer_pt.y), Vector3(prev_out.x, y, prev_out.y))
		prev_in = inner
		prev_out = outer_pt
	return verts


func _tri_up(verts: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	if n.y < 0.0:
		verts.append(a)
		verts.append(c)
		verts.append(b)
	else:
		verts.append(a)
		verts.append(b)
		verts.append(c)


func _verts_rect(verts: PackedVector3Array) -> Rect2:
	var min_x: float = verts[0].x
	var max_x: float = verts[0].x
	var min_z: float = verts[0].z
	var max_z: float = verts[0].z
	for v in verts:
		min_x = minf(min_x, v.x)
		max_x = maxf(max_x, v.x)
		min_z = minf(min_z, v.z)
		max_z = maxf(max_z, v.z)
	return Rect2(min_x, min_z, maxf(max_x - min_x, 0.05), maxf(max_z - min_z, 0.05))


func _pack_flat(verts: PackedVector3Array) -> ArrayMesh:
	var uvs := PackedVector2Array()
	for v in verts:
		uvs.append(Vector2(v.x / TILE, v.z / TILE))
	return _pack_mesh(verts, uvs)


func _paved_width() -> float:
	if not _mesh.has("straight_asphalt"):
		return 152.0 * UNIT
	var size: Vector3 = (_mesh["straight_asphalt"] as Mesh).get_aabb().size
	var width: float = size.z
	if absf(size.x - TILE) > absf(size.z - TILE):
		width = size.x
	if width < 1.0:
		width = CROSS
	return width


func _note_portals(chunk: Vector2i, a: Vector3, b: Vector3) -> void:
	var origin: Vector2 = _Layout.chunk_origin(chunk)
	var span: float = _Layout.CHUNK_SIZE_M
	var x0: float = origin.x
	var z0: float = origin.y
	var x1: float = x0 + span
	var z1: float = z0 + span
	if absf(a.z - b.z) < 0.05:
		var z: float = a.z
		if z < z0 or z >= z1:
			return
		var lo: float = minf(a.x, b.x)
		var hi: float = maxf(a.x, b.x)
		if lo < x0 and hi > x0:
			_add_portal(chunk, "west", x0, z)
		if lo < x1 and hi > x1:
			_add_portal(chunk, "east", x1, z)
		return
	var x: float = a.x
	if x < x0 or x >= x1:
		return
	var zlo: float = minf(a.z, b.z)
	var zhi: float = maxf(a.z, b.z)
	if zlo < z0 and zhi > z0:
		_add_portal(chunk, "south", x, z0)
	if zlo < z1 and zhi > z1:
		_add_portal(chunk, "north", x, z1)


func _add_portal(chunk: Vector2i, edge: String, x: float, z: float) -> void:
	var key := "%d|%d|%s|%.2f|%.2f" % [chunk.x, chunk.y, edge, x, z]
	if _portal_keys.has(key):
		return
	_portal_keys[key] = true
	_portals.append({"edge": edge, "x": x, "z": z, "chunk": chunk})


func _audit_links(window: Array[Vector2i]) -> void:
	var loaded: Dictionary = {}
	for chunk in window:
		loaded["%d|%d" % [chunk.x, chunk.y]] = true
	var by_key: Dictionary = {}
	for portal in _portals:
		var portal_chunk: Vector2i = portal["chunk"]
		var edge: String = str(portal["edge"])
		var loc := "%.2f|%.2f" % [float(portal["x"]), float(portal["z"])]
		by_key["%d|%d|%s|%s" % [portal_chunk.x, portal_chunk.y, edge, loc]] = true
	var pair_count: Dictionary = {}
	var hits: Dictionary = {}
	_portal_gaps = 0
	for portal2 in _portals:
		var edge2: String = str(portal2["edge"])
		if edge2 != "east" and edge2 != "north":
			continue
		var here: Vector2i = portal2["chunk"]
		var nxt := Vector2i(here.x + 1, here.y) if edge2 == "east" else Vector2i(here.x, here.y + 1)
		var nkey := "%d|%d" % [nxt.x, nxt.y]
		if not loaded.has(nkey):
			continue
		var back := "west" if edge2 == "east" else "south"
		var loc2 := "%.2f|%.2f" % [float(portal2["x"]), float(portal2["z"])]
		var mate := "%d|%d|%s|%s" % [nxt.x, nxt.y, back, loc2]
		var pair := "%d|%d|%d|%d" % [here.x, here.y, nxt.x, nxt.y]
		if by_key.has(mate):
			pair_count[pair] = int(pair_count.get(pair, 0)) + 1
			var ck := "%d|%d" % [here.x, here.y]
			var nk := "%d|%d" % [nxt.x, nxt.y]
			hits[ck] = int(hits.get(ck, 0)) + 1
			hits[nk] = int(hits.get(nk, 0)) + 1
		else:
			_portal_gaps += 1
			if _portal_gaps <= 8:
				LaunchConfig.log_line("PORTAL_GAP %s at %s from %s missing %s" % [edge2, loc2, str(here), str(nxt)])
	_open_edges = 0
	for chunk2 in window:
		var east := Vector2i(chunk2.x + 1, chunk2.y)
		if loaded.has("%d|%d" % [east.x, east.y]):
			var east_pair := "%d|%d|%d|%d" % [chunk2.x, chunk2.y, east.x, east.y]
			if int(pair_count.get(east_pair, 0)) < 2:
				_open_edges += 1
		var north := Vector2i(chunk2.x, chunk2.y + 1)
		if loaded.has("%d|%d" % [north.x, north.y]):
			var north_pair := "%d|%d|%d|%d" % [chunk2.x, chunk2.y, north.x, north.y]
			if int(pair_count.get(north_pair, 0)) < 2:
				_open_edges += 1
	_weak_chunks = 0
	for chunk3 in window:
		var id := "%d|%d" % [chunk3.x, chunk3.y]
		if int(hits.get(id, 0)) < 2:
			_weak_chunks += 1


func _edge_names() -> PackedStringArray:
	var names := PackedStringArray()
	var seen: Dictionary = {}
	for portal in _portals:
		var edge: String = str(portal["edge"])
		if seen.has(edge):
			continue
		seen[edge] = true
		names.append(edge)
	return names


func _fill_blocks(chunk: Vector2i) -> void:
	for j in range(_index_z0, _index_z1):
		for i in range(_index_x0, _index_x1):
			var sw: Vector2 = _crossing(i, j)
			var ne: Vector2 = _crossing(i + 1, j + 1)
			var lot_c := Vector2((sw.x + ne.x) * 0.5, (sw.y + ne.y) * 0.5)
			if _Layout.chunk_of(lot_c.x, lot_c.y) != chunk:
				continue
			var tx: int = _gap_of(0, i)
			var tz: int = _gap_of(1, j)
			if _is_park(_world_seed, i, j, tx, tz):
				_parks += 1
				continue
			var style: int = _lot_style(tx, tz)
			var inset: float = _inset_for(style)
			var x0: float = sw.x + HALF + inset
			var z0: float = sw.y + HALF + inset
			var x1: float = ne.x - HALF - inset
			var z1: float = ne.y - HALF - inset
			_fill_lot(chunk, x0, z0, x1, z1, style)


func _is_park(world_seed: int, i: int, j: int, tx: int, tz: int) -> bool:
	var long_side: int = maxi(tx, tz)
	var short_side: int = mini(tx, tz)
	if long_side >= 36 and short_side >= 28:
		return true
	if long_side >= 34 and posmod(_mix(world_seed + i * 19 + j * 23), 3) == 0:
		return true
	return false


func _lot_style(tx: int, tz: int) -> int:
	var short_side: int = mini(tx, tz)
	var long_side: int = maxi(tx, tz)
	if long_side >= 28:
		return 3
	if short_side <= 12:
		return 1
	if short_side <= 14:
		return 0
	return 2


func _inset_for(style: int) -> float:
	if style == 5:
		return 1.2
	if style == 1:
		return 2.2
	if style == 3:
		return 6.5
	if style == 0:
		return 2.8
	return SIDEWALK


func _fill_lot(chunk: Vector2i, x0: float, z0: float, x1: float, z1: float, style: int) -> void:
	var span_x: float = x1 - x0
	var span_z: float = z1 - z0
	var min_span: float = 10.0 if style == 5 else 16.0
	if span_x < min_span or span_z < min_span:
		return
	var cols := 1
	var rows := 1
	if span_x >= 78.0:
		cols = 3
	elif span_x >= 36.0:
		cols = 2
	if span_z >= 78.0:
		rows = 3
	elif span_z >= 36.0:
		rows = 2
	var cell_w: float = span_x / float(cols)
	var cell_d: float = span_z / float(rows)
	for row in rows:
		for col in cols:
			var skip: float = 0.22
			var bw: float = _rng.randf_range(8.0, 14.0)
			var bd: float = _rng.randf_range(8.0, 13.0)
			if style == 1:
				skip = 0.06
				bw = _rng.randf_range(11.0, 18.0)
				bd = _rng.randf_range(11.0, 18.0)
			elif style == 3:
				skip = 0.28
				bw = _rng.randf_range(16.0, 32.0)
				bd = _rng.randf_range(10.0, 18.0)
			elif style == 0:
				skip = 0.2
				bw = _rng.randf_range(7.0, 13.0)
				bd = _rng.randf_range(7.0, 12.0)
			elif style == 5:
				skip = 0.08
				bw = _rng.randf_range(6.0, 11.0)
				bd = _rng.randf_range(5.5, 10.0)
			if _rng.randf() < skip:
				continue
			var pad: float = 1.5
			if bw > cell_w - pad * 2.0:
				bw = cell_w - pad * 2.0
			if bd > cell_d - pad * 2.0:
				bd = cell_d - pad * 2.0
			var min_foot: float = 5.5 if style == 5 else 7.0
			if bw < min_foot or bd < min_foot:
				continue
			var room_x: float = cell_w - bw - pad * 2.0
			var room_z: float = cell_d - bd - pad * 2.0
			if room_x < 0.0:
				room_x = 0.0
			if room_z < 0.0:
				room_z = 0.0
			var ox: float = x0 + float(col) * cell_w + pad + _rng.randf() * room_x
			var oz: float = z0 + float(row) * cell_d + pad + _rng.randf() * room_z
			var foot := Rect2(ox, oz, bw, bd)
			if _near_spawn(foot) or _hits_road(foot):
				continue
			var height: float = _block_height(style)
			var pos := Vector3(ox + bw * 0.5, height * 0.5, oz + bd * 0.5)
			var tint: int = _rng.randi_range(0, 5)
			if style == 1:
				tint = 0 if _rng.randf() < 0.55 else 3
			elif style == 0:
				tint = 1 if _rng.randf() < 0.6 else 5
			elif style == 3:
				tint = 4 if _rng.randf() < 0.7 else 2
			elif style == 5:
				tint = 1 if _rng.randf() < 0.45 else (5 if _rng.randf() < 0.5 else 4)
			_blocks.append({
				"chunk": chunk,
				"pos": pos,
				"size": Vector3(bw, height, bd),
				"tint": tint,
			})


func _block_height(style: int) -> float:
	var pick: int = _rng.randi_range(0, 9)
	if style == 1:
		if pick <= 4:
			return _rng.randf_range(18.0, 32.0)
		return _rng.randf_range(34.0, 56.0)
	if style == 3:
		return _rng.randf_range(7.0, 14.0)
	if style == 0:
		return _rng.randf_range(8.0, 16.0)
	if style == 5:
		if pick <= 7:
			return _rng.randf_range(4.5, 8.5)
		return _rng.randf_range(9.0, 13.0)
	if pick <= 6:
		return _rng.randf_range(6.0, 12.0)
	return _rng.randf_range(12.0, 20.0)


func _near_spawn(foot: Rect2) -> bool:
	var cx: float = clampf(_clear_at.x, foot.position.x, foot.position.x + foot.size.x)
	var cz: float = clampf(_clear_at.y, foot.position.y, foot.position.y + foot.size.y)
	var gap: float = Vector2(_clear_at.x - cx, _clear_at.y - cz).length()
	return gap < SPAWN_CLEAR


func _hits_road(foot: Rect2) -> bool:
	var grown := Rect2(foot.position.x - 1.2, foot.position.y - 1.2, foot.size.x + 2.4, foot.size.y + 2.4)
	for item in _rects_pending:
		var road: Rect2 = item["area"]
		if grown.intersects(road):
			return true
	for walk in _walks:
		if grown.intersects(walk):
			return true
	return false


func _build_tours(chunk: Vector2i) -> void:
	var quads: Array[Dictionary] = []
	for key in _lattice.keys():
		var parts: PackedStringArray = String(key).split("|")
		var i: int = int(parts[0])
		var j: int = int(parts[1])
		if not _has_corner(i + 1, j) or not _has_corner(i + 1, j + 1) or not _has_corner(i, j + 1):
			continue
		var sw: Vector2 = _lattice[key]
		if not _quad_open(i, j):
			continue
		if not _deep(chunk, sw.x, sw.y):
			continue
		var se: Vector2 = _lattice["%d|%d" % [i + 1, j]]
		var ne: Vector2 = _lattice["%d|%d" % [i + 1, j + 1]]
		var nw: Vector2 = _lattice["%d|%d" % [i, j + 1]]
		if not _deep(chunk, se.x, se.y) or not _deep(chunk, ne.x, ne.y) or not _deep(chunk, nw.x, nw.y):
			continue
		var split_here: bool = _split_key.has("0|%d|%d" % [i, j]) or _split_key.has("1|%d|%d" % [i + 1, j]) or _split_key.has("0|%d|%d" % [i, j + 1]) or _split_key.has("1|%d|%d" % [i, j])
		quads.append({"i": i, "j": j, "split": split_here})
	if quads.is_empty():
		return
	var first: Dictionary = quads[0]
	for quad in quads:
		if bool(quad["split"]):
			first = quad
			break
	_tour = _walk_block(int(first["i"]), int(first["j"]), true)
	_tour_back = _walk_block(int(first["i"]), int(first["j"]), false)
	if quads.size() > 1:
		var other: Dictionary = quads[quads.size() - 1]
		_tour_alt = _walk_block(int(other["i"]), int(other["j"]), true)
		_tour_alt_back = _walk_block(int(other["i"]), int(other["j"]), false)


func _has_corner(i: int, j: int) -> bool:
	return _lattice.has("%d|%d" % [i, j])


func _quad_open(i: int, j: int) -> bool:
	if not _segment_open(_world_seed, i, j, 0):
		return false
	if not _segment_open(_world_seed, i, j + 1, 0):
		return false
	if not _segment_open(_world_seed, i, j, 1):
		return false
	if not _segment_open(_world_seed, i + 1, j, 1):
		return false
	return true


func _walk_block(i: int, j: int, forward: bool) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var steps: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	if not forward:
		steps = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
	var cursor := Vector2i(i, j)
	for s in steps.size():
		var move: Vector2i = steps[s]
		var nxt: Vector2i = cursor + move
		_sample_side(pts, cursor, nxt)
		var leave := Vector3(float(move.x), 0.0, float(move.y))
		var after: Vector2i = steps[(s + 1) % steps.size()]
		var next_dir := Vector3(float(after.x), 0.0, float(after.y))
		_link_corner(pts, nxt, leave, next_dir)
		cursor = nxt
	return pts


func _sample_side(pts: PackedVector3Array, a: Vector2i, b: Vector2i) -> void:
	var key_a := "%d|%d" % [a.x, a.y]
	var key_b := "%d|%d" % [b.x, b.y]
	if not _lattice.has(key_a) or not _lattice.has(key_b):
		return
	var ca: Vector2 = _lattice[key_a]
	var cb: Vector2 = _lattice[key_b]
	var delta := Vector3(cb.x - ca.x, 0.0, cb.y - ca.y)
	if delta.length_squared() < 1.0:
		return
	var dir: Vector3 = delta.normalized()
	var mouth := Vector3(ca.x, 0.0, ca.y) + dir * HALF
	var length: float = delta.length() - CROSS
	if length < TILE:
		return
	var axis := 0
	var si: int = a.x
	var sj: int = a.y
	if absf(dir.z) > absf(dir.x):
		axis = 1
		if dir.z < 0.0:
			sj = b.y
	elif dir.x < 0.0:
		si = b.x
	var split_key := "%d|%d|%d" % [axis, si, sj]
	var split: bool = _split_key.has(split_key)
	var run_tiles: int = int(_split_run.get(split_key, SPLIT_RUN))
	var right: Vector3 = _right_of(dir)
	var marks: Array[float] = [0.0, length]
	if split:
		var lead: float = float(SPLIT_LEAD) * TILE
		var taper: float = float(TAPER_TILES) * TILE
		var run: float = float(run_tiles) * TILE
		marks = [0.0, lead, lead + taper, lead + taper + run, lead + 2.0 * taper + run, length]
	var cursor: float = 0.0
	for mark_v in marks:
		var mark: float = float(mark_v)
		while cursor + 8.0 < mark - 0.2:
			cursor += 8.0
			_push(pts, mouth + dir * cursor + right * _lane_off(cursor, split, run_tiles))
		_push(pts, mouth + dir * mark + right * _lane_off(mark, split, run_tiles))
		cursor = mark


func _lane_off(dist: float, split: bool, run_tiles: int) -> float:
	if not split:
		return LANE
	var lead: float = float(SPLIT_LEAD) * TILE
	var taper: float = float(TAPER_TILES) * TILE
	var run: float = float(run_tiles) * TILE
	if dist <= lead:
		return LANE
	if dist <= lead + taper:
		return lerpf(LANE, LANE * 2.0, (dist - lead) / taper)
	if dist <= lead + taper + run:
		return LANE * 2.0
	if dist <= lead + 2.0 * taper + run:
		return lerpf(LANE * 2.0, LANE, (dist - lead - taper - run) / taper)
	return LANE


func _link_corner(pts: PackedVector3Array, index: Vector2i, arrive: Vector3, leave: Vector3) -> void:
	var key := "%d|%d" % [index.x, index.y]
	if not _lattice.has(key):
		return
	var center: Vector2 = _lattice[key]
	var c := Vector3(center.x, 0.0, center.y)
	var arrive_right: Vector3 = _right_of(arrive)
	var leave_right: Vector3 = _right_of(leave)
	_push(pts, c - arrive * HALF + arrive_right * LANE)
	_push(pts, c + arrive_right * LANE * 0.65 + leave_right * LANE * 0.65)
	_push(pts, c + leave * HALF + leave_right * LANE)


func _fallback_tour(chunk: Vector2i) -> void:
	_tour = PackedVector3Array()
	_tour_back = PackedVector3Array()
	for j in range(_index_z0, _index_z1):
		for i in range(_index_x0, _index_x1):
			if not _segment_open(_world_seed, i, j, 0):
				continue
			var a: Vector2 = _crossing(i, j)
			var b: Vector2 = _crossing(i + 1, j)
			var mid := Vector2((a.x + b.x) * 0.5, a.y)
			if _Layout.chunk_of(mid.x, mid.y) != chunk:
				continue
			var x: float = a.x + HALF
			var end_x: float = b.x - HALF
			while x <= end_x:
				_tour.append(Vector3(x, 0.0, a.y + LANE))
				x += 8.0
			var back: float = end_x
			while back >= a.x + HALF:
				_tour_back.append(Vector3(back, 0.0, a.y - LANE))
				back -= 8.0
			return


func _junction_list() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for key in _lattice.keys():
		var center: Vector2 = _lattice[key]
		out.append(center)
	return out


func _ew_name(j: int) -> String:
	var names: PackedStringArray = PackedStringArray([
		"Bridge Road", "Market Street", "Lake Street", "Oak Street", "Diner Street",
		"School Street", "Ridge Street", "Park Road", "Industrial Road", "North Street",
	])
	var n: int = j
	if n < 0:
		n = -n
	return names[n % names.size()]


func _ns_name(i: int) -> String:
	var names: PackedStringArray = PackedStringArray([
		"Hall Avenue", "Pine Street", "Mill Street", "Hospital Street", "Bank Street",
		"Commerce Street", "Tower Street", "Yard Street", "Elm Street", "Police Street",
	])
	var n: int = i
	if n < 0:
		n = -n
	return names[n % names.size()]


func _square(x: float, z: float, hx: float, hz: float) -> Rect2:
	return Rect2(x - hx, z - hz, hx * 2.0, hz * 2.0)


func _band_rect(mouth: Vector3, dir: Vector3, length: float, half_width: float) -> Rect2:
	var side: Vector3 = _right_of(dir)
	var a: Vector3 = mouth + side * half_width
	var b: Vector3 = mouth - side * half_width
	var c: Vector3 = mouth + dir * length + side * half_width
	var d: Vector3 = mouth + dir * length - side * half_width
	return _bounds4(a, b, c, d)


func _road_rect(mouth: Vector3, end: Vector3, angle: float, half_width: float) -> Rect2:
	var right: Vector3 = _right(angle)
	var a: Vector3 = mouth + right * half_width
	var b: Vector3 = mouth - right * half_width
	var c: Vector3 = end + right * half_width
	var d: Vector3 = end - right * half_width
	return _bounds4(a, b, c, d)


func _bounds4(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> Rect2:
	var x0: float = minf(minf(a.x, b.x), minf(c.x, d.x))
	var z0: float = minf(minf(a.z, b.z), minf(c.z, d.z))
	var x1: float = maxf(maxf(a.x, b.x), maxf(c.x, d.x))
	var z1: float = maxf(maxf(a.z, b.z), maxf(c.z, d.z))
	return Rect2(x0, z0, maxf(x1 - x0, 0.05), maxf(z1 - z0, 0.05))


func _remember_rect(area: Rect2, road_name: String) -> void:
	_rects_pending.append({"area": area, "name": road_name})
	_rects += 1


func _dir(angle: float) -> Vector3:
	return Vector3(cos(angle), 0.0, sin(angle))


func _right(angle: float) -> Vector3:
	return Vector3(-sin(angle), 0.0, cos(angle))


func _right_of(dir: Vector3) -> Vector3:
	return _right(atan2(dir.z, dir.x))


func _push(points: PackedVector3Array, point: Vector3) -> void:
	if points.is_empty() or points[points.size() - 1].distance_squared_to(point) > 0.16:
		points.append(point)


func _put(chunk: Vector2i, at: Vector3, angle: float, kind: String, mirrored: bool = false) -> void:
	if not _mesh.has(kind):
		return
	if kind.ends_with("yellow") or kind.ends_with("white"):
		_paint_count += 1
	var key := "%d|%d|%s" % [chunk.x, chunk.y, kind]
	if not _xf.has(key):
		_xf[key] = []
	var basis: Basis = Basis(_dir(angle), Vector3.UP, _right(angle))
	if mirrored:
		basis = Basis(_dir(angle), Vector3.UP, -_right(angle))
	var list: Array = _xf[key]
	var index: int = list.size()
	list.append(Transform3D(basis, at))
	if _track_surface(kind):
		_surfaces.append({
			"kind": kind,
			"chunk": chunk,
			"at": at,
			"angle": angle,
			"mirrored": mirrored,
			"key": key,
			"index": index,
		})


func _add_box(chunk: Vector2i, mid: Vector3, angle: float, length: float, width: float) -> void:
	_boxes.append({
		"chunk": chunk,
		"mid": mid,
		"angle": angle,
		"length": length,
		"width": width,
	})


func _add_straight_walks(chunk: Vector2i, mouth: Vector3, angle: float, length: float) -> void:
	var dir: Vector3 = _dir(angle)
	var right: Vector3 = _right(angle)
	var mid: Vector3 = mouth + dir * (length * 0.5)
	var lateral: float = HALF + WALK_W * 0.5
	_add_walk_box(chunk, mid + right * lateral, angle, length, WALK_W)
	_add_walk_box(chunk, mid - right * lateral, angle, length, WALK_W)


func _put_flare_walks(chunk: Vector2i, at: Vector3, angle: float) -> void:
	_put(chunk, at, angle, "walk_flare", false)
	_put(chunk, at, angle, "walk_flare", true)
	_place_walk_specs(chunk, at, angle, false, _flare_specs)
	_place_walk_specs(chunk, at, angle, true, _flare_specs)
	_walk_flares += 2


func _place_walk_specs(chunk: Vector2i, at: Vector3, angle: float, mirrored: bool, specs: Array[Dictionary]) -> void:
	var right: Vector3 = _right(angle)
	if mirrored:
		right = -right
	var basis := Basis(_dir(angle), Vector3.UP, right)
	for spec in specs:
		var local := Vector3(float(spec["x"]), 0.0, float(spec["z"]))
		var world: Vector3 = at + basis * local
		var fwd: Vector3 = basis * _dir(float(spec["yaw"]))
		_add_walk_box(chunk, world, atan2(fwd.z, fwd.x), float(spec["length"]), float(spec["width"]))


func _add_walk_box(chunk: Vector2i, mid: Vector3, angle: float, length: float, width: float) -> void:
	_walk_boxes.append({
		"chunk": chunk,
		"mid": mid,
		"angle": angle,
		"length": length,
		"width": width,
	})
	var dir: Vector3 = _dir(angle)
	var right: Vector3 = _right(angle)
	var hx: float = length * 0.5
	var hz: float = width * 0.5
	var a: Vector3 = mid + dir * hx + right * hz
	var b: Vector3 = mid + dir * hx - right * hz
	var c: Vector3 = mid - dir * hx + right * hz
	var d: Vector3 = mid - dir * hx - right * hz
	_walks.append(_bounds4(a, b, c, d))


func _note_mouths(center: Vector2) -> void:
	var dirs: Array[Vector2] = [Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.0, -1.0)]
	for raw in dirs:
		var dir: Vector2 = raw
		_mouths.append({
			"at": center + dir * (HALF + 0.45),
			"center": center,
		})


func _note_box_edges(center: Vector2, asphalt: bool) -> void:
	var east_a := Vector3(center.x + HALF, 0.0, center.y - HALF)
	var east_b := Vector3(center.x + HALF, 0.0, center.y + HALF)
	var west_a := Vector3(center.x - HALF, 0.0, center.y - HALF)
	var west_b := Vector3(center.x - HALF, 0.0, center.y + HALF)
	var north_a := Vector3(center.x - HALF, 0.0, center.y + HALF)
	var north_b := Vector3(center.x + HALF, 0.0, center.y + HALF)
	var south_a := Vector3(center.x - HALF, 0.0, center.y - HALF)
	var south_b := Vector3(center.x + HALF, 0.0, center.y - HALF)
	var edges: Array[Dictionary] = [
		{"a": east_a, "b": east_b},
		{"a": west_a, "b": west_b},
		{"a": north_a, "b": north_b},
		{"a": south_a, "b": south_b},
	]
	for edge in edges:
		if asphalt:
			_asphalt_lips.append(edge)
		else:
			_dirt_caps.append(edge)


func _note_lips(mouth: Vector3, end: Vector3, angle: float) -> void:
	var right: Vector3 = _right(angle) * HALF
	_asphalt_lips.append({"a": mouth + right, "b": end + right})
	_asphalt_lips.append({"a": mouth - right, "b": end - right})


func _note_cap(at: Vector3, angle: float) -> void:
	var right: Vector3 = _right(angle) * HALF
	_dirt_caps.append({"a": at + right, "b": at - right})


func _put_edge(chunk: Vector2i, at: Vector3, angle: float, side: float) -> void:
	var kind: String = "straight_white_pos" if side > 0.0 else "straight_white_neg"
	if not _mesh.has(kind):
		return
	_put(chunk, at, angle, kind, false)
	var dir: Vector3 = _dir(angle)
	var right: Vector3 = _right(angle) * (80.0 * UNIT * side)
	_paint_edges.append({
		"key": "%d|%d|%s" % [chunk.x, chunk.y, kind],
		"index": _xf_index(chunk, kind),
		"a": at + right,
		"b": at + dir * TILE + right,
	})


func _put_cross_paint(chunk: Vector2i, west: Vector3) -> void:
	for quarter in 4:
		var kind := "cross_white_%d" % quarter
		if not _mesh.has(kind):
			continue
		_put(chunk, west, 0.0, kind, false)
		var local: Vector2 = _corner_local(quarter)
		var at := Vector3(west.x + local.x, 0.0, west.z + local.y)
		_paint_edges.append({
			"key": "%d|%d|%s" % [chunk.x, chunk.y, kind],
			"index": _xf_index(chunk, kind),
			"a": at,
			"b": at,
		})


func _corner_local(quarter: int) -> Vector2:
	var spun: Vector2 = _spin(4.0, -80.0, quarter)
	return Vector2(spun.x * UNIT, spun.y * UNIT)


func _xf_index(chunk: Vector2i, kind: String) -> int:
	var key := "%d|%d|%s" % [chunk.x, chunk.y, kind]
	if not _xf.has(key):
		return 0
	return (_xf[key] as Array).size() - 1


func _drop_bare_paint() -> void:
	_bare = _bare_seams()
	_bare_count = _bare.size()
	if _bare.is_empty():
		return
	var grouped: Dictionary = {}
	for edge in _paint_edges:
		if not _edge_hits_bare(edge):
			continue
		var key: String = str(edge["key"])
		if not grouped.has(key):
			grouped[key] = {}
		(grouped[key] as Dictionary)[int(edge["index"])] = true
	for key2 in grouped.keys():
		var drop: Dictionary = grouped[key2]
		if not _xf.has(key2):
			continue
		var list: Array = _xf[key2]
		var kept: Array = []
		for n in list.size():
			if drop.has(n):
				_paint_count -= 1
				continue
			kept.append(list[n])
		if kept.is_empty():
			_xf.erase(key2)
		else:
			_xf[key2] = kept


func _bare_seams() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cap in _dirt_caps:
		var ca: Vector3 = cap["a"]
		var cb: Vector3 = cap["b"]
		var mid: Vector3 = (ca + cb) * 0.5
		var matched := false
		for lip in _asphalt_lips:
			var la: Vector3 = lip["a"]
			var lb: Vector3 = lip["b"]
			if _dist_point_seg(mid, la, lb) > 0.35:
				continue
			if _dist_point_seg(ca, la, lb) > 0.55 and _dist_point_seg(cb, la, lb) > 0.55:
				continue
			matched = true
			break
		if matched:
			out.append(cap)
	return out


func _edge_hits_bare(edge: Dictionary) -> bool:
	var a: Vector3 = edge["a"]
	var b: Vector3 = edge["b"]
	for seam in _bare:
		var sa: Vector3 = seam["a"]
		var sb: Vector3 = seam["b"]
		if _dist_point_seg(a, sa, sb) < 0.48 or _dist_point_seg(b, sa, sb) < 0.48:
			return true
		var mid: Vector3 = (a + b) * 0.5
		if _dist_point_seg(mid, sa, sb) < 0.48:
			return true
	return false


func _dist_point_seg(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab: Vector3 = b - a
	var den: float = ab.length_squared()
	if den < 0.0001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(ab) / den, 0.0, 1.0)
	return point.distance_to(a + ab * t)


func _audit_mouths() -> void:
	_empty_mouths = 0
	for mouth in _mouths:
		var at: Vector2 = mouth["at"]
		if _mouth_filled(at):
			continue
		_empty_mouths += 1
		var center: Vector2 = mouth["center"]
		push_error("4-way at (%.1f, %.1f) has an empty connector." % [center.x, center.y])
	if _empty_mouths > 0:
		_joint_error = maxf(_joint_error, 5.0)


func _mouth_filled(at: Vector2) -> bool:
	var flat := Vector3(at.x, 0.0, at.y)
	for item in _rects_pending:
		var area: Rect2 = item["area"]
		if area.has_point(at):
			return true
	for seg in _segments:
		var sa: Vector3 = seg["from"]
		var sb: Vector3 = seg["to"]
		if _dist_point_seg(flat, sa, sb) <= HALF + 0.15:
			return true
	for key in _lattice.keys():
		var parts: PackedStringArray = String(key).split("|")
		var i: int = int(parts[0])
		var j: int = int(parts[1])
		var center: Vector2 = _lattice[key]
		if _span_near(flat, center, i + 1, j):
			return true
		if _span_near(flat, center, i, j + 1):
			return true
	return false


func _span_near(flat: Vector3, center: Vector2, i: int, j: int) -> bool:
	var nxt := "%d|%d" % [i, j]
	if not _lattice.has(nxt):
		return false
	var other: Vector2 = _lattice[nxt]
	var dist: float = _dist_point_seg(flat, Vector3(center.x, 0.0, center.y), Vector3(other.x, 0.0, other.y))
	return dist <= HALF + 0.15


func _plan_decor() -> void:
	_decors.clear()
	var barrier_lat: float = HALF + WALK_W + 0.70
	for seg in _segments:
		var kind := ""
		if seg.has("kind"):
			kind = str(seg["kind"])
		var a: Vector3 = seg["from"]
		var b: Vector3 = seg["to"]
		var delta: Vector3 = b - a
		var length: float = delta.length()
		if length < 20.0:
			continue
		var dir: Vector3 = delta / length
		var right: Vector3 = _right_of(dir)
		var dress: int = posmod(_mix(_world_seed + int(a.x * 10.0) + int(a.z * 7.0)), 3)
		var paved_lamp: float = HALF + WALK_W + 0.45
		if kind == "arterial":
			_line_decor(a, dir, right, length, "lamp", 72.0, paved_lamp, true, 18.0)
			_line_decor(a, dir, right, length, "barrier", 58.0, barrier_lat, false, 34.0)
		elif kind == "street" or kind == "strips":
			_line_decor(a, dir, right, length, "lamp", 96.0, paved_lamp, false, 18.0)
			if dress == 0:
				_line_decor(a, dir, right, length, "barrier", 70.0, barrier_lat, false, 40.0)
		elif kind == "alley" or kind == "radial" or kind == "court":
			_line_decor(a, dir, right, length, "lamp", 110.0, HALF + 1.2, false, 16.0)
	_plan_signals()
	_plan_signs()


func _line_decor(origin: Vector3, dir: Vector3, right: Vector3, length: float, kind: String, step: float, lateral: float, both: bool, start: float) -> void:
	var cursor: float = start
	var flip: float = 1.0
	while cursor < length - 14.0:
		_place_line(origin, dir, right, cursor, lateral * flip, kind)
		if both:
			_place_line(origin, dir, right, cursor, -lateral * flip, kind)
		cursor += step
		if not both:
			flip = -flip


func _place_line(origin: Vector3, dir: Vector3, right: Vector3, cursor: float, side: float, kind: String) -> void:
	var at: Vector3 = origin + dir * cursor + right * side
	if kind == "barrier" and _crowded(at, 2.4):
		return
	var aim: Vector3 = dir
	if kind == "lamp":
		aim = -right if side >= 0.0 else right
	_try_decor(at, aim, kind, 0.0)


func _plan_signals() -> void:
	_plan_controls()
	for row in _controls:
		if str(row["mode"]) != "light":
			continue
		var travel: Vector3 = row["dir"]
		var center := Vector2(float(row["cx"]), float(row["cz"]))
		_place_signal(center, travel, int(row["kind"]))


func _plan_controls() -> void:
	for key in _lattice.keys():
		var parts: PackedStringArray = String(key).split("|")
		var i: int = int(parts[0])
		var j: int = int(parts[1])
		var center: Vector2 = _lattice[key]
		if not _on_artery_line(center):
			continue
		# The station grid runs past the chunk. Those corners are not paved.
		if not _paved_cross_at(center):
			continue
		_control_from(i, j, center, -1, 0)
		_control_from(i, j, center, 1, 0)
		_control_from(i, j, center, 0, -1)
		_control_from(i, j, center, 0, 1)


func _paved_cross_at(center: Vector2) -> bool:
	for placed in _paved_crosses:
		if placed.distance_squared_to(center) < 0.25:
			return true
	return false


func _control_from(i: int, j: int, center: Vector2, sx: int, sy: int) -> void:
	var ni: int = i + sx
	var nj: int = j + sy
	if not _has_corner(ni, nj):
		return
	var axis := 0
	var seg_i: int = i
	var seg_j: int = j
	if sx != 0:
		axis = 0
		seg_i = mini(i, ni)
		seg_j = j
	else:
		axis = 1
		seg_i = i
		seg_j = mini(j, nj)
	if not _segment_open(_world_seed, seg_i, seg_j, axis):
		return
	var travel := Vector3(-float(sx), 0.0, -float(sy))
	var back: float = HALF + 3.4
	var right: Vector3 = _right_of(travel)
	var line := Vector3(center.x, 0.65, center.y) - travel * back + right * LANE
	var main: bool = _is_main_segment(axis, seg_i, seg_j)
	var mode := "stop"
	var kind := 0
	if main:
		mode = "light"
		kind = 1 if absf(travel.x) >= absf(travel.z) else 2
	_controls.append({
		"pos": line,
		"dir": travel,
		"mode": mode,
		"kind": kind,
		"cx": center.x,
		"cz": center.y,
	})


func _on_artery_line(point: Vector2) -> bool:
	for key in _artery_x.keys():
		var line_x: float = float(_station_x[int(key)])
		if absf(point.x - line_x) < 1.5:
			return true
	for key2 in _artery_z.keys():
		var line_z: float = float(_station_z[int(key2)])
		if absf(point.y - line_z) < 1.5:
			return true
	return false


func _plan_signs() -> void:
	for seg in _segments:
		var kind := ""
		if seg.has("kind"):
			kind = str(seg["kind"])
		if kind == "arterial":
			_speed_sign(seg)
		elif kind != "":
			_stop_end(seg, true)
			_stop_end(seg, false)


func _speed_sign(seg: Dictionary) -> void:
	var a: Vector3 = seg["from"]
	var b: Vector3 = seg["to"]
	var delta: Vector3 = b - a
	var length: float = delta.length()
	if length < 36.0:
		return
	var dir: Vector3 = delta / length
	var at: Vector3 = a + dir * (length * 0.5) + _right_of(dir) * (HALF + WALK_W + 0.55)
	if _crowded(at, 3.0):
		return
	_try_decor(at, dir, "speed", 0.0)


func _stop_end(seg: Dictionary, at_end: bool) -> void:
	var a: Vector3 = seg["from"]
	var b: Vector3 = seg["to"]
	var kind: String = str(seg["kind"])
	var at: Vector3 = b if at_end else a
	var other: Vector3 = a if at_end else b
	if not _near_arterial(at):
		return
	var delta: Vector3 = at - other
	var length: float = delta.length()
	var back: float = HALF + 3.4
	if length < back + 6.0:
		return
	var travel: Vector3 = delta / length
	var lateral: float = HALF + WALK_W + 0.55
	if kind == "alley" or kind == "radial" or kind == "court":
		lateral = HALF + 1.05
	var pos: Vector3 = at - travel * back + _right_of(travel) * lateral
	if _crowded(pos, 3.0):
		return
	_try_decor(pos, travel, "stop", 0.0)
	if kind != "alley" and kind != "radial" and kind != "strips" and kind != "court":
		return
	var line := at - travel * back + _right_of(travel) * LANE
	var cross := _nearest_cross(at)
	_controls.append({
		"pos": Vector3(line.x, 0.65, line.z),
		"dir": travel,
		"mode": "stop",
		"kind": 0,
		"cx": cross.x,
		"cz": cross.y,
	})


func _nearest_cross(at: Vector3) -> Vector2:
	var best := Vector2(at.x, at.z)
	var best_d := 18.0
	for center in _cross_points:
		var gap: float = Vector2(center.x - at.x, center.y - at.z).length()
		if gap < best_d:
			best_d = gap
			best = center
	return best


func _near_arterial(at: Vector3) -> bool:
	for seg in _segments:
		var kind := ""
		if seg.has("kind"):
			kind = str(seg["kind"])
		if kind != "arterial":
			continue
		if _dist_point_seg(at, seg["from"], seg["to"]) <= HALF + 1.2:
			return true
	return false


func _crowded(at: Vector3, radius: float) -> bool:
	for spec in _decors:
		var there: Vector3 = spec["at"]
		if Vector2(there.x - at.x, there.z - at.z).length() < radius:
			return true
	return false


func _place_signal(center: Vector2, travel: Vector3, axis_kind: int) -> void:
	var right: Vector3 = _right_of(travel)
	var across: Vector3 = -right
	var back: float = HALF + 2.4
	var lateral: float = HALF + WALK_W + 0.08
	var post := Vector3(center.x, 0.0, center.y) - travel * back + right * lateral
	if not _signal_ok(post):
		return
	var base_y: float = _lot_top_at(post.x, post.z)
	var head_kind := "signal_head_ew" if axis_kind == 1 else "signal_head_ns"
	_decors.append({
		"at": post,
		"dir": across,
		"kind": "signal_pole",
		"lift": 0.0,
		"base_y": base_y,
	})
	var near: float = lateral - LANE
	var far: float = minf(lateral + LANE, 181.0 * UNIT - 0.2)
	var hanger_y: float = _signal_arm_y
	_decors.append({
		"at": post + across * near,
		"dir": across,
		"kind": head_kind,
		"lift": hanger_y,
		"base_y": base_y,
	})
	_decors.append({
		"at": post + across * far,
		"dir": across,
		"kind": head_kind,
		"lift": hanger_y,
		"base_y": base_y,
	})


func _signal_ok(at: Vector3) -> bool:
	if not _beside_pavement(at, WALK_W + 0.7):
		return false
	var flat := Vector2(at.x, at.z)
	for spec in _blocks:
		var pos: Vector3 = spec["pos"]
		var size: Vector3 = spec["size"]
		var foot := Rect2(pos.x - size.x * 0.5 - 0.4, pos.z - size.z * 0.5 - 0.4, size.x + 0.8, size.z + 0.8)
		if foot.has_point(flat):
			return false
	if _crowded(at, 1.6):
		return false
	return true


func _beside_pavement(at: Vector3, reach: float) -> bool:
	var flat := Vector2(at.x, at.z)
	for item in _rects_pending:
		var area: Rect2 = item["area"]
		if _rect_gap(area, flat) <= reach:
			return true
	return false


func _rect_gap(area: Rect2, flat: Vector2) -> float:
	var x: float = clampf(flat.x, area.position.x, area.position.x + area.size.x)
	var y: float = clampf(flat.y, area.position.y, area.position.y + area.size.y)
	return Vector2(flat.x - x, flat.y - y).length()


func _try_decor(at: Vector3, dir: Vector3, kind: String, lift: float) -> void:
	if not _decor_ok(at):
		return
	_decors.append({"at": at, "dir": dir, "kind": kind, "lift": lift})


func _decor_ok(at: Vector3) -> bool:
	var flat := Vector2(at.x, at.z)
	for key in _lattice.keys():
		var center: Vector2 = _lattice[key]
		if flat.distance_to(center) < HALF + 5.0:
			return false
	for seam in _bare:
		if _dist_point_seg(at, seam["a"], seam["b"]) < 6.5:
			return false
	for spec in _blocks:
		var pos: Vector3 = spec["pos"]
		var size: Vector3 = spec["size"]
		var foot := Rect2(pos.x - size.x * 0.5 - 0.6, pos.z - size.z * 0.5 - 0.6, size.x + 1.2, size.z + 1.2)
		if foot.has_point(flat):
			return false
	for item in _rects_pending:
		var area: Rect2 = item["area"]
		if area.has_point(flat):
			return false
	for walk in _walks:
		if walk.has_point(flat):
			return false
	return true


func _publish_cone_stacks(city: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	# Chunk content: seeded from the world seed plus the home chunk's grid coords.
	rng.seed = _chunk_seed(_world_seed, _Layout.chunk_of(_clear_at.x, _clear_at.y)) + 4817
	var candidates: Array[Vector3] = []
	for box in _walk_boxes:
		var length: float = float(box["length"])
		if length < 16.0:
			continue
		var mid: Vector3 = box["mid"]
		var angle: float = float(box["angle"])
		var dir: Vector3 = _dir(angle)
		var span: float = length - STACK_END * 2.0
		if span < 2.0:
			continue
		var steps: int = maxi(1, int(span / 32.0))
		var slot: float = span / float(steps)
		for s in steps:
			var along: float = -length * 0.5 + STACK_END + (float(s) + 0.35 + rng.randf() * 0.3) * slot
			var spot: Vector3 = mid + dir * along
			spot.y = 0.0
			if _stack_spot_ok(spot):
				candidates.append(spot)
	_shuffle_spots(candidates, rng)
	_prefer_near_spawn(candidates)
	var sites: Array[Dictionary] = []
	for spot in candidates:
		if sites.size() >= STACK_CAP:
			break
		if not _stack_clear(spot, sites):
			continue
		sites.append({
			"at": Vector3(spot.x, WALK_TOP, spot.z),
			"count": _stack_count(rng),
			"yaw": rng.randf_range(-0.45, 0.45),
		})
	city.set_meta("cone_stack_sites", sites)
	city.set_meta("cone_stack_count", sites.size())
	_stack_sites = sites


## Milestone 1 spawn: the sidewalk point in the target's chunk nearest the target.
## Never on asphalt: the point must sit inside a sidewalk box, clear of every road
## rect, building footprint and published cone stack.
func sidewalk_spawn(target: Vector2) -> Vector3:
	var home: Vector2i = _Layout.chunk_of(target.x, target.y)
	var best := Vector3.ZERO
	var best_d := INF
	for box in _walk_boxes:
		var chunk: Vector2i = box["chunk"]
		if chunk != home:
			continue
		var length: float = float(box["length"])
		var width: float = float(box["width"])
		if width < 1.0 or length < 2.0:
			continue
		var mid: Vector3 = box["mid"]
		var dir: Vector3 = _dir(float(box["angle"]))
		var reach: float = length * 0.5 - 0.6
		var steps: int = maxi(1, int(reach / 1.0))
		for k in range(-steps, steps + 1):
			var along: float = reach * float(k) / float(steps)
			var spot: Vector3 = mid + dir * along
			var flat := Vector2(spot.x, spot.z)
			var d: float = flat.distance_to(target)
			if d >= best_d:
				continue
			if _nearest_road_gap(flat) < 0.5:
				continue
			if _blocked_foot(flat, 0.8):
				continue
			if _near_stack_site(flat, 3.0):
				continue
			best_d = d
			best = Vector3(spot.x, WALK_TOP + 0.02, spot.z)
	if best_d == INF:
		push_warning("No sidewalk spawn found in chunk %s; spawning at the chunk centre." % str(home))
		return Vector3(target.x, WALK_TOP + 0.02, target.y)
	return best


func _near_stack_site(flat: Vector2, radius: float) -> bool:
	for spec in _stack_sites:
		var at: Vector3 = spec["at"]
		if Vector2(at.x, at.z).distance_to(flat) < radius:
			return true
	return false


func _stack_spot_ok(spot: Vector3) -> bool:
	var flat := Vector2(spot.x, spot.z)
	if flat.distance_to(_clear_at) < STACK_SPAWN:
		return false
	var gap: float = _nearest_road_gap(flat)
	if gap < 0.85 or gap > 2.3:
		return false
	for item in _rects_pending:
		var area: Rect2 = item["area"]
		if area.has_point(flat):
			return false
	if _blocked_foot(flat, 0.45):
		return false
	if _crowded(spot, 1.15):
		return false
	return true


func _nearest_road_gap(flat: Vector2) -> float:
	var best := 80.0
	for item in _rects_pending:
		var area: Rect2 = item["area"]
		var gap: float = _rect_gap(area, flat)
		if gap < best:
			best = gap
	return best


func _blocked_foot(flat: Vector2, pad: float) -> bool:
	for spec in _blocks:
		var pos: Vector3 = spec["pos"]
		var size: Vector3 = spec["size"]
		var foot := Rect2(pos.x - size.x * 0.5 - pad, pos.z - size.z * 0.5 - pad, size.x + pad * 2.0, size.z + pad * 2.0)
		if foot.has_point(flat):
			return true
	return false


func _stack_clear(spot: Vector3, sites: Array[Dictionary]) -> bool:
	for spec in sites:
		var at: Vector3 = spec["at"]
		var sep: float = Vector2(at.x - spot.x, at.z - spot.z).length()
		if sep < STACK_GAP:
			return false
	return true


func _stack_count(rng: RandomNumberGenerator) -> int:
	var roll: int = rng.randi_range(0, 9)
	if roll < 2:
		return 3
	if roll < 6:
		return 4
	if roll < 8:
		return 5
	if roll == 8:
		return 6
	return 7


func _shuffle_spots(spots: Array[Vector3], rng: RandomNumberGenerator) -> void:
	for i in range(spots.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Vector3 = spots[i]
		spots[i] = spots[j]
		spots[j] = swap


func _prefer_near_spawn(spots: Array[Vector3]) -> void:
	var best := -1
	var best_d := 120.0
	for i in spots.size():
		var d: float = Vector2(spots[i].x - _clear_at.x, spots[i].z - _clear_at.y).length()
		if d < best_d:
			best_d = d
			best = i
	if best > 0:
		var first: Vector3 = spots[best]
		spots[best] = spots[0]
		spots[0] = first


func _spawn(city: Node3D) -> void:
	var old: Node = city.get_node_or_null("RoadNet")
	if old != null:
		old.free()
	var root := Node3D.new()
	root.name = "RoadNet"
	city.add_child(root)
	for key in _xf.keys():
		var parts: PackedStringArray = String(key).split("|")
		var chunk := Vector2i(int(parts[0]), int(parts[1]))
		var kind := parts[2]
		var host: Node3D = _chunk_node(root, chunk)
		var list: Array = _xf[key]
		var many := MultiMesh.new()
		many.transform_format = MultiMesh.TRANSFORM_3D
		many.mesh = _mesh[kind]
		many.instance_count = list.size()
		for n in list.size():
			var xf: Transform3D = list[n]
			many.set_instance_transform(n, xf)
		var view := MultiMeshInstance3D.new()
		view.name = kind
		view.multimesh = many
		view.material_override = _material_for(kind)
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(view)
	for box in _boxes:
		var road_chunk: Vector2i = box["chunk"]
		var road_host: Node3D = _chunk_node(root, road_chunk)
		var body: StaticBody3D = _pavement(road_host)
		var shape := CollisionShape3D.new()
		var cube := BoxShape3D.new()
		cube.size = Vector3(float(box["length"]), 0.5, float(box["width"]))
		shape.shape = cube
		var mid: Vector3 = box["mid"]
		shape.transform = Transform3D(Basis(_dir(float(box["angle"])), Vector3.UP, _right(float(box["angle"]))), Vector3(mid.x, 0.0, mid.z))
		body.add_child(shape)
	for walk_box in _walk_boxes:
		var walk_chunk: Vector2i = walk_box["chunk"]
		var walk_host: Node3D = _chunk_node(root, walk_chunk)
		var walk_body: StaticBody3D = _walk_body(walk_host)
		var walk_shape := CollisionShape3D.new()
		var walk_cube := BoxShape3D.new()
		var walk_top: float = ROAD_Y + 6.0 * UNIT
		walk_cube.size = Vector3(float(walk_box["length"]), walk_top, float(walk_box["width"]))
		walk_shape.shape = walk_cube
		var walk_mid: Vector3 = walk_box["mid"]
		var walk_angle: float = float(walk_box["angle"])
		walk_shape.transform = Transform3D(Basis(_dir(walk_angle), Vector3.UP, _right(walk_angle)), Vector3(walk_mid.x, walk_top * 0.5, walk_mid.z))
		walk_body.add_child(walk_shape)
	_spawn_aprons(root)
	_spawn_cut_walks(root)
	_spawn_lots(root)
	_spawn_blocks(root)
	_spawn_medians(root)
	_spawn_decor(root)
	_audit_blocks()
	for item in _rects_pending:
		city.call("register_road_surface", item["area"], item["name"])
	for item2 in _segments:
		var seg_a: Vector3 = item2["from"]
		var seg_b: Vector3 = item2["to"]
		var road_kind: String = "arterial"
		if item2.has("kind"):
			road_kind = str(item2["kind"])
		city.call("register_road_segment", seg_a, seg_b, str(item2["name"]), road_kind)


func _spawn_blocks(root: Node3D) -> void:
	var groups: Dictionary = {}
	for spec in _blocks:
		var chunk: Vector2i = spec["chunk"]
		var tint: int = int(spec["tint"])
		var key := "%d|%d|%d" % [chunk.x, chunk.y, tint]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(spec)
	for key2 in groups.keys():
		var list: Array = groups[key2]
		if list.is_empty():
			continue
		var first: Dictionary = list[0]
		var chunk2: Vector2i = first["chunk"]
		var host: Node3D = _chunk_node(root, chunk2)
		var tint2: int = int(first["tint"])
		var many := MultiMesh.new()
		many.transform_format = MultiMesh.TRANSFORM_3D
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE
		many.mesh = cube
		many.instance_count = list.size()
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 1
		host.add_child(body)
		for n in list.size():
			var spec2: Dictionary = list[n]
			var pos: Vector3 = spec2["pos"]
			var size: Vector3 = spec2["size"]
			many.set_instance_transform(n, Transform3D(Basis.from_scale(size), pos))
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = size
			shape.shape = box
			shape.position = pos
			body.add_child(shape)
		var view := MultiMeshInstance3D.new()
		view.name = "Blocks%d" % tint2
		view.multimesh = many
		view.material_override = _wall_mats[tint2 % _wall_mats.size()]
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(view)


func _spawn_medians(root: Node3D) -> void:
	for spec in _medians:
		var chunk: Vector2i = spec["chunk"]
		var host: Node3D = _chunk_node(root, chunk)
		var mid: Vector3 = spec["mid"]
		var height: float = float(spec["height"])
		var length: float = float(spec["length"])
		var width: float = float(spec["width"])
		var angle: float = float(spec["angle"])
		var basis := Basis(_dir(angle), Vector3.UP, _right(angle))
		var pos := Vector3(mid.x, ROAD_Y + height * 0.5, mid.z)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 1
		body.transform = Transform3D(basis, pos)
		var shape := CollisionShape3D.new()
		var cube := BoxShape3D.new()
		cube.size = Vector3(length, height, width)
		shape.shape = cube
		body.add_child(shape)
		host.add_child(body)
	var visual: Dictionary = {}
	for tile in _median_tiles:
		var chunk2: Vector2i = tile["chunk"]
		var kind: String = str(tile["kind"])
		var key := "%d|%d|%s" % [chunk2.x, chunk2.y, kind]
		if not visual.has(key):
			visual[key] = []
		(visual[key] as Array).append(tile)
	for key2 in visual.keys():
		var list: Array = visual[key2]
		if list.is_empty():
			continue
		var bits: PackedStringArray = String(key2).split("|")
		var part: String = bits[2]
		if not _mesh.has(part):
			continue
		var chunk3 := Vector2i(int(bits[0]), int(bits[1]))
		var host2: Node3D = _chunk_node(root, chunk3)
		var many := MultiMesh.new()
		many.transform_format = MultiMesh.TRANSFORM_3D
		many.mesh = _mesh[part]
		many.instance_count = list.size()
		for n in list.size():
			var tile2: Dictionary = list[n]
			var at2: Vector3 = tile2["at"]
			var ang: float = float(tile2["angle"])
			var basis2 := Basis(_dir(ang), Vector3.UP, _right(ang))
			many.set_instance_transform(n, Transform3D(basis2, Vector3(at2.x, 0.0, at2.z)))
		var view := MultiMeshInstance3D.new()
		view.name = "Median_%s" % part
		view.multimesh = many
		view.material_override = _part_mat(part)
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host2.add_child(view)


func _spawn_decor(root: Node3D) -> void:
	var visual: Dictionary = {}
	for spec in _decors:
		var at: Vector3 = spec["at"]
		var chunk: Vector2i = _Layout.chunk_of(at.x, at.z)
		var kind: String = str(spec["kind"])
		var parts: PackedStringArray = _decor_parts(kind)
		for part in parts:
			var key := "%d|%d|%s" % [chunk.x, chunk.y, part]
			if not visual.has(key):
				visual[key] = []
			(visual[key] as Array).append(spec)
	for key2 in visual.keys():
		var list: Array = visual[key2]
		if list.is_empty():
			continue
		var bits: PackedStringArray = String(key2).split("|")
		var part2: String = bits[2]
		var mesh: Mesh = _part_mesh(part2)
		if mesh == null:
			continue
		var chunk2 := Vector2i(int(bits[0]), int(bits[1]))
		var host: Node3D = _chunk_node(root, chunk2)
		var many := MultiMesh.new()
		many.transform_format = MultiMesh.TRANSFORM_3D
		many.mesh = mesh
		many.instance_count = list.size()
		for n in list.size():
			var spec2: Dictionary = list[n]
			var at2: Vector3 = spec2["at"]
			var dir2: Vector3 = spec2["dir"]
			var kind2: String = str(spec2["kind"])
			var lift2: float = float(spec2["lift"])
			var y2: float = _lot_top_at(at2.x, at2.z)
			if spec2.has("base_y"):
				y2 = float(spec2["base_y"]) + lift2
			elif _box_decor(kind2):
				y2 += _decor_y(kind2, lift2)
			else:
				y2 += lift2
			var basis2 := Basis(dir2, Vector3.UP, _right_of(dir2))
			many.set_instance_transform(n, Transform3D(basis2, Vector3(at2.x, y2, at2.z)))
		var view := MultiMeshInstance3D.new()
		view.name = "Dress_%s" % part2
		view.multimesh = many
		view.material_override = _part_mat(part2)
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(view)
	_spawn_decor_hits(root)
	_spawn_lamp_lights(root)


func _spawn_decor_hits(root: Node3D) -> void:
	var groups: Dictionary = {}
	for spec in _decors:
		var at: Vector3 = spec["at"]
		var chunk: Vector2i = _Layout.chunk_of(at.x, at.z)
		var key := "%d|%d" % [chunk.x, chunk.y]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(spec)
	for key2 in groups.keys():
		var list: Array = groups[key2]
		if list.is_empty():
			continue
		var bits: PackedStringArray = String(key2).split("|")
		var host: Node3D = _chunk_node(root, Vector2i(int(bits[0]), int(bits[1])))
		var body := StaticBody3D.new()
		body.name = "DressHit"
		body.collision_layer = 1
		body.collision_mask = 1
		var used := 0
		for spec2 in list:
			var kind2: String = str(spec2["kind"])
			var hit: Vector3 = _decor_hit_size(kind2)
			if hit == Vector3.ZERO:
				continue
			var at2: Vector3 = spec2["at"]
			var dir2: Vector3 = spec2["dir"]
			var lift2: float = float(spec2["lift"])
			var ground_y: float = _lot_top_at(at2.x, at2.z)
			var center_y: float = ground_y + hit.y * 0.5
			if _box_decor(kind2):
				center_y = ground_y + _decor_y(kind2, lift2)
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = hit
			shape.shape = box
			var basis2 := Basis(dir2, Vector3.UP, _right_of(dir2))
			shape.transform = Transform3D(basis2, Vector3(at2.x, center_y, at2.z))
			body.add_child(shape)
			used += 1
		if used > 0:
			host.add_child(body)
		else:
			body.free()


func _decor_mesh(kind: String) -> BoxMesh:
	var box := BoxMesh.new()
	if kind == "lamp":
		box.size = Vector3(0.22, 3.8, 0.22)
	elif kind == "planter":
		box.size = Vector3(0.9, 0.42, 0.9)
	elif kind == "trunk":
		box.size = Vector3(0.28, 2.2, 0.28)
	else:
		box.size = Vector3(1.2, 1.05, 1.2)
	return box


func _decor_y(kind: String, lift: float) -> float:
	if kind == "lamp":
		return 1.9 + lift
	if kind == "planter":
		return 0.21 + lift
	if kind == "trunk":
		return 1.1 + lift
	return 2.725 + lift


func _decor_mat(kind: String) -> Material:
	if kind == "lamp":
		return _lamp_mat
	if kind == "trunk":
		return _trunk_mat
	if kind == "canopy":
		return _canopy_mat
	return _plant_mat


func _box_decor(kind: String) -> bool:
	return kind == "trunk" or kind == "canopy" or kind == "planter"


func _decor_parts(kind: String) -> PackedStringArray:
	if kind == "lamp":
		return PackedStringArray(["pole_industrial", "enclosure_industrial", "bulbs_industrial"])
	if kind == "signal_pole":
		return PackedStringArray(["pole_signal"])
	if kind == "signal_head_ew":
		return PackedStringArray(["enclosure_signal_head", "bulb_ew_red", "bulb_ew_yellow", "bulb_ew_green"])
	if kind == "signal_head_ns":
		return PackedStringArray(["enclosure_signal_head", "bulb_ns_red", "bulb_ns_yellow", "bulb_ns_green"])
	if kind == "signal":
		return PackedStringArray(["pole_signal", "enclosure_signal", "bulb_signal"])
	if kind == "stop":
		return PackedStringArray(["sign_post", "stop_sign"])
	if kind == "speed":
		return PackedStringArray(["sign_post", "speed_sign"])
	if kind == "barrier":
		return PackedStringArray(["barrier"])
	return PackedStringArray([kind])


func _part_mesh(part: String) -> Mesh:
	if _mesh.has(part):
		return _mesh[part]
	if _box_decor(part):
		return _decor_mesh(part)
	return null


func _part_mat(part: String) -> Material:
	if _part_mats.has(part):
		return _part_mats[part]
	return _decor_mat(part)


func _decor_hit_size(kind: String) -> Vector3:
	if kind == "signal_pole" and _mesh.has("pole_signal"):
		var pole_h: float = (_mesh["pole_signal"] as Mesh).get_aabb().size.y
		return Vector3(0.42, pole_h, 0.42)
	if kind.begins_with("signal_head"):
		return Vector3.ZERO
	if kind == "lamp" or kind == "signal":
		return Vector3(0.42, 2.0, 0.42)
	if kind == "stop" or kind == "speed":
		if _mesh.has("sign_post"):
			var post_h: float = (_mesh["sign_post"] as Mesh).get_aabb().size.y
			return Vector3(0.2, post_h, 0.2)
		return Vector3(0.2, 2.1, 0.2)
	if kind == "barrier" and _mesh.has("barrier"):
		return (_mesh["barrier"] as Mesh).get_aabb().size
	if _box_decor(kind):
		return (_decor_mesh(kind) as BoxMesh).size
	return Vector3.ZERO


func _audit_blocks() -> void:
	_clash = 0
	_clear_ok = true
	for spec in _blocks:
		var pos: Vector3 = spec["pos"]
		var size: Vector3 = spec["size"]
		var foot := Rect2(pos.x - size.x * 0.5, pos.z - size.z * 0.5, size.x, size.z)
		if _hits_road(foot):
			_clash += 1
		if _near_spawn(foot):
			_clear_ok = false


func _chunk_node(root: Node3D, chunk: Vector2i) -> Node3D:
	var node_name := "RoadChunk_%d_%d" % [chunk.x, chunk.y]
	return _child_node(root, node_name)


func _child_node(root: Node3D, node_name: String) -> Node3D:
	var found: Node = root.get_node_or_null(node_name)
	if found is Node3D:
		return found as Node3D
	var node := Node3D.new()
	node.name = node_name
	root.add_child(node)
	return node


func _pavement(host: Node3D) -> StaticBody3D:
	var found: Node = host.get_node_or_null("Pavement")
	if found is StaticBody3D:
		return found as StaticBody3D
	var body := StaticBody3D.new()
	body.name = "Pavement"
	body.position = Vector3(0.0, -0.25, 0.0)
	body.collision_layer = 1
	body.collision_mask = 1
	body.add_to_group("pavement")
	host.add_child(body)
	return body


func _walk_body(host: Node3D) -> StaticBody3D:
	var found: Node = host.get_node_or_null("Sidewalk")
	if found is StaticBody3D:
		return found as StaticBody3D
	var body := StaticBody3D.new()
	body.name = "Sidewalk"
	body.collision_layer = 1
	body.collision_mask = 1
	body.add_to_group("sidewalk")
	host.add_child(body)
	return body


func _material_for(kind: String) -> Material:
	if kind.begins_with("walk"):
		return _concrete_mat
	if kind.ends_with("yellow"):
		return _yellow_mat
	if kind.ends_with("white"):
		return _white_mat
	if kind == "straight_dirt":
		return _dirt_straight_mat
	if kind == "turn_dirt":
		return _dirt_turn_mat
	if kind == "cross_dirt":
		return _dirt_cross_mat
	if kind.ends_with("dirt"):
		return _gravel_mat
	return _asphalt_mat


func _publish_drive(city: Node3D) -> void:
	var raw: Array[Dictionary] = _split_side_joins(_drive_raw())
	var edges: Array = []
	var linked: Dictionary = {}
	for item in raw:
		var a: Vector3 = item["a"]
		var b: Vector3 = item["b"]
		var kind: String = str(item["kind"])
		var through: bool = bool(item.get("through", false))
		var length: float = Vector2(b.x - a.x, b.z - a.z).length()
		if length < 0.4:
			continue
		var forward: PackedVector3Array = _lane_line(a, b, through)
		var back: PackedVector3Array = _lane_line(b, a, through)
		if forward.size() < 2 or back.size() < 2:
			continue
		edges.append({
			"ax": a.x,
			"az": a.z,
			"bx": b.x,
			"bz": b.z,
			"kind": kind,
			"length": length,
			"through": through,
			"forward": forward,
			"back": back,
		})
		linked[_link_key(a, b)] = true
		linked[_link_key(b, a)] = true
	_add_mouth_links(edges, linked)
	city.set_meta("road_drive_edges", edges)
	city.set_meta("road_controls", _controls.duplicate(true))
	city.set_meta("road_half_m", HALF)


func _drive_raw() -> Array[Dictionary]:
	var raw: Array[Dictionary] = []
	for seg in _segments:
		var a: Vector3 = seg["from"]
		var b: Vector3 = seg["to"]
		if seg.has("drive_from"):
			a = seg["drive_from"]
			b = seg["drive_to"]
		var kind := "street"
		if seg.has("kind") and str(seg["kind"]) != "":
			kind = str(seg["kind"])
		var span: float = Vector2(b.x - a.x, b.z - a.z).length()
		if span < 1.0:
			continue
		raw.append({"a": a, "b": b, "kind": kind, "through": false})
	return raw


func _split_side_joins(raw: Array[Dictionary]) -> Array[Dictionary]:
	var cuts: Array = []
	cuts.resize(raw.size())
	for i in raw.size():
		cuts[i] = []
	var links: Array[Dictionary] = []
	for i in raw.size():
		var item: Dictionary = raw[i]
		var a: Vector3 = item["a"]
		var b: Vector3 = item["b"]
		_seek_join(raw, cuts, links, i, a)
		_seek_join(raw, cuts, links, i, b)
	var out: Array[Dictionary] = []
	for i2 in raw.size():
		_slice_segment(out, raw[i2], cuts[i2])
	for link in links:
		out.append(link)
	return out


func _seek_join(raw: Array[Dictionary], cuts: Array, links: Array[Dictionary], self_i: int, end_point: Vector3) -> void:
	var best_j := -1
	var best_t := 0.0
	var best_d := 7.2
	var best_q := Vector3.ZERO
	for j in raw.size():
		if j == self_i:
			continue
		var other: Dictionary = raw[j]
		var a: Vector3 = other["a"]
		var b: Vector3 = other["b"]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var span: float = ab.length()
		if span < 4.0:
			continue
		var rel := Vector2(end_point.x - a.x, end_point.z - a.z)
		var t: float = clampf(rel.dot(ab) / (span * span), 0.0, 1.0)
		if t < 0.03 or t > 0.97:
			continue
		var q := Vector3(a.x + ab.x * t, 0.0, a.z + ab.y * t)
		var gap: float = Vector2(end_point.x - q.x, end_point.z - q.z).length()
		if gap < 2.2 or gap >= best_d:
			continue
		var join := Vector3(end_point.x - q.x, 0.0, end_point.z - q.z) / gap
		var road := Vector3(ab.x / span, 0.0, ab.y / span)
		if absf(join.dot(road)) > 0.45:
			continue
		best_d = gap
		best_j = j
		best_t = t
		best_q = q
	if best_j < 0:
		return
	var host: Dictionary = raw[best_j]
	var host_a: Vector3 = host["a"]
	var host_b: Vector3 = host["b"]
	var host_span: float = Vector2(host_b.x - host_a.x, host_b.z - host_a.z).length()
	# A cut this close to an existing mouth leaves a stub shorter than a published edge and splits the road.
	if minf(best_t, 1.0 - best_t) * host_span < 0.85:
		var snap: Vector3 = host_a if best_t <= 0.5 else host_b
		links.append({"a": end_point, "b": snap, "kind": "join", "through": true})
		return
	var bucket: Array = cuts[best_j]
	bucket.append(best_t)
	links.append({"a": end_point, "b": best_q, "kind": "join", "through": true})


func _slice_segment(out: Array[Dictionary], piece: Dictionary, marks: Array) -> void:
	var a: Vector3 = piece["a"]
	var b: Vector3 = piece["b"]
	var kind: String = str(piece["kind"])
	var through: bool = bool(piece.get("through", false))
	var ordered: Array[float] = [0.0, 1.0]
	for raw_t in marks:
		var t: float = float(raw_t)
		var kept := true
		for have in ordered:
			if absf(have - t) < 0.015:
				kept = false
				break
		if kept:
			ordered.append(t)
	ordered.sort()
	for n in range(ordered.size() - 1):
		var t0: float = ordered[n]
		var t1: float = ordered[n + 1]
		if t1 - t0 < 0.012:
			continue
		out.append({
			"a": a.lerp(b, t0),
			"b": a.lerp(b, t1),
			"kind": kind,
			"through": through,
		})


func _lane_line(a: Vector3, b: Vector3, through: bool) -> PackedVector3Array:
	var delta := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length: float = delta.length()
	var pts := PackedVector3Array()
	if length < 0.4:
		return pts
	var dir: Vector3 = delta / length
	var right: Vector3 = _right_of(dir)
	var inset: float = minf(0.35, length * 0.15) if through else minf(2.4, length * 0.22)
	var start: float = inset
	var finish: float = length - inset
	if finish - start < 1.2:
		start = 0.0
		finish = length
	var cursor: float = start
	while cursor < finish - 0.15:
		pts.append(_lane_point(a, dir, right, cursor, through))
		cursor += 8.0
	pts.append(_lane_point(a, dir, right, finish, through))
	return pts


func _lane_point(a: Vector3, dir: Vector3, right: Vector3, dist: float, through: bool) -> Vector3:
	var center := a + dir * dist
	var off: float = 0.45 if through else _drive_offset(center, dir)
	var point := center + right * off
	point.y = 0.0
	return _seat_lane(point, center)


func _drive_offset(point: Vector3, travel: Vector3) -> float:
	var travel_n := travel
	if travel_n.length_squared() > 0.01:
		travel_n = travel_n.normalized()
	for span in _split_spans:
		var origin: Vector3 = span["origin"]
		var axis: Vector3 = span["dir"]
		var span_len: float = float(span["length"])
		var run_tiles: int = int(span["run_tiles"])
		var rel := point - origin
		rel.y = 0.0
		var along: float = rel.dot(axis)
		if along < -0.8 or along > span_len + 0.8:
			continue
		if (rel - axis * along).length() > 3.0:
			continue
		var align: float = travel_n.dot(axis)
		var dist: float = along
		if align < -0.5:
			dist = span_len - along
		elif align < 0.5:
			continue
		dist = clampf(dist, 0.0, span_len)
		return _lane_off(dist, true, run_tiles)
	return LANE


func _seat_lane(point: Vector3, center: Vector3) -> Vector3:
	if _covered(point.x, point.z):
		return point
	var toward := center - point
	toward.y = 0.0
	var span: float = toward.length()
	if span < 0.05:
		return point
	var step: Vector3 = toward / span
	var walked: float = 0.2
	while walked < span:
		var at: Vector3 = point + step * walked
		if _covered(at.x, at.z):
			at.y = 0.0
			return at
		walked += 0.2
	center.y = 0.0
	return center


func _covered(x: float, z: float) -> bool:
	var spot := Vector2(x, z)
	for item in _rects_pending:
		var area: Rect2 = item["area"]
		if area.has_point(spot):
			return true
	return false


func _add_mouth_links(edges: Array, linked: Dictionary) -> void:
	var unique: Array[Vector3] = []
	for raw in edges:
		var edge: Dictionary = raw
		_keep_point(unique, Vector3(float(edge["ax"]), 0.0, float(edge["az"])))
		_keep_point(unique, Vector3(float(edge["bx"]), 0.0, float(edge["bz"])))
	for i in unique.size():
		for j in range(i + 1, unique.size()):
			var a: Vector3 = unique[i]
			var b: Vector3 = unique[j]
			var gap: float = Vector2(a.x - b.x, a.z - b.z).length()
			if gap < 0.3 or gap > 9.2:
				continue
			if linked.has(_link_key(a, b)):
				continue
			var mid := (a + b) * 0.5
			if not _covered(mid.x, mid.z):
				continue
			var forward: PackedVector3Array = _lane_line(a, b, true)
			var back: PackedVector3Array = _lane_line(b, a, true)
			if forward.size() < 2 or back.size() < 2:
				continue
			edges.append({
				"ax": a.x,
				"az": a.z,
				"bx": b.x,
				"bz": b.z,
				"kind": "join",
				"length": gap,
				"through": true,
				"forward": forward,
				"back": back,
			})
			linked[_link_key(a, b)] = true
			linked[_link_key(b, a)] = true


func _keep_point(unique: Array[Vector3], point: Vector3) -> void:
	for have in unique:
		if have.distance_to(point) < 0.25:
			return
	unique.append(point)


func _link_key(a: Vector3, b: Vector3) -> String:
	return "%d|%d|%d|%d" % [int(round(a.x * 4.0)), int(round(a.z * 4.0)), int(round(b.x * 4.0)), int(round(b.z * 4.0))]


func _register_route(city: Node3D) -> void:
	if _tour.size() < 2:
		return
	city.call("register_road_route", _tour)
	var back: PackedVector3Array = _tour_back
	if back.size() < 2:
		back = _tour
	city.set_meta("road_lane_routes", [_tour, back])
	var right_opts: Array = [_tour]
	var left_opts: Array = [back]
	if _tour_alt.size() >= 8:
		right_opts.append(_tour_alt)
	if _tour_alt_back.size() >= 8:
		left_opts.append(_tour_alt_back)
	city.set_meta("road_lane_route_options", [right_opts, left_opts])


func _make_materials() -> void:
	_asphalt_mat = StandardMaterial3D.new()
	_asphalt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_asphalt_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_asphalt_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var tex: Texture2D = load("res://materials/asphalt_02/textures/asphalt_02_diff_2k.jpg") as Texture2D
	if tex != null:
		_asphalt_mat.albedo_texture = tex
		_asphalt_mat.albedo_color = Color(1.0, 1.0, 1.0)
	else:
		_asphalt_mat.albedo_color = Color(0.15, 0.16, 0.17)
	_asphalt_mat.roughness = 0.96
	_gravel_mat = StandardMaterial3D.new()
	_gravel_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_gravel_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_gravel_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var gravel: Texture2D = load("res://materials/gravel_road/textures/gravel_road_diff_2k.jpg") as Texture2D
	var gravel_n: Texture2D = load("res://materials/gravel_road/textures/gravel_road_nor_gl_2k.png") as Texture2D
	var gravel_r: Texture2D = load("res://materials/gravel_road/textures/gravel_road_rough_2k.png") as Texture2D
	if gravel == null:
		push_error("Gravel road color map failed to load.")
		_gravel_mat.albedo_color = Color(0.45, 0.40, 0.34)
	else:
		_gravel_mat.albedo_texture = gravel
		_gravel_mat.albedo_color = Color(1.0, 1.0, 1.0)
	if gravel_n != null:
		_gravel_mat.normal_enabled = true
		_gravel_mat.normal_texture = gravel_n
	if gravel_r != null:
		_gravel_mat.roughness_texture = gravel_r
		_gravel_mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		_gravel_mat.roughness = 1.0
	else:
		_gravel_mat.roughness = 0.96
	var rocky: Texture2D = load("res://materials/rocky_terrain_02/textures/rocky_terrain_02_diff_2k.jpg") as Texture2D
	var rocky_n: Texture2D = load("res://materials/rocky_terrain_02/textures/rocky_terrain_02_nor_gl_2k.png") as Texture2D
	var rocky_r: Texture2D = load("res://materials/rocky_terrain_02/textures/rocky_terrain_02_rough_2k.png") as Texture2D
	_make_dirt_materials(gravel, gravel_n, gravel_r, rocky, rocky_n, rocky_r)
	_ground_mat = _ground_cover(rocky, rocky_n, rocky_r)
	_concrete_mat = StandardMaterial3D.new()
	_concrete_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_concrete_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_concrete_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var concrete: Texture2D = load("res://materials/gravel_concrete_02/textures/gravel_concrete_03_diff_2k.jpg") as Texture2D
	var concrete_n: Texture2D = load("res://materials/gravel_concrete_02/textures/gravel_concrete_03_nor_gl_2k.png") as Texture2D
	var concrete_r: Texture2D = load("res://materials/gravel_concrete_02/textures/gravel_concrete_03_rough_2k.png") as Texture2D
	if concrete == null:
		push_error("Concrete color map failed to load.")
		_concrete_mat.albedo_color = Color(0.62, 0.60, 0.56)
	else:
		_concrete_mat.albedo_texture = concrete
		_concrete_mat.albedo_color = Color(1.0, 1.0, 1.0)
	if concrete_n != null:
		_concrete_mat.normal_enabled = true
		_concrete_mat.normal_texture = concrete_n
	if concrete_r != null:
		_concrete_mat.roughness_texture = concrete_r
		_concrete_mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		_concrete_mat.roughness = 1.0
	else:
		_concrete_mat.roughness = 0.9
	_yellow_mat = StandardMaterial3D.new()
	_yellow_mat.albedo_color = Color(0.93, 0.78, 0.12)
	_yellow_mat.roughness = 0.55
	_yellow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_white_mat = StandardMaterial3D.new()
	_white_mat.albedo_color = Color(0.94, 0.94, 0.92)
	_white_mat.roughness = 0.5
	_white_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_curb_mat = StandardMaterial3D.new()
	_curb_mat.albedo_color = Color(0.62, 0.60, 0.56)
	_curb_mat.roughness = 0.9
	_plant_mat = StandardMaterial3D.new()
	_plant_mat.albedo_color = Color(0.34, 0.40, 0.28)
	_plant_mat.roughness = 0.9
	_trunk_mat = StandardMaterial3D.new()
	_trunk_mat.albedo_color = Color(0.34, 0.24, 0.16)
	_trunk_mat.roughness = 0.86
	_canopy_mat = StandardMaterial3D.new()
	_canopy_mat.albedo_color = Color(0.24, 0.40, 0.20)
	_canopy_mat.roughness = 0.9
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(0.72, 0.68, 0.52)
	_lamp_mat.roughness = 0.55
	_wall_mats.clear()
	var colors: Array[Color] = [
		Color(0.62, 0.64, 0.66),
		Color(0.52, 0.32, 0.26),
		Color(0.74, 0.68, 0.56),
		Color(0.38, 0.46, 0.52),
		Color(0.48, 0.50, 0.52),
		Color(0.70, 0.55, 0.42),
	]
	for color in colors:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.86
		_wall_mats.append(mat)
	_make_decor_materials()


func _ground_cover(rocky: Texture2D, rocky_n: Texture2D, rocky_r: Texture2D) -> Material:
	var shader: Shader = load("res://shaders/ground_cover.gdshader") as Shader
	if shader == null:
		var plain := StandardMaterial3D.new()
		plain.albedo_color = Color(0.76, 0.88, 0.67)
		plain.roughness = 1.0
		plain.albedo_texture = rocky
		return plain
	var cover := ShaderMaterial.new()
	cover.shader = shader
	if rocky != null:
		cover.set_shader_parameter("alb", rocky)
	if rocky_n != null:
		cover.set_shader_parameter("nrm", rocky_n)
	if rocky_r != null:
		cover.set_shader_parameter("rgh", rocky_r)
	cover.set_shader_parameter("tint", Color(0.76, 0.88, 0.67))
	cover.set_shader_parameter("uv_scale", 0.22)
	return cover


func _load_modules() -> bool:
	var straight: bool = _take_glb("res://Models/road_modules/straight_tile.glb", "straight")
	var cross: bool = _take_glb("res://Models/road_modules/intersection.glb", "cross")
	_take_glb("res://Models/road_modules/turn_right.glb", "turn")
	if straight and cross:
		_used_glb = true
	else:
		_mesh.clear()
		_build_stl_modules()
		_used_glb = false
	_build_dirt_modules()
	_build_edge_marks()
	_build_lane_meshes()
	_build_split_meshes()
	_build_walks()
	_build_decor_meshes()
	if not _dirt_ready():
		push_error("Gravel streets still have a stripe channel.")
	return _mesh.has("straight_asphalt") and _mesh.has("cross_asphalt") and _mesh.has("turn_asphalt") and _mesh.has("lane_asphalt") and _mesh.has("split_asphalt") and _mesh.has("straight_white_pos") and _mesh.has("straight_white_neg") and _mesh.has("cross_white_0") and _mesh.has("walk_straight") and _mesh.has("walk_straight_neg") and _mesh.has("walk_turn") and _mesh.has("walk_flare") and _dirt_ready()


func _take_glb(path: String, prefix: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return false
	var inst: Node = packed.instantiate()
	var asphalt: Mesh = _node_mesh(inst, "Asphalt")
	if asphalt == null:
		inst.free()
		return false
	_mesh[prefix + "_asphalt"] = asphalt
	var yellow: Mesh = _node_mesh(inst, "MarkingYellow")
	if yellow != null:
		_mesh[prefix + "_yellow"] = yellow
	var white: Mesh = _node_mesh(inst, "MarkingWhite")
	if white != null:
		_mesh[prefix + "_white"] = white
	inst.free()
	return true


func _node_mesh(root: Node, node_name: String) -> Mesh:
	if root is MeshInstance3D and root.name == node_name:
		return (root as MeshInstance3D).mesh
	var found: Array = root.find_children(node_name, "MeshInstance3D", true, false)
	if found.is_empty():
		return null
	var inst: MeshInstance3D = found[0] as MeshInstance3D
	return inst.mesh


func _build_lane_meshes() -> void:
	var slab: PackedVector3Array = _read_tris(STL_DIR + "single_lane_slab.stl")
	var stripe: PackedVector3Array = _read_tris(STL_DIR + "single_lane_stripe.stl")
	var asphalt: PackedVector3Array = PackedVector3Array()
	var asphalt_uv: PackedVector2Array = PackedVector2Array()
	_map_into(asphalt, asphalt_uv, slab, STRAIGHT_X0, STRAIGHT_Y0, false, 0.0, ROAD_Y)
	_mesh["lane_asphalt"] = _pack_mesh(asphalt, asphalt_uv)
	var white: PackedVector3Array = PackedVector3Array()
	var white_uv: PackedVector2Array = PackedVector2Array()
	_map_into(white, white_uv, stripe, STRAIGHT_X0, STRAIGHT_Y0, false, 0.0, MARK_Y)
	_map_into(white, white_uv, stripe, STRAIGHT_X0, STRAIGHT_Y0, true, 0.0, MARK_Y)
	_mesh["lane_white"] = _pack_mesh(white, white_uv)


func _build_split_meshes() -> void:
	var slab: PackedVector3Array = _read_tris(STL_DIR + "road_expand_reduce_direction_1_slab_no_stretch.stl")
	var inside: PackedVector3Array = _read_tris(STL_DIR + "road_expand_reduce_direction_1_inside_stripe_no_stretch.stl")
	var outside: PackedVector3Array = _read_tris(STL_DIR + "road_expand_reduce_direction_1_outside_stripe_no_stretch.stl")
	var asphalt: PackedVector3Array = PackedVector3Array()
	var asphalt_uv: PackedVector2Array = PackedVector2Array()
	_map_split(asphalt, asphalt_uv, slab, ROAD_Y)
	_mesh["split_asphalt"] = _pack_mesh(asphalt, asphalt_uv)
	var yellow: PackedVector3Array = PackedVector3Array()
	var yellow_uv: PackedVector2Array = PackedVector2Array()
	_map_split(yellow, yellow_uv, inside, MARK_Y)
	_mesh["split_yellow"] = _pack_mesh(yellow, yellow_uv)
	var white: PackedVector3Array = PackedVector3Array()
	var white_uv: PackedVector2Array = PackedVector2Array()
	_map_split(white, white_uv, outside, MARK_Y)
	_mesh["split_white"] = _pack_mesh(white, white_uv)
	_build_split_profile()


func _build_split_profile() -> void:
	_split_profile = PackedVector2Array()
	if not _mesh.has("split_asphalt"):
		return
	var mesh: Mesh = _mesh["split_asphalt"]
	var faces: PackedVector3Array = mesh.get_faces()
	var box: AABB = mesh.get_aabb()
	var bins := 36
	var x0: float = box.position.x
	var span: float = maxf(box.size.x, 0.01)
	var max_z: Array[float] = []
	for _n in bins:
		max_z.append(0.0)
	var i := 0
	while i + 2 < faces.size():
		for k in 3:
			var v: Vector3 = faces[i + k]
			var bin: int = int((v.x - x0) / span * float(bins))
			if bin < 0:
				bin = 0
			if bin >= bins:
				bin = bins - 1
			if v.z > max_z[bin]:
				max_z[bin] = v.z
		i += 3
	var filled: Array[float] = []
	var last_known: float = HALF
	for n in bins:
		if max_z[n] > 0.05:
			last_known = max_z[n]
			filled.append(max_z[n])
		else:
			filled.append(last_known)
	var next_known: float = filled[bins - 1]
	for n in range(bins - 1, -1, -1):
		if max_z[n] > 0.05:
			next_known = max_z[n]
		elif next_known > filled[n]:
			filled[n] = next_known
	for n in bins:
		var wide: float = filled[n]
		if n + 1 < bins:
			wide = maxf(wide, filled[n + 1])
		var forward: float = x0 + float(n) * span / float(bins)
		_split_profile.append(Vector2(forward, wide))


func _profile_outer(forward_m: float) -> float:
	if _split_profile.is_empty():
		return _taper_outer(forward_m / UNIT) * UNIT
	if forward_m <= _split_profile[0].x:
		return _split_profile[0].y
	var last: int = _split_profile.size() - 1
	for i in last:
		var a: Vector2 = _split_profile[i]
		var b: Vector2 = _split_profile[i + 1]
		if forward_m >= b.x:
			continue
		return a.y
	return _split_profile[last].y


func _map_split(dest: PackedVector3Array, uvs: PackedVector2Array, src: PackedVector3Array, height: float) -> void:
	var i: int = 0
	while i + 2 < src.size():
		for n in 3:
			var src_v: Vector3 = src[i + n]
			var forward: float = (SPLIT_Y0 - src_v.y) * UNIT
			var lateral: float = (SPLIT_X0 - src_v.x) * UNIT
			dest.append(Vector3(forward, height, lateral))
			uvs.append(Vector2(forward / TILE, lateral / TILE))
		i += 3


func _dirt_ready() -> bool:
	if not _mesh.has("straight_dirt") or not _mesh.has("cross_dirt") or not _mesh.has("turn_dirt"):
		return false
	var straight: Mesh = _mesh["straight_dirt"]
	var cross: Mesh = _mesh["cross_dirt"]
	var straight_size: Vector3 = straight.get_aabb().size
	var cross_size: Vector3 = cross.get_aabb().size
	if straight_size.z < CROSS * 0.95 or cross_size.x < CROSS * 0.95 or cross_size.z < CROSS * 0.95:
		return false
	var mid_x: float = TILE * 0.5
	if not _covers(straight, mid_x, 0.0):
		return false
	if not _covers(straight, mid_x, 80.0 * UNIT):
		return false
	if not _covers(straight, mid_x, -80.0 * UNIT):
		return false
	if not _covers(cross, 0.2, -4.05):
		return false
	return true


func _covers(mesh: Mesh, x: float, z: float) -> bool:
	var faces: PackedVector3Array = mesh.get_faces()
	var i: int = 0
	while i + 2 < faces.size():
		if _in_tri(x, z, faces[i], faces[i + 1], faces[i + 2]):
			return true
		i += 3
	return false


func _in_tri(x: float, z: float, a: Vector3, b: Vector3, c: Vector3) -> bool:
	var den: float = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
	if absf(den) < 0.0000001:
		return false
	var u: float = ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / den
	var v: float = ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / den
	var w: float = 1.0 - u - v
	return u >= -0.001 and v >= -0.001 and w >= -0.001


func _build_dirt_modules() -> void:
	var slab: PackedVector3Array = _read_tris(STL_DIR + "single_lane_slab.stl")
	var stripe: PackedVector3Array = _read_tris(STL_DIR + "single_lane_stripe.stl")
	var straight: PackedVector3Array = PackedVector3Array()
	var straight_uv: PackedVector2Array = PackedVector2Array()
	_map_into(straight, straight_uv, slab, STRAIGHT_X0, STRAIGHT_Y0, false, 40.0, ROAD_Y)
	_map_into(straight, straight_uv, slab, STRAIGHT_X0, STRAIGHT_Y0, false, -40.0, ROAD_Y)
	_map_into(straight, straight_uv, stripe, STRAIGHT_X0, STRAIGHT_Y0, false, -40.0, ROAD_Y)
	_map_into(straight, straight_uv, stripe, STRAIGHT_X0, STRAIGHT_Y0, false, 40.0, ROAD_Y)
	_map_into(straight, straight_uv, stripe, STRAIGHT_X0, STRAIGHT_Y0, true, -40.0, ROAD_Y)
	_mesh["straight_dirt"] = _pack_dirt(straight, straight_uv)
	var inside_slab: PackedVector3Array = _read_tris(STL_DIR + "turn_90_inside_lane_slab_no_stretch.stl")
	var outside_slab: PackedVector3Array = _read_tris(STL_DIR + "turn_90_outside_lane_slab_no_stretch.stl")
	var inside_mark: PackedVector3Array = _read_tris(STL_DIR + "turn_90_inside_stripe_no_stretch.stl")
	var center_mark: PackedVector3Array = _read_tris(STL_DIR + "turn_90_outside_stripe_no_stretch.stl")
	var edge_mark: PackedVector3Array = _read_tris(STL_DIR + "turn_90_outside_lane_outside_stripe_no_stretch.stl")
	var turn: PackedVector3Array = PackedVector3Array()
	var turn_uv: PackedVector2Array = PackedVector2Array()
	_map_into(turn, turn_uv, inside_slab, INSIDE_X0, INSIDE_Y0, false, 40.0, ROAD_Y)
	_map_into(turn, turn_uv, outside_slab, OUTSIDE_X0, OUTSIDE_Y0, true, -40.0, ROAD_Y)
	_map_into(turn, turn_uv, center_mark, INSIDE_X0, INSIDE_Y0, false, 40.0, ROAD_Y)
	_map_into(turn, turn_uv, inside_mark, INSIDE_X0, INSIDE_Y0, false, 40.0, ROAD_Y)
	_map_into(turn, turn_uv, edge_mark, OUTSIDE_X0, OUTSIDE_Y0, true, -40.0, ROAD_Y)
	_mesh["turn_dirt"] = _pack_dirt(turn, turn_uv)
	var cross_slab: PackedVector3Array = _read_tris(STL_DIR + "4_way_bi_lane_intersection_slab_no_stretch.stl")
	var corner: PackedVector3Array = _read_tris(STL_DIR + "4_way_bi_lane_intersection_corner_stripe_square_no_stretch.stl")
	var cross: PackedVector3Array = PackedVector3Array()
	var cross_uv: PackedVector2Array = PackedVector2Array()
	_map_into(cross, cross_uv, cross_slab, CROSS_X0, CROSS_Y0, false, 0.0, ROAD_Y)
	_lay_corners(cross, cross_uv, corner, ROAD_Y)
	_mesh["cross_dirt"] = _pack_dirt(cross, cross_uv)


func _build_edge_marks() -> void:
	var stripe: PackedVector3Array = _read_tris(STL_DIR + "single_lane_stripe.stl")
	var pos: PackedVector3Array = PackedVector3Array()
	var pos_uv: PackedVector2Array = PackedVector2Array()
	_map_into(pos, pos_uv, stripe, STRAIGHT_X0, STRAIGHT_Y0, false, 40.0, MARK_Y)
	_mesh["straight_white_pos"] = _pack_mesh(pos, pos_uv)
	var neg: PackedVector3Array = PackedVector3Array()
	var neg_uv: PackedVector2Array = PackedVector2Array()
	_map_into(neg, neg_uv, stripe, STRAIGHT_X0, STRAIGHT_Y0, true, -40.0, MARK_Y)
	_mesh["straight_white_neg"] = _pack_mesh(neg, neg_uv)
	var corner: PackedVector3Array = _read_tris(STL_DIR + "4_way_bi_lane_intersection_corner_stripe_square_no_stretch.stl")
	for quarter in 4:
		var marks: PackedVector3Array = PackedVector3Array()
		var mark_uv: PackedVector2Array = PackedVector2Array()
		_lay_one_corner(marks, mark_uv, corner, MARK_Y, quarter)
		_mesh["cross_white_%d" % quarter] = _pack_mesh(marks, mark_uv)


func _lay_corners(dest: PackedVector3Array, uvs: PackedVector2Array, corner: PackedVector3Array, height: float) -> void:
	for quarter in 4:
		_lay_one_corner(dest, uvs, corner, height, quarter)


func _lay_one_corner(dest: PackedVector3Array, uvs: PackedVector2Array, corner: PackedVector3Array, height: float, quarter: int) -> void:
	var i: int = 0
	while i + 2 < corner.size():
		for v in 3:
			var src: Vector3 = corner[i + v]
			var spun: Vector2 = _spin(src.x - CROSS_X0, src.y - CROSS_Y0, quarter)
			var point := Vector3(spun.x * UNIT, height, spun.y * UNIT)
			dest.append(point)
			uvs.append(Vector2(point.x / TILE, point.z / TILE))
		i += 3


func _build_stl_modules() -> void:
	var slab: PackedVector3Array = _read_tris(STL_DIR + "single_lane_slab.stl")
	var stripe: PackedVector3Array = _read_tris(STL_DIR + "single_lane_stripe.stl")
	var asphalt: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	_map_into(asphalt, uvs, slab, STRAIGHT_X0, STRAIGHT_Y0, false, 40.0, ROAD_Y)
	_map_into(asphalt, uvs, slab, STRAIGHT_X0, STRAIGHT_Y0, false, -40.0, ROAD_Y)
	_mesh["straight_asphalt"] = _pack_mesh(asphalt, uvs)
	var yellow: PackedVector3Array = PackedVector3Array()
	var yellow_uv: PackedVector2Array = PackedVector2Array()
	_map_into(yellow, yellow_uv, stripe, STRAIGHT_X0, STRAIGHT_Y0, false, -40.0, MARK_Y)
	_mesh["straight_yellow"] = _pack_mesh(yellow, yellow_uv)
	var white: PackedVector3Array = PackedVector3Array()
	var white_uv: PackedVector2Array = PackedVector2Array()
	_map_into(white, white_uv, stripe, STRAIGHT_X0, STRAIGHT_Y0, false, 40.0, MARK_Y)
	_map_into(white, white_uv, stripe, STRAIGHT_X0, STRAIGHT_Y0, true, -40.0, MARK_Y)
	_mesh["straight_white"] = _pack_mesh(white, white_uv)

	var inside_slab: PackedVector3Array = _read_tris(STL_DIR + "turn_90_inside_lane_slab_no_stretch.stl")
	var outside_slab: PackedVector3Array = _read_tris(STL_DIR + "turn_90_outside_lane_slab_no_stretch.stl")
	var inside_mark: PackedVector3Array = _read_tris(STL_DIR + "turn_90_inside_stripe_no_stretch.stl")
	var center_mark: PackedVector3Array = _read_tris(STL_DIR + "turn_90_outside_stripe_no_stretch.stl")
	var edge_mark: PackedVector3Array = _read_tris(STL_DIR + "turn_90_outside_lane_outside_stripe_no_stretch.stl")
	var turn_asphalt: PackedVector3Array = PackedVector3Array()
	var turn_uv: PackedVector2Array = PackedVector2Array()
	_map_into(turn_asphalt, turn_uv, inside_slab, INSIDE_X0, INSIDE_Y0, false, 40.0, ROAD_Y)
	_map_into(turn_asphalt, turn_uv, outside_slab, OUTSIDE_X0, OUTSIDE_Y0, true, -40.0, ROAD_Y)
	_mesh["turn_asphalt"] = _pack_mesh(turn_asphalt, turn_uv)
	var turn_yellow: PackedVector3Array = PackedVector3Array()
	var turn_yellow_uv: PackedVector2Array = PackedVector2Array()
	_map_into(turn_yellow, turn_yellow_uv, center_mark, INSIDE_X0, INSIDE_Y0, false, 40.0, MARK_Y)
	_mesh["turn_yellow"] = _pack_mesh(turn_yellow, turn_yellow_uv)
	var turn_white: PackedVector3Array = PackedVector3Array()
	var turn_white_uv: PackedVector2Array = PackedVector2Array()
	_map_into(turn_white, turn_white_uv, inside_mark, INSIDE_X0, INSIDE_Y0, false, 40.0, MARK_Y)
	_map_into(turn_white, turn_white_uv, edge_mark, OUTSIDE_X0, OUTSIDE_Y0, true, -40.0, MARK_Y)
	_mesh["turn_white"] = _pack_mesh(turn_white, turn_white_uv)

	var cross_slab: PackedVector3Array = _read_tris(STL_DIR + "4_way_bi_lane_intersection_slab_no_stretch.stl")
	var cross_asphalt: PackedVector3Array = PackedVector3Array()
	var cross_uv: PackedVector2Array = PackedVector2Array()
	_map_into(cross_asphalt, cross_uv, cross_slab, CROSS_X0, CROSS_Y0, false, 0.0, ROAD_Y)
	_mesh["cross_asphalt"] = _pack_mesh(cross_asphalt, cross_uv)
	var corner: PackedVector3Array = _read_tris(STL_DIR + "4_way_bi_lane_intersection_corner_stripe_square_no_stretch.stl")
	var marks: PackedVector3Array = PackedVector3Array()
	var mark_uv: PackedVector2Array = PackedVector2Array()
	for quarter in 4:
		var i: int = 0
		while i + 2 < corner.size():
			for v in 3:
				var src: Vector3 = corner[i + v]
				var spun: Vector2 = _spin(src.x - CROSS_X0, src.y - CROSS_Y0, quarter)
				var point := Vector3(spun.x * UNIT, MARK_Y, spun.y * UNIT)
				marks.append(point)
				mark_uv.append(Vector2(point.x / TILE, point.z / TILE))
			i += 3
	_mesh["cross_white"] = _pack_mesh(marks, mark_uv)


func _spin(x: float, z: float, quarter: int) -> Vector2:
	var dx: float = x - 84.0
	var dz: float = z
	for _step in quarter:
		var turned: float = -dz
		dz = dx
		dx = turned
	return Vector2(dx + 84.0, dz)


func _map_into(dest: PackedVector3Array, uvs: PackedVector2Array, src: PackedVector3Array, anchor_x: float, anchor_y: float, mirror: bool, lateral: float, height: float, forward: float = 0.0) -> void:
	var i: int = 0
	while i + 2 < src.size():
		var order: Array[int] = [0, 1, 2]
		if mirror:
			order = [0, 2, 1]
		for n in order:
			var src_v: Vector3 = src[i + n]
			var dx: float = (src_v.x - anchor_x) * UNIT + forward * UNIT
			var dy: float = (src_v.y - anchor_y) * UNIT
			if mirror:
				dy = -dy
			var lz: float = dy + lateral * UNIT
			dest.append(Vector3(dx, height, lz))
			uvs.append(Vector2(dx / TILE, lz / TILE))
		i += 3


func _make_dirt_materials(gravel: Texture2D, gravel_n: Texture2D, gravel_r: Texture2D, rocky: Texture2D, rocky_n: Texture2D, rocky_r: Texture2D) -> void:
	var shader: Shader = load("res://shaders/dirt_shoulder.gdshader") as Shader
	if shader == null or gravel == null or gravel_n == null or gravel_r == null or rocky == null or rocky_n == null or rocky_r == null:
		push_error("Dirt shoulder blend failed to load. Gravel stays a flat map.")
		_dirt_straight_mat = _gravel_mat
		_dirt_turn_mat = _gravel_mat
		_dirt_cross_mat = _gravel_mat
		return
	_dirt_straight_mat = _dirt_mat(shader, 0.0, gravel, gravel_n, gravel_r, rocky, rocky_n, rocky_r)
	_dirt_turn_mat = _dirt_mat(shader, 1.0, gravel, gravel_n, gravel_r, rocky, rocky_n, rocky_r)
	_dirt_cross_mat = _dirt_mat(shader, 2.0, gravel, gravel_n, gravel_r, rocky, rocky_n, rocky_r)


func _dirt_mat(shader: Shader, shape: float, gravel: Texture2D, gravel_n: Texture2D, gravel_r: Texture2D, rocky: Texture2D, rocky_n: Texture2D, rocky_r: Texture2D) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("shape", shape)
	mat.set_shader_parameter("half_w", HALF)
	mat.set_shader_parameter("feather", SHOULDER_U * UNIT)
	mat.set_shader_parameter("turn_center", TURN)
	mat.set_shader_parameter("outer_r", 240.0 * UNIT)
	mat.set_shader_parameter("inner_r", 80.0 * UNIT)
	mat.set_shader_parameter("rocky_scale", 0.22)
	mat.set_shader_parameter("rocky_tint", Color(0.76, 0.88, 0.67))
	mat.set_shader_parameter("gravel_alb", gravel)
	mat.set_shader_parameter("gravel_nrm", gravel_n)
	mat.set_shader_parameter("gravel_rgh", gravel_r)
	mat.set_shader_parameter("rocky_alb", rocky)
	mat.set_shader_parameter("rocky_nrm", rocky_n)
	mat.set_shader_parameter("rocky_rgh", rocky_r)
	return mat


func _pack_dirt(verts: PackedVector3Array, uvs: PackedVector2Array) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in verts.size():
		tool.set_uv(uvs[i])
		tool.add_vertex(verts[i])
	tool.generate_normals()
	tool.generate_tangents()
	return tool.commit()


func _build_walks() -> void:
	_turn_specs.clear()
	_flare_specs.clear()
	var straight_src: PackedVector3Array = _read_tris(STL_DIR + "sidewalk_straight_slab.stl")
	var straight_pos: PackedVector3Array = _map_straight_side(straight_src, 1.0)
	var straight_neg: PackedVector3Array = _map_straight_side(straight_src, -1.0)
	if straight_pos.size() >= 3:
		_mesh["walk_straight"] = _pack_walk(straight_pos)
	if straight_neg.size() >= 3:
		_mesh["walk_straight_neg"] = _pack_walk(straight_neg)
	var wide_shift: float = 32.0 * UNIT
	if straight_pos.size() >= 3:
		_mesh["walk_wide"] = _pack_walk(_shift_z(straight_pos, wide_shift))
	if straight_neg.size() >= 3:
		_mesh["walk_wide_neg"] = _pack_walk(_shift_z(straight_neg, -wide_shift))
	_mesh["walk_fill"] = _walk_slab(1.0, 1.0)
	var turn_src: PackedVector3Array = _read_tris(STL_DIR + "sidewalk_turn_90_large_no_stretch.stl")
	var turn: PackedVector3Array = _map_turn_walk(turn_src)
	if turn.size() >= 3:
		var turn_mesh: ArrayMesh = _pack_walk(turn)
		_mesh["walk_turn"] = turn_mesh
		_turn_specs = _arc_specs(turn_mesh)
	var flare_src: PackedVector3Array = _read_tris(STL_DIR + "sidewalk_expand_reduce_no_stretch.stl")
	var flare: PackedVector3Array = _map_flare_walk(flare_src)
	if flare.size() >= 3:
		var flare_mesh: ArrayMesh = _pack_walk(flare)
		_mesh["walk_flare"] = flare_mesh
		_flare_specs = _x_specs(flare_mesh)
	var corner_src: PackedVector3Array = _read_tris(STL_DIR + "sidewalk_corner_no_stretch.stl")
	var corner_walk: PackedVector3Array = _map_corner_walk(corner_src, false)
	if corner_walk.size() >= 3:
		_mesh["walk_corner"] = _pack_walk(corner_walk)
	var corner_flip: PackedVector3Array = _map_corner_walk(corner_src, true)
	if corner_flip.size() >= 3:
		_mesh["walk_corner_m"] = _pack_walk(corner_flip)


func _map_corner_walk(src: PackedVector3Array, mirror: bool) -> PackedVector3Array:
	var dest := PackedVector3Array()
	var i := 0
	while i + 2 < src.size():
		for n in 3:
			var v: Vector3 = src[i + n]
			var lx: float = (CORNER_AY - v.y) * UNIT
			var lz: float = (CORNER_AX - v.x) * UNIT
			if mirror:
				lz = -lz
			var ly: float = v.z * UNIT + ROAD_Y
			dest.append(Vector3(lx, ly, lz))
		i += 3
	return _orient_top(dest)


func _map_straight_side(src: PackedVector3Array, sign: float) -> PackedVector3Array:
	var dest := PackedVector3Array()
	if src.size() < 3:
		return dest
	var lift: float = SIDE_LIFT if sign > 0.0 else 0.0
	var i := 0
	while i + 2 < src.size():
		var order: Array[int] = [0, 1, 2]
		if sign > 0.0:
			order = [0, 2, 1]
		for n in order:
			var v: Vector3 = src[i + n]
			var lx: float = (v.x - WALK_X0) * UNIT
			var lz: float = sign * (84.0 + (v.y - WALK_Y0)) * UNIT
			var ly: float = v.z * UNIT + ROAD_Y + lift
			dest.append(Vector3(lx, ly, lz))
		i += 3
	return _orient_top(dest)


func _map_turn_walk(src: PackedVector3Array) -> PackedVector3Array:
	var dest := PackedVector3Array()
	var i := 0
	while i + 2 < src.size():
		for n in 3:
			var v: Vector3 = src[i + n]
			var lx: float = (v.x - TURN_CX) * UNIT
			var lz: float = (156.0 - (v.y - TURN_CY)) * UNIT
			var ly: float = v.z * UNIT + ROAD_Y
			dest.append(Vector3(lx, ly, lz))
		i += 3
	return _orient_top(dest)


func _map_flare_walk(src: PackedVector3Array) -> PackedVector3Array:
	var gutter: PackedVector2Array = _flare_gutter(src)
	var dest := PackedVector3Array()
	var i := 0
	while i + 2 < src.size():
		for n in 3:
			var v: Vector3 = src[i + n]
			var gutter_x: float = _gutter_x(gutter, v.y)
			var mirrored_x: float = gutter_x + (gutter_x - v.x)
			var forward: float = (v.y - FLARE_Y0) * UNIT
			var lateral: float = (84.0 + (mirrored_x - FLARE_X0)) * UNIT
			var ly: float = (v.z - 1.0) * UNIT + ROAD_Y
			dest.append(Vector3(forward, ly, lateral))
		i += 3
	return _orient_top(dest)


func _flare_gutter(src: PackedVector3Array) -> PackedVector2Array:
	var raw: Array[Vector2] = []
	for v in src:
		if absf(v.z - 1.0) > 0.2:
			continue
		raw.append(Vector2(v.y, v.x))
	for i in range(1, raw.size()):
		var key: Vector2 = raw[i]
		var j: int = i - 1
		while j >= 0 and raw[j].x > key.x:
			raw[j + 1] = raw[j]
			j -= 1
		raw[j + 1] = key
	var out := PackedVector2Array()
	var last_y := -100000.0
	for point in raw:
		if point.x - last_y < 0.04:
			continue
		out.append(point)
		last_y = point.x
	return out


func _gutter_x(points: PackedVector2Array, y: float) -> float:
	if points.is_empty():
		return FLARE_X0
	if y <= points[0].x:
		return points[0].y
	var last: int = points.size() - 1
	if y >= points[last].x:
		return points[last].y
	for i in last:
		var y0: float = points[i].x
		var y1: float = points[i + 1].x
		if y > y1:
			continue
		var span: float = y1 - y0
		var t: float = 0.0
		if span > 0.0001:
			t = (y - y0) / span
		return lerpf(points[i].y, points[i + 1].y, t)
	return points[last].y


func _orient_top(verts: PackedVector3Array) -> PackedVector3Array:
	if verts.size() < 3:
		return verts
	var best_y := -1000.0
	var best_ny := 0.0
	var i := 0
	while i + 2 < verts.size():
		var a: Vector3 = verts[i]
		var b: Vector3 = verts[i + 1]
		var c: Vector3 = verts[i + 2]
		var n: Vector3 = (b - a).cross(c - a)
		var ay: float = (a.y + b.y + c.y) / 3.0
		if ay > best_y and n.length_squared() > 0.0000001:
			best_y = ay
			best_ny = n.y
		i += 3
	if best_ny >= 0.0:
		return verts
	var flipped := PackedVector3Array()
	i = 0
	while i + 2 < verts.size():
		flipped.append(verts[i])
		flipped.append(verts[i + 2])
		flipped.append(verts[i + 1])
		i += 3
	return flipped


func _walk_slab(length: float, width: float) -> ArrayMesh:
	var y0: float = -0.08
	var y1: float = WALK_TOP
	var x0: float = -length * 0.5
	var x1: float = length * 0.5
	var z0: float = -width * 0.5
	var z1: float = width * 0.5
	var verts := PackedVector3Array()
	_slab_tri(verts, Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1))
	_slab_tri(verts, Vector3(x0, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1))
	_slab_tri(verts, Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y0, z0))
	_slab_tri(verts, Vector3(x0, y0, z1), Vector3(x1, y0, z0), Vector3(x0, y0, z0))
	_slab_tri(verts, Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x0, y1, z1))
	_slab_tri(verts, Vector3(x0, y0, z0), Vector3(x0, y1, z1), Vector3(x0, y0, z1))
	_slab_tri(verts, Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0))
	_slab_tri(verts, Vector3(x1, y0, z1), Vector3(x1, y1, z0), Vector3(x1, y0, z0))
	_slab_tri(verts, Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x1, y1, z1))
	_slab_tri(verts, Vector3(x0, y0, z1), Vector3(x1, y1, z1), Vector3(x1, y0, z1))
	_slab_tri(verts, Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0))
	_slab_tri(verts, Vector3(x1, y0, z0), Vector3(x0, y1, z0), Vector3(x0, y0, z0))
	return _pack_walk(verts)


func _slab_tri(verts: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	verts.append(a)
	verts.append(b)
	verts.append(c)


func _pack_walk(verts: PackedVector3Array) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var i := 0
	while i + 2 < verts.size():
		var a: Vector3 = verts[i]
		var b: Vector3 = verts[i + 1]
		var c: Vector3 = verts[i + 2]
		var n: Vector3 = (b - a).cross(c - a)
		if n.length_squared() < 0.0000001:
			n = Vector3.UP
		else:
			n = n.normalized()
		tool.set_normal(n)
		tool.set_uv(Vector2(a.x, a.z) * 0.4)
		tool.add_vertex(a)
		tool.set_normal(n)
		tool.set_uv(Vector2(b.x, b.z) * 0.4)
		tool.add_vertex(b)
		tool.set_normal(n)
		tool.set_uv(Vector2(c.x, c.z) * 0.4)
		tool.add_vertex(c)
		i += 3
	tool.generate_tangents()
	return tool.commit()


func _arc_specs(mesh: Mesh) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var faces: PackedVector3Array = mesh.get_faces()
	if faces.is_empty():
		return out
	var center := Vector2(0.0, TURN)
	var slices := 4
	var buckets: Array = []
	for _step in slices:
		buckets.append([])
	for v in faces:
		var rel := Vector2(v.x - center.x, v.z - center.y)
		var ang: float = atan2(rel.y, rel.x)
		var t: float = (ang + PI * 0.5) / (PI * 0.5)
		var idx: int = clampi(int(floor(t * float(slices))), 0, slices - 1)
		(buckets[idx] as Array).append(v)
	for s in slices:
		var bucket: Array = buckets[s]
		if bucket.is_empty():
			continue
		var min_r := 1000.0
		var max_r := 0.0
		var min_a := 10.0
		var max_a := -10.0
		for item in bucket:
			var p: Vector3 = item
			var rel2 := Vector2(p.x - center.x, p.z - center.y)
			var rad: float = rel2.length()
			var ang2: float = atan2(rel2.y, rel2.x)
			min_r = minf(min_r, rad)
			max_r = maxf(max_r, rad)
			min_a = minf(min_a, ang2)
			max_a = maxf(max_a, ang2)
		var mid_a: float = (min_a + max_a) * 0.5
		var mid_r: float = (min_r + max_r) * 0.5
		var dir2 := Vector2(cos(mid_a), sin(mid_a))
		var tangent := Vector2(-dir2.y, dir2.x)
		var arc_len: float = maxf(max_a - min_a, 0.15) * mid_r
		out.append({
			"x": center.x + dir2.x * mid_r,
			"z": center.y + dir2.y * mid_r,
			"yaw": atan2(tangent.y, tangent.x),
			"length": arc_len * 1.08,
			"width": maxf(max_r - min_r, 0.4),
		})
	return out


func _x_specs(mesh: Mesh) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var faces: PackedVector3Array = mesh.get_faces()
	if faces.is_empty():
		return out
	var min_x := 1000.0
	var max_x := -1000.0
	for v in faces:
		min_x = minf(min_x, v.x)
		max_x = maxf(max_x, v.x)
	var span: float = max_x - min_x
	if span < 0.2:
		return out
	var slices := 4
	for s in slices:
		var x0: float = min_x + span * float(s) / float(slices)
		var x1: float = min_x + span * float(s + 1) / float(slices)
		var min_z := 1000.0
		var max_z := -1000.0
		var count := 0
		for v2 in faces:
			if v2.x < x0 - 0.02 or v2.x > x1 + 0.02:
				continue
			min_z = minf(min_z, v2.z)
			max_z = maxf(max_z, v2.z)
			count += 1
		if count == 0:
			continue
		out.append({
			"x": (x0 + x1) * 0.5,
			"z": (min_z + max_z) * 0.5,
			"yaw": 0.0,
			"length": (x1 - x0) + 0.08,
			"width": maxf(max_z - min_z, 0.4),
		})
	return out


func _plan_lots(map_center: Vector3) -> void:
	_lots.clear()
	for key in _lattice.keys():
		var parts: PackedStringArray = String(key).split("|")
		var i: int = int(parts[0])
		var j: int = int(parts[1])
		if not _has_corner(i + 1, j) or not _has_corner(i + 1, j + 1) or not _has_corner(i, j + 1):
			continue
		var sw: Vector2 = _crossing(i, j)
		var ne: Vector2 = _crossing(i + 1, j + 1)
		var lot_c := Vector2((sw.x + ne.x) * 0.5, (sw.y + ne.y) * 0.5)
		var chunk: Vector2i = _Layout.chunk_of(lot_c.x, lot_c.y)
		var cell := Rect2(sw.x, sw.y, ne.x - sw.x, ne.y - sw.y)
		var free: Array = _cut_obstacles([cell])
		for item in free:
			var rect: Rect2 = item
			if rect.size.x < 0.6 or rect.size.y < 0.6:
				continue
			var top: float = 0.0
			if _beside_walk(rect):
				top = WALK_TOP - 0.003
			_lots.append({"chunk": chunk, "rect": rect, "top": top})
	_add_field(map_center)


func _cut_obstacles(free: Array) -> Array:
	var blocks: Array[Rect2] = []
	for item in _rects_pending:
		var road: Rect2 = item["area"]
		blocks.append(_grow_rect(road, 0.05))
	for walk in _walks:
		blocks.append(_grow_rect(walk, -0.04))
	for med in _medians:
		blocks.append(_median_block(med))
	var rest: Array = free
	for block in blocks:
		if block.size.x < 0.05 or block.size.y < 0.05:
			continue
		rest = _cut_list(rest, block)
	return rest


func _median_block(spec: Dictionary) -> Rect2:
	var mid: Vector3 = spec["mid"]
	var length: float = float(spec["length"]) + 2.0 * TILE
	var angle: float = float(spec["angle"])
	var dir: Vector3 = _dir(angle)
	var a: Vector3 = mid - dir * (length * 0.5)
	var b: Vector3 = mid + dir * (length * 0.5)
	return _road_rect(a, b, angle, float(spec["width"]) * 0.5)


func _grow_rect(rect: Rect2, pad: float) -> Rect2:
	return Rect2(rect.position.x - pad, rect.position.y - pad, rect.size.x + pad * 2.0, rect.size.y + pad * 2.0)


func _cut_list(free: Array, block: Rect2) -> Array:
	var next: Array[Rect2] = []
	for item in free:
		var src: Rect2 = item
		if not src.intersects(block):
			next.append(src)
			continue
		var x0: float = src.position.x
		var z0: float = src.position.y
		var x1: float = x0 + src.size.x
		var z1: float = z0 + src.size.y
		var ix0: float = maxf(x0, block.position.x)
		var iz0: float = maxf(z0, block.position.y)
		var ix1: float = minf(x1, block.position.x + block.size.x)
		var iz1: float = minf(z1, block.position.y + block.size.y)
		if ix0 - x0 > 0.04:
			next.append(Rect2(x0, z0, ix0 - x0, z1 - z0))
		if x1 - ix1 > 0.04:
			next.append(Rect2(ix1, z0, x1 - ix1, z1 - z0))
		var span_x: float = ix1 - ix0
		if span_x > 0.04 and iz0 - z0 > 0.04:
			next.append(Rect2(ix0, z0, span_x, iz0 - z0))
		if span_x > 0.04 and z1 - iz1 > 0.04:
			next.append(Rect2(ix0, iz1, span_x, z1 - iz1))
	return next


func _beside_walk(rect: Rect2) -> bool:
	var grown := Rect2(rect.position.x - 0.35, rect.position.y - 0.35, rect.size.x + 0.7, rect.size.y + 0.7)
	for walk in _walks:
		if grown.intersects(walk):
			return true
	return false


func _add_field(map_center: Vector3) -> void:
	if _station_x.is_empty() or _station_z.is_empty():
		return
	var min_x: float = float(_station_x[_index_x0]) - HALF - WALK_W
	var max_x: float = float(_station_x[_index_x1]) + HALF + WALK_W
	var min_z: float = float(_station_z[_index_z0]) - HALF - WALK_W
	var max_z: float = float(_station_z[_index_z1]) + HALF + WALK_W
	var pad0 := Vector2(map_center.x - 1100.0, map_center.z - 1100.0)
	var pad1 := Vector2(map_center.x + 1100.0, map_center.z + 1100.0)
	var chunk: Vector2i = _Layout.chunk_of(map_center.x, map_center.z)
	_add_field_rect(chunk, pad0.x, pad0.y, min_x, pad1.y)
	_add_field_rect(chunk, max_x, pad0.y, pad1.x, pad1.y)
	_add_field_rect(chunk, min_x, pad0.y, max_x, min_z)
	_add_field_rect(chunk, min_x, max_z, max_x, pad1.y)


func _add_field_rect(chunk: Vector2i, x0: float, z0: float, x1: float, z1: float) -> void:
	if x1 - x0 < 1.0 or z1 - z0 < 1.0:
		return
	_lots.append({
		"chunk": chunk,
		"rect": Rect2(x0, z0, x1 - x0, z1 - z0),
		"top": 0.0,
	})


func _lift_blocks() -> void:
	for spec in _blocks:
		var pos: Vector3 = spec["pos"]
		var size: Vector3 = spec["size"]
		var top: float = _lot_top_at(pos.x, pos.z)
		spec["pos"] = Vector3(pos.x, top + size.y * 0.5 - 0.01, pos.z)


func _lot_top_at(x: float, z: float) -> float:
	var at := Vector2(x, z)
	var best_d: float = 0.8
	var top: float = 0.0
	var inside := false
	for lot in _lots:
		var rect: Rect2 = lot["rect"]
		if rect.has_point(at):
			if not inside or float(lot["top"]) > top:
				top = float(lot["top"])
				inside = true
			continue
		if inside:
			continue
		var cx: float = clampf(x, rect.position.x, rect.position.x + rect.size.x)
		var cz: float = clampf(z, rect.position.y, rect.position.y + rect.size.y)
		var dist: float = Vector2(x - cx, z - cz).length()
		if dist < best_d:
			best_d = dist
			top = float(lot["top"])
	return top


func _spawn_lots(root: Node3D) -> void:
	if _lots.is_empty() or _ground_mat == null:
		return
	var groups: Dictionary = {}
	for spec in _lots:
		var chunk: Vector2i = spec["chunk"]
		var key := "%d|%d" % [chunk.x, chunk.y]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(spec)
	for key2 in groups.keys():
		var list: Array = groups[key2]
		if list.is_empty():
			continue
		var first: Dictionary = list[0]
		var host: Node3D = _chunk_node(root, first["chunk"])
		var many := MultiMesh.new()
		many.transform_format = MultiMesh.TRANSFORM_3D
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE
		many.mesh = cube
		many.instance_count = list.size()
		var body := StaticBody3D.new()
		body.name = "LotGrass"
		body.collision_layer = 1
		body.collision_mask = 1
		host.add_child(body)
		for n in list.size():
			var spec2: Dictionary = list[n]
			var rect: Rect2 = spec2["rect"]
			var top: float = float(spec2["top"])
			var size := Vector3(rect.size.x, LOT_THICK, rect.size.y)
			var pos := Vector3(rect.position.x + rect.size.x * 0.5, top - LOT_THICK * 0.5, rect.position.y + rect.size.y * 0.5)
			many.set_instance_transform(n, Transform3D(Basis.from_scale(size), pos))
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = size
			shape.shape = box
			shape.position = pos
			body.add_child(shape)
		var view := MultiMeshInstance3D.new()
		view.name = "LotGrass"
		view.multimesh = many
		view.material_override = _ground_mat
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(view)


func _make_decor_materials() -> void:
	_part_mats.clear()
	_part_mats["pole_industrial"] = _metal_mat(Color(0.22, 0.23, 0.25))
	_part_mats["pole_signal"] = _metal_mat(Color(0.22, 0.23, 0.25))
	_part_mats["sign_post"] = _metal_mat(Color(0.55, 0.56, 0.58))
	_part_mats["enclosure_industrial"] = _metal_mat(Color(0.30, 0.32, 0.34))
	_part_mats["enclosure_signal"] = _metal_mat(Color(0.16, 0.17, 0.18))
	_part_mats["enclosure_signal_head"] = _part_mats["enclosure_signal"]
	var street := _glow_mat(Color(1.0, 0.86, 0.45))
	street.emission_energy_multiplier = 2.4
	_part_mats["bulbs_industrial"] = street
	_part_mats["bulb_signal"] = _glow_mat(Color(0.95, 0.22, 0.12))
	_signal_mats.clear()
	_signal_mats["ew_red"] = _lens_mat(Color(0.85, 0.12, 0.10), false)
	_signal_mats["ew_yellow"] = _lens_mat(Color(0.92, 0.72, 0.12), false)
	_signal_mats["ew_green"] = _lens_mat(Color(0.20, 0.85, 0.25), true)
	_signal_mats["ns_red"] = _lens_mat(Color(0.85, 0.12, 0.10), true)
	_signal_mats["ns_yellow"] = _lens_mat(Color(0.92, 0.72, 0.12), false)
	_signal_mats["ns_green"] = _lens_mat(Color(0.20, 0.85, 0.25), false)
	_part_mats["bulb_ew_red"] = _signal_mats["ew_red"]
	_part_mats["bulb_ew_yellow"] = _signal_mats["ew_yellow"]
	_part_mats["bulb_ew_green"] = _signal_mats["ew_green"]
	_part_mats["bulb_ns_red"] = _signal_mats["ns_red"]
	_part_mats["bulb_ns_yellow"] = _signal_mats["ns_yellow"]
	_part_mats["bulb_ns_green"] = _signal_mats["ns_green"]
	var rim := _curb_mat.duplicate() as StandardMaterial3D
	rim.cull_mode = BaseMaterial3D.CULL_DISABLED
	_part_mats["median_base"] = rim
	_part_mats["median_cap"] = rim
	var soil := StandardMaterial3D.new()
	soil.albedo_color = Color(0.26, 0.30, 0.18)
	soil.roughness = 0.95
	soil.cull_mode = BaseMaterial3D.CULL_DISABLED
	_part_mats["median_inlay"] = soil
	_part_mats["median_cap_inlay"] = soil
	_part_mats["stop_sign"] = _flat_mat(Color(0.72, 0.08, 0.08))
	_part_mats["speed_sign"] = _flat_mat(Color(0.93, 0.93, 0.90))
	_part_mats["barrier"] = _curb_mat
	_part_mats["trunk"] = _trunk_mat
	_part_mats["canopy"] = _canopy_mat
	_part_mats["planter"] = _plant_mat


func _metal_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.65
	mat.roughness = 0.42
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _flat_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.55
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _glow_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.6
	mat.roughness = 0.25
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _lens_mat(color: Color, lit: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.4 if lit else 0.0
	mat.roughness = 0.28
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _build_decor_meshes() -> void:
	_lamp_locals.clear()
	var pole_i: PackedVector3Array = _read_tris(DECOR_DIR + "pole_street_lamp_industrial.stl")
	var enc_i: PackedVector3Array = _read_tris(DECOR_DIR + "enclosure_street_lamp_industrial.stl")
	var bulb_i: PackedVector3Array = _read_tris(DECOR_DIR + "bulbs_street_lamp_industrial.stl")
	var anchor_i: Vector2 = _base_center(pole_i)
	var ind_pole: PackedVector3Array = _map_decor(pole_i, anchor_i, UNIT, false)
	var ind_enc: PackedVector3Array = _map_decor(enc_i, anchor_i, UNIT, false)
	var ind_bulb: PackedVector3Array = _map_decor(bulb_i, anchor_i, UNIT, false)
	if _mean_x(ind_enc) < 0.0:
		ind_pole = _negate_x(ind_pole)
		ind_enc = _negate_x(ind_enc)
		ind_bulb = _negate_x(ind_bulb)
	var enc_far: PackedVector3Array = _negate_x(ind_enc)
	var bulb_far: PackedVector3Array = _negate_x(ind_bulb)
	_lamp_locals.append(_centroid(ind_bulb))
	_lamp_locals.append(_centroid(bulb_far))
	ind_enc.append_array(enc_far)
	ind_bulb.append_array(bulb_far)
	_store_decor("pole_industrial", ind_pole)
	_store_decor("enclosure_industrial", ind_enc)
	_store_decor("bulbs_industrial", ind_bulb)
	var pole_s: PackedVector3Array = _read_tris(DECOR_DIR + "pole_street_light_signal.stl")
	var enc_s: PackedVector3Array = _read_tris(DECOR_DIR + "enclosure_street_light_signal.stl")
	var bulb_s: PackedVector3Array = _read_tris(DECOR_DIR + "bulb_street_light_signal.stl")
	var anchor_s: Vector2 = _base_center(pole_s)
	var sig_pole: PackedVector3Array = _map_decor(pole_s, anchor_s, UNIT, false)
	var sig_enc: PackedVector3Array = _map_decor(enc_s, anchor_s, UNIT, false)
	var sig_bulb: PackedVector3Array = _map_decor(bulb_s, anchor_s, UNIT, false)
	if _mean_x(sig_enc) < 0.0:
		sig_pole = _negate_x(sig_pole)
		sig_enc = _negate_x(sig_enc)
		sig_bulb = _negate_x(sig_bulb)
	_store_decor("pole_signal", sig_pole)
	_store_decor("enclosure_signal", sig_enc)
	_store_decor("bulb_signal", sig_bulb)
	_build_signal_heads(sig_enc, sig_bulb)
	var post: PackedVector3Array = _read_tris(DECOR_DIR + "sign_post.stl")
	var anchor_p: Vector2 = _base_center(post)
	_store_decor("sign_post", _map_decor(post, anchor_p, SIGN_SCALE, true))
	_store_decor("stop_sign", _map_decor(_read_tris(DECOR_DIR + "stop_sign_octagon.stl"), anchor_p, SIGN_SCALE, true))
	_store_decor("speed_sign", _map_decor(_read_tris(DECOR_DIR + "speed_limit_sign_rectangle.stl"), anchor_p, SIGN_SCALE, true))
	var bar: PackedVector3Array = _read_tris(DECOR_DIR + "cement_parking_barrier.stl")
	_store_decor("barrier", _map_decor(bar, _base_center(bar), UNIT, false))
	_build_median_meshes()


func _store_decor(part: String, verts: PackedVector3Array) -> void:
	if verts.size() < 3:
		push_error("Decoration %s has no triangles." % part)
		return
	_mesh[part] = _pack_closed(verts)


func _base_center(verts: PackedVector3Array) -> Vector2:
	if verts.is_empty():
		return Vector2.ZERO
	var zmin: float = verts[0].z
	for v in verts:
		if v.z < zmin:
			zmin = v.z
	var sx: float = 0.0
	var sy: float = 0.0
	var n: int = 0
	for v2 in verts:
		if v2.z > zmin + 0.75:
			continue
		sx += v2.x
		sy += v2.y
		n += 1
	if n == 0:
		return Vector2.ZERO
	return Vector2(sx / float(n), sy / float(n))


func _map_decor(verts: PackedVector3Array, anchor: Vector2, scale: float, sign_face: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	for v in verts:
		var lx: float = (v.x - anchor.x) * scale
		var lz: float = (v.y - anchor.y) * scale
		var ly: float = v.z * scale
		if sign_face:
			lx = (v.y - anchor.y) * scale
			lz = (v.x - anchor.x) * scale
		out.append(Vector3(lx, ly, lz))
	return out


func _mean_x(verts: PackedVector3Array) -> float:
	if verts.is_empty():
		return 0.0
	var sum: float = 0.0
	for v in verts:
		sum += v.x
	return sum / float(verts.size())


func _negate_x(verts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for v in verts:
		out.append(Vector3(-v.x, v.y, v.z))
	return out


func _pack_closed(verts: PackedVector3Array) -> ArrayMesh:
	var vol: float = 0.0
	var i: int = 0
	while i + 2 < verts.size():
		var a: Vector3 = verts[i]
		var b: Vector3 = verts[i + 1]
		var c: Vector3 = verts[i + 2]
		vol += a.dot(b.cross(c))
		i += 3
	var flip: bool = vol < 0.0
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	i = 0
	while i + 2 < verts.size():
		var a2: Vector3 = verts[i]
		var b2: Vector3 = verts[i + 1]
		var c2: Vector3 = verts[i + 2]
		if flip:
			var swap: Vector3 = b2
			b2 = c2
			c2 = swap
		var nrm: Vector3 = (b2 - a2).cross(c2 - a2)
		if nrm.length_squared() < 0.0000001:
			nrm = Vector3.UP
		else:
			nrm = nrm.normalized()
		tool.set_normal(nrm)
		tool.add_vertex(a2)
		tool.set_normal(nrm)
		tool.add_vertex(b2)
		tool.set_normal(nrm)
		tool.add_vertex(c2)
		i += 3
	return tool.commit()


func _pack_mesh(verts: PackedVector3Array, uvs: PackedVector2Array) -> ArrayMesh:
	var normals: PackedVector3Array = PackedVector3Array()
	normals.resize(verts.size())
	for i in verts.size():
		normals[i] = Vector3.UP
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	if verts.size() >= 3:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _read_tris(path: String) -> PackedVector3Array:
	var verts: PackedVector3Array = PackedVector3Array()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Missing road STL %s" % path)
		return verts
	file.seek(80)
	var count: int = int(file.get_32())
	for _tri in count:
		file.get_float()
		file.get_float()
		file.get_float()
		for _v in 3:
			var x: float = file.get_float()
			var y: float = file.get_float()
			var z: float = file.get_float()
			verts.append(Vector3(x, y, z))
		file.get_16()
	file.close()
	return verts


func _track_surface(kind: String) -> bool:
	if kind.contains("yellow") or kind.contains("white") or kind.contains("inlay"):
		return false
	return true


func _centroid(verts: PackedVector3Array) -> Vector3:
	if verts.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for v in verts:
		sum += v
	return sum / float(verts.size())


func _shift_y(verts: PackedVector3Array, dy: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for v in verts:
		out.append(Vector3(v.x, v.y + dy, v.z))
	return out


func _translate_verts(verts: PackedVector3Array, delta: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for v in verts:
		out.append(v - delta)
	return out


func _top_center(verts: PackedVector3Array) -> Vector3:
	if verts.is_empty():
		return Vector3.ZERO
	var ymax: float = verts[0].y
	for v in verts:
		if v.y > ymax:
			ymax = v.y
	var sum := Vector3.ZERO
	var n := 0
	for v2 in verts:
		if v2.y < ymax - 0.04:
			continue
		sum += v2
		n += 1
	if n == 0:
		return Vector3(0.0, ymax, 0.0)
	return sum / float(n)


func _visor_offsets(enc: PackedVector3Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if enc.is_empty():
		return out
	var zmin: float = enc[0].z
	for v in enc:
		if v.z < zmin:
			zmin = v.z
	var limit: float = zmin + 1.2 * UNIT
	var ys: Array[float] = []
	for v2 in enc:
		if v2.z <= limit:
			ys.append(v2.y)
	if ys.is_empty():
		return out
	ys.sort()
	var band_sum: float = 0.0
	var band_n := 0
	var band_last: float = ys[0]
	var mids: Array[float] = []
	for y in ys:
		if band_n > 0 and y - band_last > 0.15:
			mids.append(band_sum / float(band_n))
			band_sum = 0.0
			band_n = 0
		band_sum += y
		band_n += 1
		band_last = y
	if band_n > 0:
		mids.append(band_sum / float(band_n))
	if mids.is_empty():
		return out
	var top: float = mids[mids.size() - 1]
	for mid in mids:
		var delta: float = mid - top
		if absf(delta) < 0.05:
			continue
		out.append(delta)
	return out


func _build_signal_heads(enc: PackedVector3Array, bulb: PackedVector3Array) -> void:
	if enc.size() < 3 or bulb.size() < 3:
		push_error("Signal head pieces failed to load.")
		_joint_error = maxf(_joint_error, 5.0)
		return
	var hanger: Vector3 = _top_center(enc)
	_signal_arm_y = hanger.y
	var head: PackedVector3Array = _translate_verts(enc, hanger)
	var red: PackedVector3Array = _translate_verts(bulb, hanger)
	var offsets: PackedFloat32Array = _visor_offsets(enc)
	var lower: Array[float] = []
	for shift in offsets:
		lower.append(shift)
	lower.sort()
	var yellow: PackedVector3Array = red
	var green: PackedVector3Array = red
	if lower.size() >= 1:
		green = _translate_verts(_shift_y(bulb, lower[0]), hanger)
	if lower.size() >= 2:
		yellow = _translate_verts(_shift_y(bulb, lower[lower.size() - 1]), hanger)
	elif lower.size() == 1:
		yellow = green
	_store_decor("enclosure_signal_head", head)
	var red_mesh: ArrayMesh = _pack_closed(red)
	var yellow_mesh: ArrayMesh = _pack_closed(yellow)
	var green_mesh: ArrayMesh = _pack_closed(green)
	_mesh["bulb_ew_red"] = red_mesh
	_mesh["bulb_ew_yellow"] = yellow_mesh
	_mesh["bulb_ew_green"] = green_mesh
	_mesh["bulb_ns_red"] = red_mesh
	_mesh["bulb_ns_yellow"] = yellow_mesh
	_mesh["bulb_ns_green"] = green_mesh
	_signal_glow_local = _centroid(yellow)


func _src_bounds(src: PackedVector3Array) -> Dictionary:
	var xmin: float = src[0].x
	var xmax: float = src[0].x
	var ymin: float = src[0].y
	var ymax: float = src[0].y
	for v in src:
		xmin = minf(xmin, v.x)
		xmax = maxf(xmax, v.x)
		ymin = minf(ymin, v.y)
		ymax = maxf(ymax, v.y)
	return {"xmin": xmin, "xmax": xmax, "ymin": ymin, "ymax": ymax}


func _map_median(src: PackedVector3Array, x_center: float, y_nose: float, y_joint: float, nose_at_zero: bool, lift: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for v in src:
		var lx: float = (v.y - y_joint) * UNIT
		if nose_at_zero:
			lx = (y_nose - v.y) * UNIT
		var lz: float = (v.x - x_center) * UNIT
		var ly: float = v.z * UNIT + ROAD_Y + lift
		out.append(Vector3(lx, ly, lz))
	return out


func _build_median_meshes() -> void:
	var base: PackedVector3Array = _read_tris(DECOR_DIR + "decorative_median_base.stl")
	var inlay: PackedVector3Array = _read_tris(DECOR_DIR + "decorative_median_inlay.stl")
	var cap: PackedVector3Array = _read_tris(DECOR_DIR + "decorative_median_round_cap_base_no_stretch.stl")
	var cap_in: PackedVector3Array = _read_tris(DECOR_DIR + "decorative_median_round_cap_inlay_no_stretch.stl")
	if base.size() < 3 or cap.size() < 3 or inlay.size() < 3 or cap_in.size() < 3:
		push_error("Median pieces failed to load.")
		_joint_error = maxf(_joint_error, 5.0)
		return
	var base_b: Dictionary = _src_bounds(base)
	var cap_b: Dictionary = _src_bounds(cap)
	var base_cx: float = (float(base_b["xmin"]) + float(base_b["xmax"])) * 0.5
	var cap_cx: float = (float(cap_b["xmin"]) + float(cap_b["xmax"])) * 0.5
	_store_decor("median_base", _map_median(base, base_cx, float(base_b["ymax"]), float(base_b["ymin"]), false, 0.0))
	_store_decor("median_inlay", _map_median(inlay, base_cx, float(base_b["ymax"]), float(base_b["ymin"]), false, 0.002))
	_store_decor("median_cap", _map_median(cap, cap_cx, float(cap_b["ymax"]), float(cap_b["ymin"]), true, 0.0))
	_store_decor("median_cap_inlay", _map_median(cap_in, cap_cx, float(cap_b["ymax"]), float(cap_b["ymin"]), true, 0.002))


func _spawn_lamp_lights(root: Node3D) -> void:
	for spec in _decors:
		var kind: String = str(spec["kind"])
		if kind == "lamp":
			_spawn_street_light(root, spec)
		elif kind.begins_with("signal_head"):
			_spawn_signal_light(root, spec)


func _spawn_street_light(root: Node3D, spec: Dictionary) -> void:
	if _lamp_locals.is_empty():
		return
	var at: Vector3 = spec["at"]
	var dir: Vector3 = spec["dir"]
	var y: float = _lot_top_at(at.x, at.z) + float(spec["lift"])
	var host := Node3D.new()
	host.name = "StreetLamp"
	host.add_to_group("night_lamp")
	host.transform = Transform3D(Basis(dir, Vector3.UP, _right_of(dir)), Vector3(at.x, y, at.z))
	for local in _lamp_locals:
		var omni := OmniLight3D.new()
		omni.position = local
		omni.light_color = Color(1.0, 0.78, 0.45)
		omni.light_energy = 0.0
		omni.omni_range = 14.0
		omni.omni_attenuation = 1.4
		omni.shadow_enabled = false
		host.add_child(omni)
	var chunk: Vector2i = _Layout.chunk_of(at.x, at.z)
	_chunk_node(root, chunk).add_child(host)


func _spawn_signal_light(root: Node3D, spec: Dictionary) -> void:
	var at: Vector3 = spec["at"]
	var aim: Vector3 = spec["dir"]
	var base_y: float = _lot_top_at(at.x, at.z)
	if spec.has("base_y"):
		base_y = float(spec["base_y"])
	var y: float = base_y + float(spec["lift"])
	var basis := Basis(aim, Vector3.UP, _right_of(aim))
	var omni := OmniLight3D.new()
	omni.position = Vector3(at.x, y, at.z) + basis * _signal_glow_local
	omni.add_to_group("signal_lamp")
	var axis := 1
	if str(spec["kind"]) != "signal_head_ew":
		axis = 2
	omni.set_meta("signal_axis", axis)
	if axis == 1:
		omni.light_color = Color(0.20, 0.85, 0.25)
	else:
		omni.light_color = Color(0.85, 0.12, 0.10)
	omni.light_energy = 0.0
	omni.omni_range = 8.0
	omni.omni_attenuation = 1.3
	omni.shadow_enabled = false
	var chunk: Vector2i = _Layout.chunk_of(at.x, at.z)
	_chunk_node(root, chunk).add_child(omni)


func _spawn_aprons(root: Node3D) -> void:
	for apron in _aprons:
		var chunk: Vector2i = apron["chunk"]
		var host: Node3D = _chunk_node(root, chunk)
		var view := MeshInstance3D.new()
		if apron.has("verts"):
			view.mesh = _pack_flat(apron["verts"])
		else:
			var mesh := BoxMesh.new()
			mesh.size = Vector3(float(apron["length"]), 0.03, float(apron["width"]))
			view.mesh = mesh
			var mid: Vector3 = apron["mid"]
			var angle: float = float(apron["angle"])
			view.transform = Transform3D(Basis(_dir(angle), Vector3.UP, _right(angle)), Vector3(mid.x, ROAD_Y, mid.z))
		if bool(apron["dirt"]):
			view.material_override = _gravel_mat
		else:
			view.material_override = _asphalt_mat
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(view)


func _spawn_cut_walks(root: Node3D) -> void:
	for spec in _cut_walks:
		var chunk: Vector2i = spec["chunk"]
		var host: Node3D = _chunk_node(root, chunk)
		var view := MeshInstance3D.new()
		var verts: PackedVector3Array = spec["verts"]
		view.mesh = _pack_walk(verts)
		var at: Vector3 = spec["at"]
		var angle: float = float(spec["angle"])
		var right: Vector3 = _right(angle)
		if bool(spec["mirrored"]):
			right = -right
		view.transform = Transform3D(Basis(_dir(angle), Vector3.UP, right), at)
		view.material_override = _material_for(str(spec["kind"]))
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(view)


func _gap_sidewalks() -> void:
	_mouth_corners.clear()
	_walk_corners.clear()
	var corridors: Array[Rect2] = []
	_add_corner_notches(corridors)
	var mouths: Array[Rect2] = _mouth_corridors()
	for rect in mouths:
		corridors.append(rect)
	_add_apron_corridors(corridors)
	if corridors.is_empty():
		return
	_split_walk_boxes(corridors)
	if _mesh.has("walk_corner") and _mesh.has("walk_corner_m"):
		_clip_loose_walks(corridors)
		_place_walk_corners()
	else:
		_drop_walk_tiles(corridors)
		_clip_loose_walks(corridors)
	_fill_cross_corners()


func _clip_loose_walks(corridors: Array[Rect2]) -> void:
	var bands: Array[Rect2] = []
	for corridor in corridors:
		bands.append(corridor)
	for surf0 in _surfaces:
		if str(surf0["kind"]) != "walk_fill" or not surf0.has("rect"):
			continue
		bands.append(surf0["rect"])
	var drop: Dictionary = {}
	var kept: Array[Dictionary] = []
	for surf in _surfaces:
		var kind: String = str(surf["kind"])
		if not _clip_walk_kind(kind):
			kept.append(surf)
			continue
		if not _hits_corridor(_surface_rect(surf), bands):
			kept.append(surf)
			continue
		var faces: PackedVector3Array = _mesh_faces(str(surf["kind"]))
		var loops: Array = []
		for corridor in bands:
			if _rect_pen(_surface_rect(surf), corridor).x <= 0.05:
				continue
			if _rect_pen(_surface_rect(surf), corridor).y <= 0.05:
				continue
			loops.append(_local_loop(surf, corridor))
		var cut: Dictionary = _cut_faces(faces, loops)
		if not bool(cut["changed"]) or int(cut["count"]) < 3:
			if int(cut["count"]) < 3:
				_mark_drop(drop, surf)
				continue
			kept.append(surf)
			continue
		var local: PackedVector3Array = cut["verts"]
		var flat: PackedVector2Array = _world_flat(surf, local)
		surf["flat"] = flat
		kept.append(surf)
		_mark_drop(drop, surf)
		_cut_walks.append({
			"chunk": surf["chunk"],
			"verts": local,
			"at": surf["at"],
			"angle": surf["angle"],
			"mirrored": bool(surf.get("mirrored", false)),
			"kind": kind,
		})
	_surfaces = kept
	_compact_xf(drop)


func _clip_walk_kind(kind: String) -> bool:
	if kind == "walk_flare" or kind == "walk_turn":
		return true
	if not _mesh.has("walk_corner"):
		return false
	return _walk_tile_kind(kind)


func _mark_drop(drop: Dictionary, surf: Dictionary) -> void:
	var key: String = str(surf["key"])
	if not drop.has(key):
		drop[key] = {}
	(drop[key] as Dictionary)[int(surf["index"])] = true


func _compact_xf(drop: Dictionary) -> void:
	for key2 in drop.keys():
		if not _xf.has(key2):
			continue
		var gone: Dictionary = drop[key2]
		var list: Array = _xf[key2]
		var remain: Array = []
		for n in list.size():
			if gone.has(n):
				continue
			remain.append(list[n])
		if remain.is_empty():
			_xf.erase(key2)
		else:
			_xf[key2] = remain


func _mesh_faces(kind: String) -> PackedVector3Array:
	if not _mesh.has(kind):
		return PackedVector3Array()
	return (_mesh[kind] as Mesh).get_faces()


func _local_loop(surf: Dictionary, rect: Rect2) -> PackedVector2Array:
	var at: Vector3 = surf["at"]
	var angle: float = float(surf["angle"])
	var right: Vector3 = _right(angle)
	if bool(surf.get("mirrored", false)):
		right = -right
	var inv: Basis = Basis(_dir(angle), Vector3.UP, right).inverse()
	var x0: float = rect.position.x
	var z0: float = rect.position.y
	var x1: float = x0 + rect.size.x
	var z1: float = z0 + rect.size.y
	var world: Array[Vector3] = [Vector3(x0, 0.0, z0), Vector3(x1, 0.0, z0), Vector3(x1, 0.0, z1), Vector3(x0, 0.0, z1)]
	var flat: Array[Vector2] = []
	for w in world:
		var local: Vector3 = inv * (w - at)
		flat.append(Vector2(local.x, local.z))
	var ordered: Array[Vector2] = _ccw(flat)
	var out := PackedVector2Array()
	for p in ordered:
		out.append(p)
	return out


func _world_flat(surf: Dictionary, local: PackedVector3Array) -> PackedVector2Array:
	var at: Vector3 = surf["at"]
	var angle: float = float(surf["angle"])
	var right: Vector3 = _right(angle)
	if bool(surf.get("mirrored", false)):
		right = -right
	var basis := Basis(_dir(angle), Vector3.UP, right)
	var flat := PackedVector2Array()
	for v in local:
		var world: Vector3 = at + basis * v
		flat.append(Vector2(world.x, world.z))
	return flat


func _cut_faces(faces: PackedVector3Array, loops: Array) -> Dictionary:
	var polys: Array = []
	var i := 0
	while i + 2 < faces.size():
		polys.append([faces[i], faces[i + 1], faces[i + 2]])
		i += 3
	var changed := false
	for loop in loops:
		var ring: PackedVector2Array = loop
		if ring.size() < 3 or polys.is_empty():
			continue
		var next: Array = []
		for poly in polys:
			var piece: Array = poly
			if not _poly_hits_loop(piece, ring):
				next.append(piece)
				continue
			var kept_parts: Array = _outside_loop(piece, ring)
			if kept_parts.size() != 1:
				changed = true
			else:
				var only: Array = kept_parts[0]
				if only.size() != piece.size():
					changed = true
				else:
					for n in only.size():
						var moved: Vector3 = only[n]
						var was: Vector3 = piece[n]
						if moved.distance_squared_to(was) > 0.000001:
							changed = true
							break
			if kept_parts.is_empty():
				changed = true
			for part in kept_parts:
				next.append(part)
		if next.size() != polys.size():
			changed = true
		polys = next
	var verts := PackedVector3Array()
	for poly2 in polys:
		var fan: Array = poly2
		if fan.size() < 3:
			continue
		var p0: Vector3 = fan[0]
		for k in range(1, fan.size() - 1):
			var b: Vector3 = fan[k]
			var c: Vector3 = fan[k + 1]
			verts.append(p0)
			verts.append(b)
			verts.append(c)
	return {"verts": verts, "changed": changed, "count": verts.size()}


func _poly_hits_loop(poly: Array, ring: PackedVector2Array) -> bool:
	var min_x: float = 1000000.0
	var max_x: float = -1000000.0
	var min_z: float = 1000000.0
	var max_z: float = -1000000.0
	for item in poly:
		var p: Vector3 = item
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	var rmin_x: float = ring[0].x
	var rmax_x: float = ring[0].x
	var rmin_z: float = ring[0].y
	var rmax_z: float = ring[0].y
	for q in ring:
		rmin_x = minf(rmin_x, q.x)
		rmax_x = maxf(rmax_x, q.x)
		rmin_z = minf(rmin_z, q.y)
		rmax_z = maxf(rmax_z, q.y)
	return max_x >= rmin_x and min_x <= rmax_x and max_z >= rmin_z and min_z <= rmax_z


func _outside_loop(poly: Array, ring: PackedVector2Array) -> Array:
	var pending: Array = [poly]
	var final: Array = []
	var n: int = ring.size()
	for e in n:
		var ax: Vector2 = ring[e]
		var ay: Vector2 = ring[(e + 1) % n]
		var nxt: Array = []
		for piece in pending:
			var parts: Array = _split_inside(piece, ax, ay)
			var inside: Array = parts[0]
			var outside: Array = parts[1]
			if outside.size() >= 3:
				final.append(outside)
			if inside.size() >= 3:
				nxt.append(inside)
		pending = nxt
		if pending.is_empty():
			break
	return final


func _split_inside(poly: Array, ax: Vector2, ay: Vector2) -> Array:
	var inside: Array = []
	var outside: Array = []
	var n: int = poly.size()
	for i in n:
		var cur: Vector3 = poly[i]
		var prev: Vector3 = poly[(i + n - 1) % n]
		var cur_in: bool = _left_of(ax, ay, Vector2(cur.x, cur.z))
		var prev_in: bool = _left_of(ax, ay, Vector2(prev.x, prev.z))
		var hit: Vector3 = cur
		if cur_in:
			if not prev_in:
				hit = _line_hit3(prev, cur, ax, ay)
				outside.append(hit)
				inside.append(hit)
			inside.append(cur)
		else:
			if prev_in:
				hit = _line_hit3(prev, cur, ax, ay)
				inside.append(hit)
				outside.append(hit)
			outside.append(cur)
	return [inside, outside]


func _line_hit3(p: Vector3, q: Vector3, ax: Vector2, ay: Vector2) -> Vector3:
	var hit: Vector2 = _line_hit(Vector2(p.x, p.z), Vector2(q.x, q.z), ax, ay)
	var dx: float = q.x - p.x
	var dz: float = q.z - p.z
	var t: float = 0.0
	if absf(dx) >= absf(dz):
		if absf(dx) > 0.0000001:
			t = (hit.x - p.x) / dx
	elif absf(dz) > 0.0000001:
		t = (hit.y - p.z) / dz
	t = clampf(t, 0.0, 1.0)
	return p.lerp(q, t)


func _mouth_corridors() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for seg in _segments:
		var kind := ""
		if seg.has("kind"):
			kind = str(seg["kind"])
		if kind != "alley" and kind != "radial" and kind != "strips" and kind != "court":
			continue
		if not seg.has("drive_from") or not seg.has("drive_to"):
			continue
		var a: Vector3 = seg["drive_from"]
		var b: Vector3 = seg["drive_to"]
		_add_mouth_corridor(out, a, b, kind)
		_add_mouth_corridor(out, b, a, kind)
	return out


func _add_mouth_corridor(out: Array[Rect2], mouth: Vector3, other: Vector3, kind: String) -> void:
	if not _near_paved(mouth):
		return
	var delta: Vector3 = other - mouth
	var length: float = delta.length()
	if length < 0.5:
		return
	var reach: float = WALK_W + 1.0
	if reach > length:
		reach = length
	var dir: Vector3 = delta / length
	var right: Vector3 = _right_of(dir)
	var mid: Vector3 = mouth + dir * (reach * 0.5)
	var hx: float = reach * 0.5
	var hz: float = CROSS * 0.5
	var c0: Vector3 = mid + dir * hx + right * hz
	var c1: Vector3 = mid + dir * hx - right * hz
	var c2: Vector3 = mid - dir * hx + right * hz
	var c3: Vector3 = mid - dir * hx - right * hz
	out.append(_bounds4(c0, c1, c2, c3))
	var side: float = HALF + WALK_W * 0.5
	for sign in [1.0, -1.0]:
		var curb: Vector3 = mouth + right * (HALF * sign)
		if _corner_taken(curb):
			continue
		if kind == "strips" and _mesh.has("walk_corner"):
			var outward: Vector3 = right * sign
			var foot: Rect2 = _corner_footprint(curb, dir, outward)
			if not _corner_hits(foot):
				out.append(foot)
				_walk_corners.append({
					"at": curb,
					"along": dir,
					"outward": outward,
					"rect": foot,
				})
				continue
		var corner_mid: Vector3 = mouth + dir * (WALK_W * 0.5) + right * (side * sign)
		var corner: Rect2 = _centered_rect(corner_mid, dir, WALK_W, WALK_W)
		if _corner_hits(corner):
			continue
		out.append(corner)
		_mouth_corners.append(corner)


func _near_paved(at: Vector3) -> bool:
	var reach: float = HALF + TILE + 1.2
	for seg in _segments:
		var kind := ""
		if seg.has("kind"):
			kind = str(seg["kind"])
		if kind != "arterial" and kind != "street" and kind != "strips":
			continue
		if _dist_point_seg(at, seg["from"], seg["to"]) <= reach:
			return true
	var flat := Vector2(at.x, at.z)
	for surf in _surfaces:
		if not _walk_tile_kind(str(surf["kind"])):
			continue
		var rect: Rect2 = _surface_rect(surf)
		if flat.x < rect.position.x - 0.4 or flat.x > rect.position.x + rect.size.x + 0.4:
			continue
		if flat.y < rect.position.y - 0.4 or flat.y > rect.position.y + rect.size.y + 0.4:
			continue
		return true
	return false


func _walk_tile_kind(kind: String) -> bool:
	return kind == "walk_straight" or kind == "walk_straight_neg" or kind == "walk_wide" or kind == "walk_wide_neg"


func _drop_walk_tiles(corridors: Array[Rect2]) -> void:
	var drop: Dictionary = {}
	var kept: Array[Dictionary] = []
	var dropped: Array[Rect2] = []
	for surf in _surfaces:
		var kind: String = str(surf["kind"])
		if not _walk_tile_kind(kind):
			kept.append(surf)
			continue
		var rect: Rect2 = _surface_rect(surf)
		if not _hits_corridor(rect, corridors):
			kept.append(surf)
			continue
		dropped.append(rect)
		var key: String = str(surf["key"])
		if not drop.has(key):
			drop[key] = {}
		(drop[key] as Dictionary)[int(surf["index"])] = true
	_surfaces = kept
	for key2 in drop.keys():
		if not _xf.has(key2):
			continue
		var gone: Dictionary = drop[key2]
		var list: Array = _xf[key2]
		var remain: Array = []
		for n in list.size():
			if gone.has(n):
				continue
			remain.append(list[n])
		if remain.is_empty():
			_xf.erase(key2)
		else:
			_xf[key2] = remain
	_fill_dropped_walks(dropped, corridors)


func _add_corner_notches(out: Array[Rect2]) -> void:
	var sides: Array[float] = [1.0, -1.0]
	var meshed: bool = _mesh.has("walk_corner") and _mesh.has("walk_corner_m")
	for center in _paved_crosses:
		for sx in sides:
			for sz in sides:
				if not meshed:
					out.append(_corner_rect(center, sx, sz))
					continue
				var at := Vector3(center.x + sx * HALF, 0.0, center.y + sz * HALF)
				var along := Vector3(0.0, 0.0, sz)
				var outward := Vector3(sx, 0.0, 0.0)
				var rect := _corner_footprint(at, along, outward)
				out.append(rect)
				_walk_corners.append({
					"at": at,
					"along": along,
					"outward": outward,
					"rect": rect,
				})


func _corner_footprint(at: Vector3, along: Vector3, outward: Vector3) -> Rect2:
	var far: Vector3 = at + along * CORNER_ALONG
	var side: Vector3 = at + outward * WALK_W
	var far_side: Vector3 = far + outward * WALK_W
	return _bounds4(at, far, side, far_side)


func _corner_hits(rect: Rect2) -> bool:
	for spec in _walk_corners:
		var have: Rect2 = spec["rect"]
		var pen: Vector2 = _rect_pen(rect, have)
		if pen.x > 0.15 and pen.y > 0.15:
			return true
	return false


func _corner_taken(at: Vector3) -> bool:
	for spec in _walk_corners:
		var have: Vector3 = spec["at"]
		if have.distance_squared_to(at) < 0.16:
			return true
	return false


func _place_walk_corners() -> void:
	for spec in _walk_corners:
		var at: Vector3 = spec["at"]
		var along: Vector3 = spec["along"]
		var outward: Vector3 = spec["outward"]
		var kind := "walk_corner"
		var side: Vector3 = outward
		if Basis(along, Vector3.UP, outward).determinant() < 0.0:
			kind = "walk_corner_m"
			side = -outward
		if not _mesh.has(kind):
			continue
		var chunk: Vector2i = _Layout.chunk_of(at.x, at.z)
		var key := "%d|%d|%s" % [chunk.x, chunk.y, kind]
		if not _xf.has(key):
			_xf[key] = []
		var basis := Basis(along, Vector3.UP, side)
		var list: Array = _xf[key]
		var index: int = list.size()
		list.append(Transform3D(basis, at))
		var faces: PackedVector3Array = _mesh_faces(kind)
		var flat := PackedVector2Array()
		var min_x: float = 1000000.0
		var max_x: float = -1000000.0
		var min_z: float = 1000000.0
		var max_z: float = -1000000.0
		for vert in faces:
			var world: Vector3 = at + basis * vert
			flat.append(Vector2(world.x, world.z))
			min_x = minf(min_x, world.x)
			max_x = maxf(max_x, world.x)
			min_z = minf(min_z, world.z)
			max_z = maxf(max_z, world.z)
		var mesh_rect := Rect2(min_x, min_z, maxf(max_x - min_x, 0.05), maxf(max_z - min_z, 0.05))
		_surfaces.append({
			"kind": kind,
			"chunk": chunk,
			"at": at,
			"angle": atan2(along.z, along.x),
			"mirrored": false,
			"key": key,
			"index": index,
			"rect": mesh_rect,
			"flat": flat,
		})
		var mid: Vector3 = at + along * (CORNER_ALONG * 0.5) + outward * (WALK_W * 0.5)
		_add_walk_box(chunk, mid, atan2(along.z, along.x), CORNER_ALONG, WALK_W)


func _corner_rect(center: Vector2, sx: float, sz: float) -> Rect2:
	var x0: float = center.x + HALF
	var z0: float = center.y + HALF
	if sx < 0.0:
		x0 = center.x - HALF - WALK_W
	if sz < 0.0:
		z0 = center.y - HALF - WALK_W
	return Rect2(x0, z0, WALK_W, WALK_W)


func _add_apron_corridors(out: Array[Rect2]) -> void:
	for apron in _aprons:
		if apron.has("gap"):
			out.append(apron["gap"])
		else:
			out.append(apron["rect"])


func _fill_dropped_walks(dropped: Array[Rect2], corridors: Array[Rect2]) -> void:
	for rect in dropped:
		var pieces: Array[Rect2] = _remainders(rect, corridors)
		for piece in pieces:
			_put_fill(piece)


func _remainders(rect: Rect2, corridors: Array[Rect2]) -> Array[Rect2]:
	var pieces: Array = [rect]
	for corridor in corridors:
		var cut: Array = []
		for piece in pieces:
			var piece_rect: Rect2 = piece
			var pen: Vector2 = _rect_pen(piece_rect, corridor)
			if pen.x <= 0.05 or pen.y <= 0.05:
				cut.append(piece_rect)
				continue
			var parts: Array = _cut_list([piece_rect], corridor)
			for part in parts:
				var part_rect: Rect2 = part
				cut.append(part_rect)
		pieces = cut
	var out: Array[Rect2] = []
	for piece2 in pieces:
		var got: Rect2 = piece2
		if got.size.x < 0.2 or got.size.y < 0.2:
			continue
		out.append(got)
	return out


func _fill_cross_corners() -> void:
	var seen: Dictionary = {}
	var sides: Array[float] = [1.0, -1.0]
	if not (_mesh.has("walk_corner") and _mesh.has("walk_corner_m")):
		for center in _paved_crosses:
			for sx in sides:
				for sz in sides:
					_put_corner_fill(_corner_rect(center, sx, sz), seen)
	for mouth_rect in _mouth_corners:
		_put_corner_fill(mouth_rect, seen)


func _put_corner_fill(rect: Rect2, seen: Dictionary) -> void:
	var key := "%d|%d" % [int(round(rect.position.x * 10.0)), int(round(rect.position.y * 10.0))]
	if seen.has(key):
		return
	seen[key] = true
	_put_fill(rect)
	var mid := Vector3(rect.position.x + rect.size.x * 0.5, 0.0, rect.position.y + rect.size.y * 0.5)
	_add_walk_box(_Layout.chunk_of(mid.x, mid.z), mid, 0.0, rect.size.x, rect.size.y)


func _centered_rect(mid: Vector3, dir: Vector3, length: float, width: float) -> Rect2:
	var right: Vector3 = _right_of(dir)
	var hx: float = length * 0.5
	var hz: float = width * 0.5
	var a: Vector3 = mid + dir * hx + right * hz
	var b: Vector3 = mid + dir * hx - right * hz
	var c: Vector3 = mid - dir * hx + right * hz
	var d: Vector3 = mid - dir * hx - right * hz
	return _bounds4(a, b, c, d)


func _put_fill(rect: Rect2) -> void:
	if rect.size.x < 0.2 or rect.size.y < 0.2:
		return
	if not _mesh.has("walk_fill"):
		return
	var center := Vector3(rect.position.x + rect.size.x * 0.5, 0.0, rect.position.y + rect.size.y * 0.5)
	var chunk: Vector2i = _Layout.chunk_of(center.x, center.z)
	var key := "%d|%d|walk_fill" % [chunk.x, chunk.y]
	if not _xf.has(key):
		_xf[key] = []
	var basis := Basis(Vector3(rect.size.x, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, rect.size.y))
	var list: Array = _xf[key]
	var index: int = list.size()
	list.append(Transform3D(basis, center))
	_surfaces.append({
		"kind": "walk_fill",
		"chunk": chunk,
		"at": center,
		"angle": 0.0,
		"mirrored": false,
		"key": key,
		"index": index,
		"rect": rect,
	})


func _hits_corridor(rect: Rect2, corridors: Array[Rect2]) -> bool:
	for corridor in corridors:
		var pen: Vector2 = _rect_pen(rect, corridor)
		if pen.x > 0.05 and pen.y > 0.05:
			return true
	return false


func _split_walk_boxes(corridors: Array[Rect2]) -> void:
	var next: Array[Dictionary] = []
	for box in _walk_boxes:
		var pieces: Array[Rect2] = [_box_rect(box)]
		for corridor in corridors:
			var cut: Array[Rect2] = []
			for piece in pieces:
				var pen: Vector2 = _rect_pen(piece, corridor)
				if pen.x <= 0.05 or pen.y <= 0.05:
					cut.append(piece)
					continue
				var parts: Array = _cut_list([piece], corridor)
				for part in parts:
					var part_rect: Rect2 = part
					cut.append(part_rect)
			pieces = cut
		var angle: float = float(box["angle"])
		var chunk: Vector2i = box["chunk"]
		for piece2 in pieces:
			if piece2.size.x < 0.25 or piece2.size.y < 0.25:
				continue
			next.append(_walk_box_from_rect(chunk, piece2, angle))
	_walk_boxes = next


func _box_rect(box: Dictionary) -> Rect2:
	var mid: Vector3 = box["mid"]
	var angle: float = float(box["angle"])
	var dir: Vector3 = _dir(angle)
	var right: Vector3 = _right(angle)
	var hx: float = float(box["length"]) * 0.5
	var hz: float = float(box["width"]) * 0.5
	var c0: Vector3 = mid + dir * hx + right * hz
	var c1: Vector3 = mid + dir * hx - right * hz
	var c2: Vector3 = mid - dir * hx + right * hz
	var c3: Vector3 = mid - dir * hx - right * hz
	return _bounds4(c0, c1, c2, c3)


func _walk_box_from_rect(chunk: Vector2i, rect: Rect2, angle: float) -> Dictionary:
	var along_x: bool = absf(cos(angle)) >= absf(sin(angle))
	var length: float = rect.size.y
	var width: float = rect.size.x
	var use: float = PI * 0.5
	if along_x:
		length = rect.size.x
		width = rect.size.y
		use = 0.0
	var mid := Vector3(rect.position.x + rect.size.x * 0.5, 0.0, rect.position.y + rect.size.y * 0.5)
	return {
		"chunk": chunk,
		"mid": mid,
		"angle": use,
		"length": length,
		"width": width,
	}


func _plan_median_tiles() -> void:
	_median_tiles.clear()
	for spec in _medians:
		var tiles: int = int(spec["tiles"])
		if tiles < 2:
			continue
		var start: Vector3 = spec["start"]
		var angle: float = float(spec["angle"])
		var dir: Vector3 = _dir(angle)
		var chunk: Vector2i = spec["chunk"]
		_add_median_tile(chunk, start, angle, "median_cap")
		_add_median_tile(chunk, start, angle, "median_cap_inlay")
		var cursor: Vector3 = start + dir * TILE
		var straights: int = tiles - 2
		for n in straights:
			var at: Vector3 = cursor + dir * (TILE * float(n))
			_add_median_tile(chunk, at, angle, "median_base")
			_add_median_tile(chunk, at, angle, "median_inlay")
		var far: Vector3 = start + dir * (float(tiles) * TILE)
		_add_median_tile(chunk, far, angle + PI, "median_cap")
		_add_median_tile(chunk, far, angle + PI, "median_cap_inlay")


func _add_median_tile(chunk: Vector2i, at: Vector3, angle: float, kind: String) -> void:
	_median_tiles.append({
		"chunk": chunk,
		"at": at,
		"angle": angle,
		"kind": kind,
	})
	if kind.contains("inlay"):
		return
	if not _mesh.has(kind):
		return
	_surfaces.append({
		"kind": kind,
		"chunk": chunk,
		"at": at,
		"angle": angle,
		"mirrored": false,
		"key": "",
		"index": -1,
	})


func _audit_overlaps(seed: int) -> void:
	_tri_cache.clear()
	var rects: Array[Rect2] = []
	var kinds := PackedStringArray()
	var ats: Array[Vector2] = []
	var owners: Array[int] = []
	var surf_refs: Array = []
	var owner := 0
	for surf in _surfaces:
		var kind: String = str(surf["kind"])
		var at: Vector3 = surf["at"]
		var flat := Vector2(at.x, at.z)
		if surf.has("rect"):
			rects.append(surf["rect"])
			kinds.append(kind)
			ats.append(flat)
			owners.append(owner)
			surf_refs.append(surf)
			owner += 1
			continue
		if not _mesh.has(kind):
			continue
		rects.append(_surface_rect(surf))
		kinds.append(kind)
		ats.append(flat)
		owners.append(owner)
		surf_refs.append(surf)
		owner += 1
	for apron in _aprons:
		var apron_rect: Rect2 = apron["rect"]
		var apron_mid: Vector3 = apron["mid"]
		rects.append(apron_rect)
		kinds.append("apron")
		ats.append(Vector2(apron_mid.x, apron_mid.z))
		owners.append(owner)
		var apron_surf: Dictionary = {}
		if apron.has("flat"):
			apron_surf["flat"] = apron["flat"]
		surf_refs.append(apron_surf)
		owner += 1
	var bins: Dictionary = {}
	var cell: float = 8.0
	for i in rects.size():
		var rect: Rect2 = rects[i]
		var x0: int = int(floor(rect.position.x / cell))
		var x1: int = int(floor((rect.position.x + rect.size.x) / cell))
		var z0: int = int(floor(rect.position.y / cell))
		var z1: int = int(floor((rect.position.y + rect.size.y) / cell))
		for x in range(x0, x1 + 1):
			for z in range(z0, z1 + 1):
				var key := "%d|%d" % [x, z]
				if not bins.has(key):
					bins[key] = []
				(bins[key] as Array).append(i)
	var seen: Dictionary = {}
	var lines := PackedStringArray()
	var pairs := 0
	var worst: float = 0.0
	for key2 in bins.keys():
		var ids: Array = bins[key2]
		for a in ids.size():
			for b in range(a + 1, ids.size()):
				var ia: int = int(ids[a])
				var ib: int = int(ids[b])
				if ia == ib:
					continue
				if owners[ia] == owners[ib]:
					continue
				var lo: int = ia
				var hi: int = ib
				if ib < ia:
					lo = ib
					hi = ia
				var pair_key := "%d|%d" % [lo, hi]
				if seen.has(pair_key):
					continue
				seen[pair_key] = true
				var pen: Vector2 = _rect_pen(rects[lo], rects[hi])
				if pen.x <= 0.15 or pen.y <= 0.15:
					continue
				if not _pair_solid(surf_refs[lo], surf_refs[hi], kinds[lo], kinds[hi], rects[lo], rects[hi]):
					continue
				var depth: float = minf(pen.x, pen.y)
				pairs += 1
				if depth > worst:
					worst = depth
				if lines.size() < 8:
					var mid: Vector2 = (ats[lo] + ats[hi]) * 0.5
					lines.append("OVERLAP seed=%d a=%s b=%s at=(%.2f, %.2f) depth=%.3f" % [seed, kinds[lo], kinds[hi], mid.x, mid.y, depth])
	_overlap_pairs = pairs
	_overlap_worst = worst
	lines.append("SUMMARY seed=%d pairs=%d worst=%.3f joint=%.3f empty=%d medians=%d" % [seed, pairs, worst, _joint_error, _empty_mouths, _medians.size()])
	_append_overlap(lines)


func _loose_kind(kind: String) -> bool:
	return kind.contains("flare") or kind.contains("split") or kind.contains("turn")


func _pair_solid(a_surf, b_surf, ka: String, kb: String, a_rect: Rect2, b_rect: Rect2) -> bool:
	var a_use: bool = _use_tris(a_surf, ka)
	var b_use: bool = _use_tris(b_surf, kb)
	if not a_use and not b_use:
		return true
	if a_use and b_use:
		return _tris_hit(_pair_flat(a_surf, ka), _pair_flat(b_surf, kb))
	if a_use:
		return _tris_hit_rect(_pair_flat(a_surf, ka), b_rect)
	return _tris_hit_rect(_pair_flat(b_surf, kb), a_rect)


func _use_tris(surf, kind: String) -> bool:
	if surf == null:
		return false
	if surf.has("flat"):
		return true
	return _loose_kind(kind)


func _pair_flat(surf, kind: String) -> PackedVector2Array:
	if surf != null and surf.has("flat"):
		return surf["flat"]
	return _xz_tris(surf)


func _xz_tris(surf: Dictionary) -> PackedVector2Array:
	var cache_key := "%s|%d|%s" % [str(surf["key"]), int(surf["index"]), str(surf["kind"])]
	if _tri_cache.has(cache_key):
		return _tri_cache[cache_key]
	var mesh: Mesh = _mesh[str(surf["kind"])]
	var faces: PackedVector3Array = mesh.get_faces()
	var at: Vector3 = surf["at"]
	var angle: float = float(surf["angle"])
	var right: Vector3 = _right(angle)
	if bool(surf.get("mirrored", false)):
		right = -right
	var basis := Basis(_dir(angle), Vector3.UP, right)
	var flat := PackedVector2Array()
	var i := 0
	while i + 2 < faces.size():
		var pa: Vector3 = at + basis * faces[i]
		var pb: Vector3 = at + basis * faces[i + 1]
		var pc: Vector3 = at + basis * faces[i + 2]
		flat.append(Vector2(pa.x, pa.z))
		flat.append(Vector2(pb.x, pb.z))
		flat.append(Vector2(pc.x, pc.z))
		i += 3
	_tri_cache[cache_key] = flat
	return flat


func _tris_hit(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	var na: int = int(a.size() / 3)
	var nb: int = int(b.size() / 3)
	for i in na:
		var a0: Vector2 = a[i * 3]
		var a1: Vector2 = a[i * 3 + 1]
		var a2: Vector2 = a[i * 3 + 2]
		for j in nb:
			var b0: Vector2 = b[j * 3]
			var b1: Vector2 = b[j * 3 + 1]
			var b2: Vector2 = b[j * 3 + 2]
			if _tri_depth(a0, a1, a2, b0, b1, b2) > 0.15:
				return true
	return false


func _tris_hit_rect(tris: PackedVector2Array, rect: Rect2) -> bool:
	var x0: float = rect.position.x
	var z0: float = rect.position.y
	var x1: float = x0 + rect.size.x
	var z1: float = z0 + rect.size.y
	var r0 := Vector2(x0, z0)
	var r1 := Vector2(x1, z0)
	var r2 := Vector2(x1, z1)
	var r3 := Vector2(x0, z1)
	var n: int = int(tris.size() / 3)
	for i in n:
		var a0: Vector2 = tris[i * 3]
		var a1: Vector2 = tris[i * 3 + 1]
		var a2: Vector2 = tris[i * 3 + 2]
		if _poly_depth(_clip_poly(_clip_poly(_clip_poly(_clip_poly([a0, a1, a2], r0, r1), r1, r2), r2, r3), r3, r0)) > 0.15:
			return true
	return false


func _tri_depth(a0: Vector2, a1: Vector2, a2: Vector2, b0: Vector2, b1: Vector2, b2: Vector2) -> float:
	if _span_pen(a0.x, a1.x, a2.x, b0.x, b1.x, b2.x) <= 0.15:
		return 0.0
	if _span_pen(a0.y, a1.y, a2.y, b0.y, b1.y, b2.y) <= 0.15:
		return 0.0
	var poly: Array[Vector2] = _ccw([a0, a1, a2])
	var clip: Array[Vector2] = _ccw([b0, b1, b2])
	for i in 3:
		var c0: Vector2 = clip[i]
		var c1: Vector2 = clip[(i + 1) % 3]
		poly = _clip_poly(poly, c0, c1)
		if poly.size() < 3:
			return 0.0
	return _poly_depth(poly)


func _span_pen(a0: float, a1: float, a2: float, b0: float, b1: float, b2: float) -> float:
	var a_lo: float = minf(a0, minf(a1, a2))
	var a_hi: float = maxf(a0, maxf(a1, a2))
	var b_lo: float = minf(b0, minf(b1, b2))
	var b_hi: float = maxf(b0, maxf(b1, b2))
	return minf(a_hi, b_hi) - maxf(a_lo, b_lo)


func _ccw(pts: Array[Vector2]) -> Array[Vector2]:
	var area: float = 0.0
	for i in pts.size():
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[(i + 1) % pts.size()]
		area += p.x * q.y - q.x * p.y
	if area < 0.0:
		pts.reverse()
	return pts


func _clip_poly(poly: Array[Vector2], ax: Vector2, ay: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var n: int = poly.size()
	if n == 0:
		return out
	for i in n:
		var cur: Vector2 = poly[i]
		var prev: Vector2 = poly[(i + n - 1) % n]
		var cur_in: bool = _left_of(ax, ay, cur)
		var prev_in: bool = _left_of(ax, ay, prev)
		if cur_in:
			if not prev_in:
				out.append(_line_hit(prev, cur, ax, ay))
			out.append(cur)
		elif prev_in:
			out.append(_line_hit(prev, cur, ax, ay))
	return out


func _left_of(ax: Vector2, ay: Vector2, p: Vector2) -> bool:
	var e: Vector2 = ay - ax
	var w: Vector2 = p - ax
	return e.x * w.y - e.y * w.x >= -0.0001


func _line_hit(p: Vector2, q: Vector2, ax: Vector2, ay: Vector2) -> Vector2:
	var s: Vector2 = q - p
	var e: Vector2 = ay - ax
	var den: float = s.x * e.y - s.y * e.x
	if absf(den) < 0.0000001:
		return q
	var t: float = ((ax.x - p.x) * e.y - (ax.y - p.y) * e.x) / den
	t = clampf(t, 0.0, 1.0)
	return p + s * t


func _poly_depth(poly: Array[Vector2]) -> float:
	if poly.size() < 3:
		return 0.0
	var min_x: float = poly[0].x
	var max_x: float = poly[0].x
	var min_z: float = poly[0].y
	var max_z: float = poly[0].y
	for p in poly:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.y)
		max_z = maxf(max_z, p.y)
	return minf(max_x - min_x, max_z - min_z)


func _surface_rect(surf: Dictionary) -> Rect2:
	var kind: String = str(surf["kind"])
	var mesh: Mesh = _mesh[kind]
	var aabb: AABB = mesh.get_aabb()
	var at: Vector3 = surf["at"]
	var angle: float = float(surf["angle"])
	var right: Vector3 = _right(angle)
	if bool(surf.get("mirrored", false)):
		right = -right
	var basis := Basis(_dir(angle), Vector3.UP, right)
	var origin: Vector3 = aabb.position
	var size: Vector3 = aabb.size
	var min_x: float = 1000000.0
	var max_x: float = -1000000.0
	var min_z: float = 1000000.0
	var max_z: float = -1000000.0
	for ix in 2:
		for iy in 2:
			for iz in 2:
				var local := Vector3(origin.x + size.x * float(ix), origin.y + size.y * float(iy), origin.z + size.z * float(iz))
				var world: Vector3 = at + basis * local
				min_x = minf(min_x, world.x)
				max_x = maxf(max_x, world.x)
				min_z = minf(min_z, world.z)
				max_z = maxf(max_z, world.z)
	return Rect2(min_x, min_z, maxf(max_x - min_x, 0.01), maxf(max_z - min_z, 0.01))


func _rect_pen(a: Rect2, b: Rect2) -> Vector2:
	var ox: float = minf(a.position.x + a.size.x, b.position.x + b.size.x) - maxf(a.position.x, b.position.x)
	var oz: float = minf(a.position.y + a.size.y, b.position.y + b.size.y) - maxf(a.position.y, b.position.y)
	if ox < 0.0:
		ox = 0.0
	if oz < 0.0:
		oz = 0.0
	return Vector2(ox, oz)


func _append_overlap(lines: PackedStringArray) -> void:
	if not LaunchConfig.logs:
		return
	var path: String = ProjectSettings.globalize_path("res://../logs/road_overlap.log")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = null
	if FileAccess.file_exists(path):
		file = FileAccess.open(path, FileAccess.READ_WRITE)
	else:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("road overlap log failed: %s" % path)
		return
	file.seek_end()
	for line in lines:
		file.store_line(line)
	file.close()
