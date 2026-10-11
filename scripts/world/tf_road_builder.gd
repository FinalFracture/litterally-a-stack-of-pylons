class_name TfRoadBuilder
extends RefCounted

## Twin Falls roads, rail, street signs and landmark models, one chunk at a time.
## prepare() is main-thread. apply_cuts() and build_chunk() only read that data,
## so the terrain worker may call them. jobs() runs on the main thread and puts
## one mesh, one collision body, the signs and the landmark instances under host.
##
## Cuts only lower the heightfield (carriageway to road_y - 0.02, then a 6 m
## shoulder). Fills are skirts, not raised ground. Deck and bridge segments
## leave the terrain alone. The Perrine model is the landmark, not a second deck.

const DATA := "res://world/twin_falls/data"
const BUCKET := 64.0
const BLEND_M := 6.0
const SHAVE_M := 0.02
const LIFT_M := 0.03
const DECK_LIFT_M := 0.06
const SKIRT_GAP_M := 0.30
const LINE_W := 0.12
const RAIL_HALF := 1.9
const RAIL_GAUGE := 0.75

var _roads: Array = []
var _edges: Array = []
var _buckets: Dictionary = {}
var _junctions: Array = []
var _marks: Array = []
var _name_of: Dictionary = {}
var _by_id: Dictionary = {}
var _mats: Dictionary = {}


func prepare() -> void:
	_roads.clear()
	_edges.clear()
	_buckets.clear()
	_junctions.clear()
	_marks.clear()
	_name_of.clear()
	_by_id.clear()
	var roads: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA + "/roads.json"))
	if roads is Dictionary:
		for item in roads.get("roads", []):
			if item is Dictionary:
				_add_road(item, false)
		var rail: Array = roads.get("railways", [])
		for item in rail:
			if item is Dictionary:
				_add_road(item, true)
		for item in roads.get("intersections", []):
			if item is Dictionary:
				_junctions.append(item)
	var marks: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA + "/landmarks.json"))
	if marks is Dictionary:
		for item in marks.get("landmarks", []):
			if not (item is Dictionary):
				continue
			var path: Variant = item.get("model")
			if not (path is String) or path == "":
				continue
			var pos: Array = item.get("position", [])
			if pos.size() < 3:
				continue
			var yaw := 0.0
			if item.get("yaw_deg") != null:
				yaw = float(item["yaw_deg"])
			_marks.append({
				"id": str(item.get("id", "mark")),
				"path": path,
				"at": Vector3(float(pos[0]), float(pos[1]), float(pos[2])),
				"yaw": yaw,
			})
	_build_mats()


## Lower the carriageway of cut (and high grade) segments. Never raises a cell.
func apply_cuts(grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	if n < 2 or grid.size() != n * n or _edges.is_empty():
		return
	var reach := 16.0
	var x0 := origin.x - reach
	var z0 := origin.y - reach
	var x1 := origin.x + 500.0 + reach
	var z1 := origin.y + 500.0 + reach
	var seen := {}
	for gz in range(int(floor(z0 / BUCKET)), int(floor(z1 / BUCKET)) + 1):
		for gx in range(int(floor(x0 / BUCKET)), int(floor(x1 / BUCKET)) + 1):
			var packed: PackedInt32Array = _buckets.get(Vector2i(gx, gz), PackedInt32Array())
			for ei in packed:
				if seen.has(ei):
					continue
				seen[ei] = true
				_cut_edge(grid, origin, n, spacing, _edges[ei])


func build_chunk(coord: Vector2i, grid: PackedFloat32Array, n: int, spacing: float) -> Dictionary:
	var rect := WorldConfig.chunk_rect(coord)
	var surfs := {
		"asphalt": _Surf.new(),
		"yellow": _Surf.new(),
		"white": _Surf.new(),
		"basalt": _Surf.new(),
		"ballast": _Surf.new(),
		"rail": _Surf.new(),
		"board": _Surf.new(),
	}
	var faces := PackedVector3Array()
	for road in _roads:
		_emit_road(road, rect, grid, n, spacing, coord, surfs, faces)
	_emit_junctions(coord, surfs["asphalt"], faces)
	var signs := _signs_for(coord, surfs["board"])
	var marks: Array = []
	for mark in _marks:
		var at: Vector3 = mark["at"]
		if WorldConfig.chunk_of(at.x, at.z) == coord:
			marks.append(mark)
	var surfaces: Array = []
	for key in surfs.keys():
		var surf: _Surf = surfs[key]
		if surf.idx.is_empty():
			continue
		surfaces.append({"mat": key, "v": surf.v, "n": surf.nrm, "uv": surf.uv, "i": surf.idx})
	if surfaces.is_empty() and faces.is_empty() and signs.is_empty() and marks.is_empty():
		return {}
	return {"surfaces": surfaces, "faces": faces, "signs": signs, "marks": marks}


func jobs(host: Node3D, pack: Dictionary) -> Array[Callable]:
	var out: Array[Callable] = []
	if pack.is_empty():
		return out
	var surfaces: Array = pack.get("surfaces", [])
	if not surfaces.is_empty():
		out.append(_job_mesh.bind(host, surfaces))
	var face_v: Variant = pack.get("faces", null)
	if face_v is PackedVector3Array and (face_v as PackedVector3Array).size() >= 9:
		out.append(_job_body.bind(host, face_v))
	var signs: Array = pack.get("signs", [])
	if not signs.is_empty():
		out.append(_job_signs.bind(host, signs))
	var marks: Array = pack.get("marks", [])
	for i in marks.size():
		out.append(_job_mark.bind(host, marks[i]))
	return out


func _add_road(item: Dictionary, rail: bool) -> void:
	var raw: Array = item.get("polyline", [])
	if raw.size() < 2:
		return
	var pts := PackedVector3Array()
	for p in raw:
		if p is Array and p.size() >= 3:
			pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	if pts.size() < 2:
		return
	var lanes := int(item.get("lanes", 1))
	var width := float(item.get("lane_width_m", 3.35)) * float(maxi(lanes, 1))
	if rail:
		lanes = 0
		width = RAIL_HALF * 2.0
	var half := width * 0.5
	var kinds := PackedStringArray()
	kinds.resize(pts.size() - 1)
	kinds.fill("grade")
	if not rail:
		for seg in item.get("segments", []):
			if not (seg is Array) or seg.size() < 3:
				continue
			var a := clampi(int(seg[0]), 0, pts.size() - 2)
			var b := clampi(int(seg[1]), a + 1, pts.size() - 1)
			var kind := str(seg[2])
			for i in range(a, b):
				kinds[i] = kind
	var miters := _miters(pts, half)
	var chain := PackedFloat32Array()
	chain.resize(pts.size())
	var walked := 0.0
	for i in range(1, pts.size()):
		walked += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		chain[i] = walked
	var rec := {
		"id": str(item.get("id", "")),
		"half": half,
		"lanes": lanes,
		"pts": pts,
		"left": miters[0],
		"right": miters[1],
		"chain": chain,
		"kind": kinds,
		"rail": rail,
	}
	var ri := _roads.size()
	_roads.append(rec)
	_by_id[rec["id"]] = ri
	var nm = item.get("name")
	if nm is String and nm != "":
		_name_of[rec["id"]] = nm
	for i in pts.size() - 1:
		var edge := {
			"ax": pts[i].x, "ay": pts[i].y, "az": pts[i].z,
			"bx": pts[i + 1].x, "by": pts[i + 1].y, "bz": pts[i + 1].z,
			"half": half,
			"kind": kinds[i],
		}
		var ei := _edges.size()
		_edges.append(edge)
		_bucket_edge(ei, edge)


func _bucket_edge(ei: int, edge: Dictionary) -> void:
	var pad: float = float(edge["half"]) + BLEND_M + 4.0
	var minx := int(floor((minf(edge["ax"], edge["bx"]) - pad) / BUCKET))
	var maxx := int(floor((maxf(edge["ax"], edge["bx"]) + pad) / BUCKET))
	var minz := int(floor((minf(edge["az"], edge["bz"]) - pad) / BUCKET))
	var maxz := int(floor((maxf(edge["az"], edge["bz"]) + pad) / BUCKET))
	for gz in range(minz, maxz + 1):
		for gx in range(minx, maxx + 1):
			var key := Vector2i(gx, gz)
			var packed: PackedInt32Array = _buckets.get(key, PackedInt32Array())
			packed.append(ei)
			_buckets[key] = packed


## True when a cut or a high grade would drop this block by more than `limit` metres.
## `ground_at` is (x, z) -> DEM height. Read-only, so a worker may call it.
func cuts_block(rect: Vector4, limit: float, ground_at: Callable) -> bool:
	if rect.z < rect.x or _edges.is_empty():
		return false
	var min_x := rect.x
	var min_z := rect.y
	var max_x := rect.z
	var max_z := rect.w
	var pad := 18.0
	var gx0 := int(floor((min_x - pad) / BUCKET))
	var gx1 := int(floor((max_x + pad) / BUCKET))
	var gz0 := int(floor((min_z - pad) / BUCKET))
	var gz1 := int(floor((max_z + pad) / BUCKET))
	var seen := {}
	for gz in range(gz0, gz1 + 1):
		for gx in range(gx0, gx1 + 1):
			var packed: PackedInt32Array = _buckets.get(Vector2i(gx, gz), PackedInt32Array())
			for ei in packed:
				if seen.has(ei):
					continue
				seen[ei] = true
				if _edge_drops(_edges[ei], min_x, min_z, max_x, max_z, limit, ground_at):
					return true
	return false


func _edge_drops(edge: Dictionary, min_x: float, min_z: float, max_x: float, max_z: float, limit: float, ground_at: Callable) -> bool:
	var kind := str(edge["kind"])
	if kind == "deck" or kind == "bridge" or kind == "fill":
		return false
	var ax := float(edge["ax"])
	var az := float(edge["az"])
	var bx := float(edge["bx"])
	var bz := float(edge["bz"])
	var half := float(edge["half"])
	var reach := half + BLEND_M
	var length := Vector2(bx - ax, bz - az).length()
	var steps := maxi(int(ceil(length / 4.0)), 1)
	for s in steps + 1:
		var t := float(s) / float(steps)
		var px := lerpf(ax, bx, t)
		var pz := lerpf(az, bz, t)
		var cx := clampf(px, min_x, max_x)
		var cz := clampf(pz, min_z, max_z)
		if Vector2(px - cx, pz - cz).length() > reach:
			continue
		var ground := float(ground_at.call(cx, cz))
		if ground < -70.0:
			continue
		var hit := _seg(cx, cz, ax, az, bx, bz)
		if hit.x > reach:
			continue
		var road_y := lerpf(float(edge["ay"]), float(edge["by"]), hit.y)
		var target := road_y - SHAVE_M
		if kind == "grade" and ground <= target:
			continue
		var shoulder := 0.0
		if hit.x > half:
			shoulder = smoothstep(half, reach, hit.x)
		if ground - lerpf(target, ground, shoulder) > limit:
			return true
	return false


func _cut_edge(grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, edge: Dictionary) -> void:
	var kind := str(edge["kind"])
	if kind == "deck" or kind == "bridge" or kind == "fill":
		return
	var ax := float(edge["ax"])
	var az := float(edge["az"])
	var bx := float(edge["bx"])
	var bz := float(edge["bz"])
	var half := float(edge["half"])
	var reach := half + BLEND_M
	var length := Vector2(bx - ax, bz - az).length()
	var steps := maxi(int(ceil(length / spacing)), 1)
	var rad := int(ceil(reach / spacing)) + 1
	for s in steps + 1:
		var t := float(s) / float(steps)
		var px := lerpf(ax, bx, t)
		var pz := lerpf(az, bz, t)
		var gc := int(floor((px - origin.x) / spacing))
		var gr := int(floor((pz - origin.y) / spacing))
		for dr in range(-rad, rad + 1):
			var r := gr + dr
			if r < 0 or r >= n:
				continue
			for dc in range(-rad, rad + 1):
				var c := gc + dc
				if c < 0 or c >= n:
					continue
				var x := origin.x + float(c) * spacing
				var z := origin.y + float(r) * spacing
				var hit := _seg(x, z, ax, az, bx, bz)
				if hit.x > reach:
					continue
				var road_y := lerpf(float(edge["ay"]), float(edge["by"]), hit.y)
				var target := road_y - SHAVE_M
				var i := r * n + c
				var orig := grid[i]
				if kind == "grade" and orig <= target:
					continue
				var shoulder := 0.0
				if hit.x > half:
					shoulder = smoothstep(half, reach, hit.x)
				grid[i] = minf(orig, lerpf(target, orig, shoulder))


func _emit_road(road: Dictionary, rect: Rect2, grid: PackedFloat32Array, n: int, spacing: float, _coord: Vector2i, surfs: Dictionary, faces: PackedVector3Array) -> void:
	var pts: PackedVector3Array = road["pts"]
	var left: PackedVector3Array = road["left"]
	var right: PackedVector3Array = road["right"]
	var chain: PackedFloat32Array = road["chain"]
	var kinds: PackedStringArray = road["kind"]
	var half := float(road["half"])
	var lanes := int(road["lanes"])
	var rail := bool(road["rail"])
	var origin := rect.position
	for i in pts.size() - 1:
		var span := _clip_span(pts[i], pts[i + 1], rect)
		if span.is_empty():
			continue
		var t0 := span[0]
		var t1 := span[1]
		var l0 := left[i].lerp(left[i + 1], t0)
		var l1 := left[i].lerp(left[i + 1], t1)
		var r0 := right[i].lerp(right[i + 1], t0)
		var r1 := right[i].lerp(right[i + 1], t1)
		var kind := kinds[i]
		var lift := DECK_LIFT_M if (kind == "deck" or kind == "bridge") else LIFT_M
		var c0 := chain[i] + (chain[i + 1] - chain[i]) * t0
		var c1 := chain[i] + (chain[i + 1] - chain[i]) * t1
		if rail:
			var ball: _Surf = surfs["ballast"]
			_quad(ball, l0, r0, r1, l1, c0, c1, 0.0, half * 2.0, true, faces)
			_rails(surfs["rail"], l0, r0, r1, l1, c0, c1)
			continue
		var top: _Surf = surfs["asphalt"]
		_quad(top, _up(l0, lift), _up(r0, lift), _up(r1, lift), _up(l1, lift), c0, c1, 0.0, half * 2.0, true, faces)
		if lanes >= 2:
			_line(surfs["yellow"], l0, r0, l1, r1, half, 0.0, LINE_W, lift + 0.01, c0, c1, false)
		_line(surfs["white"], l0, r0, l1, r1, half, -(half - 0.22), LINE_W, lift + 0.01, c0, c1, false)
		_line(surfs["white"], l0, r0, l1, r1, half, half - 0.22, LINE_W, lift + 0.01, c0, c1, false)
		if lanes > 2:
			var lane_w := half * 2.0 / float(lanes)
			var k := 1
			while float(k) * lane_w < half - 0.45:
				_line(surfs["white"], l0, r0, l1, r1, half, float(k) * lane_w, LINE_W, lift + 0.01, c0, c1, true)
				_line(surfs["white"], l0, r0, l1, r1, half, -float(k) * lane_w, LINE_W, lift + 0.01, c0, c1, true)
				k += 1
		if kind == "cut" or kind == "fill":
			_skirts(surfs["basalt"], l0, r0, l1, r1, grid, origin, n, spacing, faces)


func _skirts(surf: _Surf, l0: Vector3, r0: Vector3, l1: Vector3, r1: Vector3, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, faces: PackedVector3Array) -> void:
	if n < 2:
		return
	_skirt_side(surf, l0, l1, r0, grid, origin, n, spacing, faces)
	_skirt_side(surf, r0, r1, l0, grid, origin, n, spacing, faces)


func _skirt_side(surf: _Surf, a: Vector3, b: Vector3, other: Vector3, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, faces: PackedVector3Array) -> void:
	var outward := Vector3(a.x - other.x, 0.0, a.z - other.z)
	if outward.length_squared() < 0.01:
		return
	outward = outward.normalized()
	var toe_a := _ground(grid, origin, n, spacing, a.x + outward.x * BLEND_M, a.z + outward.z * BLEND_M)
	var toe_b := _ground(grid, origin, n, spacing, b.x + outward.x * BLEND_M, b.z + outward.z * BLEND_M)
	if absf(a.y - toe_a) < SKIRT_GAP_M and absf(b.y - toe_b) < SKIRT_GAP_M:
		return
	# A few centimetres clear of the heightfield so the basalt reads as a face.
	# Sit just above the blended heightfield so the face does not z-fight the cut.
	var top_a := a + Vector3(0.0, 0.08, 0.0) + outward * 0.06
	var top_b := b + Vector3(0.0, 0.08, 0.0) + outward * 0.06
	var bot_a := Vector3(a.x, toe_a + 0.08, a.z) + outward * BLEND_M
	var bot_b := Vector3(b.x, toe_b + 0.08, b.z) + outward * BLEND_M
	_wall(surf, top_a, top_b, bot_b, bot_a, true, faces)


func _rails(surf: _Surf, l0: Vector3, r0: Vector3, r1: Vector3, l1: Vector3, c0: float, c1: float) -> void:
	var across := Vector3(r0.x - l0.x, 0.0, r0.z - l0.z)
	if across.length_squared() < 0.01:
		return
	var side := across.normalized()
	for off_v in [RAIL_GAUGE, -RAIL_GAUGE]:
		var shift := side * float(off_v)
		var lift := Vector3(0.0, 0.18, 0.0)
		var hw := side * 0.06
		var a := (l0.lerp(r0, 0.5) + shift + lift)
		var b := (l1.lerp(r1, 0.5) + shift + lift)
		var empty := PackedVector3Array()
		_quad(surf, a - hw, a + hw, b + hw, b - hw, c0, c1, 0.0, 0.12, false, empty)


func _line(surf: _Surf, l0: Vector3, r0: Vector3, l1: Vector3, r1: Vector3, half: float, offset: float, width: float, lift: float, c0: float, c1: float, dashed: bool) -> void:
	var u := clampf(0.5 + offset / (half * 2.0), 0.02, 0.98)
	var hw := width / (half * 4.0)
	var a0 := l0.lerp(r0, u - hw)
	var b0 := l0.lerp(r0, u + hw)
	var a1 := l1.lerp(r1, u - hw)
	var b1 := l1.lerp(r1, u + hw)
	if not dashed:
		var empty := PackedVector3Array()
		_quad(surf, _up(a0, lift), _up(b0, lift), _up(b1, lift), _up(a1, lift), c0, c1, 0.0, 1.0, false, empty)
		return
	var span := c1 - c0
	if span < 0.05:
		return
	var period := 9.0
	var on := 3.0
	var t := c0
	while t < c1 - 0.01:
		var phase := fmod(t, period)
		if phase < 0.0:
			phase += period
		if phase >= on:
			t += period - phase
			continue
		var t_end := minf(c1, t + (on - phase))
		if t_end <= t:
			t += period
			continue
		var u0 := (t - c0) / span
		var u1 := (t_end - c0) / span
		var empty2 := PackedVector3Array()
		_quad(surf, _up(a0.lerp(a1, u0), lift), _up(b0.lerp(b1, u0), lift), _up(b0.lerp(b1, u1), lift), _up(a0.lerp(a1, u1), lift), t, t_end, 0.0, 1.0, false, empty2)
		t = t_end


func _emit_junctions(coord: Vector2i, surf: _Surf, faces: PackedVector3Array) -> void:
	for item in _junctions:
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var at := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		if WorldConfig.chunk_of(at.x, at.z) != coord:
			continue
		var radius := 4.0
		for id in item.get("roads", []):
			if not _by_id.has(str(id)):
				continue
			var road: Dictionary = _roads[int(_by_id[str(id)])]
			radius = maxf(radius, float(road["half"]) + 1.0)
		var y := at.y + SHAVE_M
		var fan := PackedVector3Array()
		var centre := WorldConfig.to_local(Vector3(at.x, y, at.z))
		fan.append(centre)
		var sides := 10
		for s in sides + 1:
			var ang := float(s) / float(sides) * TAU
			fan.append(WorldConfig.to_local(Vector3(at.x + cos(ang) * radius, y, at.z + sin(ang) * radius)))
		for s in sides:
			_tri(surf, fan[0], fan[s + 1], fan[s + 2], faces)


func _signs_for(coord: Vector2i, board: _Surf) -> Array:
	var signs: Array = []
	for item in _junctions:
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var at := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		if WorldConfig.chunk_of(at.x, at.z) != coord:
			continue
		var text := _sign_text(item.get("roads", []))
		if text == "":
			continue
		var dir := Vector3(0.0, 0.0, -1.0)
		var half := 4.0
		for id in item.get("roads", []):
			if not _by_id.has(str(id)):
				continue
			var road: Dictionary = _roads[int(_by_id[str(id)])]
			half = maxf(half, float(road["half"]) + 1.0)
			dir = _road_dir(road, at)
			break
		var side := Vector3(-dir.z, 0.0, dir.x)
		if side.length_squared() < 0.01:
			side = Vector3(1.0, 0.0, 0.0)
		side = side.normalized()
		var stand := at + side * (half + 1.4)
		stand.y = at.y
		var back := side
		var right := Vector3.UP.cross(back).normalized()
		var basis := Basis(right, Vector3.UP, back)
		var lines := text.split("\n")
		var width := 1.3
		for line in lines:
			width = maxf(width, float(line.length()) * 0.13)
		var height := float(lines.size()) * 0.36 + 0.22
		var top := 2.15
		_post(board, stand, basis)
		var centre := stand + Vector3(0.0, top, 0.0)
		var hx := basis.x * width * 0.5
		var hy := Vector3(0.0, height * 0.5, 0.0)
		var hz := basis.z * 0.03
		var empty := PackedVector3Array()
		_wall(board, centre - hx - hy + hz, centre + hx - hy + hz, centre + hx + hy + hz, centre - hx + hy + hz, false, empty)
		# Label faces -Z (toward the road). Keep it on the near side of the board.
		signs.append({
			"at": centre - basis.z * 0.04,
			"basis": basis,
			"text": text,
		})
	return signs


func _post(surf: _Surf, stand: Vector3, basis: Basis) -> void:
	var x := basis.x * 0.05
	var z := basis.z * 0.05
	var top := stand + Vector3(0.0, 2.0, 0.0)
	var empty := PackedVector3Array()
	_wall(surf, stand - x, stand + x, top + x, top - x, false, empty)
	_wall(surf, stand - z, stand + z, top + z, top - z, false, empty)


func _sign_text(ids: Array) -> String:
	var seen := {}
	var lines := PackedStringArray()
	for id in ids:
		var name := str(_name_of.get(str(id), ""))
		if name == "" or seen.has(name):
			continue
		seen[name] = true
		lines.append(name)
	return "\n".join(lines)


func _road_dir(road: Dictionary, at: Vector3) -> Vector3:
	var pts: PackedVector3Array = road["pts"]
	var best := 1.0e12
	var dir := Vector3(0.0, 0.0, -1.0)
	for i in pts.size() - 1:
		var mid := (pts[i] + pts[i + 1]) * 0.5
		var d := Vector2(mid.x - at.x, mid.z - at.z).length_squared()
		if d < best:
			best = d
			dir = pts[i + 1] - pts[i]
			dir.y = 0.0
	if dir.length_squared() < 0.01:
		return Vector3(0.0, 0.0, -1.0)
	return dir.normalized()


func _job_mesh(host: Node3D, surfaces: Array) -> void:
	if host.get_node_or_null("Roads") != null:
		return
	var mesh := ArrayMesh.new()
	var keys: PackedStringArray = []
	for surf in surfaces:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surf["v"]
		arrays[Mesh.ARRAY_NORMAL] = surf["n"]
		arrays[Mesh.ARRAY_TEX_UV] = surf["uv"]
		arrays[Mesh.ARRAY_INDEX] = surf["i"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		keys.append(str(surf["mat"]))
	for i in keys.size():
		mesh.surface_set_material(i, _mats.get(keys[i], _mats["asphalt"]))
	var inst := MeshInstance3D.new()
	inst.name = "Roads"
	inst.mesh = mesh
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	host.add_child(inst)


func _job_body(host: Node3D, faces: PackedVector3Array) -> void:
	if host.get_node_or_null("RoadBody") != null:
		return
	var body := StaticBody3D.new()
	body.name = "RoadBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.data = faces
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	host.add_child(body)


func _job_signs(host: Node3D, signs: Array) -> void:
	if host.get_node_or_null("StreetSigns") != null:
		return
	var root := Node3D.new()
	root.name = "StreetSigns"
	host.add_child(root)
	for item in signs:
		var label := Label3D.new()
		label.text = str(item["text"])
		label.font_size = 56
		label.pixel_size = 0.0055
		label.modulate = Color(0.96, 0.94, 0.88)
		label.outline_modulate = Color(0.08, 0.08, 0.08)
		label.outline_size = 8
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.position = WorldConfig.to_local(item["at"])
		label.basis = item["basis"]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		root.add_child(label)


func _job_mark(host: Node3D, mark: Dictionary) -> void:
	var node_name := "Lm_%s" % str(mark["id"])
	if host.get_node_or_null(node_name) != null:
		return
	var packed := load(str(mark["path"])) as PackedScene
	if packed == null:
		push_error("Landmark failed to load: %s" % str(mark["path"]))
		return
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return
	inst.name = node_name
	var at: Vector3 = mark["at"]
	inst.position = WorldConfig.to_local(at)
	var yaw_deg := float(mark["yaw"])
	# The v3 deck's +Z end is the south approach. Positive yaw swings that end
	# east, onto the US-93 centreline. The file stores the bearing as -1.7.
	if str(mark["id"]) == "perrine_bridge":
		yaw_deg = -yaw_deg
	inst.rotation = Vector3(0.0, deg_to_rad(yaw_deg), 0.0)
	host.add_child(inst)
	_ensure_collision(inst)


func _ensure_collision(root: Node3D) -> void:
	if root.find_child("CollisionShape3D", true, false) != null:
		return
	var body := StaticBody3D.new()
	body.name = "LandmarkBody"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	_collect_meshes(root, root, body)


func _collect_meshes(root: Node3D, node: Node, body: StaticBody3D) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var shape := mi.mesh.create_trimesh_shape()
			if shape != null:
				var col := CollisionShape3D.new()
				col.shape = shape
				col.transform = _mesh_xf(root, mi)
				body.add_child(col)
	for child in node.get_children():
		if child == body:
			continue
		_collect_meshes(root, child, body)


func _mesh_xf(root: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _build_mats() -> void:
	_mats["asphalt"] = _textured("res://materials/asphalt_02/textures/asphalt_02_diff_2k.jpg", "res://materials/asphalt_02/textures/asphalt_02_rough_2k.jpg", 0.85)
	_mats["ballast"] = _textured("res://materials/gravel_road/textures/gravel_road_diff_2k.jpg", "res://materials/gravel_road/textures/gravel_road_rough_2k.png", 0.95)
	_mats["basalt"] = _textured("res://materials/twin_falls_terrain/textures/tf_basalt_albedo_2k.jpg", "", 0.9)
	# Opaque samples of the atlas's left-hand stripes. The rest of the sheet is
	# arrows on transparent black, which would scissor a line quad into holes.
	_mats["yellow"] = _stripe(0.040, 0.054)
	_mats["white"] = _stripe(0.008, 0.024)
	var rail := StandardMaterial3D.new()
	rail.albedo_color = Color(0.22, 0.20, 0.18)
	rail.metallic = 0.65
	rail.roughness = 0.45
	_mats["rail"] = rail
	var board := StandardMaterial3D.new()
	board.albedo_color = Color(0.16, 0.20, 0.16)
	board.roughness = 0.7
	board.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["board"] = board
	var basalt: StandardMaterial3D = _mats["basalt"]
	basalt.cull_mode = BaseMaterial3D.CULL_DISABLED


func _textured(alb: String, rough: String, rough_v: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(alb) as Texture2D
	if rough != "":
		mat.roughness_texture = load(rough) as Texture2D
	mat.roughness = rough_v
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return mat


func _stripe(u0: float, u1: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://materials/road_markings/road_markings_atlas_2k.png") as Texture2D
	mat.roughness = 0.55
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.uv1_offset = Vector3((u0 + u1) * 0.5, 0.0, 0.0)
	mat.uv1_scale = Vector3(u1 - u0, 1.0, 1.0)
	return mat


func _miters(pts: PackedVector3Array, half: float) -> Array:
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	left.resize(pts.size())
	right.resize(pts.size())
	for i in pts.size():
		var prev := Vector3.ZERO
		var nxt := Vector3.ZERO
		if i > 0:
			prev = pts[i] - pts[i - 1]
		if i + 1 < pts.size():
			nxt = pts[i + 1] - pts[i]
		prev.y = 0.0
		nxt.y = 0.0
		if prev.length_squared() < 0.04:
			prev = nxt
		if nxt.length_squared() < 0.04:
			nxt = prev
		if prev.length_squared() < 0.04:
			prev = Vector3(0.0, 0.0, -1.0)
			nxt = prev
		prev = prev.normalized()
		nxt = nxt.normalized()
		var lp := Vector3(-prev.z, 0.0, prev.x)
		var ln := Vector3(-nxt.z, 0.0, nxt.x)
		var mid := lp + ln
		if mid.length_squared() < 0.04:
			mid = lp
		else:
			mid = mid.normalized()
		var m := half / clampf(mid.dot(lp), 0.4, 1.0)
		if m > half * 1.8:
			m = half
			mid = lp
		left[i] = pts[i] + mid * m
		right[i] = pts[i] - mid * m
	return [left, right]


func _clip_span(a: Vector3, b: Vector3, rect: Rect2) -> PackedFloat32Array:
	var span := Vector2(0.0, 1.0)
	var dx := b.x - a.x
	var dz := b.z - a.z
	span = _clip_plane(-dx, a.x - rect.position.x, span)
	if span.x > span.y:
		return PackedFloat32Array()
	span = _clip_plane(dx, rect.position.x + rect.size.x - a.x, span)
	if span.x > span.y:
		return PackedFloat32Array()
	span = _clip_plane(-dz, a.z - rect.position.y, span)
	if span.x > span.y:
		return PackedFloat32Array()
	span = _clip_plane(dz, rect.position.y + rect.size.y - a.z, span)
	if span.x > span.y:
		return PackedFloat32Array()
	var tmid := (span.x + span.y) * 0.5
	var mx := lerpf(a.x, b.x, tmid)
	var mz := lerpf(a.z, b.z, tmid)
	# Half-open on the far edges so a boundary segment belongs to one chunk.
	var x1 := rect.position.x + rect.size.x
	var z1 := rect.position.y + rect.size.y
	if mx < rect.position.x or mz < rect.position.y or mx >= x1 or mz >= z1:
		return PackedFloat32Array()
	var out := PackedFloat32Array()
	out.append(span.x)
	out.append(span.y)
	return out


func _clip_plane(p: float, q: float, span: Vector2) -> Vector2:
	if absf(p) < 0.0000001:
		if q < 0.0:
			return Vector2(1.0, 0.0)
		return span
	var r := q / p
	if p < 0.0:
		if r > span.y:
			return Vector2(1.0, 0.0)
		if r > span.x:
			span.x = r
	else:
		if r < span.x:
			return Vector2(1.0, 0.0)
		if r < span.y:
			span.y = r
	return span


func _quad(surf: _Surf, a: Vector3, b: Vector3, c: Vector3, d: Vector3, v0: float, v1: float, u0: float, u1: float, solid: bool, faces: PackedVector3Array) -> void:
	var n := (b - a).cross(d - a)
	var flip := n.y < 0.0
	if n.length_squared() < 0.000001:
		return
	n = n.normalized()
	if flip:
		n = -n
	var la := WorldConfig.to_local(a)
	var lb := WorldConfig.to_local(b)
	var lc := WorldConfig.to_local(c)
	var ld := WorldConfig.to_local(d)
	var base := surf.v.size()
	surf.v.append(la)
	surf.v.append(lb)
	surf.v.append(lc)
	surf.v.append(ld)
	for _i in 4:
		surf.nrm.append(n)
	var tile_v0 := v0 / 4.0
	var tile_v1 := v1 / 4.0
	var tile_u0 := u0 / 4.0
	var tile_u1 := u1 / 4.0
	surf.uv.append(Vector2(tile_u0, tile_v0))
	surf.uv.append(Vector2(tile_u1, tile_v0))
	surf.uv.append(Vector2(tile_u1, tile_v1))
	surf.uv.append(Vector2(tile_u0, tile_v1))
	if flip:
		surf.idx.append(base)
		surf.idx.append(base + 3)
		surf.idx.append(base + 2)
		surf.idx.append(base)
		surf.idx.append(base + 2)
		surf.idx.append(base + 1)
	else:
		surf.idx.append(base)
		surf.idx.append(base + 1)
		surf.idx.append(base + 2)
		surf.idx.append(base)
		surf.idx.append(base + 2)
		surf.idx.append(base + 3)
	if solid:
		if flip:
			faces.append(la)
			faces.append(ld)
			faces.append(lc)
			faces.append(la)
			faces.append(lc)
			faces.append(lb)
		else:
			faces.append(la)
			faces.append(lb)
			faces.append(lc)
			faces.append(la)
			faces.append(lc)
			faces.append(ld)


func _wall(surf: _Surf, a: Vector3, b: Vector3, c: Vector3, d: Vector3, solid: bool, faces: PackedVector3Array) -> void:
	var n := (b - a).cross(d - a)
	if n.length_squared() < 0.000001:
		return
	n = n.normalized()
	var la := WorldConfig.to_local(a)
	var lb := WorldConfig.to_local(b)
	var lc := WorldConfig.to_local(c)
	var ld := WorldConfig.to_local(d)
	var base := surf.v.size()
	surf.v.append(la)
	surf.v.append(lb)
	surf.v.append(lc)
	surf.v.append(ld)
	for _i in 4:
		surf.nrm.append(n)
	surf.uv.append(Vector2(0.0, 0.0))
	surf.uv.append(Vector2(1.0, 0.0))
	surf.uv.append(Vector2(1.0, 1.0))
	surf.uv.append(Vector2(0.0, 1.0))
	surf.idx.append(base)
	surf.idx.append(base + 1)
	surf.idx.append(base + 2)
	surf.idx.append(base)
	surf.idx.append(base + 2)
	surf.idx.append(base + 3)
	if solid:
		faces.append(la)
		faces.append(lb)
		faces.append(lc)
		faces.append(la)
		faces.append(lc)
		faces.append(ld)


func _tri(surf: _Surf, a: Vector3, b: Vector3, c: Vector3, faces: PackedVector3Array) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 0.000001:
		return
	if n.y < 0.0:
		var tmp := b
		b = c
		c = tmp
		n = -n
	n = n.normalized()
	var base := surf.v.size()
	surf.v.append(a)
	surf.v.append(b)
	surf.v.append(c)
	for _i in 3:
		surf.nrm.append(n)
	surf.uv.append(Vector2(0.5, 0.5))
	surf.uv.append(Vector2(1.0, 0.0))
	surf.uv.append(Vector2(0.0, 0.0))
	surf.idx.append(base)
	surf.idx.append(base + 1)
	surf.idx.append(base + 2)
	faces.append(a)
	faces.append(b)
	faces.append(c)


func _ground(grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, x: float, z: float) -> float:
	if n < 2 or grid.size() != n * n:
		return -80.0
	var col := (x - origin.x) / spacing
	var row := (z - origin.y) / spacing
	var max_i := float(n - 1)
	col = clampf(col, 0.0, max_i)
	row = clampf(row, 0.0, max_i)
	var c0 := int(col)
	var r0 := int(row)
	var c1 := mini(c0 + 1, n - 1)
	var r1 := mini(r0 + 1, n - 1)
	var tx := col - float(c0)
	var tz := row - float(r0)
	var h00 := grid[r0 * n + c0]
	var h10 := grid[r0 * n + c1]
	var h01 := grid[r1 * n + c0]
	var h11 := grid[r1 * n + c1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func _seg(px: float, pz: float, ax: float, az: float, bx: float, bz: float) -> Vector2:
	var abx := bx - ax
	var abz := bz - az
	var len2 := abx * abx + abz * abz
	var t := 0.0
	if len2 > 0.0001:
		t = clampf(((px - ax) * abx + (pz - az) * abz) / len2, 0.0, 1.0)
	var dx := px - (ax + abx * t)
	var dz := pz - (az + abz * t)
	return Vector2(sqrt(dx * dx + dz * dz), t)


func _up(p: Vector3, lift: float) -> Vector3:
	return Vector3(p.x, p.y + lift, p.z)


class _Surf:
	extends RefCounted
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
