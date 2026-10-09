extends Node3D

## Zero uses the world seed from LaunchConfig (fixed default, or PYLONS_SEED / --seed).
## A non-zero value here overrides it for editor experiments only.
@export var road_test_seed: int = 0

const ASPHALT := Color(0.15, 0.16, 0.17)
const GRASS := Color(0.30, 0.44, 0.22)
const GRASS_DARK := Color(0.24, 0.36, 0.18)
const SAND := Color(0.50, 0.44, 0.32)
const BANK := Color(0.34, 0.42, 0.22)
const WATER_DEEP := Color(0.07, 0.2, 0.26, 1.0)
const WATER := Color(0.14, 0.4, 0.48, 0.8)
const MARK := Color(0.82, 0.8, 0.62)
const CURB := Color(0.62, 0.6, 0.56)
const STONE := Color(0.58, 0.52, 0.46)
const BRICK := Color(0.52, 0.32, 0.26)
const CREAM := Color(0.74, 0.68, 0.56)
const BLUE := Color(0.38, 0.46, 0.52)
const GLASS := Color(0.14, 0.2, 0.28)
const CURB_H := 0.2
const MAIN_HALF := 6.6
const LOCAL_HALF := 3.3
const MAIN_KEEP := 9.6
const LOCAL_KEEP := 6.3
const RIVER_LO := -348.0
const RIVER_HI := -252.0
const SHELL_CAP := 320
const _ASPHALT_CELL := 32.0


const DETAIL_ON := 100.0
const DETAIL_OFF := 125.0
const _CONE := preload("res://scenes/player/standard_cone.tscn")
const _MINI := preload("res://scenes/player/mini_cone.tscn")
const _BARREL := preload("res://scenes/player/barrel.tscn")
const _ChunkLayout := preload("res://scripts/road_chunk_layout.gd")
const _WorldCone := preload("res://scripts/world_cone.gd")
const _Streamer := preload("res://scripts/world/chunk_streamer.gd")

var _spots: Array[Dictionary]
var _built: Array[Rect2]
var _street_x: Array[float]
var _street_z: Array[float]
var _name_x: PackedStringArray = PackedStringArray()
var _name_z: PackedStringArray = PackedStringArray()
var _segments: Array[Dictionary]
var _seq := 0
var _cursor := 0
var _detail_wait := 0.0
var _glass: StandardMaterial3D
var _grass_tex: NoiseTexture2D
var _wall_noise: NoiseTexture2D
var _asphalt: Array[Rect2] = []
var _asphalt_road: PackedStringArray = PackedStringArray()
var _asphalt_grid: Dictionary = {}
var _stall := Vector3(32.0, 0.65, -8.0)
var _rocky: ShaderMaterial
var _asphalt_free: PackedInt32Array = PackedInt32Array()
var _asphalt_by_chunk: Dictionary = {}
var _chunk_data: Dictionary = {}
var _seg_rows: Dictionary = {}
var _cone_root: Node3D
var streamer: Node


func _ready() -> void:
	# Seeded districts in the player's chunk. The hand-built districts stay in this file.
	_grass_tex = _grain()
	_tuning_block()


func _process(delta: float) -> void:
	_detail_wait += delta
	if _detail_wait < 0.3:
		return
	_detail_wait = 0.0
	var soul := get_tree().get_first_node_in_group("soul") as Node3D
	if soul == null or _spots.is_empty():
		return
	var origin := soul.global_position
	var budget := 3
	var steps := mini(_spots.size(), 20)
	for _step in steps:
		if budget <= 0:
			break
		var spot: Dictionary = _spots[_cursor]
		_cursor = (_cursor + 1) % _spots.size()
		var at: Vector3 = spot["at"]
		var dist: float = Vector2(at.x - origin.x, at.z - origin.z).length()
		var shown: bool = spot["on"]
		if not shown and dist < DETAIL_ON:
			_show_detail(spot)
			budget -= 1
		elif shown and dist > DETAIL_OFF:
			_hide_detail(spot)
			budget -= 1


func _floor() -> void:
	_slab("FloorWest", Vector3(-420.0, -0.25, 0.0), Vector3(160.0, 0.5, 1000.0), Vector3(160.2, 0.5, 1000.2), Color(0.34, 0.36, 0.34), true)
	_slab("FloorEast", Vector3(120.0, -0.25, 0.0), Vector3(760.0, 0.5, 1000.0), Vector3(760.2, 0.5, 1000.2), Color(0.34, 0.36, 0.34), true)
	_water(Vector3(-300.0, -2.2, 0.0), Vector2(70.0, 1000.0), WATER)


func _districts() -> void:
	_sheet("ParkSheet", Vector3(40.0, 0.006, -180.0), Vector3(250.0, 0.012, 190.0), _grass_mat())
	_sheet("SuburbSheet", Vector3(370.0, 0.006, 0.0), Vector3(240.0, 0.012, 860.0), _grass_mat())
	_sheet("WorksSheet", Vector3(-420.0, 0.006, 40.0), Vector3(140.0, 0.012, 240.0), _flat(Color(0.32, 0.3, 0.26)))


func _grid() -> void:
	_add_x(-450.0, "Yard Street")
	_add_x(-360.0, "Mill Street")
	_add_x(-250.0, "Hospital Street")
	_add_x(-160.0, "Bank Street")
	_add_x(-80.0, "Oak Street")
	_add_x(80.0, "Pine Street")
	_add_x(160.0, "Market Street")
	_add_x(250.0, "Elm Street")
	_add_x(340.0, "Commerce Street")
	_add_x(430.0, "Tower Street")
	_add_z(-450.0, "South Street")
	_add_z(-360.0, "Industrial Road")
	_add_z(-270.0, "Park Road")
	_add_z(-180.0, "Lake Street")
	_add_z(-90.0, "Diner Street")
	_add_z(90.0, "Police Street")
	_add_z(180.0, "School Street")
	_add_z(270.0, "North Street")
	_add_z(360.0, "Ridge Street")
	_add_z(450.0, "Limit Street")


func _add_x(x: float, road_name: String) -> void:
	_street_x.append(x)
	_name_x.append(road_name)


func _add_z(z: float, road_name: String) -> void:
	_street_z.append(z)
	_name_z.append(road_name)


func _avenues() -> void:
	_road_ns(0.0, MAIN_HALF * 2.0, true, "Hall Avenue")
	_road_ew(0.0, MAIN_HALF * 2.0, true, "Bridge Road")
	_walk_ns(0.0, MAIN_HALF)
	_walk_ew(0.0, MAIN_HALF)
	for i in _street_x.size():
		_road_ns(_street_x[i], LOCAL_HALF * 2.0, false, _name_x[i])
		_walk_ns(_street_x[i], LOCAL_HALF)
	for i in _street_z.size():
		_road_ew(_street_z[i], LOCAL_HALF * 2.0, false, _name_z[i])
		_walk_ew(_street_z[i], LOCAL_HALF)
	_sheet("LineNS", Vector3(0.0, 0.05, 0.0), Vector3(0.12, 0.01, 980.0), _flat(MARK))
	_sheet("LineWest", Vector3(-424.0, 0.05, 0.0), Vector3(148.0, 0.01, 0.12), _flat(MARK))
	_sheet("LineDeck", Vector3(-300.0, 0.05, 0.0), Vector3(110.0, 0.01, 0.12), _flat(MARK))
	_sheet("LineEast", Vector3(124.0, 0.05, 0.0), Vector3(740.0, 0.01, 0.12), _flat(MARK))


func _road_ns(x: float, width: float, main_road: bool, road_name: String) -> void:
	var y: float = 0.036 if main_road else 0.028
	_sheet("Ns%d" % int(x + 2000.0), Vector3(x, y, 0.0), Vector3(width, 0.02, 1000.0), _flat(ASPHALT))
	_remember(x, -500.0, x, 500.0, road_name, main_road)


func _road_ew(z: float, width: float, main_road: bool, road_name: String) -> void:
	var y: float = 0.036 if main_road else 0.028
	var tag: int = int(z + 2000.0)
	_sheet("EwW%d" % tag, Vector3(-424.0, y, z), Vector3(152.0, 0.02, width), _flat(ASPHALT))
	_sheet("EwE%d" % tag, Vector3(124.0, y, z), Vector3(752.0, 0.02, width), _flat(ASPHALT))
	_remember(-500.0, z, -348.0, z, road_name, main_road)
	_remember(-252.0, z, 500.0, z, road_name, main_road)
	if main_road:
		_remember(-348.0, z, -252.0, z, road_name, true)


func _walk_ns(x: float, half: float) -> void:
	var side: float = half + 0.9
	var tag: int = int(x + 3000.0)
	_sheet("SwA%d" % tag, Vector3(x - side, 0.016, 0.0), Vector3(1.8, 0.016, 1000.0), _flat(CURB))
	_sheet("SwB%d" % tag, Vector3(x + side, 0.016, 0.0), Vector3(1.8, 0.016, 1000.0), _flat(CURB))


func _walk_ew(z: float, half: float) -> void:
	var side: float = half + 0.9
	var tag: int = int(z + 4000.0)
	_sheet("SeW%d" % tag, Vector3(-424.0, 0.016, z - side), Vector3(152.0, 0.016, 1.8), _flat(CURB))
	_sheet("SeE%d" % tag, Vector3(124.0, 0.016, z - side), Vector3(752.0, 0.016, 1.8), _flat(CURB))
	_sheet("SnW%d" % tag, Vector3(-424.0, 0.016, z + side), Vector3(152.0, 0.016, 1.8), _flat(CURB))
	_sheet("SnE%d" % tag, Vector3(124.0, 0.016, z + side), Vector3(752.0, 0.016, 1.8), _flat(CURB))


func _remember(x0: float, z0: float, x1: float, z1: float, road_name: String, main_road: bool) -> void:
	_segments.append({"x0": x0, "z0": z0, "x1": x1, "z1": z1, "name": road_name, "main": main_road})


func _bridge() -> void:
	_slab("BridgeDeck", Vector3(-300.0, -0.25, 0.0), Vector3(130.0, 0.5, 13.2), Vector3(130.0, 0.5, 13.4), ASPHALT, true)
	var tower_x: Array[float] = [-348.0, -252.0]
	var tower_z: Array[float] = [11.5, -11.5]
	for x in tower_x:
		for z in tower_z:
			_slab("Pier%d_%d" % [int(x), int(z)], Vector3(x, -0.25, z), Vector3(6.0, 0.5, 5.0), Vector3(6.2, 0.5, 5.2), ASPHALT, true)
			_shell("Tower%d_%d" % [int(x), int(z)], Vector3(x, 0.0, z), Vector3(3.0, 34.0, 2.6), Color(0.45, 0.46, 0.48), "tower")
	for side in [1.0, -1.0]:
		var edge: float = side * 7.6
		_catenary(Vector3(-348.0, 30.0, edge), Vector3(-300.0, 8.2, edge), Vector3(-252.0, 30.0, edge), side)


func _landmarks() -> void:
	_try_shell("CityHall", Vector3(32.0, 0.0, 34.0), Vector3(22.0, 16.0, 16.0), Color(0.62, 0.62, 0.64), "hall")
	_face_south("CityHall")
	_try_shell("Police", Vector3(116.0, 0.0, 30.0), Vector3(20.0, 12.0, 16.0), Color(0.42, 0.46, 0.52), "police")
	_face_south("Police")
	_try_shell("Hospital", Vector3(-200.0, 0.0, 32.0), Vector3(26.0, 18.0, 16.0), Color(0.7, 0.7, 0.72), "hospital")
	_face_south("Hospital")
	_try_shell("DinerA", Vector3(26.0, 0.0, -16.0), Vector3(14.0, 6.0, 8.0), Color(0.55, 0.5, 0.46), "diner")
	_try_shell("DinerB", Vector3(50.0, 0.0, -16.0), Vector3(12.0, 5.5, 8.0), Color(0.48, 0.46, 0.44), "diner")
	_try_shell("DinerC", Vector3(-34.0, 0.0, -16.0), Vector3(14.0, 6.0, 8.0), Color(0.52, 0.48, 0.44), "diner")
	_try_shell("ScrapA", Vector3(-412.0, 0.0, 26.0), Vector3(16.0, 8.0, 12.0), Color(0.38, 0.36, 0.32), "scrap")
	_try_shell("ScrapB", Vector3(-412.0, 0.0, 58.0), Vector3(14.0, 6.0, 12.0), Color(0.34, 0.32, 0.3), "scrap")
	_reserve(11.0, 7.2, 53.0, 24.8)
	var benches := PackedFloat64Array([-36.0, -14.0, 18.0, 40.0, 62.0])
	for i in benches.size():
		_bench(Vector3(benches[i], 0.0, -150.0))
		_bench(Vector3(benches[i], 0.0, -210.0))
	var trees := PackedFloat64Array([-48.0, -24.0, 22.0, 46.0, 68.0])
	for i in trees.size():
		_tree(Vector3(trees[i], 0.0, -170.0))
		_tree(Vector3(trees[i] + 8.0, 0.0, -230.0))


func _face_south(node_name: String) -> void:
	var body: Node3D = get_node_or_null(node_name) as Node3D
	if body != null:
		body.rotation.y = PI


func _reserve(x0: float, z0: float, x1: float, z1: float) -> void:
	_built.append(Rect2(x0, z0, x1 - x0, z1 - z0))


func _fill() -> void:
	var xs: Array[float]
	var xk: Array[float]
	var zs: Array[float]
	var zk: Array[float]
	_push_dividers(_street_x, xs, xk)
	_push_dividers(_street_z, zs, zk)
	var cells: Array[Rect2]
	for i in range(xs.size() - 1):
		for j in range(zs.size() - 1):
			var x0: float = xs[i] + xk[i]
			var x1: float = xs[i + 1] - xk[i + 1]
			var z0: float = zs[j] + zk[j]
			var z1: float = zs[j + 1] - zk[j + 1]
			if x1 - x0 < 22.0 or z1 - z0 < 22.0:
				continue
			if _overlap(xs[i], xs[i + 1], RIVER_LO, RIVER_HI):
				continue
			var cx: float = (x0 + x1) * 0.5
			var cz: float = (z0 + z1) * 0.5
			if cx > -90.0 and cx < 170.0 and cz < -85.0 and cz > -275.0:
				continue
			cells.append(Rect2(x0, z0, x1 - x0, z1 - z0))
	cells.sort_custom(func(a: Rect2, b: Rect2) -> bool: return _nearer_hall(a, b))
	for cell in cells:
		if _seq >= SHELL_CAP:
			break
		_dress(cell.position.x, cell.position.x + cell.size.x, cell.position.y, cell.position.y + cell.size.y)


func _push_dividers(src: Array[float], into: Array[float], keep: Array[float]) -> void:
	var placed := false
	for value in src:
		if value > 0.0 and not placed:
			into.append(0.0)
			keep.append(MAIN_KEEP)
			placed = true
		into.append(value)
		keep.append(LOCAL_KEEP)
	if not placed:
		into.append(0.0)
		keep.append(MAIN_KEEP)


func _nearer_hall(a: Rect2, b: Rect2) -> bool:
	var ac: Vector2 = a.get_center()
	var bc: Vector2 = b.get_center()
	var da: float = Vector2(ac.x - 32.0, ac.y - 20.0).length()
	var db: float = Vector2(bc.x - 32.0, bc.y - 20.0).length()
	return da < db


func _dress(x0: float, x1: float, z0: float, z1: float) -> void:
	var cx: float = (x0 + x1) * 0.5
	var suburb: bool = cx > 240.0 or cx < -380.0
	var depth: float = 8.5 if suburb else 12.0
	_pack_x(x0, x1, z0 + depth * 0.5, depth, suburb)
	_pack_x(x0, x1, z1 - depth * 0.5, depth, suburb)
	var mid0: float = z0 + depth + 2.0
	var mid1: float = z1 - depth - 2.0
	if mid1 - mid0 > 16.0 and not suburb:
		_pack_z(mid0, mid1, x0 + 6.0, 12.0)
		_pack_z(mid0, mid1, x1 - 6.0, 12.0)


func _pack_x(x0: float, x1: float, z: float, depth: float, suburb: bool) -> void:
	var span: float = x1 - x0
	var gap: float = 3.0
	var wide: float = 11.0 if suburb else 18.0
	var count: int = int((span + gap) / (wide + gap))
	if count > 4:
		count = 4
	if count < 1 or _seq >= SHELL_CAP:
		return
	if not suburb:
		wide = minf(22.0, (span - gap * float(count - 1) - 2.0) / float(count))
	if wide < 8.0:
		return
	var total: float = wide * float(count) + gap * float(count - 1)
	var cursor: float = x0 + (span - total) * 0.5 + wide * 0.5
	for _i in count:
		_place(cursor, z, wide, depth, suburb)
		cursor += wide + gap


func _pack_z(z0: float, z1: float, x: float, depth: float) -> void:
	var span: float = z1 - z0
	var gap: float = 3.0
	var wide: float = 18.0
	var count: int = int((span + gap) / (wide + gap))
	if count > 3:
		count = 3
	if count < 1 or _seq >= SHELL_CAP:
		return
	wide = minf(22.0, (span - gap * float(count - 1) - 2.0) / float(count))
	if wide < 8.0:
		return
	var total: float = wide * float(count) + gap * float(count - 1)
	var cursor: float = z0 + (span - total) * 0.5 + wide * 0.5
	for _i in count:
		_place(x, cursor, depth, wide, false)
		cursor += wide + gap


func _place(cx: float, cz: float, w: float, d: float, suburb: bool) -> void:
	if _seq >= SHELL_CAP:
		return
	var kind := "block"
	var height: float = 10.0
	var mix: float = fmod(absf(cx * 0.17 + cz * 0.13), 4.0)
	var color := Color(0.56, 0.55, 0.53)
	if suburb or absf(cz) > 320.0 or cx < -380.0:
		kind = "house"
		height = 6.2 + fmod(absf(cx + cz), 2.3)
		color = Color(0.64, 0.58, 0.5)
	elif cz > 24.0 and absf(cx) < 210.0 and mix > 2.7:
		kind = "tower"
		height = 26.0 + fmod(absf(cx) + cz, 26.0)
		color = Color(0.45, 0.47, 0.51)
	elif absf(cx) < 230.0 and cz > -40.0:
		height = 12.0 + fmod(absf(cz + cx * 0.25), 10.0)
		color = Color(0.52, 0.53, 0.56)
	else:
		height = 8.0 + fmod(absf(cx + cz), 5.0)
		color = Color(0.58, 0.56, 0.52)
	if kind == "block" and mix < 1.2:
		color = Color(0.5, 0.45, 0.4)
	_try_shell("Block%d" % _seq, Vector3(cx, 0.0, cz), Vector3(w, height, d), color, kind)


func _depot() -> void:
	for i in 8:
		var x: float = 14.2 + float(i % 4) * 1.15
		var z: float = 16.4 + float(i / 4) * 1.25
		_cone(Vector3(x, 0.0, z))


func _bridge_cones() -> void:
	for i in 5:
		_cone(Vector3(-228.0, 0.0, 7.5 + float(i) * 0.32))


func _crossing() -> void:
	for i in 6:
		var t: float = -4.0 + float(i) * 1.6
		_paint(Vector3(t, 0.05, 5.2), Vector3(0.7, 0.012, 1.2))
		_paint(Vector3(t, 0.05, -5.2), Vector3(0.7, 0.012, 1.2))
		_paint(Vector3(5.2, 0.05, t), Vector3(1.2, 0.012, 0.7))
		_paint(Vector3(-5.2, 0.05, t), Vector3(1.2, 0.012, 0.7))


func _signpost() -> void:
	var root := Node3D.new()
	root.name = "StreetSign"
	root.position = Vector3(14.0, 0.0, 8.8)
	add_child(root)
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.08
	cyl.height = 2.4
	pole.mesh = cyl
	pole.position = Vector3(0.0, 1.2, 0.0)
	pole.material_override = _flat(Color(0.2, 0.2, 0.22))
	root.add_child(pole)
	var board := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.6, 0.7, 0.06)
	board.mesh = box
	board.position = Vector3(0.0, 2.15, 0.0)
	board.material_override = _flat(Color(0.12, 0.32, 0.28))
	root.add_child(board)
	var hall := Label3D.new()
	hall.text = "Hall Avenue"
	hall.font_size = 32
	hall.pixel_size = 0.01
	hall.position = Vector3(0.0, 2.28, 0.05)
	hall.rotation.y = PI
	root.add_child(hall)
	var bridge := Label3D.new()
	bridge.text = "Bridge Road"
	bridge.font_size = 32
	bridge.pixel_size = 0.01
	bridge.position = Vector3(0.0, 1.95, 0.05)
	bridge.rotation.y = PI
	root.add_child(bridge)


func _try_shell(node_name: String, at: Vector3, size: Vector3, color: Color, kind: String) -> void:
	if _seq >= SHELL_CAP:
		return
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	if _hits_road(at.x, at.z, hx, hz) or _hits_built(at.x, at.z, hx, hz):
		return
	_built.append(Rect2(at.x - hx, at.z - hz, size.x, size.z))
	_seq += 1
	_shell(node_name, at, size, color, kind)


func _hits_road(cx: float, cz: float, hx: float, hz: float) -> bool:
	var x0: float = cx - hx
	var x1: float = cx + hx
	var z0: float = cz - hz
	var z1: float = cz + hz
	if _overlap(x0, x1, -MAIN_KEEP, MAIN_KEEP):
		return true
	if _overlap(z0, z1, -MAIN_KEEP, MAIN_KEEP):
		return true
	for sx in _street_x:
		if _overlap(x0, x1, sx - LOCAL_KEEP, sx + LOCAL_KEEP):
			return true
	for sz in _street_z:
		if _overlap(z0, z1, sz - LOCAL_KEEP, sz + LOCAL_KEEP):
			return true
	return false


func map_segments() -> Array[Dictionary]:
	return _segments


func map_blocks() -> Array[Rect2]:
	return _built


func on_asphalt(x: float, z: float) -> bool:
	var spot := Vector2(x, z)
	var bucket: Array = _asphalt_bucket(_asphalt_cell(x, z))
	for item in bucket:
		if _asphalt[int(item)].has_point(spot):
			return true
	return false


func surface_at(x: float, z: float) -> Dictionary:
	# The road name travels with the rect. Probes must not scan every segment.
	var found := _asphalt_near(x, z)
	return {"asphalt": bool(found["asphalt"]), "off": float(found["off"]), "road": str(found["road"])}


func nearest_asphalt(x: float, z: float) -> Vector3:
	var found := _asphalt_near(x, z)
	return Vector3(float(found["x"]), 0.65, float(found["z"]))


func _asphalt_cell(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / _ASPHALT_CELL)), int(floor(z / _ASPHALT_CELL)))


func _asphalt_bucket(cell: Vector2i) -> Array:
	if not _asphalt_grid.has(cell):
		return []
	return _asphalt_grid[cell]


func _note_asphalt(area: Rect2, road_name: String) -> int:
	var index := _asphalt.size()
	if not _asphalt_free.is_empty():
		index = _asphalt_free[_asphalt_free.size() - 1]
		_asphalt_free.remove_at(_asphalt_free.size() - 1)
		_asphalt[index] = area
		_asphalt_road[index] = road_name
	else:
		_asphalt.append(area)
		_asphalt_road.append(road_name)
	var x0 := int(floor(area.position.x / _ASPHALT_CELL))
	var x1 := int(floor(area.end.x / _ASPHALT_CELL))
	var z0 := int(floor(area.position.y / _ASPHALT_CELL))
	var z1 := int(floor(area.end.y / _ASPHALT_CELL))
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var key := Vector2i(cx, cz)
			var bucket: Array
			if _asphalt_grid.has(key):
				bucket = _asphalt_grid[key]
			else:
				bucket = []
				_asphalt_grid[key] = bucket
			bucket.append(index)
	return index


## Streaming: forget one asphalt rect (its slot is reused by the next chunk).
func _drop_asphalt(index: int) -> void:
	var area: Rect2 = _asphalt[index]
	var x0 := int(floor(area.position.x / _ASPHALT_CELL))
	var x1 := int(floor(area.end.x / _ASPHALT_CELL))
	var z0 := int(floor(area.position.y / _ASPHALT_CELL))
	var z1 := int(floor(area.end.y / _ASPHALT_CELL))
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var key := Vector2i(cx, cz)
			if not _asphalt_grid.has(key):
				continue
			var bucket: Array = _asphalt_grid[key]
			bucket.erase(index)
			if bucket.is_empty():
				_asphalt_grid.erase(key)
	_asphalt[index] = Rect2(Vector2(INF, INF), Vector2.ZERO)
	_asphalt_free.append(index)


func _asphalt_near(x: float, z: float) -> Dictionary:
	var none := {"asphalt": false, "off": 0.0, "road": "open ground", "x": x, "z": z}
	if _asphalt.is_empty():
		return none
	var home := _asphalt_cell(x, z)
	var inside := _asphalt_hit(home, x, z)
	if bool(inside["hit"]):
		return {"asphalt": true, "off": 0.0, "road": str(inside["road"]), "x": x, "z": z}
	var best := {"off": 100000.0, "road": "open ground", "x": x, "z": z, "i": 2147483647}
	var ring := 0
	while ring < 40:
		if ring == 0:
			_asphalt_gap(home, x, z, best)
		else:
			var x0 := home.x - ring
			var x1 := home.x + ring
			var z0 := home.y - ring
			var z1 := home.y + ring
			for cx in range(x0, x1 + 1):
				_asphalt_gap(Vector2i(cx, z0), x, z, best)
				_asphalt_gap(Vector2i(cx, z1), x, z, best)
			for cz in range(z0 + 1, z1):
				_asphalt_gap(Vector2i(x0, cz), x, z, best)
				_asphalt_gap(Vector2i(x1, cz), x, z, best)
		if float(best["off"]) <= float(ring) * _ASPHALT_CELL:
			break
		ring += 1
	if float(best["off"]) >= 100000.0:
		for index in _asphalt.size():
			if not is_finite(_asphalt[index].position.x):
				continue
			_asphalt_gap_index(index, x, z, best)
	var on_road: bool = float(best["off"]) <= 0.001
	return {
		"asphalt": on_road,
		"off": 0.0 if on_road else float(best["off"]),
		"road": str(best["road"]),
		"x": x if on_road else float(best["x"]),
		"z": z if on_road else float(best["z"]),
	}


func _asphalt_hit(cell: Vector2i, x: float, z: float) -> Dictionary:
	var spot := Vector2(x, z)
	var bucket: Array = _asphalt_bucket(cell)
	for item in bucket:
		var index := int(item)
		if not _asphalt[index].has_point(spot):
			continue
		var rect_name := "Modular Loop"
		if index < _asphalt_road.size():
			rect_name = _asphalt_road[index]
		return {"hit": true, "road": rect_name}
	return {"hit": false, "road": ""}


func _asphalt_gap(cell: Vector2i, x: float, z: float, best: Dictionary) -> void:
	var bucket: Array = _asphalt_bucket(cell)
	for item in bucket:
		_asphalt_gap_index(int(item), x, z, best)


func _asphalt_gap_index(index: int, x: float, z: float, best: Dictionary) -> void:
	var rect: Rect2 = _asphalt[index]
	var cx: float = clampf(x, rect.position.x, rect.end.x)
	var cz: float = clampf(z, rect.position.y, rect.end.y)
	var gap: float = Vector2(x - cx, z - cz).length()
	var off: float = float(best["off"])
	if gap > off:
		return
	if gap == off and index >= int(best["i"]):
		return
	var rect_name := "Modular Loop"
	if index < _asphalt_road.size():
		rect_name = _asphalt_road[index]
	best["off"] = gap
	best["road"] = rect_name
	best["x"] = cx
	best["z"] = cz
	best["i"] = index


func parking_stall() -> Vector3:
	return _stall


func stall_rect() -> Rect2:
	return Rect2(_stall.x - 1.7, _stall.z - 3.3, 3.4, 6.6)


func map_bounds() -> Rect2:
	var min_x := _stall.x
	var max_x := _stall.x
	var min_z := _stall.z
	var max_z := _stall.z
	for seg in _segments:
		var x0: float = float(seg["x0"])
		var z0: float = float(seg["z0"])
		var x1: float = float(seg["x1"])
		var z1: float = float(seg["z1"])
		min_x = minf(min_x, minf(x0, x1))
		max_x = maxf(max_x, maxf(x0, x1))
		min_z = minf(min_z, minf(z0, z1))
		max_z = maxf(max_z, maxf(z0, z1))
	min_x -= 12.0
	max_x += 12.0
	min_z -= 10.0
	max_z += 10.0
	return Rect2(min_x, min_z, maxf(max_x - min_x, 20.0), maxf(max_z - min_z, 20.0))


func _tuning_block() -> void:
	# M2: the world streams in 500 m chunks, a 3x3 window around the player.
	# The start chunk is built right away (boot), its neighbours stream in the background.
	var soul := get_tree().get_first_node_in_group("soul") as Node3D
	var world_seed: int = road_test_seed if road_test_seed != 0 else LaunchConfig.world_seed
	WorldConfig.world_half_m = LaunchConfig.world_half_m
	var chunk: Vector2i = WorldConfig.clamp_chunk(LaunchConfig.start_chunk)
	_cone_root = Node3D.new()
	_cone_root.name = "WorldCones"
	add_child(_cone_root)
	streamer = _Streamer.new()
	streamer.name = "ChunkStreamer"
	add_child(streamer)
	var generator := RoadChunkGenerator.new()
	streamer.setup(self, world_seed, generator)
	var kit: RefCounted = generator.kit()
	set_meta("road_seed", world_seed)
	set_meta("road_lane_m", kit.LANE)
	set_meta("road_half_m", kit.HALF)
	set_meta("road_chunk_m", WorldConfig.CHUNK_SIZE_M)
	set_meta("signal_mats", kit.get("_signal_mats"))
	set_meta("street_bulb_mat", (kit.get("_part_mats") as Dictionary).get("bulbs_industrial", null))
	set_meta("world_half_m", WorldConfig.world_half_m)
	var data: ChunkData = streamer.load_now(chunk)
	set_current_chunk(chunk)
	var spawn: Vector3 = data.spawn
	if LaunchConfig.has_spawn_override:
		spawn = LaunchConfig.spawn_override
	set_meta("spawn_point", spawn)
	_stall = Vector3(spawn.x, 0.65, spawn.z)
	if soul != null:
		soul.global_position = spawn
		streamer.target = soul
	LaunchConfig.announce(spawn)


## The chunk the player is in (clamped to the world). Respawns stay inside it.
func set_current_chunk(chunk: Vector2i) -> void:
	set_meta("current_chunk", chunk)
	set_meta("chunk_bounds", WorldConfig.chunk_rect(chunk))


func cone_root() -> Node3D:
	return _cone_root


## Streaming: small main-thread steps that make a loaded chunk's roads queryable.
func register_jobs(coord: Vector2i, data: ChunkData) -> Array[Callable]:
	var jobs: Array[Callable] = []
	var at := 0
	while at < data.road_rects.size():
		jobs.append(_register_rects.bind(coord, data.road_rects.slice(at, at + 160)))
		at += 160
	jobs.append(_register_rest.bind(coord, data))
	return jobs


func unregister_jobs(coord: Vector2i) -> Array[Callable]:
	var jobs: Array[Callable] = [_unregister_rest.bind(coord)]
	var ids: PackedInt32Array = _asphalt_by_chunk.get(coord, PackedInt32Array())
	var at := 0
	while at < ids.size():
		jobs.append(_unregister_rects.bind(ids.slice(at, at + 160)))
		at += 160
	jobs.append(func() -> void: _asphalt_by_chunk.erase(coord))
	return jobs


func _register_rects(coord: Vector2i, rows: Array) -> void:
	var ids: PackedInt32Array = _asphalt_by_chunk.get(coord, PackedInt32Array())
	for item in rows:
		ids.append(_note_asphalt(item["area"], str(item["name"])))
	_asphalt_by_chunk[coord] = ids


func _unregister_rects(ids: PackedInt32Array) -> void:
	for index in ids:
		_drop_asphalt(index)


func _register_rest(coord: Vector2i, data: ChunkData) -> void:
	var segs: Array[Dictionary] = []
	for seg in data.road_segments:
		var a: Vector3 = seg["from"]
		var b: Vector3 = seg["to"]
		var kind: String = str(seg["kind"])
		segs.append({"x0": a.x, "z0": a.z, "x1": b.x, "z1": b.z, "name": str(seg["name"]),
			"main": kind == "" or kind == "arterial", "kind": kind})
	var blocks: Array[Rect2] = []
	for r in data.blocks:
		blocks.append(r)
	var joins: Array[Vector2] = []
	for j in data.junctions:
		joins.append(j)
	_seg_rows[coord] = [segs, blocks, joins]
	_chunk_data[coord] = data
	_rebuild_unions()


func _unregister_rest(coord: Vector2i) -> void:
	_chunk_data.erase(coord)
	_seg_rows.erase(coord)
	_rebuild_unions()


func _rebuild_unions() -> void:
	_segments.clear()
	_built.clear()
	var junctions: Array[Vector2] = []
	var keys: Array = _chunk_data.keys()
	keys.sort()
	for coord in keys:
		var rows: Array = _seg_rows[coord]
		_segments.append_array(rows[0])
		_built.append_array(rows[1])
		junctions.append_array(rows[2])
	set_meta("road_junctions", junctions)


## Loaded chunk data, keyed by chunk coords (only chunks whose registration finished).
func loaded_chunks() -> Dictionary:
	return _chunk_data


func register_road_surface(area: Rect2, road_name: String = "Modular Loop") -> void:
	_note_asphalt(area, road_name)


func register_road_segment(from: Vector3, to: Vector3, road_name: String = "Modular Loop", kind: String = "") -> void:
	var main_road: bool = kind == "" or kind == "arterial"
	_segments.append({
		"x0": from.x,
		"z0": from.z,
		"x1": to.x,
		"z1": to.z,
		"name": road_name,
		"main": main_road,
		"kind": kind,
	})


func register_road_route(points: PackedVector3Array) -> void:
	set_meta("modular_road_route", points)


func _lane_dashes(prefix: String, z: float, x_from: float, x_to: float, mat: StandardMaterial3D) -> void:
	var dash: float = 3.0
	var gap: float = 6.0
	var x: float = x_from
	var n := 0
	while x + dash <= x_to:
		_sheet("%s%d" % [prefix, n], Vector3(x + dash * 0.5, 0.045, z), Vector3(dash, 0.02, 0.12), mat)
		x += dash + gap
		n += 1


func _lane_dashes_ns(prefix: String, x: float, z_from: float, z_to: float, mat: StandardMaterial3D) -> void:
	var dash: float = 3.0
	var gap: float = 6.0
	var z: float = z_from
	var n := 0
	while z + dash <= z_to:
		_sheet("%s%d" % [prefix, n], Vector3(x, 0.045, z + dash * 0.5), Vector3(0.12, 0.02, dash), mat)
		z += dash + gap
		n += 1


func _mark_stall() -> void:
	var c := _stall
	var paint_y := 0.08
	_sheet("StallPad", Vector3(c.x, 0.05, c.z), Vector3(3.6, 0.04, 6.8), _flat(Color(0.82, 0.78, 0.66)))
	var line := _flat(Color(0.97, 0.97, 0.94))
	_sheet("StallNorth", Vector3(c.x, paint_y, c.z + 3.3), Vector3(3.6, 0.025, 0.12), line)
	_sheet("StallSouth", Vector3(c.x, paint_y, c.z - 3.3), Vector3(3.6, 0.025, 0.12), line)
	_sheet("StallWest", Vector3(c.x - 1.74, paint_y, c.z), Vector3(0.12, 0.025, 6.8), line)
	_sheet("StallEast", Vector3(c.x + 1.74, paint_y, c.z), Vector3(0.12, 0.025, 6.8), line)
	var mouth := _flat(Color(0.96, 0.78, 0.12))
	mouth.emission_enabled = true
	mouth.emission = Color(0.9, 0.65, 0.08)
	mouth.emission_energy_multiplier = 0.35
	_sheet("StallMouth", Vector3(c.x, paint_y + 0.01, c.z + 3.05), Vector3(2.5, 0.02, 0.22), mouth)
	_sheet("StallGuide", Vector3(c.x, paint_y, c.z + 1.7), Vector3(0.34, 0.02, 2.4), mouth)
	_stall_post("StallPostW", Vector3(c.x - 1.85, 0.0, c.z + 3.15))
	_stall_post("StallPostE", Vector3(c.x + 1.85, 0.0, c.z + 3.15))
	var sign := Label3D.new()
	sign.name = "StallSign"
	sign.text = "STALL"
	sign.font_size = 120
	sign.pixel_size = 0.012
	sign.position = Vector3(c.x, 2.55, c.z)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.modulate = Color(0.98, 0.82, 0.16)
	sign.outline_size = 18
	sign.outline_modulate = Color(0.08, 0.06, 0.04)
	add_child(sign)
	var word := Label3D.new()
	word.name = "StallWord"
	word.text = "STALL"
	word.font_size = 72
	word.pixel_size = 0.016
	word.position = Vector3(c.x, 0.16, c.z - 0.2)
	word.rotation.x = -PI * 0.5
	word.modulate = Color(0.12, 0.1, 0.08)
	add_child(word)


func _stall_post(node_name: String, at: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.13
	cyl.bottom_radius = 0.16
	cyl.height = 1.25
	mesh.mesh = cyl
	mesh.position = at + Vector3(0.0, 0.62, 0.0)
	var mat := _flat(Color(0.95, 0.42, 0.08))
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.35, 0.05)
	mat.emission_energy_multiplier = 0.45
	mesh.material_override = mat
	add_child(mesh)


func _road_rect(node_name: String, x: float, z: float, hx: float, hz: float) -> void:
	_ground(node_name, Vector3(x, -0.25, z), Vector3(hx * 2.0, 0.5, hz * 2.0), Vector3(hx * 2.0, 0.5, hz * 2.0), ASPHALT, true)
	_note_asphalt(Rect2(x - hx, z - hz, hx * 2.0, hz * 2.0), node_name)


func _tuning_cones() -> void:
	# Piles sit on grass inside the blocks. The near edge is about 43 m from the nearest lane, past the 16 m chain grab.
	_cone_depot(90.0, 90.0, 1.0)
	_cone_depot(200.0, 200.0, 1.0)


func _cone_depot(x0: float, z_near: float, side: float) -> void:
	var step: float = 1.35
	for i in 6:
		for j in 4:
			_piece("standard", Vector3(x0 + float(i) * step, 0.0, z_near + side * float(j) * step))
	var far: float = z_near + side * 6.2
	for i in 4:
		for j in 3:
			_piece("mini", Vector3(x0 + float(i) * step, 0.0, far + side * float(j) * step))
			_piece("barrel", Vector3(x0 + 6.0 + float(i) * step, 0.0, far + side * float(j) * step))
	var sign := Label3D.new()
	sign.name = "ConeSign"
	sign.text = "CONES"
	sign.font_size = 96
	sign.pixel_size = 0.014
	sign.position = Vector3(x0 + 3.4, 2.4, z_near - side * 2.2)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.modulate = Color(0.95, 0.55, 0.12)
	sign.outline_size = 16
	sign.outline_modulate = Color(0.08, 0.06, 0.04)
	add_child(sign)


func _world_cone_body(at: Vector3, yaw: float = 0.0) -> RigidBody3D:
	# World cones are knockable, bottom-heavy rigid bodies (M1, REAL-001/005). See world_cone.gd.
	var body := _WorldCone.new() as RigidBody3D
	body.position = at
	body.rotation.y = yaw
	add_child(body)
	return body


func _piece(kind: String, at: Vector3) -> void:
	var body := _world_cone_body(at)
	var scene: PackedScene = _CONE
	var lift: float = GameConstants.STANDARD_H * 0.5
	if kind == "mini":
		scene = _MINI
		lift = GameConstants.MINI_H * 0.5
	elif kind == "barrel":
		scene = _BARREL
		lift = GameConstants.BARREL_H * 0.5
	var piece := scene.instantiate() as Node3D
	body.add_child(piece)
	piece.position = Vector3(0.0, lift, 0.0)


func _nearest_road_name(x: float, z: float) -> String:
	var best := ""
	var best_d := 100000.0
	for seg in _segments:
		var x0: float = float(seg["x0"])
		var z0: float = float(seg["z0"])
		var x1: float = float(seg["x1"])
		var z1: float = float(seg["z1"])
		var along := Vector2(x1 - x0, z1 - z0)
		var from := Vector2(x - x0, z - z0)
		var len2: float = along.length_squared()
		var dist: float = from.length()
		if len2 >= 0.0001:
			var t: float = clampf(from.dot(along) / len2, 0.0, 1.0)
			dist = from.distance_to(along * t)
		if dist < best_d:
			best_d = dist
			best = str(seg["name"])
	if best == "":
		return "open ground"
	return best


func nearest_names(x: float, z: float) -> PackedStringArray:
	var best_x := "Hall Avenue"
	var best_dx: float = absf(x)
	for i in _street_x.size():
		var dx: float = absf(x - _street_x[i])
		if dx < best_dx:
			best_dx = dx
			best_x = _name_x[i]
	var best_z := "Bridge Road"
	var best_dz: float = absf(z)
	for i in _street_z.size():
		var dz: float = absf(z - _street_z[i])
		if dz < best_dz:
			best_dz = dz
			best_z = _name_z[i]
	var out := PackedStringArray()
	out.append(best_x)
	out.append(best_z)
	return out


func _hits_built(cx: float, cz: float, hx: float, hz: float) -> bool:
	var mine := Rect2(cx - hx, cz - hz, hx * 2.0, hz * 2.0)
	for old in _built:
		if mine.intersects(old):
			return true
	return false


func _overlap(a0: float, a1: float, b0: float, b1: float) -> bool:
	return a0 < b1 and a1 > b0


func _shell(node_name: String, at: Vector3, size: Vector3, color: Color, kind: String) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = Vector3(at.x, size.y * 0.5, at.z)
	body.collision_layer = 1
	body.collision_mask = 1
	add_child(body)
	_box_mesh(body, Vector3.ZERO, size, color, 0.86)
	var wall: MeshInstance3D = body.get_child(0) as MeshInstance3D
	if wall != null and wall.material_override is StandardMaterial3D and _wall_noise != null:
		var wall_mat: StandardMaterial3D = wall.material_override as StandardMaterial3D
		wall_mat.albedo_texture = _wall_noise
		wall_mat.uv1_scale = Vector3(0.18, 0.28, 0.18)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_spots.append({"at": Vector3(at.x, 0.0, at.z), "kind": kind, "host": body, "on": false, "size": size})


func _bench(at: Vector3) -> void:
	_spot(at, "bench")
	var body := StaticBody3D.new()
	body.position = at + Vector3(0.0, 0.4, 0.0)
	body.collision_layer = 1
	body.collision_mask = 1
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 0.8, 0.5)
	shape.shape = box
	body.add_child(shape)


func _garage() -> void:
	_reserve(-148.0, 16.0, -108.0, 44.0)
	var concrete := Color(0.52, 0.53, 0.55)
	var column := Color(0.38, 0.39, 0.42)
	for level in 4:
		var y: float = 3.4 + float(level) * 3.4
		_play_box(Vector3(-128.0, y, 32.0), Vector3(32.0, 0.22, 20.0), concrete)
	_play_box(Vector3(-128.0, 17.1, 30.0), Vector3(40.0, 0.28, 28.0), Color(0.46, 0.47, 0.5))
	_play_box(Vector3(-128.0, 8.6, 16.4), Vector3(40.0, 17.2, 0.35), column)
	_play_box(Vector3(-128.0, 8.6, 43.6), Vector3(40.0, 17.2, 0.35), column)
	_play_box(Vector3(-147.6, 8.6, 30.0), Vector3(0.35, 17.2, 28.0), column)
	_play_box(Vector3(-108.4, 11.2, 22.0), Vector3(0.35, 12.0, 12.0), column)
	_play_box(Vector3(-108.4, 11.2, 38.0), Vector3(0.35, 12.0, 12.0), column)
	for x in [-142.0, -128.0, -116.0]:
		for z in [22.0, 30.0, 38.0]:
			_play_box(Vector3(x, 8.5, z), Vector3(0.45, 17.0, 0.45), column)
	for step in 8:
		var t: float = float(step)
		_play_box(Vector3(-142.0, 0.35 + t * 0.42, 20.0 + t * 1.6), Vector3(7.0, 0.22, 1.8), Color(0.4, 0.4, 0.43))
	_sheet("GarageDrive", Vector3(-96.0, 0.03, 12.0), Vector3(28.0, 0.04, 20.0), _flat(ASPHALT))


func _playground() -> void:
	_play_post(Vector3(-34.0, 0.0, -214.0))
	_play_post(Vector3(-26.0, 0.0, -214.0))
	_play_bar(Vector3(-30.0, 2.15, -214.0))
	_play_slide(Vector3(-18.0, 0.0, -206.0))
	_play_box(Vector3(-42.0, 0.15, -206.0), Vector3(3.2, 0.3, 3.2), Color(0.72, 0.62, 0.36))


func _play_post(at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = at + Vector3(0.0, 1.1, 0.0)
	body.collision_layer = 1
	body.collision_mask = 1
	add_child(body)
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.1
	cyl.height = 2.2
	mesh.mesh = cyl
	mesh.material_override = _flat(Color(0.25, 0.28, 0.32))
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var cap := CylinderShape3D.new()
	cap.radius = 0.12
	cap.height = 2.2
	shape.shape = cap
	body.add_child(shape)


func _play_bar(at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 1
	add_child(body)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(8.2, 0.12, 0.12)
	mesh.mesh = box
	mesh.material_override = _flat(Color(0.7, 0.18, 0.14))
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var solid := BoxShape3D.new()
	solid.size = box.size
	shape.shape = solid
	body.add_child(shape)


func _play_slide(at: Vector3) -> void:
	_play_box(at + Vector3(0.0, 0.7, 0.4), Vector3(0.8, 1.4, 2.4), Color(0.2, 0.45, 0.72))
	_play_box(at + Vector3(0.0, 1.5, -0.7), Vector3(0.9, 0.2, 0.9), Color(0.85, 0.55, 0.15))


func _play_box(at: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 1
	add_child(body)
	_box_mesh(body, Vector3.ZERO, size, color, 0.7)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)


func _spot(at: Vector3, kind: String) -> void:
	_spots.append({"at": at, "kind": kind, "host": self, "on": false, "size": Vector3.ONE})


func _show_detail(spot: Dictionary) -> void:
	spot["on"] = true
	var host: Node3D = spot["host"]
	var kind: String = spot["kind"]
	var size: Vector3 = spot["size"]
	var holder := Node3D.new()
	holder.name = "NearBit"
	if kind == "bench":
		holder.position = spot["at"]
		add_child(holder)
		_box_mesh(holder, Vector3(0.0, 0.42, 0.0), Vector3(1.4, 0.08, 0.45), Color(0.4, 0.34, 0.28), 0.8)
		_box_mesh(holder, Vector3(0.0, 0.7, -0.18), Vector3(1.4, 0.4, 0.08), Color(0.4, 0.34, 0.28), 0.8)
		spot["bits"] = holder
		return
	host.add_child(holder)
	var band_h: float = minf(size.y * 0.22, 4.0)
	_box_mesh(holder, Vector3(0.0, size.y * 0.08, size.z * 0.5 + 0.05), Vector3(size.x * 0.7, band_h, 0.08), GLASS, 0.35)
	if kind == "hall":
		_box_mesh(holder, Vector3(-8.0, -size.y * 0.5 + 3.2, size.z * 0.5 + 0.4), Vector3(1.1, 6.4, 1.1), Color(0.72, 0.72, 0.74), 0.7)
		_box_mesh(holder, Vector3(8.0, -size.y * 0.5 + 3.2, size.z * 0.5 + 0.4), Vector3(1.1, 6.4, 1.1), Color(0.72, 0.72, 0.74), 0.7)
	elif kind == "police":
		_box_mesh(holder, Vector3(0.0, size.y * 0.12, size.z * 0.5 + 0.08), Vector3(2.6, 0.7, 0.08), Color(0.16, 0.28, 0.55), 0.45)
	elif kind == "hospital":
		var y: float = size.y * 0.2
		var z: float = size.z * 0.5 + 0.08
		_box_mesh(holder, Vector3(0.0, y, z), Vector3(0.5, 3.2, 0.08), Color(0.75, 0.18, 0.16), 0.5)
		_box_mesh(holder, Vector3(0.0, y, z), Vector3(3.2, 0.5, 0.08), Color(0.75, 0.18, 0.16), 0.5)
	elif kind == "diner":
		_box_mesh(holder, Vector3(0.0, -size.y * 0.5 + 3.1, size.z * 0.5 + 1.2), Vector3(size.x * 0.8, 0.12, 2.2), Color(0.72, 0.28, 0.16), 0.6)
	elif kind == "scrap":
		_box_mesh(holder, Vector3(4.0, -size.y * 0.5 + 0.6, 6.0), Vector3(2.2, 1.2, 1.4), Color(0.45, 0.32, 0.2), 0.9)
		_box_mesh(holder, Vector3(-3.0, -size.y * 0.5 + 0.4, 5.0), Vector3(1.6, 0.8, 1.6), Color(0.3, 0.32, 0.28), 0.85)
	spot["bits"] = holder


func _hide_detail(spot: Dictionary) -> void:
	spot["on"] = false
	var bits: Node = spot["bits"]
	spot["bits"] = null
	if bits != null and is_instance_valid(bits):
		bits.queue_free()


func _concrete() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.08
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.width = 64
	tex.height = 64
	tex.seamless = true
	return tex


func _park_hills() -> void:
	_wedge("HillPark", Vector3(-58.0, 0.0, -236.0), 0.15, 12.0, 16.0, 1.15, GRASS)
	_wedge("HillSouth", Vector3(28.0, 0.0, -156.0), -0.2, 14.0, 12.0, 0.9, GRASS)
	_wedge("HillSuburb", Vector3(292.0, 0.0, 28.0), 0.4, 11.0, 14.0, 1.05, GRASS)


func _street_lights() -> void:
	var z: float = -400.0
	while z <= 400.0:
		if absf(z) > 8.2:
			_lamp_post(Vector3(-7.8, 0.0, z))
			_lamp_post(Vector3(7.8, 0.0, z))
		z += 56.0
	var x: float = -400.0
	while x <= 400.0:
		if absf(x) > 8.2 and (x <= -348.0 or x >= -252.0):
			_lamp_post(Vector3(x, 0.0, -7.8))
			_lamp_post(Vector3(x, 0.0, 7.8))
		x += 56.0


func _lamp_post(at: Vector3) -> void:
	var root := StaticBody3D.new()
	root.position = at
	root.collision_layer = 1
	root.collision_mask = 1
	root.add_to_group("night_lamp")
	add_child(root)
	var shape := CollisionShape3D.new()
	var capsule := CylinderShape3D.new()
	capsule.radius = 0.16
	capsule.height = 4.2
	shape.shape = capsule
	shape.position = Vector3(0.0, 2.1, 0.0)
	root.add_child(shape)
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.08
	cyl.height = 4.2
	pole.mesh = cyl
	pole.position = Vector3(0.0, 2.1, 0.0)
	pole.material_override = _flat(Color(0.16, 0.16, 0.17))
	root.add_child(pole)
	var head := MeshInstance3D.new()
	head.name = "Head"
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 0.12, 0.28)
	head.mesh = box
	head.position = Vector3(0.0, 4.2, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.28, 0.16)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.62, 0.28)
	mat.emission_energy_multiplier = 0.0
	head.material_override = mat
	root.add_child(head)
	var glow := OmniLight3D.new()
	glow.name = "Glow"
	glow.position = Vector3(0.0, 4.15, 0.0)
	glow.light_color = Color(1.0, 0.67, 0.32)
	glow.light_energy = 0.0
	glow.omni_range = 14.0
	glow.shadow_enabled = false
	root.add_child(glow)


func _manholes() -> void:
	var z: float = -210.0
	while z <= 210.0:
		_lid(Vector3(1.4, 0.055, z))
		z += 70.0
	var x: float = -210.0
	while x <= 210.0:
		if x <= -348.0 or x >= -252.0:
			_lid(Vector3(x, 0.055, 1.4))
		x += 80.0


func _lid(at: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.42
	cyl.bottom_radius = 0.42
	cyl.height = 0.04
	mesh.mesh = cyl
	mesh.position = at
	mesh.material_override = _flat(Color(0.12, 0.12, 0.13))
	add_child(mesh)


func _shrubs() -> void:
	var spots := PackedVector3Array([
		Vector3(-48, 0, -220), Vector3(-40, 0, -228), Vector3(36, 0, -148),
		Vector3(44, 0, -140), Vector3(300, 0, 36), Vector3(308, 0, 42),
		Vector3(-70, 0, -200), Vector3(60, 0, -200),
	])
	for spot in spots:
		var mesh := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.38
		ball.height = 0.62
		mesh.mesh = ball
		mesh.position = spot + Vector3(0.0, 0.28, 0.0)
		mesh.material_override = _flat(Color(0.18, 0.36, 0.16))
		add_child(mesh)
		var bush := StaticBody3D.new()
		bush.position = spot + Vector3(0.0, 0.28, 0.0)
		bush.collision_layer = 1
		bush.collision_mask = 1
		add_child(bush)
		var shape := CollisionShape3D.new()
		var ball_shape := SphereShape3D.new()
		ball_shape.radius = 0.38
		shape.shape = ball_shape
		bush.add_child(shape)
	_tree(Vector3(-46.0, 0.0, -214.0))
	_tree(Vector3(40.0, 0.0, -142.0))
	_tree(Vector3(304.0, 0.0, 48.0))


func _catenary(a: Vector3, mid: Vector3, b: Vector3, side: float) -> void:
	var prev := a
	for i in 8:
		var t: float = float(i + 1) / 8.0
		var p: Vector3 = _sag(a, mid, b, t)
		_cable(prev, p)
		if i % 2 == 0:
			_cable(p, Vector3(p.x, 0.7, side * 6.35))
		prev = p


func _sag(a: Vector3, mid: Vector3, b: Vector3, t: float) -> Vector3:
	var ab: Vector3 = a.lerp(b, t)
	var drop: float = 1.0 - absf(t * 2.0 - 1.0)
	drop = drop * drop
	ab.y = lerpf(ab.y, mid.y, drop)
	ab.z = mid.z
	return ab


func _overpasses() -> void:
	_gantry("HallGate", Vector3(0.0, 2.55, 62.0), Vector3(18.0, 0.34, 1.1), true)
	_gantry("BridgeGate", Vector3(110.0, 2.55, 0.0), Vector3(1.1, 0.34, 18.0), false)


func _gantry(node_name: String, at: Vector3, size: Vector3, along_x: bool) -> void:
	var beam := StaticBody3D.new()
	beam.name = node_name
	beam.position = at
	beam.collision_layer = 1
	beam.collision_mask = 1
	beam.add_to_group("overhead")
	add_child(beam)
	_box_mesh(beam, Vector3.ZERO, size, Color(0.42, 0.44, 0.46), 0.7)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	beam.add_child(shape)
	var post := 8.6
	if along_x:
		_post(Vector3(-post, 0.0, at.z))
		_post(Vector3(post, 0.0, at.z))
	else:
		_post(Vector3(at.x, 0.0, -post))
		_post(Vector3(at.x, 0.0, post))


func _post(at: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.2
	cyl.height = 2.6
	mesh.mesh = cyl
	mesh.position = at + Vector3(0.0, 1.3, 0.0)
	mesh.material_override = _flat(Color(0.4, 0.42, 0.44))
	add_child(mesh)


func _cable(a: Vector3, b: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	var span: Vector3 = b - a
	box.size = Vector3(0.15, 0.15, span.length())
	mesh.mesh = box
	mesh.position = (a + b) * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.25, 0.27)
	mat.roughness = 0.6
	mesh.material_override = mat
	add_child(mesh)
	mesh.look_at(b, Vector3.UP)


func _scatter_cone_stacks() -> void:
	if not has_meta("cone_stack_sites"):
		return
	var sites: Variant = get_meta("cone_stack_sites")
	if not (sites is Array):
		return
	var index := 0
	for item in sites:
		if not (item is Dictionary):
			continue
		var spec: Dictionary = item
		var at: Vector3 = spec["at"]
		var count: int = int(spec["count"])
		var yaw: float = float(spec["yaw"])
		_cone_stack(at, count, yaw, index)
		index += 1
	LaunchConfig.log_line("Cone stacks %d" % index)


func _cone_stack(at: Vector3, count: int, yaw: float, index: int) -> void:
	var body := _world_cone_body(at, yaw)
	body.name = "ConeStack%d" % index
	var extra: float = GameConstants.STANDARD_EXTRA
	var height: float = GameConstants.STANDARD_H
	for i in count:
		var piece := _CONE.instantiate() as Node3D
		body.add_child(piece)
		var center_y: float = float(i) * extra + height * 0.5
		piece.position = Vector3(0.0, center_y, 0.0)


func _cone(at: Vector3) -> void:
	var body := _world_cone_body(at)
	var piece := _CONE.instantiate() as Node3D
	body.add_child(piece)
	piece.position = Vector3(0.0, 0.2286, 0.0)


func _grain() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.04
	noise.fractal_octaves = 2
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.width = 128
	tex.height = 128
	tex.seamless = true
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.26, 0.38, 0.2))
	ramp.set_color(1, Color(0.34, 0.48, 0.26))
	tex.color_ramp = ramp
	return tex


func _grass_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _grass_tex
	mat.albedo_color = Color(1, 1, 1)
	mat.roughness = 0.95
	return mat


func _flat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat


func _sheet(node_name: String, at: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	mesh.material_override = mat
	add_child(mesh)


func _slab(node_name: String, at: Vector3, mesh_size: Vector3, col_size: Vector3, color: Color, pavement: bool) -> void:
	_ground(node_name, at, mesh_size, col_size, color, pavement)


func _roads() -> void:
	_ground("RoadEW", Vector3(0.0, -0.25, 0.0), Vector3(88.0, 0.5, 10.0), Vector3(88.0, 0.5, 10.8), ASPHALT, true)
	_ground("RoadNSNorth", Vector3(0.0, -0.25, 23.5), Vector3(10.0, 0.5, 37.0), Vector3(10.8, 0.5, 37.6), ASPHALT, true)
	_ground("RoadNSSouth", Vector3(0.0, -0.25, -23.5), Vector3(10.0, 0.5, 37.0), Vector3(10.8, 0.5, 37.6), ASPHALT, true)
	_ground("SideRoadNorth", Vector3(24.0, -0.25, 13.5), Vector3(8.0, 0.5, 17.0), Vector3(8.6, 0.5, 17.6), ASPHALT, true)
	_ground("SideRoadSouth", Vector3(24.0, -0.25, -7.0), Vector3(8.0, 0.5, 4.0), Vector3(8.6, 0.5, 4.6), ASPHALT, true)


func _grass() -> void:
	_ground("Park", Vector3(-24.0, -0.25, 22.5), Vector3(38.0, 0.5, 35.0), Vector3(38.6, 0.5, 35.6), GRASS, false)
	_ground("NorthEastWest", Vector3(12.5, -0.25, 22.5), Vector3(15.0, 0.5, 35.0), Vector3(15.4, 0.5, 35.6), GRASS_DARK, false)
	_ground("NorthEastEast", Vector3(35.5, -0.25, 22.5), Vector3(15.0, 0.5, 35.0), Vector3(15.4, 0.5, 35.6), GRASS_DARK, false)
	_ground("NorthEastCap", Vector3(24.0, -0.25, 31.1), Vector3(8.0, 0.5, 17.8), Vector3(8.4, 0.5, 18.2), GRASS_DARK, false)
	_ground("SouthWest", Vector3(-24.0, -0.25, -22.5), Vector3(38.0, 0.5, 33.0), Vector3(38.6, 0.5, 33.6), GRASS_DARK, false)
	_ground("PondBankWest", Vector3(12.5, -0.25, -7.0), Vector3(15.0, 0.5, 4.0), Vector3(15.4, 0.5, 4.6), GRASS, false)
	_ground("PondBankEast", Vector3(33.5, -0.25, -7.0), Vector3(11.0, 0.5, 4.0), Vector3(11.4, 0.5, 4.6), GRASS, false)


func _pond() -> void:
	_wedge("PondBank", Vector3(22.0, -1.05, -18.2), 0.0, 30.0, 9.2, 1.05, BANK)
	_ground("Beach", Vector3(22.0, -1.3, -19.4), Vector3(30.0, 0.5, 2.4), Vector3(30.4, 0.5, 2.8), SAND, false)
	_water(Vector3(22.0, -1.7, -28.0), Vector2(34.0, 16.0), WATER_DEEP)
	_water(Vector3(22.0, -1.42, -28.0), Vector2(34.0, 16.0), WATER)


func _park() -> void:
	_wedge("ParkMound", Vector3(-30.0, 0.0, 18.0), 0.0, 12.0, 14.0, 1.15, GRASS)
	_ground("MoundTop", Vector3(-30.0, 1.0, 32.6), Vector3(12.0, 0.3, 4.0), Vector3(12.4, 0.5, 4.4), GRASS, false)


func _sidewalks() -> void:
	_curb("WalkNE", Vector3(12.5, 0.1, 6.1), Vector3(10.6, CURB_H, 2.2))
	_curb("WalkNEFar", Vector3(35.1, 0.1, 6.1), Vector3(9.8, CURB_H, 2.2))
	_curb("WalkEN", Vector3(6.1, 0.1, 22.6), Vector3(2.2, CURB_H, 30.8))
	_curb("WalkCornerNE", Vector3(6.1, 0.1, 6.1), Vector3(2.2, CURB_H, 2.2))
	_curb("WalkCornerSE", Vector3(6.1, 0.1, -6.1), Vector3(2.2, CURB_H, 2.2))
	_curb("WalkCornerNW", Vector3(-6.1, 0.1, 6.1), Vector3(2.2, CURB_H, 2.2))
	_curb("WalkSW", Vector3(-23.6, 0.1, -6.1), Vector3(32.8, CURB_H, 2.2))
	_curb("WalkWS", Vector3(-6.1, 0.1, -22.6), Vector3(2.2, CURB_H, 30.8))
	_curb("WalkCornerSW", Vector3(-6.1, 0.1, -6.1), Vector3(2.2, CURB_H, 2.2))
	_curb("WalkFourNW", Vector3(18.9, 0.1, 6.1), Vector3(2.2, CURB_H, 2.2))
	_curb("WalkFourNE", Vector3(29.1, 0.1, 6.1), Vector3(2.2, CURB_H, 2.2))
	_curb("WalkFourSW", Vector3(18.9, 0.1, -6.1), Vector3(2.2, CURB_H, 2.2))
	_curb("WalkFourSE", Vector3(29.1, 0.1, -6.1), Vector3(2.2, CURB_H, 2.2))
	_curb("WalkSideWest", Vector3(18.9, 0.1, 12.4), Vector3(2.2, CURB_H, 10.4))
	_curb("WalkSideEast", Vector3(29.1, 0.1, 12.4), Vector3(2.2, CURB_H, 10.4))


func _ledges() -> void:
	_curb("Fountain", Vector3(-18.0, 0.22, 26.0), Vector3(3.6, 0.44, 3.6))
	_curb("Stoop", Vector3(13.5, 0.18, 21.25), Vector3(3.4, 0.36, 1.5))
	_curb("LoadingDock", Vector3(-22.0, 0.24, -12.8), Vector3(6.0, 0.48, 1.6))


func _buildings() -> void:
	_building("NorthBlock", Vector3(13.5, 7.0, 26.0), Vector3(6.0, 14.0, 8.0), CREAM)
	_building("NorthSmall", Vector3(34.0, 2.3, 12.0), Vector3(5.0, 4.6, 4.6), BRICK)
	_building("NorthTall", Vector3(30.0, 9.0, 32.0), Vector3(7.0, 18.0, 6.5), STONE)
	_building("NorthMid", Vector3(12.0, 4.0, 34.0), Vector3(6.0, 8.0, 5.5), BLUE)
	_building("SouthBlock", Vector3(-22.0, 6.0, -18.0), Vector3(10.0, 12.0, 8.0), STONE)
	_building("SouthSmall", Vector3(-35.0, 2.0, -28.0), Vector3(4.6, 4.0, 4.4), BRICK)
	_building("SouthShop", Vector3(-34.0, 2.6, -12.0), Vector3(5.2, 5.2, 4.8), CREAM)
	_building("WestLow", Vector3(-38.0, 3.2, 8.0), Vector3(5.0, 6.4, 6.0), BLUE)
	_building("ParkShed", Vector3(-38.0, 1.7, 34.0), Vector3(4.2, 3.4, 3.8), BRICK)


func _trees() -> void:
	_tree(Vector3(-38.0, 0.0, 12.0))
	_tree(Vector3(-12.0, 0.0, 14.0))
	_tree(Vector3(-14.0, 0.0, 34.0))
	_tree(Vector3(-36.0, 0.0, 36.0))
	_tree(Vector3(-26.0, 0.0, 12.0))
	_tree(Vector3(-40.0, 0.0, 24.0))


func _markings() -> void:
	for i in 9:
		var x: float = -32.0 + float(i) * 8.0
		_paint(Vector3(x, 0.03, 0.0), Vector3(2.2, 0.02, 0.16))
	for i in 7:
		var z: float = -28.0 + float(i) * 8.0
		if absf(z) < 6.0:
			continue
		_paint(Vector3(0.0, 0.03, z), Vector3(0.16, 0.02, 2.2))
	for i in 4:
		var side_z: float = 8.0 + float(i) * 3.2
		_paint(Vector3(24.0, 0.03, side_z), Vector3(0.16, 0.02, 1.4))
	_cross_x(0.0, 4.15, 9.0)
	_cross_x(0.0, -4.15, 9.0)
	_cross_z(4.15, 0.0, 9.0)
	_cross_z(-4.15, 0.0, 9.0)
	_cross_x(24.0, 4.15, 7.0)
	_cross_x(24.0, -4.15, 7.0)
	_cross_z(20.6, 0.0, 8.0)
	_cross_z(27.4, 0.0, 8.0)
	_cross_x(24.0, 18.2, 6.4)
	_paint(Vector3(-7.2, 0.045, 1.6), Vector3(0.18, 0.02, 2.4))
	_paint(Vector3(7.2, 0.045, -1.6), Vector3(0.18, 0.02, 2.4))
	_paint(Vector3(1.6, 0.045, -7.2), Vector3(2.4, 0.02, 0.18))
	_paint(Vector3(-1.6, 0.045, 7.2), Vector3(2.4, 0.02, 0.18))
	_paint(Vector3(16.8, 0.045, 1.6), Vector3(0.18, 0.02, 2.4))
	_paint(Vector3(31.2, 0.045, -1.6), Vector3(0.18, 0.02, 2.4))
	_paint(Vector3(25.6, 0.045, -6.4), Vector3(2.4, 0.02, 0.18))
	_paint(Vector3(22.4, 0.045, 6.8), Vector3(2.4, 0.02, 0.18))


func _test_lots() -> void:
	_ground("TestSouth", Vector3(0.0, -0.25, -52.0), Vector3(100.0, 0.5, 40.0), Vector3(100.2, 0.5, 40.2), GRASS, false)
	_ground("FollowRoad", Vector3(-33.0, -0.25, -40.0), Vector3(28.0, 0.5, 8.6), Vector3(28.4, 0.5, 8.8), ASPHALT, true)
	_ground("UTurnRoad", Vector3(34.0, -0.25, -40.0), Vector3(26.0, 0.5, 9.2), Vector3(26.4, 0.5, 9.4), ASPHALT, true)
	_ground("LeftPad", Vector3(-30.0, -0.25, -56.0), Vector3(20.0, 0.5, 14.0), Vector3(20.4, 0.5, 14.4), ASPHALT, true)
	_ground("RightPad", Vector3(10.0, -0.25, -56.0), Vector3(16.0, 0.5, 14.0), Vector3(16.4, 0.5, 14.4), ASPHALT, true)
	_ground("ReverseRoad", Vector3(32.0, -0.25, -56.0), Vector3(18.0, 0.5, 4.4), Vector3(18.4, 0.5, 4.8), ASPHALT, true)


func _ground(node_name: String, at: Vector3, mesh_size: Vector3, col_size: Vector3, color: Color, pavement: bool) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 1
	if pavement:
		body.add_to_group("pavement")
	add_child(body)
	var mesh_at := Vector3.ZERO if pavement else Vector3(0.0, -0.04, 0.0)
	_box_mesh(body, mesh_at, mesh_size, color, 0.9)
	if not pavement:
		var ground_mesh := body.get_child(0) as MeshInstance3D
		if ground_mesh != null:
			ground_mesh.material_override = _rocky_cover()
			ground_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = col_size
	shape.shape = box
	body.add_child(shape)


func _rocky_cover() -> ShaderMaterial:
	if _rocky != null:
		return _rocky
	_rocky = ShaderMaterial.new()
	_rocky.shader = load("res://shaders/ground_cover.gdshader") as Shader
	_rocky.set_shader_parameter("alb", load("res://materials/rocky_terrain_02/textures/rocky_terrain_02_diff_2k.jpg"))
	_rocky.set_shader_parameter("nrm", load("res://materials/rocky_terrain_02/textures/rocky_terrain_02_nor_gl_2k.png"))
	_rocky.set_shader_parameter("rgh", load("res://materials/rocky_terrain_02/textures/rocky_terrain_02_rough_2k.png"))
	_rocky.set_shader_parameter("tint", Color(0.76, 0.88, 0.67))
	_rocky.set_shader_parameter("uv_scale", 0.22)
	return _rocky


func _curb(node_name: String, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = at
	body.collision_layer = 4
	body.collision_mask = 1
	add_child(body)
	_box_mesh(body, Vector3.ZERO, size, CURB, 0.78)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)


func _water(at: Vector3, size: Vector2, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Water"
	var plane := PlaneMesh.new()
	plane.size = size
	mesh.mesh = plane
	mesh.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.12
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	add_child(mesh)


func _building(node_name: String, at: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 1
	add_child(body)
	_box_mesh(body, Vector3.ZERO, size, color, 0.84)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var band_h: float = size.y * 0.16
	var band := Vector3(size.x * 0.72, band_h, 0.08)
	var glass_y: float = size.y * 0.08
	_box_mesh(body, Vector3(0.0, glass_y, size.z * 0.5 + 0.03), band, GLASS, 0.35)
	_box_mesh(body, Vector3(0.0, glass_y, -size.z * 0.5 - 0.03), band, GLASS, 0.35)
	_box_mesh(body, Vector3(size.x * 0.5 + 0.03, glass_y, 0.0), Vector3(0.08, band_h, size.z * 0.62), GLASS, 0.35)


func _tree(at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = at + Vector3(0.0, 0.9, 0.0)
	body.collision_layer = 1
	body.collision_mask = 1
	add_child(body)
	var trunk := MeshInstance3D.new()
	var log := CylinderMesh.new()
	log.top_radius = 0.14
	log.bottom_radius = 0.18
	log.height = 1.8
	trunk.mesh = log
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.32, 0.22, 0.14)
	trunk.material_override = bark
	body.add_child(trunk)
	var shape := CollisionShape3D.new()
	var capsule := CylinderShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.9
	shape.shape = capsule
	body.add_child(shape)
	var top := MeshInstance3D.new()
	var leaf := SphereMesh.new()
	leaf.radius = 1.35
	leaf.height = 2.1
	top.mesh = leaf
	top.position = Vector3(0.0, 1.7, 0.0)
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.18, 0.38, 0.16)
	green.roughness = 0.9
	top.material_override = green
	body.add_child(top)


func _cross_x(origin_x: float, origin_z: float, span: float) -> void:
	var count: int = int(span / 0.7)
	var left: float = origin_x - span * 0.5
	for i in count:
		var x: float = left + float(i) * 0.7 + 0.2
		_paint(Vector3(x, 0.04, origin_z), Vector3(0.32, 0.02, 1.5))


func _cross_z(origin_x: float, origin_z: float, span: float) -> void:
	var count: int = int(span / 0.7)
	var left: float = origin_z - span * 0.5
	for i in count:
		var z: float = left + float(i) * 0.7 + 0.2
		_paint(Vector3(origin_x, 0.04, z), Vector3(1.5, 0.02, 0.32))


func _paint(at: Vector3, size: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = MARK
	mat.roughness = 0.7
	mesh.material_override = mat
	add_child(mesh)


func _wedge(node_name: String, at: Vector3, yaw: float, width: float, length: float, height: float, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = at
	body.rotation.y = yaw
	body.collision_layer = 1
	body.collision_mask = 1
	add_child(body)
	var hx: float = width * 0.5
	var pts := PackedVector3Array([
		Vector3(-hx, 0.0, 0.0),
		Vector3(hx, 0.0, 0.0),
		Vector3(hx, 0.0, length),
		Vector3(-hx, 0.0, length),
		Vector3(-hx, 0.0, 0.0),
		Vector3(hx, 0.0, 0.0),
		Vector3(hx, height, length),
		Vector3(-hx, height, length),
	])
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tri(tool, pts, 4, 5, 6)
	_tri(tool, pts, 4, 6, 7)
	_tri(tool, pts, 0, 2, 1)
	_tri(tool, pts, 0, 3, 2)
	_tri(tool, pts, 1, 2, 6)
	_tri(tool, pts, 1, 6, 5)
	_tri(tool, pts, 2, 3, 7)
	_tri(tool, pts, 2, 7, 6)
	_tri(tool, pts, 3, 0, 4)
	_tri(tool, pts, 3, 4, 7)
	tool.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = tool.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.94
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var convex := ConvexPolygonShape3D.new()
	convex.points = pts
	shape.shape = convex
	body.add_child(shape)


func _tri(tool: SurfaceTool, pts: PackedVector3Array, a: int, b: int, c: int) -> void:
	tool.add_vertex(pts[a])
	tool.add_vertex(pts[b])
	tool.add_vertex(pts[c])


func _box_mesh(parent: Node3D, at: Vector3, size: Vector3, color: Color, rough: float) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mesh.material_override = mat
	parent.add_child(mesh)
