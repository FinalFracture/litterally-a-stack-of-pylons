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
## Ribbon sits this far above the drawn heightfield. Deck and bridge keep their grade.
const ROAD_CLEAR_M := 0.05
## v4 lanes sit on the polyline (142.76). A higher lift steps the approach off the deck.
const DECK_LIFT_M := 0.0
const SKIRT_GAP_M := 0.30
const LINE_W := 0.12
const RAIL_HALF := 1.9
## Half of 1.435 m standard gauge. Overwritten from railways[].gauge_m when present.
const RAIL_GAUGE := 0.7175
const GRADE_TAIL_M := 54.0
const RAMP_TOP := Vector3(2445.0, -3.74, -6757.0)
const SIGN_SCENE := "res://Models/street_furniture/tf_street_name_sign.glb"
const RAMP_SCENE := "res://Models/twin_falls/tf_boat_ramp_8m_v2.glb"
const DOCK_SCENE := "res://Models/twin_falls/tf_launch_dock_3x15m.glb"
const FONT_PATH := "res://Models/street_furniture/_fonts/Overpass-Bold.ttf"
## v4 slots that have a matching tres. Lamp and rail stay on the glb materials.
const BRIDGE_SLOTS := {
	"bridge_deck_concrete": "res://materials/twin_falls/bridge_deck_concrete.tres",
	"bridge_road_asphalt": "res://materials/twin_falls/bridge_road_asphalt.tres",
	"bridge_steel_corten": "res://materials/twin_falls/bridge_steel_corten.tres",
	"bridge_xbrace_card": "res://materials/twin_falls/bridge_xbrace_card.tres",
}
## Minor roads ramp to the wider road over this distance so a junction has no step.
const JOIN_M := 16.0
## Footprint samples about this far apart. A plinth fills anything steeper than this.
const FOOT_STEP_M := 1.0
const PLINTH_GAP_M := 0.02
const STATION_MODULE_M := 25.0
const DROP_RAIL_M := 2.0
const GUARD_ROADS := {
	"canyon_springs_grade": true,
	"rim_road_south": true,
}

var _roads: Array = []
var _edges: Array = []
var _buckets: Dictionary = {}
var _junctions: Array = []
var _marks: Array = []
var _name_of: Dictionary = {}
var _by_id: Dictionary = {}
var _mats: Dictionary = {}
var _gauge_half := RAIL_GAUGE
var _grade_end := -1.0
var _plates: Array = []
var _font: Font


func prepare() -> void:
	_roads.clear()
	_edges.clear()
	_buckets.clear()
	_junctions.clear()
	_marks.clear()
	_name_of.clear()
	_by_id.clear()
	_plates.clear()
	_grade_end = -1.0
	_gauge_half = RAIL_GAUGE
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
			var at := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
			var yaw := 0.0
			if item.get("yaw_deg") != null:
				yaw = float(item["yaw_deg"])
			var gid := str(item.get("id", "mark"))
			if gid == "centennial_park_ramp":
				# v2 pivot is the top edge. Local -Z runs into the river.
				# Node y is water + 1.5 so about 7.5 m of the slope is submerged.
				path = RAMP_SCENE
				at = RAMP_TOP
				yaw = 0.0
			var fp := Vector2(4.0, 4.0)
			var raw_fp: Variant = item.get("footprint_m", [])
			if raw_fp is Array and (raw_fp as Array).size() >= 2:
				fp = Vector2(float((raw_fp as Array)[0]), float((raw_fp as Array)[1]))
			# The bridge origin is the water, and the falls card is outside the grid.
			var seat := gid != "perrine_bridge" and gid != "shoshone_falls_card" and gid != "centennial_park_ramp"
			_marks.append({
				"id": gid,
				"path": path,
				"at": at,
				"yaw": yaw,
				"fp": fp,
				"seat": seat,
			})
	_collect_plates()
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
	_cut_joins(grid, origin, n, spacing)


func build_chunk(coord: Vector2i, grid: PackedFloat32Array, n: int, spacing: float) -> Dictionary:
	var rect := WorldConfig.chunk_rect(coord)
	var surfs := {
		"asphalt": _Surf.new(),
		"yellow": _Surf.new(),
		"white": _Surf.new(),
		"basalt": _Surf.new(),
		"ballast": _Surf.new(),
		"rail": _Surf.new(),
		"guard": _Surf.new(),
		"board": _Surf.new(),
	}
	var faces := PackedVector3Array()
	for road in _roads:
		_emit_road(road, rect, grid, n, spacing, coord, surfs, faces)
	_emit_junctions(coord, surfs["asphalt"], faces, grid, n, spacing)
	var signs := _signs_for(coord)
	var plates: Array = []
	for plate in _plates:
		var pat: Vector3 = plate["at"]
		if WorldConfig.chunk_of(pat.x, pat.z) == coord:
			plates.append(plate)
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
	if surfaces.is_empty() and faces.is_empty() and signs.is_empty() and marks.is_empty() and plates.is_empty():
		return {}
	return {"surfaces": surfaces, "faces": faces, "signs": signs, "marks": marks, "plates": plates}


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
	var plates: Array = pack.get("plates", [])
	if not plates.is_empty():
		out.append(_job_plates.bind(host, plates))
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
	if rail:
		var gauge := float(item.get("gauge_m", 1.435))
		if gauge > 0.4:
			_gauge_half = gauge * 0.5
	if str(item.get("id", "")) == "canyon_springs_grade":
		var authored := 0.0
		for i in range(1, pts.size()):
			authored += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		_grade_end = authored
		pts = _extend_grade(pts)
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
		"advisory": _advisory_of(item, pts.size() - 1),
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


## The grade stops on the canyon floor short of the river. Continue it north to the
## south edge of the rendered ribbon and crest onto the boat-ramp head.
func _extend_grade(pts: PackedVector3Array) -> PackedVector3Array:
	var end := pts[pts.size() - 1]
	var out := pts.duplicate()
	var run: Array[Vector3] = [
		Vector3(end.x, -8.0, end.z - 25.0),
		Vector3(2448.0, -8.0, -6680.0),
		Vector3(2446.0, -8.0, -6735.0),
		Vector3(2445.0, -8.0, -6745.0),
		RAMP_TOP,
	]
	for p in run:
		out.append(p)
	return out


func _advisory_of(item: Dictionary, nseg: int) -> PackedInt32Array:
	var adv := PackedInt32Array()
	adv.resize(maxi(nseg, 0))
	var raw: Variant = item.get("advisory_mph", [])
	if not (raw is Array):
		return adv
	var rows: Array = raw
	for i in mini(rows.size(), adv.size()):
		if rows[i] != null:
			adv[i] = int(rows[i])
	return adv


func _collect_plates() -> void:
	for road in _roads:
		if bool(road["rail"]):
			continue
		var adv: PackedInt32Array = road["advisory"]
		var pts: PackedVector3Array = road["pts"]
		var i := 0
		while i < adv.size():
			if adv[i] != 15:
				i += 1
				continue
			var start := i
			while i < adv.size() and adv[i] == 15:
				i += 1
			var p: Vector3 = pts[start]
			var nxt: Vector3 = pts[mini(start + 1, pts.size() - 1)]
			var dir := nxt - p
			dir.y = 0.0
			if dir.length_squared() < 0.01:
				dir = Vector3(0.0, 0.0, -1.0)
			else:
				dir = dir.normalized()
			var side := Vector3(-dir.z, 0.0, dir.x)
			var at := p + side * (float(road["half"]) + 1.5)
			at.y = p.y
			_plates.append({"at": at, "yaw": atan2(-dir.z, dir.x)})


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
		var road_id := str(road["id"])
		var kind := kinds[i]
		var lift := DECK_LIFT_M if (kind == "deck" or kind == "bridge") else LIFT_M
		var seg_len := Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length() * (t1 - t0)
		var pieces := maxi(int(ceil(seg_len / 4.0)), 1)
		for p in pieces:
			var a := t0 + (t1 - t0) * float(p) / float(pieces)
			var b := t0 + (t1 - t0) * float(p + 1) / float(pieces)
			_emit_span(road_id, kind, rail, lanes, half, lift, left[i], left[i + 1], right[i], right[i + 1], chain[i], chain[i + 1], a, b, grid, origin, n, spacing, surfs, faces)


func _emit_span(road_id: String, kind: String, rail: bool, lanes: int, half: float, lift: float, left_a: Vector3, left_b: Vector3, right_a: Vector3, right_b: Vector3, chain_a: float, chain_b: float, t0: float, t1: float, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, surfs: Dictionary, faces: PackedVector3Array) -> void:
		if kind != "deck" and kind != "bridge" and _span_misses(left_a, left_b, right_a, right_b, t0, t1, grid, origin, n, spacing):
			var mid := (t0 + t1) * 0.5
			_emit_span(road_id, kind, rail, lanes, half, lift, left_a, left_b, right_a, right_b, chain_a, chain_b, t0, mid, grid, origin, n, spacing, surfs, faces)
			_emit_span(road_id, kind, rail, lanes, half, lift, left_a, left_b, right_a, right_b, chain_a, chain_b, mid, t1, grid, origin, n, spacing, surfs, faces)
			return
		var l0 := left_a.lerp(left_b, t0)
		var l1 := left_a.lerp(left_b, t1)
		var r0 := right_a.lerp(right_b, t0)
		var r1 := right_a.lerp(right_b, t1)
		l0.y = _surface_y(l0, road_id, kind, lift, grid, origin, n, spacing)
		l1.y = _surface_y(l1, road_id, kind, lift, grid, origin, n, spacing)
		r0.y = _surface_y(r0, road_id, kind, lift, grid, origin, n, spacing)
		r1.y = _surface_y(r1, road_id, kind, lift, grid, origin, n, spacing)
		var c0 := chain_a + (chain_b - chain_a) * t0
		var c1 := chain_a + (chain_b - chain_a) * t1
		l0.y = _seat_grade(road_id, c0, l0, l0.y, grid, origin, n, spacing)
		l1.y = _seat_grade(road_id, c1, l1, l1.y, grid, origin, n, spacing)
		r0.y = _seat_grade(road_id, c0, r0, r0.y, grid, origin, n, spacing)
		r1.y = _seat_grade(road_id, c1, r1, r1.y, grid, origin, n, spacing)
		# Centreline vertices, so a wide cross-slope cannot pull the lanes
		# through the ground between the two edges.
		var m0 := l0.lerp(r0, 0.5)
		var m1 := l1.lerp(r1, 0.5)
		m0.y = _surface_y(m0, road_id, kind, lift, grid, origin, n, spacing)
		m1.y = _surface_y(m1, road_id, kind, lift, grid, origin, n, spacing)
		m0.y = _seat_grade(road_id, c0, m0, m0.y, grid, origin, n, spacing)
		m1.y = _seat_grade(road_id, c1, m1, m1.y, grid, origin, n, spacing)
		# The v4 model is the deck. A second asphalt sheet hides the lanes and
		# puts the ray on the sheet instead of the deck. Keep the walk surface.
		if kind == "bridge" and not rail:
			_solid_quad(faces, l0, m0, m1, l1)
			_solid_quad(faces, m0, r0, r1, m1)
			return
		if rail:
			var ball: _Surf = surfs["ballast"]
			_quad(ball, l0, m0, m1, l1, c0, c1, 0.0, half, true, faces)
			_quad(ball, m0, r0, r1, m1, c0, c1, half, half * 2.0, true, faces)
			_rails(surfs["rail"], l0, r0, r1, l1, c0, c1)
			if kind == "trestle":
				_trestle(surfs["basalt"], l0, r0, r1, l1, grid, origin, n, spacing, faces)
			return
		var top: _Surf = surfs["asphalt"]
		_quad(top, l0, m0, m1, l1, c0, c1, 0.0, half, true, faces)
		_quad(top, m0, r0, r1, m1, c0, c1, half, half * 2.0, true, faces)
		if lanes >= 2:
			_line(surfs["yellow"], l0, r0, l1, r1, half, 0.0, LINE_W, 0.01, c0, c1, false)
		_line(surfs["white"], l0, r0, l1, r1, half, -(half - 0.22), LINE_W, 0.01, c0, c1, false)
		_line(surfs["white"], l0, r0, l1, r1, half, half - 0.22, LINE_W, 0.01, c0, c1, false)
		if lanes > 2:
			var lane_w := half * 2.0 / float(lanes)
			var k := 1
			while float(k) * lane_w < half - 0.45:
				_line(surfs["white"], l0, r0, l1, r1, half, float(k) * lane_w, LINE_W, 0.01, c0, c1, true)
				_line(surfs["white"], l0, r0, l1, r1, half, -float(k) * lane_w, LINE_W, 0.01, c0, c1, true)
				k += 1
		if kind == "cut" or kind == "fill":
			_skirts(surfs["basalt"], l0, r0, l1, r1, grid, origin, n, spacing, faces)
		if GUARD_ROADS.has(road_id):
			var rim := road_id == "rim_road_south"
			_guard_edge(surfs["guard"], l0, l1, r0, grid, origin, n, spacing, faces, rim)
			_guard_edge(surfs["guard"], r0, r1, l0, grid, origin, n, spacing, faces, rim)


func _skirts(surf: _Surf, l0: Vector3, r0: Vector3, l1: Vector3, r1: Vector3, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, faces: PackedVector3Array) -> void:
	if n < 2:
		return
	_skirt_side(surf, l0, l1, r0, grid, origin, n, spacing, faces)
	_skirt_side(surf, r0, r1, l0, grid, origin, n, spacing, faces)


func _skirt_side(surf: _Surf, a: Vector3, b: Vector3, other: Vector3, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, _faces: PackedVector3Array) -> void:
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
	# No collision: on a shallow shoulder the face is a slab above the ribbon,
	# and a downward ray lands on it instead of the road.
	var top_a := a + Vector3(0.0, 0.08, 0.0) + outward * 0.06
	var top_b := b + Vector3(0.0, 0.08, 0.0) + outward * 0.06
	var bot_a := Vector3(a.x, toe_a + 0.08, a.z) + outward * BLEND_M
	var bot_b := Vector3(b.x, toe_b + 0.08, b.z) + outward * BLEND_M
	var empty := PackedVector3Array()
	_wall(surf, top_a, top_b, bot_b, bot_a, false, empty)


func _rails(surf: _Surf, l0: Vector3, r0: Vector3, r1: Vector3, l1: Vector3, c0: float, c1: float) -> void:
	var across := Vector3(r0.x - l0.x, 0.0, r0.z - l0.z)
	if across.length_squared() < 0.01:
		return
	var side := across.normalized()
	for off_v in [_gauge_half, -_gauge_half]:
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


func _emit_junctions(coord: Vector2i, surf: _Surf, faces: PackedVector3Array, grid: PackedFloat32Array, n: int, spacing: float) -> void:
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
		var origin := WorldConfig.chunk_origin(coord)
		var road_id := _major_id(item)
		var kind := _kind_near(road_id, at.x, at.z)
		var lift := _joint_lift(item)
		var centre_y := _surface_y(Vector3(at.x, _major_y(item), at.z), road_id, kind, lift, grid, origin, n, spacing)
		var rings := maxi(int(ceil(radius / 2.0)), 1)
		var sides := maxi(int(ceil(TAU * radius / 2.0)), 12)
		var prev := PackedVector3Array()
		prev.append(WorldConfig.to_local(Vector3(at.x, centre_y, at.z)))
		for ring in rings:
			var rad := radius * float(ring + 1) / float(rings)
			var ring_pts := PackedVector3Array()
			for s in sides:
				var ang := float(s) / float(sides) * TAU
				var px := at.x + cos(ang) * rad
				var pz := at.z + sin(ang) * rad
				var y := _surface_y(Vector3(px, centre_y, pz), road_id, kind, lift, grid, origin, n, spacing)
				ring_pts.append(WorldConfig.to_local(Vector3(px, y, pz)))
			for s in sides:
				var nxt := (s + 1) % sides
				if prev.size() == 1:
					_tri(surf, prev[0], ring_pts[s], ring_pts[nxt], faces)
				else:
					_tri(surf, prev[s], ring_pts[s], ring_pts[nxt], faces)
					_tri(surf, prev[s], ring_pts[nxt], prev[nxt], faces)
			prev = ring_pts


func _signs_for(coord: Vector2i) -> Array:
	var signs: Array = []
	for item in _junctions:
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var at := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		if WorldConfig.chunk_of(at.x, at.z) != coord:
			continue
		var names := _sign_names(item.get("roads", []))
		if names.is_empty():
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
		var stand := at + side * (half + 1.6)
		stand.y = at.y
		# Blade A runs along local +X, so it is parallel to the street it names.
		signs.append({
			"at": stand,
			"yaw": atan2(-dir.z, dir.x),
			"a": names[0],
			"b": names[1] if names.size() > 1 else "",
		})
	return signs


func _sign_names(ids: Array) -> PackedStringArray:
	var seen := {}
	var names := PackedStringArray()
	for id in ids:
		var name := _short_street(str(_name_of.get(str(id), "")))
		if name == "" or seen.has(name):
			continue
		seen[name] = true
		names.append(name)
		if names.size() == 2:
			break
	return names


func _short_street(raw: String) -> String:
	var s := raw
	var cut := s.find("(")
	if cut > 1:
		s = s.substr(0, cut).strip_edges()
	s = s.replace("Boulevard", "Blvd")
	s = s.replace("Avenue", "Ave")
	s = s.replace("Street", "St")
	s = s.replace("Road", "Rd")
	s = s.replace("Drive", "Dr")
	return s


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
	shape.backface_collision = true
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	host.add_child(body)


func _job_signs(host: Node3D, signs: Array) -> void:
	if host.get_node_or_null("StreetSigns") != null:
		return
	var packed := load(SIGN_SCENE) as PackedScene
	if packed == null:
		push_error("Street sign failed to load: %s" % SIGN_SCENE)
		return
	var root := Node3D.new()
	root.name = "StreetSigns"
	host.add_child(root)
	var font := _sign_font()
	for item in signs:
		var inst := packed.instantiate() as Node3D
		if inst == null:
			continue
		var at: Vector3 = item["at"]
		var ground := _terrain_at(host, at.x, at.z)
		if ground > -70.0:
			at.y = ground
		inst.position = WorldConfig.to_local(at)
		inst.rotation = Vector3(0.0, float(item["yaw"]), 0.0)
		root.add_child(inst)
		_blade_label(inst, "TextAnchor_A_front", str(item["a"]), font)
		_blade_label(inst, "TextAnchor_A_back", str(item["a"]), font)
		if str(item["b"]) != "":
			_blade_label(inst, "TextAnchor_B_front", str(item["b"]), font)
			_blade_label(inst, "TextAnchor_B_back", str(item["b"]), font)
		_ensure_collision(inst)
		if inst.find_child("CollisionShape3D", true, false) == null:
			_post_box(inst)


func _apply_named_slots(root: Node, slots: Dictionary) -> void:
	var loaded := {}
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat == null:
				continue
			var key := str(mat.resource_name)
			if not slots.has(key):
				continue
			if not loaded.has(key):
				loaded[key] = load(str(slots[key])) as Material
			var ext: Material = loaded[key]
			if ext == null:
				push_error("Material slot missing: %s" % str(slots[key]))
				continue
			mi.set_surface_override_material(s, ext)


func _job_mark(host: Node3D, mark: Dictionary) -> void:
	if str(mark["id"]) == "station_site":
		_place_station(host, mark)
		return
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
	var yaw_deg := float(mark["yaw"])
	# v4 lanes are local y=148 and the origin is the water, so landmark y is the
	# water height and the deck lands on 142.76. File yaw -1.7 aims local +Z at
	# the south road end. A centreline ray hits the median, so flush checks use a lane.
	if str(mark["id"]) == "centennial_park_ramp":
		# v2 pivot is the top edge. Local -Z runs downhill into the river.
		at = RAMP_TOP
		yaw_deg = 0.0
	var fp: Vector2 = mark.get("fp", Vector2(4.0, 4.0))
	_finish_mark(host, inst, at, yaw_deg, fp, bool(mark.get("seat", false)))
	if str(mark["id"]) == "perrine_bridge":
		_apply_named_slots(inst, BRIDGE_SLOTS)
	if str(mark["id"]) == "centennial_park_ramp":
		_place_dock(host, at)
	if str(mark["id"]) == "coin_viewers":
		_extra_viewers(inst, str(mark["path"]))


## The depot glb is one 25 m module. The site footprint is six of them end to end.
func _place_station(host: Node3D, mark: Dictionary) -> void:
	var packed := load(str(mark["path"])) as PackedScene
	if packed == null:
		push_error("Landmark failed to load: %s" % str(mark["path"]))
		return
	var at: Vector3 = mark["at"]
	var yaw_deg := float(mark["yaw"])
	var fp_site: Vector2 = mark.get("fp", Vector2(150.0, 4.0))
	var count := maxi(int(round(fp_site.x / STATION_MODULE_M)), 1)
	var mod_len := fp_site.x / float(count)
	for i in count:
		var node_name := "Lm_station_site_%d" % i
		if host.get_node_or_null(node_name) != null:
			continue
		var inst := packed.instantiate() as Node3D
		if inst == null:
			return
		inst.name = node_name
		var lx := -fp_site.x * 0.5 + mod_len * 0.5 + float(i) * mod_len
		var off := _yaw_offset(yaw_deg, lx, 0.0)
		var pos := Vector3(at.x + off.x, at.y, at.z + off.y)
		_finish_mark(host, inst, pos, yaw_deg, Vector2(mod_len, fp_site.y), true)


func _finish_mark(host: Node3D, inst: Node3D, at: Vector3, yaw_deg: float, fp: Vector2, seat: bool) -> void:
	var min_x := -fp.x * 0.5
	var max_x := fp.x * 0.5
	var min_z := -fp.y * 0.5
	var max_z := fp.y * 0.5
	var box := _mesh_aabb(inst)
	if box.size.length_squared() > 0.01:
		min_x = minf(min_x, box.position.x)
		max_x = maxf(max_x, box.end.x)
		min_z = minf(min_z, box.position.z)
		max_z = maxf(max_z, box.end.z)
	var foot := _foot_ys(host, at, yaw_deg, min_x, max_x, min_z, max_z)
	var mesh_bottom := 0.0
	if seat:
		mesh_bottom = _mesh_min_y(inst)
		if foot.x > -70.0:
			# Mesh bottom on the high sample. The plinth fills down to the low sample.
			at.y = foot.y - mesh_bottom
	inst.position = WorldConfig.to_local(at)
	inst.rotation = Vector3(0.0, deg_to_rad(yaw_deg), 0.0)
	host.add_child(inst)
	_ensure_collision(inst)
	if seat and foot.x > -70.0 and foot.y - foot.x > PLINTH_GAP_M:
		_plinth(inst, max_x - min_x, max_z - min_z, (min_x + max_x) * 0.5, (min_z + max_z) * 0.5, foot.y - foot.x, mesh_bottom)


func _major_id(item: Dictionary) -> String:
	var best := -1.0
	var found := ""
	for id in item.get("roads", []):
		if not _by_id.has(str(id)):
			continue
		var road: Dictionary = _roads[int(_by_id[str(id)])]
		var half := float(road["half"])
		if half < best:
			continue
		best = half
		found = str(id)
	return found


## The authored grade's tail and the run down to the ramp sit on the drawn ground.
func _seat_grade(road_id: String, chain: float, p: Vector3, y: float, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> float:
	if road_id != "canyon_springs_grade" or _grade_end < 0.0:
		return y
	var g := _ground(grid, origin, n, spacing, p.x, p.z)
	if g < -70.0:
		return y
	# The ramp head is a landmark. The ribbon stays on the drawn ground so the
	# approach cannot float above the heightfield the way a fill used to.
	if chain > _grade_end or chain >= _grade_end - GRADE_TAIL_M:
		return g + ROAD_CLEAR_M
	return y


func _trestle(surf: _Surf, l0: Vector3, r0: Vector3, r1: Vector3, l1: Vector3, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, faces: PackedVector3Array) -> void:
	var mid := (l0 + r0 + r1 + l1) * 0.25
	var g := _ground(grid, origin, n, spacing, mid.x, mid.z)
	if g < -70.0 or mid.y - g < 2.0:
		return
	var across := Vector3(r0.x - l0.x, 0.0, r0.z - l0.z)
	if across.length_squared() < 0.01:
		return
	var side := across.normalized()
	for off_v in [_gauge_half, -_gauge_half]:
		var top := mid + side * float(off_v)
		top.y = mid.y - 0.05
		_column(surf, top, g, 0.16, 0.16, faces)


func _column(surf: _Surf, top: Vector3, ground_y: float, hx: float, hz: float, faces: PackedVector3Array) -> void:
	var corners: Array[Vector3] = [
		Vector3(-hx, 0.0, -hz),
		Vector3(hx, 0.0, -hz),
		Vector3(hx, 0.0, hz),
		Vector3(-hx, 0.0, hz),
	]
	for i in 4:
		var j := (i + 1) % 4
		var a := top + corners[i]
		var b := top + corners[j]
		var c := Vector3(b.x, ground_y, b.z)
		var d := Vector3(a.x, ground_y, a.z)
		_wall(surf, a, b, c, d, true, faces)


func _sign_font() -> Font:
	if _font != null:
		return _font
	if ResourceLoader.exists(FONT_PATH):
		var loaded := load(FONT_PATH) as Font
		if loaded != null:
			_font = loaded
			return _font
	var sys := SystemFont.new()
	sys.font_weight = 700
	_font = sys
	return _font


func _fit_font(text: String) -> int:
	var n := text.length()
	if n <= 9:
		return 214
	return clampi(int(214.0 * 9.0 / float(n)), 171, 214)


func _blade_label(root: Node3D, anchor_name: String, text: String, font: Font) -> void:
	if text == "":
		return
	var anchor := root.find_child(anchor_name, true, false) as Node3D
	if anchor == null:
		push_error("Sign anchor missing: %s" % anchor_name)
		return
	var label := Label3D.new()
	label.text = text
	label.font = font
	label.pixel_size = 0.001
	label.font_size = _fit_font(text)
	label.modulate = Color(245.0 / 255.0, 245.0 / 255.0, 240.0 / 255.0)
	label.outline_size = 0
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = false
	label.shaded = false
	label.no_depth_test = false
	label.width = 860.0
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Anchor +Z points out of the face. An identity Label3D reads correctly.
	anchor.add_child(label)


func _post_box(root: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "SignPost"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.0604, 2.27, 0.0604)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0.0, 1.135, 0.0)
	body.add_child(col)
	root.add_child(body)


func _job_plates(host: Node3D, plates: Array) -> void:
	if host.get_node_or_null("Advisory") != null:
		return
	var root := Node3D.new()
	root.name = "Advisory"
	host.add_child(root)
	var font := _sign_font()
	for item in plates:
		var at: Vector3 = item["at"]
		var ground := _terrain_at(host, at.x, at.z)
		if ground > -70.0:
			at.y = ground
		var node := Node3D.new()
		node.position = WorldConfig.to_local(at)
		node.rotation = Vector3(0.0, float(item["yaw"]), 0.0)
		root.add_child(node)
		_advisory_plate(node, font)
		_post_box(node)


func _advisory_plate(node: Node3D, font: Font) -> void:
	var post := MeshInstance3D.new()
	var pole := BoxMesh.new()
	pole.size = Vector3(0.08, 2.15, 0.08)
	post.mesh = pole
	post.position = Vector3(0.0, 1.075, 0.0)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.72, 0.74, 0.76)
	steel.metallic = 0.6
	steel.roughness = 0.4
	post.material_override = steel
	node.add_child(post)
	var board := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(0.02, 0.55, 0.45)
	board.mesh = slab
	board.position = Vector3(0.0, 1.85, 0.0)
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color(0.95, 0.78, 0.1)
	yellow.roughness = 0.45
	board.material_override = yellow
	node.add_child(board)
	for flip in [0.0, PI]:
		var label := Label3D.new()
		label.text = "15"
		label.font = font
		label.pixel_size = 0.001
		label.font_size = 214
		label.modulate = Color(0.08, 0.08, 0.08)
		label.outline_size = 0
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.shaded = false
		label.position = Vector3(0.02 if flip == 0.0 else -0.02, 1.85, 0.0)
		label.rotation = Vector3(0.0, flip, 0.0)
		node.add_child(label)


## Returns (min_y, max_y). min_y < -70 when the footprint is off the DEM.
## `min_*` / `max_*` are local XZ before yaw. Offset matches Node3D yaw.
func _foot_ys(host: Node, at: Vector3, yaw_deg: float, min_x: float, max_x: float, min_z: float, max_z: float) -> Vector2:
	var span_x := maxf(max_x - min_x, 0.1)
	var span_z := maxf(max_z - min_z, 0.1)
	var nx := mini(maxi(int(ceil(span_x / FOOT_STEP_M)) + 1, 3), 41)
	var nz := mini(maxi(int(ceil(span_z / FOOT_STEP_M)) + 1, 3), 41)
	var lo := 1.0e9
	var hi := -1.0e9
	var hits := 0
	for ix in nx:
		var u := 0.0 if nx == 1 else float(ix) / float(nx - 1)
		var lx := lerpf(min_x, max_x, u)
		for iz in nz:
			var v := 0.0 if nz == 1 else float(iz) / float(nz - 1)
			var lz := lerpf(min_z, max_z, v)
			var off := _yaw_offset(yaw_deg, lx, lz)
			var h := _terrain_at(host, at.x + off.x, at.z + off.y)
			if h < -70.0:
				continue
			hits += 1
			lo = minf(lo, h)
			hi = maxf(hi, h)
	if hits == 0:
		return Vector2(-80.0, -80.0)
	return Vector2(lo, hi)


func _yaw_offset(yaw_deg: float, lx: float, lz: float) -> Vector2:
	var yaw := deg_to_rad(yaw_deg)
	var c := cos(yaw)
	var s := sin(yaw)
	return Vector2(lx * c + lz * s, -lx * s + lz * c)


func _mesh_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var found := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var ab: AABB = _mesh_xf(root, mi) * mi.mesh.get_aabb()
		if not found:
			box = ab
			found = true
		else:
			box = box.merge(ab)
	return box if found else AABB()


func _mesh_min_y(root: Node3D) -> float:
	var lo := 0.0
	var found := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var aabb := mi.mesh.get_aabb()
		var xf := _mesh_xf(root, mi)
		for i in 8:
			var corner := Vector3(
				aabb.position.x if (i & 1) == 0 else aabb.end.x,
				aabb.position.y if (i & 2) == 0 else aabb.end.y,
				aabb.position.z if (i & 4) == 0 else aabb.end.z
			)
			var y := (xf * corner).y
			if not found or y < lo:
				lo = y
				found = true
	return lo if found else 0.0


## `top_y` is the mesh bottom in the landmark's local frame. The box meets that
## bottom and reaches `drop` metres further down, to the low sample of the slope.
func _plinth(inst: Node3D, size_x: float, size_z: float, center_x: float, center_z: float, drop: float, top_y: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(maxf(size_x, 0.2), drop, maxf(size_z, 0.2))
	var mi := MeshInstance3D.new()
	mi.name = "Plinth"
	mi.mesh = mesh
	mi.position = Vector3(center_x, top_y - drop * 0.5, center_z)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.53, 0.50)
	mat.roughness = 0.9
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.add_child(mi)
	var body := inst.find_child("StaticBody3D", true, false) as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = "PlinthBody"
		body.collision_layer = 1
		body.collision_mask = 0
		inst.add_child(body)
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = mi.position
	body.add_child(col)


func _place_dock(host: Node3D, ramp_at: Vector3) -> void:
	if host.get_node_or_null("Lm_launch_dock") != null:
		return
	var packed := load(DOCK_SCENE) as PackedScene
	if packed == null:
		push_error("Dock failed to load")
		return
	var dock := packed.instantiate() as Node3D
	if dock == null:
		return
	dock.name = "Lm_launch_dock"
	# East of the ramp. Local +Z stays on the bank; the dock runs north into the water.
	var at := Vector3(ramp_at.x + 6.2, -5.24 + 0.25, ramp_at.z - 7.5)
	dock.position = WorldConfig.to_local(at)
	host.add_child(dock)
	_ensure_collision(dock)


func _extra_viewers(root: Node3D, path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		return
	for x in [-2.0, 2.0]:
		var extra := packed.instantiate() as Node3D
		if extra == null:
			continue
		extra.name = "Viewer"
		extra.position = Vector3(x, 0.0, 0.0)
		root.add_child(extra)


func _terrain_at(host: Node, x: float, z: float) -> float:
	var n: Node = host
	while n != null:
		var gen: Object = n.get("generator")
		if gen != null and gen.has_method("drawn_height_at"):
			return float(gen.call("drawn_height_at", x, z))
		if gen != null and gen.has_method("height_at"):
			return float(gen.call("height_at", x, z))
		n = n.get_parent()
	return -80.0


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
	var guard := StandardMaterial3D.new()
	guard.albedo_color = Color(0.55, 0.57, 0.58)
	guard.metallic = 0.72
	guard.roughness = 0.38
	guard.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["guard"] = guard
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
	# Each triangle is flipped on its own. A pinched quad can have one triangle
	# pointing down even when the other points up, and a downward face is invisible
	# from above and missed by a one-sided ray.
	var la := WorldConfig.to_local(a)
	var lb := WorldConfig.to_local(b)
	var lc := WorldConfig.to_local(c)
	var ld := WorldConfig.to_local(d)
	var n1 := (lb - la).cross(lc - la)
	var n2 := (lc - la).cross(ld - la)
	if n1.length_squared() < 0.0000000001 and n2.length_squared() < 0.0000000001:
		return
	# Godot shows clockwise-from-above as the front face (geometric y <= 0).
	# The previous flip forced the opposite winding, so the lit side was the
	# underside and the ribbon read as a black slab.
	var flip1 := n1.y > 0.0
	var flip2 := n2.y > 0.0
	if flip1:
		n1 = -n1
	if flip2:
		n2 = -n2
	var n := n1 + n2
	if n.length_squared() < 0.0000000001:
		n = Vector3.DOWN
	else:
		n = n.normalized()
	var shade := -n
	if shade.y < 0.0:
		shade = -shade
	var base := surf.v.size()
	surf.v.append(la)
	surf.v.append(lb)
	surf.v.append(lc)
	surf.v.append(ld)
	for _i in 4:
		surf.nrm.append(shade)
	var tile_v0 := v0 / 4.0
	var tile_v1 := v1 / 4.0
	var tile_u0 := u0 / 4.0
	var tile_u1 := u1 / 4.0
	surf.uv.append(Vector2(tile_u0, tile_v0))
	surf.uv.append(Vector2(tile_u1, tile_v0))
	surf.uv.append(Vector2(tile_u1, tile_v1))
	surf.uv.append(Vector2(tile_u0, tile_v1))
	if flip1:
		surf.idx.append(base)
		surf.idx.append(base + 2)
		surf.idx.append(base + 1)
	else:
		surf.idx.append(base)
		surf.idx.append(base + 1)
		surf.idx.append(base + 2)
	if flip2:
		surf.idx.append(base)
		surf.idx.append(base + 3)
		surf.idx.append(base + 2)
	else:
		surf.idx.append(base)
		surf.idx.append(base + 2)
		surf.idx.append(base + 3)
	if solid:
		if flip1:
			faces.append(la)
			faces.append(lc)
			faces.append(lb)
		else:
			faces.append(la)
			faces.append(lb)
			faces.append(lc)
		if flip2:
			faces.append(la)
			faces.append(ld)
			faces.append(lc)
		else:
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
	if n.y > 0.0:
		var tmp := b
		b = c
		c = tmp
		n = -n
	n = -n.normalized()
	if n.y < 0.0:
		n = -n
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


## Keep the last 2 m of a joined road on the blend so a terrain hump cannot reopen the step.
func _pin_end(p: Vector3, road_id: String, lift: float, current: float) -> float:
	if _join_dist(p, road_id) > 2.0:
		return current
	return _join_y(p, road_id) + lift


func _join_dist(p: Vector3, road_id: String) -> float:
	var best := JOIN_M + 1.0
	for item in _junctions:
		var ids: Array = item.get("roads", [])
		if not ids.has(road_id):
			continue
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var dx := p.x - float(pos[0])
		var dz := p.z - float(pos[2])
		best = minf(best, sqrt(dx * dx + dz * dz))
	return best


func _cut_joins(grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	if n < 2 or grid.size() != n * n:
		return
	var margin := JOIN_M + 24.0
	for item in _junctions:
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var jx := float(pos[0])
		var jz := float(pos[2])
		if jx < origin.x - margin or jx > origin.x + 500.0 + margin:
			continue
		if jz < origin.y - margin or jz > origin.y + 500.0 + margin:
			continue
		var major := _major_half(item)
		var major_y := _major_y(item)
		for id in item.get("roads", []):
			if not _by_id.has(str(id)):
				continue
			var road: Dictionary = _roads[int(_by_id[str(id)])]
			if float(road["half"]) + 0.05 >= major:
				continue
			_cut_join_road(road, jx, jz, major_y, grid, origin, n, spacing)


func _major_half(item: Dictionary) -> float:
	var best := 0.0
	for id in item.get("roads", []):
		if not _by_id.has(str(id)):
			continue
		var road: Dictionary = _roads[int(_by_id[str(id)])]
		best = maxf(best, float(road["half"]))
	return best


func _cut_join_road(road: Dictionary, jx: float, jz: float, major_y: float, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	var pts: PackedVector3Array = road["pts"]
	var half := float(road["half"])
	var reach := half + 3.0
	for i in pts.size() - 1:
		var len := Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length()
		if len < 0.5:
			continue
		var steps := maxi(int(ceil(len / spacing)), 1)
		for s in steps + 1:
			var t := float(s) / float(steps)
			var p := pts[i].lerp(pts[i + 1], t)
			var dist := Vector2(p.x - jx, p.z - jz).length()
			if dist >= JOIN_M:
				continue
			var u := 1.0 - dist / JOIN_M
			u = u * u * (3.0 - 2.0 * u)
			var road_y := lerpf(p.y, major_y, u)
			var rad := int(ceil(reach / spacing)) + 1
			var gc := int(floor((p.x - origin.x) / spacing))
			var gr := int(floor((p.z - origin.y) / spacing))
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
					var hit := _seg(x, z, pts[i].x, pts[i].z, pts[i + 1].x, pts[i + 1].z)
					if hit.x > reach:
						continue
					var shoulder := 0.0
					if hit.x > half:
						shoulder = smoothstep(half, reach, hit.x)
					var target := road_y - SHAVE_M
					var idx := r * n + c
					grid[idx] = minf(grid[idx], lerpf(target, grid[idx], shoulder))


func _join_y(p: Vector3, road_id: String) -> float:
	var y := p.y
	var best := 0.0
	for item in _junctions:
		var ids: Array = item.get("roads", [])
		if not ids.has(road_id):
			continue
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var dx := p.x - float(pos[0])
		var dz := p.z - float(pos[2])
		var dist := sqrt(dx * dx + dz * dz)
		if dist >= JOIN_M:
			continue
		var t := 1.0 - dist / JOIN_M
		t = t * t * (3.0 - 2.0 * t)
		if t <= best:
			continue
		best = t
		y = lerpf(p.y, _major_y(item), t)
	return y


## Bridge joints stay on the lane height. A 3 cm lift would step the apron off the v4 deck.
func _joint_lift(item: Dictionary) -> float:
	for id in item.get("roads", []):
		if str(id) == "us93_perrine_bridge":
			return 0.0
	return LIFT_M


func _major_y(item: Dictionary) -> float:
	var pos: Array = item.get("pos", [])
	var fallback := float(pos[1]) if pos.size() >= 3 else 0.0
	if pos.size() < 3:
		return fallback
	var best_half := -1.0
	var y := fallback
	var x := float(pos[0])
	var z := float(pos[2])
	for id in item.get("roads", []):
		if not _by_id.has(str(id)):
			continue
		var road: Dictionary = _roads[int(_by_id[str(id)])]
		var half := float(road["half"])
		if half < best_half:
			continue
		best_half = half
		y = _polyline_y(road["pts"], x, z, fallback)
	return y


func _polyline_y(pts: PackedVector3Array, x: float, z: float, fallback: float) -> float:
	var best := 1.0e12
	var y := fallback
	for i in pts.size() - 1:
		var hit := _seg(x, z, pts[i].x, pts[i].z, pts[i + 1].x, pts[i + 1].z)
		if hit.x < best:
			best = hit.x
			y = lerpf(pts[i].y, pts[i + 1].y, hit.y)
	return y


## Deck and bridge keep the authored grade. Everywhere else the vertex sits on
## the drawn ground. A grade more than 0.3 m off that ground is earthwork, and
## outside a deck it must not leave a ribbon you can walk under.
func _surface_y(p: Vector3, road_id: String, kind: String, lift: float, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> float:
	var design := _join_y(p, road_id) + lift
	var g := _ground(grid, origin, n, spacing, p.x, p.z)
	if kind == "deck" or kind == "bridge":
		if g > -70.0 and design < g + ROAD_CLEAR_M:
			return g + ROAD_CLEAR_M
		return design
	if g < -70.0:
		return design
	if absf(design - g) > 0.3:
		return g + ROAD_CLEAR_M
	return g + ROAD_CLEAR_M


func _kind_near(road_id: String, x: float, z: float) -> String:
	if not _by_id.has(road_id):
		return "grade"
	var road: Dictionary = _roads[int(_by_id[road_id])]
	var pts: PackedVector3Array = road["pts"]
	var kinds: PackedStringArray = road["kind"]
	var best := 1.0e12
	var kind := "grade"
	for i in pts.size() - 1:
		var hit := _seg(x, z, pts[i].x, pts[i].z, pts[i + 1].x, pts[i + 1].z)
		if hit.x < best:
			best = hit.x
			kind = kinds[i]
	return kind


## True when a straight chord misses the heightfield by enough to walk under.
func _span_misses(left_a: Vector3, left_b: Vector3, right_a: Vector3, right_b: Vector3, t0: float, t1: float, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> bool:
	var l0 := left_a.lerp(left_b, t0)
	var l1 := left_a.lerp(left_b, t1)
	var r0 := right_a.lerp(right_b, t0)
	var r1 := right_a.lerp(right_b, t1)
	var c0 := l0.lerp(r0, 0.5)
	var c1 := l1.lerp(r1, 0.5)
	return _chord_miss(l0, l1, grid, origin, n, spacing) or _chord_miss(r0, r1, grid, origin, n, spacing) or _chord_miss(c0, c1, grid, origin, n, spacing)


func _chord_miss(a: Vector3, b: Vector3, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> bool:
	# Keep going under a metre. A 0.5 m chord across a cut still sits 15 cm
	# above the heightfield, which is enough to walk under.
	if Vector2(b.x - a.x, b.z - a.z).length() <= 0.15:
		return false
	var g0 := _ground(grid, origin, n, spacing, a.x, a.z)
	var g1 := _ground(grid, origin, n, spacing, b.x, b.z)
	if g0 < -70.0 or g1 < -70.0:
		return false
	for k in 3:
		var t := float(k + 1) / 4.0
		var p := a.lerp(b, t)
		var g := _ground(grid, origin, n, spacing, p.x, p.z)
		if g < -70.0:
			continue
		if absf(g - lerpf(g0, g1, t)) > 0.02:
			return true
	return false


## How far this quad's interior sits under the drawn ground. Zero when it already clears.
func _peak_lift(l0: Vector3, r0: Vector3, l1: Vector3, r1: Vector3, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> float:
	if n < 2 or grid.size() != n * n or spacing <= 0.0:
		return 0.0
	var min_x := minf(l0.x, minf(l1.x, minf(r0.x, r1.x)))
	var max_x := maxf(l0.x, maxf(l1.x, maxf(r0.x, r1.x)))
	var min_z := minf(l0.z, minf(l1.z, minf(r0.z, r1.z)))
	var max_z := maxf(l0.z, maxf(l1.z, maxf(r0.z, r1.z)))
	var c0 := clampi(int(floor((min_x - origin.x) / spacing)), 0, n - 1)
	var c1 := clampi(int(ceil((max_x - origin.x) / spacing)), 0, n - 1)
	var r0i := clampi(int(floor((min_z - origin.y) / spacing)), 0, n - 1)
	var r1i := clampi(int(ceil((max_z - origin.y) / spacing)), 0, n - 1)
	if c1 - c0 > 24:
		c1 = c0 + 24
	if r1i - r0i > 24:
		r1i = r0i + 24
	var extra := 0.0
	for r in range(r0i, r1i + 1):
		var z := origin.y + float(r) * spacing
		var row := r * n
		for c in range(c0, c1 + 1):
			var x := origin.x + float(c) * spacing
			if not _in_quad(x, z, l0, r0, r1, l1):
				continue
			var road_y := _bary_y(x, z, l0, r0, r1, l1)
			extra = maxf(extra, grid[row + c] + 0.04 - road_y)
	return extra


func _in_quad(x: float, z: float, l0: Vector3, r0: Vector3, r1: Vector3, l1: Vector3) -> bool:
	return _in_tri2(x, z, l0, r0, r1) or _in_tri2(x, z, l0, r1, l1)


func _in_tri2(x: float, z: float, a: Vector3, b: Vector3, c: Vector3) -> bool:
	var den := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
	if absf(den) < 0.00000001:
		return false
	var wa := ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / den
	var wb := ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / den
	var wc := 1.0 - wa - wb
	return wa >= -0.05 and wb >= -0.05 and wc >= -0.05


func _bary_y(x: float, z: float, l0: Vector3, r0: Vector3, r1: Vector3, l1: Vector3) -> float:
	if _in_tri2(x, z, l0, r0, r1):
		return _tri_y(x, z, l0, r0, r1)
	return _tri_y(x, z, l0, r1, l1)


func _tri_y(x: float, z: float, a: Vector3, b: Vector3, c: Vector3) -> float:
	var den := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
	if absf(den) < 0.00000001:
		return a.y
	var wa := ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / den
	var wb := ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / den
	var wc := 1.0 - wa - wb
	return wa * a.y + wb * b.y + wc * c.y


func _guard_edge(surf: _Surf, a: Vector3, b: Vector3, other: Vector3, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, faces: PackedVector3Array, rim: bool) -> void:
	var outward := Vector3(a.x - other.x, 0.0, a.z - other.z)
	if outward.length_squared() < 0.01:
		return
	outward = outward.normalized()
	var mid := (a + b) * 0.5
	var g := _ground(grid, origin, n, spacing, mid.x + outward.x * 3.0, mid.z + outward.z * 3.0)
	var need := 0.35 if rim else DROP_RAIL_M
	if g < -70.0 or mid.y - g < need:
		return
	if rim:
		# Overlap the next piece and sit just inside the pavement edge.
		var along := b - a
		along.y = 0.0
		if along.length() > 0.2:
			along = along.normalized() * 0.4
			a -= along
			b += along
	var out := outward * (-0.08 if rim else 0.16)
	var hi := 0.68
	var lo := 0.36
	var top_a := a + out + Vector3(0.0, hi, 0.0)
	var top_b := b + out + Vector3(0.0, hi, 0.0)
	var bot_a := a + out + Vector3(0.0, lo, 0.0)
	var bot_b := b + out + Vector3(0.0, lo, 0.0)
	var empty := PackedVector3Array()
	_wall(surf, bot_a, bot_b, top_b, top_a, false, empty)
	_solid_both(faces, bot_a, bot_b, top_b, top_a)
	var post := outward * (-0.08 if rim else 0.05)
	var foot_a := a + post
	var foot_b := a + post + Vector3(0.0, hi, 0.0)
	_wall(surf, foot_a, foot_a + outward * 0.12, foot_b + outward * 0.12, foot_b, false, empty)
	_solid_both(faces, foot_a, foot_a + outward * 0.12, foot_b + outward * 0.12, foot_b)


## Walkable quad, no render surface. Used where a landmark mesh is the deck.
## Winding matches the asphalt ribbon: clockwise from above (geometric normal
## y <= 0). The opposite winding is a back face, so a downward ray falls
## through the deck onto the ground.
func _solid_quad(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var la := WorldConfig.to_local(a)
	var lb := WorldConfig.to_local(b)
	var lc := WorldConfig.to_local(c)
	var ld := WorldConfig.to_local(d)
	var n1 := (lb - la).cross(lc - la)
	var n2 := (lc - la).cross(ld - la)
	if n1.y > 0.0:
		faces.append(la)
		faces.append(lc)
		faces.append(lb)
	elif n1.length_squared() > 0.0000000001:
		faces.append(la)
		faces.append(lb)
		faces.append(lc)
	if n2.y > 0.0:
		faces.append(la)
		faces.append(ld)
		faces.append(lc)
	elif n2.length_squared() > 0.0000000001:
		faces.append(la)
		faces.append(lc)
		faces.append(ld)


func _solid_both(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var la := WorldConfig.to_local(a)
	var lb := WorldConfig.to_local(b)
	var lc := WorldConfig.to_local(c)
	var ld := WorldConfig.to_local(d)
	faces.append(la)
	faces.append(lb)
	faces.append(lc)
	faces.append(la)
	faces.append(lc)
	faces.append(ld)
	faces.append(la)
	faces.append(lc)
	faces.append(lb)
	faces.append(la)
	faces.append(ld)
	faces.append(lc)


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
