class_name RoadLabGenerator
extends TwinFallsTerrainGenerator

## Synthetic 600 m dev area on the same builder path as Twin Falls.
## prepare() still runs TfRoadBuilder. The heightfield is terrain.json, not lidar.
## Chunks outside the lab still answer with the base height so a neighbour
## query does not look like a void.

const LAB_ROADS := "res://world/twin_falls/data/road_lab/roads.json"
const LAB_TERRAIN := "res://world/twin_falls/data/road_lab/terrain.json"

var _base_y := 120.0
var _ops: Array = []


func _init() -> void:
	super._init()
	generator_name = "road_lab"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAB_TERRAIN))
	if parsed is Dictionary:
		_base_y = float(parsed.get("base_y", _base_y))
		var ops: Variant = parsed.get("ops", [])
		if ops is Array:
			_ops = ops


func prepare() -> void:
	roads_path = LAB_ROADS
	super.prepare()


func height_at(x: float, z: float) -> float:
	return _lab_height(x, z)


func _dem_at(x: float, z: float) -> float:
	return _lab_height(x, z)


func _heights(cx: int, cz: int, hi: bool) -> PackedFloat32Array:
	var n := HI_N if hi else LOW_N
	var spacing := HI_SP if hi else LOW_SP
	var origin := _data_origin(cx, cz)
	var grid := PackedFloat32Array()
	grid.resize(n * n)
	for row in n:
		var z := origin.y + float(row) * spacing
		var base := row * n
		for col in n:
			grid[base + col] = _lab_height(origin.x + float(col) * spacing, z)
	return grid


func _lab_height(x: float, z: float) -> float:
	var y := _base_y
	for item in _ops:
		if not (item is Dictionary):
			continue
		var op := str(item.get("op", ""))
		if op == "plane":
			if _inside(item, x, z):
				var z0 := float(item["z0"])
				var z1 := float(item["z1"])
				var t := 0.0 if absf(z1 - z0) < 0.01 else clampf((z - z0) / (z1 - z0), 0.0, 1.0)
				y = lerpf(float(item["y_at_z0"]), float(item["y_at_z1"]), t)
		elif op == "add":
			if _inside(item, x, z):
				y += float(item.get("dy", 0.0))
		elif op == "flat":
			if _inside(item, x, z):
				y = float(item["y"])
		elif op == "slot":
			y = _slot(item, x, z, y)
		elif op == "drop_north":
			y = _drop_north(item, x, z, y)
	return y


func _inside(item: Dictionary, x: float, z: float) -> bool:
	return x >= float(item["x0"]) and x <= float(item["x1"]) and z >= float(item["z0"]) and z <= float(item["z1"])


func _slot(item: Dictionary, x: float, z: float, y: float) -> float:
	var x0 := float(item["x0"])
	var x1 := float(item["x1"])
	var z0 := float(item["z0"])
	var z1 := float(item["z1"])
	if x < x0 or x > x1 or z < z0 or z > z1:
		return y
	var inset := minf(minf(x - x0, x1 - x), minf(z - z0, z1 - z))
	var lip := maxf(float(item.get("lip_m", 6.0)), 0.1)
	var floor_y := float(item["floor_y"])
	if inset >= lip:
		return floor_y
	return lerpf(y, floor_y, inset / lip)


func _drop_north(item: Dictionary, x: float, z: float, y: float) -> float:
	var x0 := float(item["x0"])
	var x1 := float(item["x1"])
	if x < x0 or x > x1:
		return y
	var line := float(item["z_line"])
	if z > line:
		return y
	var lip := maxf(float(item.get("lip_m", 5.0)), 0.1)
	var depth := line - z
	var floor_y := float(item["floor_y"])
	if depth >= lip:
		return floor_y
	return lerpf(y, floor_y, depth / lip)
