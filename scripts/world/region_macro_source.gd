class_name RegionMacroSource
extends RegionSource

## Reads the Civil Engineer's region_macro.json (schema pylons-region-macro/0.x): regional
## roads (every class under "roads"), rail lines and rivers as polylines in km, converted
## to world metres (x east, z south; the same axes as the game). Indexed in a coarse grid
## so per-chunk queries stay cheap. Read-only after prepare().

@export_file("*.json") var path := "res://data/region_macro.json"

const CELL_M := 2000.0

var _features: Array[Dictionary] = []   # {id, kind, points: PackedVector2Array (m)}
var _grid: Dictionary = {}              # Vector2i -> PackedInt32Array of (feature << 12 | segment)
var loaded := false


func prepare() -> void:
	if loaded:
		return
	_features.clear()
	_grid.clear()
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_warning("Region data not found at %s; chunks get no regional features." % path)
		return
	var root: Variant = JSON.parse_string(text)
	if not (root is Dictionary):
		push_warning("Region data at %s is not a JSON object." % path)
		return
	var roads: Variant = root.get("roads", {})
	if roads is Dictionary:
		for kind in (roads as Dictionary).keys():
			for item in roads[kind]:
				if item is Dictionary and item.has("polyline_km"):
					_add(str(item.get("name", "%s-%d" % [kind, _features.size()])), str(kind), item["polyline_km"])
	var rail: Variant = root.get("rail", {})
	if rail is Dictionary:
		for line in ["mainline", "branch"]:
			if (rail as Dictionary).has(line):
				_add("rail-%s" % line, "rail", rail[line])
	for river in root.get("rivers", []):
		if river is Dictionary and river.has("polyline_km"):
			_add(str(river.get("name", "river")), "river", river["polyline_km"])
	loaded = true


func feature_count() -> int:
	return _features.size()


func _add(id: String, kind: String, km: Variant) -> void:
	if not (km is Array):
		return
	var pts := PackedVector2Array()
	for p in km:
		if p is Array and (p as Array).size() >= 2:
			pts.append(Vector2(float(p[0]) * 1000.0, float(p[1]) * 1000.0))
	if pts.size() < 2:
		return
	var fi := _features.size()
	_features.append({"id": id, "kind": kind, "points": pts})
	for si in range(pts.size() - 1):
		var a := pts[si]
		var b := pts[si + 1]
		var c0 := Vector2i(int(floor(minf(a.x, b.x) / CELL_M)), int(floor(minf(a.y, b.y) / CELL_M)))
		var c1 := Vector2i(int(floor(maxf(a.x, b.x) / CELL_M)), int(floor(maxf(a.y, b.y) / CELL_M)))
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				var key := Vector2i(cx, cz)
				var bucket: PackedInt32Array = _grid.get(key, PackedInt32Array())
				bucket.append((fi << 12) | si)
				_grid[key] = bucket


func features_in(area: Rect2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var per: Dictionary = {}
	var c0 := Vector2i(int(floor(area.position.x / CELL_M)), int(floor(area.position.y / CELL_M)))
	var c1 := Vector2i(int(floor(area.end.x / CELL_M)), int(floor(area.end.y / CELL_M)))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			for code in _grid.get(Vector2i(cx, cz), PackedInt32Array()):
				var fi: int = code >> 12
				var si: int = code & 0xfff
				var pts: PackedVector2Array = _features[fi]["points"]
				if not _seg_touches(area, pts[si], pts[si + 1]):
					continue
				if not per.has(fi):
					per[fi] = {}
				per[fi][si] = true
	var keys: Array = per.keys()
	keys.sort()
	for fi2 in keys:
		var segs: Array = (per[fi2] as Dictionary).keys()
		segs.sort()
		var pts2: PackedVector2Array = _features[fi2]["points"]
		var piece := PackedVector2Array()
		var last := -2
		for si2 in segs:
			if si2 != last + 1 and not piece.is_empty():
				out.append({"id": _features[fi2]["id"], "kind": _features[fi2]["kind"], "points": piece})
				piece = PackedVector2Array()
			if piece.is_empty():
				piece.append(pts2[si2])
			piece.append(pts2[si2 + 1])
			last = si2
		if not piece.is_empty():
			out.append({"id": _features[fi2]["id"], "kind": _features[fi2]["kind"], "points": piece})
	return out


func border_crossings(coord: Vector2i, side: int) -> Array[Dictionary]:
	var o := WorldConfig.chunk_origin(coord)
	var s := WorldConfig.CHUNK_SIZE_M
	var a: Vector2
	var b: Vector2
	match side:
		ChunkGenerator.SIDE_WEST:
			a = o; b = o + Vector2(0, s)
		ChunkGenerator.SIDE_EAST:
			a = o + Vector2(s, 0); b = o + Vector2(s, s)
		ChunkGenerator.SIDE_SOUTH:
			a = o; b = o + Vector2(s, 0)
		_:
			a = o + Vector2(0, s); b = o + Vector2(s, s)
	var out: Array[Dictionary] = []
	for f in features_in(Rect2(o, Vector2(s, s)).grow(1.0)):
		var pts: PackedVector2Array = f["points"]
		for i in range(pts.size() - 1):
			var hit: Variant = Geometry2D.segment_intersects_segment(pts[i], pts[i + 1], a, b)
			if hit == null:
				continue
			var d := pts[i + 1] - pts[i]
			out.append({"t": (hit as Vector2).distance_to(a), "id": f["id"], "kind": f["kind"], "heading": atan2(d.y, d.x)})
	out.sort_custom(func(l: Dictionary, r: Dictionary) -> bool: return float(l["t"]) < float(r["t"]))
	return out


static func _seg_touches(area: Rect2, a: Vector2, b: Vector2) -> bool:
	var box := Rect2(a, Vector2.ZERO).expand(b)
	if not area.intersects(box, true):
		return false
	if area.has_point(a) or area.has_point(b):
		return true
	var corners := [area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, corners[i], corners[(i + 1) % 4]) != null:
			return true
	return false
