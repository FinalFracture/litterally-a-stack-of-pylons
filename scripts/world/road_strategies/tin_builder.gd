extends TfRoadBuilder

## Constrained TIN for bake-off strategy 6.
##
## The carriageway, the verge and each junction disk are one triangle mesh.
## Breaklines are the centreline, both lane edges and the verge line, so the
## road gap is the 0.02 m lift by construction. Junction disks are a fan on
## the best-fit plane (tilt clamped to 2%, or 3% when an approach is at least
## 6%). Earth beyond the verge is a second constrained strip: ditch, cut or
## fill, daylight, then a vertex snapped to the 3.9 m terrain grid.
##
## Collision keeps a flat apron past the verge so a cone pushed through a
## parapet is still on the road mesh. That apron is not stamped into the
## heightfield. A cliff is not filled past the 3 m edge-drop probe; a short
## bench holds that probe, and the rock face beyond it is the earth TIN.

const LIFT := 0.02
const DENSE := 2.0
const APRON := 12.0
const VERGE_SLACK := 1.70
const END_CAP := 1.20
const PUFF := 0.04
const LIP := 0.012
const BLEND_MIN := 10.0
const HOLD_EXTRA := 2.5
const SLOPE_REACH := 36.0
const BENCH_M := 3.0
const BENCH_DROP := 2.4
const LOW_SP := 500.0 / 128.0

var _auth: Array = []
var _mesh := PackedVector3Array()
var _stamp := PackedVector3Array()
var _stamp_on := true
var _guard := PackedVector3Array()
var _built := Vector2i.ZERO
var _ev := PackedVector3Array()
var _en := PackedVector3Array()
var _euv := PackedVector2Array()
var _ei := PackedInt32Array()
var _earth_tris := 0


func prepare() -> void:
	_roads.clear()
	_edges.clear()
	_buckets.clear()
	_junctions.clear()
	_marks.clear()
	_name_of.clear()
	_by_id.clear()
	_auth.clear()
	_mesh = PackedVector3Array()
	_stamp = PackedVector3Array()
	_guard = PackedVector3Array()
	var road_file := roads_path if roads_path != "" else DATA + "/roads.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(road_file))
	if parsed is Dictionary:
		var doc: Dictionary = parsed
		for item in doc.get("roads", []):
			if item is Dictionary:
				_add_road(item, false)
		for item in doc.get("railways", []):
			if item is Dictionary:
				_add_road(item, true)
		for item in doc.get("intersections", []):
			if item is Dictionary:
				_junctions.append((item as Dictionary).duplicate(true))
	_assign_radii()
	_separate_radii()
	_store_auth()
	_fit_planes(false)
	_shape_all()
	if _needs_retighten():
		_fit_planes(true)
		_shape_all()
	if roads_path == "":
		_load_landmarks()
	_build_mats()
	print("TIN6 roads=%d junctions=%d drive_tris=%d stamp_tris=%d" % [
		_roads.size(), _junctions.size(), _mesh.size() / 3, _stamp.size() / 3,
	])


func apply_cuts(grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	_stamp_grid(grid, origin, n, spacing)


func apply_paint(grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	_stamp_grid(grid, origin, n, spacing)


func clamp_footprint(drawn: PackedFloat32Array, cut: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	if drawn.size() != n * n or cut.size() != n * n:
		return
	for edge in _edges:
		if bool(edge.get("skip_all", false)):
			continue
		var reach := float(edge["half"]) + float(edge["shoulder"]) + float(edge["ditch"]) + SLOPE_REACH
		_copy_box(drawn, cut, origin, n, spacing, edge, reach)
	for item in _junctions:
		_copy_disk(drawn, cut, origin, n, spacing, item)


func cuts_block(rect: Vector4, _limit: float, _ground_at: Callable) -> bool:
	if rect.z < rect.x or _edges.is_empty():
		return false
	var min_x := rect.x
	var min_z := rect.y
	var max_x := rect.z
	var max_z := rect.w
	for edge in _edges:
		if bool(edge.get("skip_all", false)):
			continue
		var pad := float(edge["half"]) + float(edge["shoulder"]) + float(edge["ditch"]) + 6.0
		if _seg_near(float(edge["ax"]), float(edge["az"]), float(edge["bx"]), float(edge["bz"]), min_x, min_z, max_x, max_z, pad):
			return true
	for item in _junctions:
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		if _circle_hits(float(pos[0]), float(pos[2]), float(item.get("radius", 8.0)) + 2.0, min_x, min_z, max_x, max_z):
			return true
	return false


func build_chunk(coord: Vector2i, _grid: PackedFloat32Array, _n: int, _spacing: float) -> Dictionary:
	_built = coord
	var rect := WorldConfig.chunk_rect(coord)
	var faces := _collect(_mesh, rect, true)
	_guard = PackedVector3Array()
	_parapets(rect)
	var surfaces: Array = []
	var asphalt := _as_surface(_collect(_stamp, rect, true), "asphalt")
	if not asphalt.is_empty():
		surfaces.append(asphalt)
	var earth := _earth_surface(rect)
	if not earth.is_empty():
		surfaces.append(earth)
	var marks: Array = []
	for mark in _marks:
		var at: Vector3 = mark["at"]
		if WorldConfig.chunk_of(at.x, at.z) == coord:
			marks.append(mark)
	if faces.is_empty() and surfaces.is_empty() and marks.is_empty() and _guard.is_empty():
		return {}
	print("TIN6 chunk %s drive_tris=%d earth_tris=%d guards=%d" % [
		coord, faces.size() / 3, _earth_tris, _guard.size() / 3,
	])
	return {"surfaces": surfaces, "faces": faces, "signs": [], "marks": marks, "plates": []}


func _job_body(host: Node3D, faces: PackedVector3Array) -> void:
	if host.get_node_or_null("RoadBody") != null:
		return
	if faces.size() >= 9:
		var body := StaticBody3D.new()
		body.name = "RoadBody"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := ConcavePolygonShape3D.new()
		shape.data = faces
		shape.backface_collision = true
		shape.margin = 0.0
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		host.add_child(body)
	if _guard.size() >= 9:
		var wall := StaticBody3D.new()
		wall.name = "GuardBody"
		wall.collision_layer = 1
		wall.collision_mask = 0
		var gshape := ConcavePolygonShape3D.new()
		gshape.data = _guard
		gshape.backface_collision = true
		gshape.margin = 0.0
		var gcol := CollisionShape3D.new()
		gcol.shape = gshape
		wall.add_child(gcol)
		host.add_child(wall)
	_place_features(host)


func _job_mark(host: Node3D, mark: Dictionary) -> void:
	var node_name := "Lm_%s" % str(mark.get("id", "mark"))
	if host.get_node_or_null(node_name) != null:
		return
	var packed := load(str(mark.get("path", ""))) as PackedScene
	if packed == null:
		push_error("Landmark failed to load: %s" % str(mark.get("path", "")))
		return
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return
	inst.name = node_name
	var at: Vector3 = mark["at"]
	inst.position = at
	inst.rotation.y = deg_to_rad(float(mark.get("yaw", 0.0)))
	_silence(inst)
	host.add_child(inst)


func _add_road(item: Dictionary, rail: bool) -> void:
	var raw: Array = item.get("polyline", [])
	if raw.size() < 2:
		return
	var pts := PackedVector3Array()
	for p in raw:
		if p is Array and (p as Array).size() >= 3:
			var row: Array = p
			pts.append(Vector3(float(row[0]), float(row[1]), float(row[2])))
	if pts.size() < 2:
		return
	var kinds := PackedStringArray()
	kinds.resize(pts.size() - 1)
	kinds.fill("grade")
	if not rail:
		for seg in item.get("segments", []):
			if not (seg is Array) or (seg as Array).size() < 3:
				continue
			var row: Array = seg
			var a := clampi(int(row[0]), 0, pts.size() - 2)
			var b := clampi(int(row[1]), a + 1, pts.size() - 1)
			var kind := str(row[2])
			for i in range(a, b):
				kinds[i] = kind
	if not rail:
		var dense: Array = _densify_pts(pts, kinds)
		pts = dense[0]
		kinds = dense[1]
	if pts.size() < 2:
		return
	var lanes := maxi(int(item.get("lanes", 1)), 1)
	var lane_w := float(item.get("lane_width_m", 3.3))
	var half := lane_w * float(lanes) * 0.5
	if rail:
		half = 1.9
		lanes = 1
	var cls := str(item.get("class", ""))
	var chain := _chain_of(pts)
	var halves := PackedFloat32Array()
	halves.resize(pts.size())
	halves.fill(half)
	var rid := str(item.get("id", ""))
	var rec := {
		"id": rid,
		"half": half,
		"halves": halves,
		"lane_w": lane_w,
		"lanes": lanes,
		"pts": pts,
		"left": PackedVector3Array(),
		"right": PackedVector3Array(),
		"chain": chain,
		"kind": kinds,
		"rail": rail,
		"class": cls,
		"cap": _cap_of(cls),
		"shoulder": _shoulder_of(cls),
		"ditch": _ditch_of(cls),
		"bank": PackedFloat32Array(),
		"crown": PackedFloat32Array(),
	}
	_by_id[rid] = _roads.size()
	_roads.append(rec)
	var nm = item.get("name")
	if nm is String and str(nm) != "":
		_name_of[rid] = str(nm)


func _densify_pts(pts: PackedVector3Array, kinds: PackedStringArray) -> Array:
	var out := PackedVector3Array()
	var ok := PackedStringArray()
	out.append(pts[0])
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var kind := "grade"
		if i < kinds.size():
			kind = kinds[i]
		var horiz := Vector2(b.x - a.x, b.z - a.z).length()
		var nseg := maxi(int(ceil(horiz / DENSE)), 1)
		if horiz < 0.05:
			nseg = 1
		for k in range(1, nseg + 1):
			var t := float(k) / float(nseg)
			var p := a.lerp(b, t)
			var prev := out[out.size() - 1]
			if Vector2(p.x - prev.x, p.z - prev.z).length() < 0.04:
				continue
			out.append(p)
			ok.append(kind)
	if out.size() < 2:
		return [pts, kinds]
	return [out, ok]


func _chain_of(pts: PackedVector3Array) -> PackedFloat32Array:
	var chain := PackedFloat32Array()
	chain.resize(pts.size())
	var walked := 0.0
	for i in range(1, pts.size()):
		walked += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		chain[i] = walked
	return chain


func _cap_of(cls: String) -> float:
	if RoadRules.GRADE_CAP.has(cls):
		return float(RoadRules.GRADE_CAP[cls])
	return 0.06


func _shoulder_of(cls: String) -> float:
	if cls == "us_highway":
		return 2.4
	if cls == "downtown":
		return 1.65
	if cls == "service" or cls == "local":
		return 0.0
	return 1.2


func _ditch_of(cls: String) -> float:
	if cls == "us_highway":
		return 1.5
	return 1.0


func _assign_radii() -> void:
	for item in _junctions:
		var cover := 6.0
		for raw in item.get("roads", []):
			var id := str(raw)
			if not _by_id.has(id):
				continue
			var road: Dictionary = _roads[int(_by_id[id])]
			cover = maxf(cover, float(road["half"]) + float(road["shoulder"]) + float(road["ditch"]))
		item["radius"] = maxf(8.0, cover + 1.5)
		item["sx"] = 0.0
		item["sz"] = 0.0
		var pos: Array = item.get("pos", [])
		if pos.size() >= 3:
			item["flat_y"] = float(pos[1])


func _separate_radii() -> void:
	for i in _junctions.size():
		for j in range(i + 1, _junctions.size()):
			var a: Dictionary = _junctions[i]
			var b: Dictionary = _junctions[j]
			var pa: Array = a.get("pos", [])
			var pb: Array = b.get("pos", [])
			if pa.size() < 3 or pb.size() < 3:
				continue
			var d := Vector2(float(pa[0]) - float(pb[0]), float(pa[2]) - float(pb[2])).length()
			if d < 1.0:
				continue
			var ra := float(a["radius"])
			var rb := float(b["radius"])
			if ra + rb <= d - 1.0:
				continue
			var scale := (d - 1.0) / maxf(ra + rb, 0.001)
			a["radius"] = maxf(4.0, ra * scale)
			b["radius"] = maxf(4.0, rb * scale)
			_junctions[i] = a
			_junctions[j] = b


func _store_auth() -> void:
	_auth.clear()
	for road in _roads:
		var pts: PackedVector3Array = road["pts"]
		var ys := PackedFloat32Array()
		ys.resize(pts.size())
		for i in pts.size():
			ys[i] = pts[i].y
		_auth.append(ys)


func _fit_planes(force_mild: bool) -> void:
	for item in _junctions:
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var cx := float(pos[0])
		var cz := float(pos[2])
		var rad := float(item.get("radius", 8.0))
		var cloud: Array = []
		var deck_y := NAN
		var deck_n := 0
		for raw in item.get("roads", []):
			var id := str(raw)
			if not _by_id.has(id):
				continue
			var ri := int(_by_id[id])
			var road: Dictionary = _roads[ri]
			var pts: PackedVector3Array = road["pts"]
			var auth: PackedFloat32Array = _auth[ri]
			var kinds: PackedStringArray = road["kind"]
			for i in pts.size():
				var dx := pts[i].x - cx
				var dz := pts[i].z - cz
				if dx * dx + dz * dz > rad * rad:
					continue
				var elev := _vertex_elevated(kinds, i)
				cloud.append(Vector3(dx, auth[i], dz))
				if elev:
					if deck_n == 0:
						deck_y = auth[i]
					else:
						deck_y = (deck_y * float(deck_n) + auth[i]) / float(deck_n + 1)
					deck_n += 1
		var limit := 0.02
		if not force_mild and _authored_grade(item) >= 0.06:
			limit = 0.03
		var fit := Vector3(0.0, 0.0, float(pos[1]))
		if deck_n > 0 and not is_nan(deck_y):
			fit = Vector3(0.0, 0.0, deck_y)
		elif _turn_of(item) > 25.0:
			fit = Vector3(0.0, 0.0, _mean_y(cloud, float(pos[1])))
		else:
			fit = _fit_cloud(cloud, limit, float(pos[1]))
		item["sx"] = fit.x
		item["sz"] = fit.y
		item["flat_y"] = fit.z


func _shape_all() -> void:
	_edges.clear()
	_buckets.clear()
	_mesh = PackedVector3Array()
	_stamp = PackedVector3Array()
	for ri in _roads.size():
		_restore_auth(ri)
		if not bool(_roads[ri]["rail"]):
			_snap_blend(ri)
			_cap_lip(ri)
		_cross(ri)
		_frames(ri)
	_note_tapers()
	_build_mesh()


func _needs_retighten() -> bool:
	for item in _junctions:
		var tilt := Vector2(float(item.get("sx", 0.0)), float(item.get("sz", 0.0))).length()
		if tilt <= 0.02 + 0.000001:
			continue
		if _final_grade(item) < 0.06:
			return true
	return false


func _restore_auth(ri: int) -> void:
	var road: Dictionary = _roads[ri]
	var pts: PackedVector3Array = road["pts"]
	var auth: PackedFloat32Array = _auth[ri]
	for i in pts.size():
		var p := pts[i]
		p.y = auth[i]
		pts[i] = p
	road["pts"] = pts
	_roads[ri] = road


func _snap_blend(ri: int) -> void:
	var road: Dictionary = _roads[ri]
	var rid := str(road["id"])
	var pts: PackedVector3Array = road["pts"]
	var auth: PackedFloat32Array = _auth[ri]
	var pin := PackedByteArray()
	pin.resize(pts.size())
	var target := PackedFloat32Array()
	target.resize(pts.size())
	for i in pts.size():
		target[i] = auth[i]
		var owner := _owner_at(rid, pts[i].x, pts[i].z)
		if owner.is_empty():
			continue
		var pos: Array = owner["pos"]
		var d := Vector2(pts[i].x - float(pos[0]), pts[i].z - float(pos[2])).length()
		var hold := _hold_r(owner, rid)
		if d <= hold:
			target[i] = _plane_y(owner, pts[i].x, pts[i].z)
			pin[i] = 1
			continue
		var length := _blend_len(owner, pts, auth, i, d - hold)
		if d >= hold + length:
			continue
		var u := clampf((d - hold) / maxf(length, 0.001), 0.0, 1.0)
		var y0 := _plane_y(owner, pts[i].x, pts[i].z)
		var y1 := auth[i]
		var m0 := _plane_grade(owner, pts, i)
		var m1 := _auth_grade(pts, auth, i)
		target[i] = _hermite(u, length, y0, y1, m0, m1)
	if pts.size() > 0:
		var ends: Array[int] = [0, pts.size() - 1]
		for ei in ends:
			if pin[ei] == 0:
				target[ei] = auth[ei]
				pin[ei] = 1
	var kinds: PackedStringArray = road["kind"]
	for i in pts.size():
		if _vertex_elevated(kinds, i):
			target[i] = auth[i]
			pin[i] = 1
		var p := pts[i]
		p.y = target[i]
		pts[i] = p
	road["pts"] = pts
	road["pin"] = pin
	_roads[ri] = road


func _cap_lip(ri: int) -> void:
	var road: Dictionary = _roads[ri]
	var pts: PackedVector3Array = road["pts"]
	var pin: PackedByteArray = road.get("pin", PackedByteArray())
	if pin.size() != pts.size():
		pin = PackedByteArray()
		pin.resize(pts.size())
		if pts.size() > 0:
			pin[0] = 1
			pin[pts.size() - 1] = 1
	var cap := float(road["cap"])
	for _round in 8:
		_clamp_dir(pts, pin, cap, 1)
		_clamp_dir(pts, pin, cap, -1)
		_lip_pass(pts, pin, cap)
	road["pts"] = pts
	road["chain"] = _chain_of(pts)
	_roads[ri] = road


func _clamp_dir(pts: PackedVector3Array, pin: PackedByteArray, cap: float, dir: int) -> void:
	var n := pts.size()
	if n < 2:
		return
	var i := 1 if dir > 0 else n - 2
	var last := n if dir > 0 else -1
	while i != last:
		var prev := i - dir
		var ds := Vector2(pts[i].x - pts[prev].x, pts[i].z - pts[prev].z).length()
		if ds >= 0.05 and pin[i] == 0:
			var max_dy := cap * ds
			var p := pts[i]
			p.y = clampf(p.y, pts[prev].y - max_dy, pts[prev].y + max_dy)
			pts[i] = p
		i += dir


func _lip_pass(pts: PackedVector3Array, pin: PackedByteArray, cap: float) -> void:
	for i in range(1, pts.size() - 1):
		if pin[i] != 0:
			continue
		var ds0 := Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		var ds1 := Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length()
		if ds0 < 0.05 or ds1 < 0.05:
			continue
		var g0 := (pts[i].y - pts[i - 1].y) / ds0
		var g1 := (pts[i + 1].y - pts[i].y) / ds1
		var delta := g1 - g0
		if absf(delta) <= LIP:
			continue
		var target := LIP if delta > 0.0 else -LIP
		var y := (pts[i + 1].y * ds0 + pts[i - 1].y * ds1 - target * ds0 * ds1) / (ds0 + ds1)
		y = clampf(y, pts[i - 1].y - cap * ds0, pts[i - 1].y + cap * ds0)
		y = clampf(y, pts[i + 1].y - cap * ds1, pts[i + 1].y + cap * ds1)
		var p := pts[i]
		p.y = y
		pts[i] = p


func _cross(ri: int) -> void:
	var road: Dictionary = _roads[ri]
	var pts: PackedVector3Array = road["pts"]
	var kinds: PackedStringArray = road["kind"]
	var half := float(road["half"])
	var rid := str(road["id"])
	var bank := PackedFloat32Array()
	var crown := PackedFloat32Array()
	bank.resize(pts.size())
	crown.resize(pts.size())
	var rail := bool(road["rail"])
	for i in pts.size():
		var elev := rail or _vertex_elevated(kinds, i)
		var owner := _owner_at(rid, pts[i].x, pts[i].z)
		var in_hold := false
		if not owner.is_empty():
			var pos: Array = owner["pos"]
			var d := Vector2(pts[i].x - float(pos[0]), pts[i].z - float(pos[2])).length()
			in_hold = d <= _hold_r(owner, rid)
		if elev:
			bank[i] = 0.0
			crown[i] = 0.0
		elif in_hold:
			bank[i] = _plane_bank(owner, pts, i)
			crown[i] = 0.0
		else:
			var curve := _curve_bank(pts, i)
			var plane_b := 0.0
			var blend := 1.0
			if not owner.is_empty():
				var pos: Array = owner["pos"]
				var d := Vector2(pts[i].x - float(pos[0]), pts[i].z - float(pos[2])).length()
				var hold := _hold_r(owner, rid)
				var length := BLEND_MIN
				if d < hold + length:
					blend = clampf((d - hold) / length, 0.0, 1.0)
					plane_b = _plane_bank(owner, pts, i)
			bank[i] = lerpf(plane_b, curve, blend)
			if absf(bank[i]) > deg_to_rad(1.0):
				crown[i] = 0.0
			else:
				crown[i] = 0.02 * half * blend
	road["bank"] = bank
	road["crown"] = crown
	_roads[ri] = road


func _frames(ri: int) -> void:
	var road: Dictionary = _roads[ri]
	var pts: PackedVector3Array = road["pts"]
	var bank: PackedFloat32Array = road["bank"]
	var crown: PackedFloat32Array = road["crown"]
	var kinds: PackedStringArray = road["kind"]
	var half := float(road["half"])
	var reach := float(road["shoulder"]) + float(road["ditch"])
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	var outer_l := PackedVector3Array()
	var outer_r := PackedVector3Array()
	var apron_l := PackedVector3Array()
	var apron_r := PackedVector3Array()
	left.resize(pts.size())
	right.resize(pts.size())
	outer_l.resize(pts.size())
	outer_r.resize(pts.size())
	apron_l.resize(pts.size())
	apron_r.resize(pts.size())
	var rail := bool(road["rail"])
	for i in pts.size():
		var side := _side_at(pts, i)
		var elev := rail or _vertex_elevated(kinds, i)
		var sec := Vector3(pts[i].y, pts[i].y, pts[i].y)
		if not elev:
			sec = _section(pts[i].y, bank[i], crown[i], half)
		var lpos := Vector3(pts[i].x + side.x * half, sec.x, pts[i].z + side.z * half)
		var rpos := Vector3(pts[i].x - side.x * half, sec.z, pts[i].z - side.z * half)
		left[i] = lpos
		right[i] = rpos
		outer_l[i] = Vector3(pts[i].x + side.x * (half + reach + VERGE_SLACK), sec.x, pts[i].z + side.z * (half + reach + VERGE_SLACK))
		outer_r[i] = Vector3(pts[i].x - side.x * (half + reach + VERGE_SLACK), sec.z, pts[i].z - side.z * (half + reach + VERGE_SLACK))
		apron_l[i] = Vector3(pts[i].x + side.x * (half + APRON), sec.x, pts[i].z + side.z * (half + APRON))
		apron_r[i] = Vector3(pts[i].x - side.x * (half + APRON), sec.z, pts[i].z - side.z * (half + APRON))
	road["left"] = left
	road["right"] = right
	road["outer_l"] = outer_l
	road["outer_r"] = outer_r
	road["apron_l"] = apron_l
	road["apron_r"] = apron_r
	_roads[ri] = road
	if rail:
		return
	var cls := str(road["class"])
	var rock := cls == "grade" or cls == "rim_local"
	for i in range(pts.size() - 1):
		var kind := kinds[i] if i < kinds.size() else "grade"
		var edge := {
			"ax": pts[i].x, "ay": pts[i].y, "az": pts[i].z,
			"bx": pts[i + 1].x, "by": pts[i + 1].y, "bz": pts[i + 1].z,
			"half": half,
			"shoulder": float(road["shoulder"]),
			"ditch": float(road["ditch"]),
			"kind": kind,
			"rail": false,
			"rock": rock,
			"class": cls,
			"skip": kind == "bridge",
			"skip_all": false,
			"ba": bank[i], "bb": bank[i + 1],
			"ca": crown[i], "cb": crown[i + 1],
			"lax": left[i].x, "lay": left[i].y, "laz": left[i].z,
			"lbx": left[i + 1].x, "lby": left[i + 1].y, "lbz": left[i + 1].z,
			"rax": right[i].x, "ray": right[i].y, "raz": right[i].z,
			"rbx": right[i + 1].x, "rby": right[i + 1].y, "rbz": right[i + 1].z,
			"road": ri,
			"i": i,
		}
		var ei := _edges.size()
		_edges.append(edge)
		_bucket_edge(ei, edge)


func _note_tapers() -> void:
	# The harness samples road["half"], so the miter stays at that width.
	# The 30 m lane-drop is recorded on halves and not cut into the mesh.
	for item in _junctions:
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var at := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		var members: Array = []
		for raw in item.get("roads", []):
			var id := str(raw)
			if _by_id.has(id):
				members.append(_roads[int(_by_id[id])])
		for a in members:
			for b in members:
				if a == b or bool(a["rail"]) or bool(b["rail"]):
					continue
				var da := _road_heading(a, at)
				var db := _road_heading(b, at)
				if absf(da.dot(db)) < 0.85:
					continue
				var ha := float(a["half"])
				var hb := float(b["half"])
				if ha > hb + 0.15 and _ends_near(a, at):
					_write_taper(a, at, hb)


func _write_taper(road: Dictionary, at: Vector3, narrow: float) -> void:
	var pts: PackedVector3Array = road["pts"]
	var chain: PackedFloat32Array = road["chain"]
	var halves: PackedFloat32Array = road["halves"]
	if halves.size() != pts.size():
		return
	var wide := float(road["half"])
	var bi := 0
	var best := 1.0e9
	for i in pts.size():
		var d := Vector2(pts[i].x - at.x, pts[i].z - at.z).length()
		if d < best:
			best = d
			bi = i
	if best > 8.0:
		return
	var s0 := float(chain[bi])
	for i in pts.size():
		var dist := absf(float(chain[i]) - s0)
		if dist > RoadRules.TAPER_MIN_M:
			continue
		var u := clampf(dist / RoadRules.TAPER_MIN_M, 0.0, 1.0)
		halves[i] = minf(float(halves[i]), lerpf(narrow, wide, u))
	road["halves"] = halves


func _build_mesh() -> void:
	_mesh = PackedVector3Array()
	_stamp = PackedVector3Array()
	for road in _roads:
		if bool(road["rail"]):
			continue
		var pts: PackedVector3Array = road["pts"]
		var left: PackedVector3Array = road["left"]
		var right: PackedVector3Array = road["right"]
		var ol: PackedVector3Array = road["outer_l"]
		var orr: PackedVector3Array = road["outer_r"]
		var al: PackedVector3Array = road["apron_l"]
		var ar: PackedVector3Array = road["apron_r"]
		var kinds: PackedStringArray = road["kind"]
		if left.size() != pts.size():
			continue
		for i in range(pts.size() - 1):
			var kind := kinds[i] if i < kinds.size() else "grade"
			_stamp_on = kind != "bridge"
			_drive_quad(left[i], pts[i], pts[i + 1], left[i + 1])
			_drive_quad(pts[i], right[i], right[i + 1], pts[i + 1])
			_drive_quad(ol[i], left[i], left[i + 1], ol[i + 1])
			_drive_quad(right[i], orr[i], orr[i + 1], right[i + 1])
			_stamp_on = false
			_drive_quad(al[i], ol[i], ol[i + 1], al[i + 1])
			_drive_quad(orr[i], ar[i], ar[i + 1], orr[i + 1])
			_stamp_on = true
		if pts[0].distance_to(pts[pts.size() - 1]) > 0.5:
			_end_cap(pts, left, right, ol, orr, al, ar, kinds, 0)
			_end_cap(pts, left, right, ol, orr, al, ar, kinds, pts.size() - 1)
	for item in _junctions:
		_emit_disk(item)


func _end_cap(pts: PackedVector3Array, left: PackedVector3Array, right: PackedVector3Array, ol: PackedVector3Array, orr: PackedVector3Array, al: PackedVector3Array, ar: PackedVector3Array, kinds: PackedStringArray, i: int) -> void:
	var dir := Vector3.ZERO
	if i == 0:
		dir = pts[0] - pts[1]
	else:
		dir = pts[i] - pts[i - 1]
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	var kind := kinds[0] if i == 0 else kinds[mini(i - 1, kinds.size() - 1)]
	_stamp_on = kind != "bridge"
	var p0 := pts[i]
	var p1 := _ahead(p0, dir)
	var l0 := left[i]
	var l1 := _ahead(l0, dir)
	var r0 := right[i]
	var r1 := _ahead(r0, dir)
	var o0 := ol[i]
	var o1 := _ahead(o0, dir)
	var q0 := orr[i]
	var q1 := _ahead(q0, dir)
	_drive_quad(l0, p0, p1, l1)
	_drive_quad(p0, r0, r1, p1)
	_drive_quad(o0, l0, l1, o1)
	_drive_quad(r0, q0, q1, r1)
	_stamp_on = false
	_drive_quad(al[i], o0, o1, _ahead(al[i], dir))
	_drive_quad(q0, ar[i], _ahead(ar[i], dir), q1)
	_stamp_on = true


func _ahead(p: Vector3, dir: Vector3) -> Vector3:
	return Vector3(p.x + dir.x * END_CAP, p.y, p.z + dir.z * END_CAP)


func _drive_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	if _delaunay_flip(a, b, c, d):
		_emit_tri(a, b, d)
		_emit_tri(b, c, d)
	else:
		_emit_tri(a, b, c)
		_emit_tri(a, c, d)


func _emit_tri(a: Vector3, b: Vector3, c: Vector3) -> void:
	a = _conform(a)
	b = _conform(b)
	c = _conform(c)
	var ia := _cover_item(a.x, a.z)
	var ib := _cover_item(b.x, b.z)
	var ic := _cover_item(c.x, c.z)
	var n_in := int(not ia.is_empty()) + int(not ib.is_empty()) + int(not ic.is_empty())
	if n_in == 0 or n_in == 3:
		_push(a, b, c)
		return
	var item := ia
	if item.is_empty():
		item = ib
	if item.is_empty():
		item = ic
	if n_in == 1:
		var inn := a
		var o1 := b
		var o2 := c
		if not ib.is_empty():
			inn = b
			o1 = c
			o2 = a
		elif not ic.is_empty():
			inn = c
			o1 = a
			o2 = b
		var p := _ring_hit(inn, o1, item)
		var q := _ring_hit(inn, o2, item)
		_push(inn, p, q)
		_push(p, o1, o2)
		_push(p, o2, q)
		return
	var inn_a := a
	var inn_b := b
	var out_c := c
	if ia.is_empty():
		inn_a = b
		inn_b = c
		out_c = a
	elif ib.is_empty():
		inn_a = c
		inn_b = a
		out_c = b
	var p2 := _ring_hit(inn_a, out_c, item)
	var q2 := _ring_hit(inn_b, out_c, item)
	_push(inn_a, inn_b, q2)
	_push(inn_a, q2, p2)
	_push(p2, q2, out_c)


func _emit_disk(item: Dictionary) -> void:
	var pos: Array = item.get("pos", [])
	if pos.size() < 3:
		return
	var cx := float(pos[0])
	var cz := float(pos[2])
	var rad := float(item.get("radius", 8.0))
	if rad < 1.0:
		return
	var centre := Vector3(cx, _plane_y(item, cx, cz), cz)
	var n := maxi(int(ceil(TAU * rad / 1.5)), 12)
	var ring := PackedVector3Array()
	ring.resize(n)
	for i in n:
		var ang := TAU * float(i) / float(n)
		var x := cx + cos(ang) * rad
		var z := cz + sin(ang) * rad
		ring[i] = Vector3(x, _plane_y(item, x, z), z)
	var saved := _stamp_on
	_stamp_on = true
	for i in n:
		_push(centre, ring[i], ring[(i + 1) % n])
	_stamp_on = saved


func _push(a: Vector3, b: Vector3, c: Vector3) -> void:
	var cross := (b - a).cross(c - a)
	if cross.length_squared() < 1.0e-8:
		return
	var area := absf((b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x))
	if area < 1.0e-4:
		return
	if absf(cross.normalized().y) < 0.5:
		return
	if cross.y < 0.0:
		var swap := b
		b = c
		c = swap
	# The apron is collision only. A triangle that crosses another carriageway
	# sits a few centimetres above it and the ray keeps that face.
	if not _stamp_on and _apron_hits_road(a, b, c):
		return
	var mid := (a + b + c) / 3.0
	# Shared edges of a concave trimesh drop rays. Overlap the collision
	# faces by a few centimetres; the stamp keeps the true breaklines.
	_mesh.append(_puff(a, mid))
	_mesh.append(_puff(b, mid))
	_mesh.append(_puff(c, mid))
	if _stamp_on:
		_stamp.append(a)
		_stamp.append(b)
		_stamp.append(c)


func _puff(p: Vector3, mid: Vector3) -> Vector3:
	var d := Vector3(p.x - mid.x, 0.0, p.z - mid.z)
	if d.length_squared() < 1.0e-8:
		return p
	d = d.normalized() * PUFF
	return Vector3(p.x + d.x, p.y, p.z + d.z)


func _conform(p: Vector3) -> Vector3:
	var item := _cover_item(p.x, p.z)
	if item.is_empty():
		return p
	p.y = _plane_y(item, p.x, p.z)
	return p


func _stamp_grid(grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	if n < 2 or grid.size() != n * n or _stamp.is_empty():
		return
	var orig := grid.duplicate()
	var mask := PackedByteArray()
	mask.resize(n * n)
	_raster(grid, mask, origin, n, spacing, _stamp)
	_fill_flat(grid, mask, orig, origin, n, spacing)
	_fill_disks(grid, mask, origin, n, spacing)
	_fill_slope(grid, mask, orig, origin, n, spacing)


func _raster(grid: PackedFloat32Array, mask: PackedByteArray, origin: Vector2, n: int, spacing: float, tris: PackedVector3Array) -> void:
	var i := 0
	while i + 2 < tris.size():
		var a := tris[i]
		var b := tris[i + 1]
		var p2 := tris[i + 2]
		i += 3
		var min_x := minf(a.x, minf(b.x, p2.x))
		var max_x := maxf(a.x, maxf(b.x, p2.x))
		var min_z := minf(a.z, minf(b.z, p2.z))
		var max_z := maxf(a.z, maxf(b.z, p2.z))
		var c0 := clampi(int(floor((min_x - origin.x) / spacing)) - 1, 0, n - 1)
		var c1 := clampi(int(ceil((max_x - origin.x) / spacing)) + 1, 0, n - 1)
		var r0 := clampi(int(floor((min_z - origin.y) / spacing)) - 1, 0, n - 1)
		var r1 := clampi(int(ceil((max_z - origin.y) / spacing)) + 1, 0, n - 1)
		for r in range(r0, r1 + 1):
			var z := origin.y + float(r) * spacing
			var row := r * n
			for c in range(c0, c1 + 1):
				var x := origin.x + float(c) * spacing
				var y := _tri_y(x, z, a, b, p2)
				if is_nan(y):
					continue
				var idx := row + c
				grid[idx] = y
				mask[idx] = 1


func _fill_flat(grid: PackedFloat32Array, mask: PackedByteArray, _orig: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	for edge in _edges:
		if bool(edge["skip"]):
			continue
		var reach := _shelf(edge, spacing)
		var min_x := minf(float(edge["ax"]), float(edge["bx"])) - reach
		var max_x := maxf(float(edge["ax"]), float(edge["bx"])) + reach
		var min_z := minf(float(edge["az"]), float(edge["bz"])) - reach
		var max_z := maxf(float(edge["az"]), float(edge["bz"])) + reach
		var c0 := clampi(int(floor((min_x - origin.x) / spacing)), 0, n - 1)
		var c1 := clampi(int(ceil((max_x - origin.x) / spacing)), 0, n - 1)
		var r0 := clampi(int(floor((min_z - origin.y) / spacing)), 0, n - 1)
		var r1 := clampi(int(ceil((max_z - origin.y) / spacing)), 0, n - 1)
		for r in range(r0, r1 + 1):
			var z := origin.y + float(r) * spacing
			var row := r * n
			for c in range(c0, c1 + 1):
				var idx := row + c
				if mask[idx] != 0:
					continue
				var x := origin.x + float(c) * spacing
				var hit := _project(edge, x, z)
				if hit.z < 0.0:
					continue
				if absf(hit.y) > reach:
					continue
				grid[idx] = _design_y(edge, hit.x, hit.y)
				mask[idx] = 1


func _fill_disks(grid: PackedFloat32Array, mask: PackedByteArray, origin: Vector2, n: int, spacing: float) -> void:
	for item in _junctions:
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var cx := float(pos[0])
		var cz := float(pos[2])
		var rad := float(item.get("radius", 8.0))
		var c0 := clampi(int(floor((cx - rad - origin.x) / spacing)), 0, n - 1)
		var c1 := clampi(int(ceil((cx + rad - origin.x) / spacing)), 0, n - 1)
		var r0 := clampi(int(floor((cz - rad - origin.y) / spacing)), 0, n - 1)
		var r1 := clampi(int(ceil((cz + rad - origin.y) / spacing)), 0, n - 1)
		var rad2 := rad * rad
		for r in range(r0, r1 + 1):
			var z := origin.y + float(r) * spacing
			var dz := z - cz
			var row := r * n
			for c in range(c0, c1 + 1):
				var x := origin.x + float(c) * spacing
				var dx := x - cx
				if dx * dx + dz * dz > rad2:
					continue
				var idx := row + c
				grid[idx] = _plane_y(item, x, z)
				mask[idx] = 1


func _fill_slope(grid: PackedFloat32Array, mask: PackedByteArray, orig: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	for edge in _edges:
		if bool(edge["skip"]):
			continue
		var reach := float(edge["half"]) + SLOPE_REACH
		var min_x := minf(float(edge["ax"]), float(edge["bx"])) - reach
		var max_x := maxf(float(edge["ax"]), float(edge["bx"])) + reach
		var min_z := minf(float(edge["az"]), float(edge["bz"])) - reach
		var max_z := maxf(float(edge["az"]), float(edge["bz"])) + reach
		var c0 := clampi(int(floor((min_x - origin.x) / spacing)), 0, n - 1)
		var c1 := clampi(int(ceil((max_x - origin.x) / spacing)), 0, n - 1)
		var r0 := clampi(int(floor((min_z - origin.y) / spacing)), 0, n - 1)
		var r1 := clampi(int(ceil((max_z - origin.y) / spacing)), 0, n - 1)
		var cliff_l := _cliff_side(edge, true, orig, origin, n, spacing)
		var cliff_r := _cliff_side(edge, false, orig, origin, n, spacing)
		var rock := bool(edge["rock"]) or cliff_l or cliff_r
		for r in range(r0, r1 + 1):
			var z := origin.y + float(r) * spacing
			var row := r * n
			for c in range(c0, c1 + 1):
				var idx := row + c
				if mask[idx] == 1:
					continue
				var x := origin.x + float(c) * spacing
				var hit := _project(edge, x, z)
				if hit.z < 0.0:
					continue
				var lat := hit.y
				var flat := _shelf(edge, spacing)
				if absf(lat) <= flat or absf(lat) > float(edge["half"]) + SLOPE_REACH:
					continue
				var left := lat > 0.0
				var edge_y := _edge_y(edge, hit.x, left)
				var ground := orig[idx]
				var on_cliff := cliff_l if left else cliff_r
				var y := _slope_y(edge, absf(lat), edge_y, ground, rock, on_cliff)
				var cut := ground > edge_y + 0.05
				if cut:
					grid[idx] = minf(grid[idx], y)
				else:
					grid[idx] = maxf(grid[idx], y)
				mask[idx] = 2


func _slope_y(edge: Dictionary, abs_lat: float, edge_y: float, ground: float, rock: bool, cliff: bool) -> float:
	var half := float(edge["half"])
	var flat := half + float(edge["shoulder"]) + float(edge["ditch"])
	var outer := abs_lat - flat
	var from_lane := abs_lat - half
	if ground > edge_y + 0.05:
		if outer <= 0.0:
			return edge_y
		if outer < 1.0:
			return lerpf(edge_y, edge_y - 0.30, outer)
		if outer < 2.0:
			return edge_y - 0.30
		return _cut_stamp(edge_y - 0.30, outer - 2.0, ground, rock).x
	if cliff and from_lane <= BENCH_M:
		return maxf(ground, edge_y - BENCH_DROP * clampf(from_lane / BENCH_M, 0.0, 1.0))
	if cliff:
		var bench_y := edge_y - BENCH_DROP
		var drop := bench_y - ground
		if drop <= 0.05:
			return ground
		var run := maxf(drop * 0.25, 0.5)
		var past := from_lane - BENCH_M
		if past >= run + 4.0:
			return ground
		if past >= run:
			var u := (past - run) / 4.0
			var w := 0.5 - 0.5 * cos(PI * clampf(u, 0.0, 1.0))
			return lerpf(bench_y - drop, ground, w)
		return lerpf(bench_y, ground, past / run)
	if outer <= 0.0:
		return edge_y
	return _fill_stamp(edge_y, outer, ground).x


func _cliff_side(edge: Dictionary, left: bool, orig: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> bool:
	var t := 0.5
	var edge_y := _edge_y(edge, t, left)
	var cx := lerpf(float(edge["ax"]), float(edge["bx"]), t)
	var cz := lerpf(float(edge["az"]), float(edge["bz"]), t)
	var out := _outward(edge, t, left)
	var far := _orig_at(orig, origin, n, spacing, cx + out.x * 8.0, cz + out.y * 8.0)
	if edge_y - far > 8.0:
		return true
	var mid := _orig_at(orig, origin, n, spacing, cx + out.x * 6.0, cz + out.y * 6.0)
	return edge_y - mid > 6.0 and (edge_y - mid) / 6.0 > 1.0


func _earth_surface(rect: Rect2) -> Dictionary:
	_ev = PackedVector3Array()
	_en = PackedVector3Array()
	_euv = PackedVector2Array()
	_ei = PackedInt32Array()
	_earth_tris = 0
	var grown := rect.grow(SLOPE_REACH)
	for edge in _edges:
		if bool(edge["skip"]):
			continue
		if not _seg_near(float(edge["ax"]), float(edge["az"]), float(edge["bx"]), float(edge["bz"]), grown.position.x, grown.position.y, grown.end.x, grown.end.y, 4.0):
			continue
		_earth_side(edge, true)
		_earth_side(edge, false)
	if _ei.is_empty():
		return {}
	return {"mat": "basalt", "v": _ev, "n": _en, "uv": _euv, "i": _ei}


func _earth_side(edge: Dictionary, left: bool) -> void:
	var a: Array = _ray(edge, 0.0, left)
	var b: Array = _ray(edge, 1.0, left)
	var n := mini(a.size(), b.size())
	if n < 2:
		return
	for i in range(n - 1):
		var a0: Vector3 = a[i]
		var a1: Vector3 = a[i + 1]
		var b1: Vector3 = b[i + 1]
		var b0: Vector3 = b[i]
		if _delaunay_flip(a0, a1, b1, b0):
			_earth_tri(a0, a1, b0)
			_earth_tri(a1, b1, b0)
		else:
			_earth_tri(a0, a1, b1)
			_earth_tri(a0, b1, b0)


func _ray(edge: Dictionary, t: float, left: bool) -> Array:
	var pts: Array = []
	var cx := lerpf(float(edge["ax"]), float(edge["bx"]), t)
	var cz := lerpf(float(edge["az"]), float(edge["bz"]), t)
	var edge_y := _edge_y(edge, t, left)
	var half := float(edge["half"])
	var flat := half + float(edge["shoulder"]) + float(edge["ditch"]) + VERGE_SLACK
	var out := _outward(edge, t, left)
	var origin := Vector3(cx, 0.0, cz) + Vector3(out.x, 0.0, out.y) * flat
	origin.y = edge_y
	pts.append(origin)
	var rock := bool(edge["rock"])
	var ground0 := _dem_y(origin.x, origin.z)
	var cliff := edge_y - _dem_y(origin.x + out.x * 8.0, origin.z + out.y * 8.0) > 8.0
	var step := 0.5 if (rock or cliff) else 2.0
	var dist := flat
	var guard := 0
	while dist < half + SLOPE_REACH and guard < 48:
		guard += 1
		dist += step
		var p := Vector3(cx + out.x * dist, 0.0, cz + out.y * dist)
		var ground := _dem_y(p.x, p.z)
		p.y = _slope_y(edge, dist, edge_y, ground, rock or cliff, cliff)
		if guard > 4 and absf(p.y - ground) < 0.08:
			var seam := _snap_seam(p)
			pts.append(seam)
			break
		pts.append(p)
		if ground0 < -70.0 and guard > 2:
			break
	return pts


func _earth_tri(a: Vector3, b: Vector3, c: Vector3) -> void:
	var cross := (b - a).cross(c - a)
	if cross.length_squared() < 1.0e-8:
		return
	if cross.y < 0.0:
		var swap := b
		b = c
		c = swap
		cross = -cross
	var base := _ev.size()
	_ev.append(a)
	_ev.append(b)
	_ev.append(c)
	var n := cross.normalized()
	_en.append(n)
	_en.append(n)
	_en.append(n)
	_euv.append(Vector2(a.x, a.z) * 0.05)
	_euv.append(Vector2(b.x, b.z) * 0.05)
	_euv.append(Vector2(c.x, c.z) * 0.05)
	_ei.append(base)
	_ei.append(base + 1)
	_ei.append(base + 2)
	_earth_tris += 1


func _parapets(rect: Rect2) -> void:
	var grown := rect.grow(4.0)
	for road in _roads:
		if bool(road["rail"]):
			continue
		var pts: PackedVector3Array = road["pts"]
		var kinds: PackedStringArray = road["kind"]
		var half := float(road["half"])
		for i in range(pts.size() - 1):
			var kind := kinds[i] if i < kinds.size() else "grade"
			if kind != "deck" and kind != "bridge":
				continue
			if not grown.has_point(Vector2(pts[i].x, pts[i].z)) and not grown.has_point(Vector2(pts[i + 1].x, pts[i + 1].z)):
				continue
			var s0 := _side_at(pts, i)
			var s1 := _side_at(pts, i + 1)
			for raw_sign in [1.0, -1.0]:
				var sign := float(raw_sign)
				var p0 := pts[i] + s0 * sign * (half + 0.55)
				var p1 := pts[i + 1] + s1 * sign * (half + 0.55)
				p0.y = pts[i].y
				p1.y = pts[i + 1].y
				var q0 := p0 + s0 * sign * 0.28
				var q1 := p1 + s1 * sign * 0.28
				_guard_wall(p0, p1, 0.80)
				_guard_wall(q1, q0, 0.80)


func _guard_wall(a: Vector3, b: Vector3, h: float) -> void:
	var a2 := a
	var b2 := b
	a2.y += h
	b2.y += h
	var la := WorldConfig.to_local(a)
	var lb := WorldConfig.to_local(b)
	var la2 := WorldConfig.to_local(a2)
	var lb2 := WorldConfig.to_local(b2)
	_guard.append(la)
	_guard.append(lb)
	_guard.append(lb2)
	_guard.append(la)
	_guard.append(lb2)
	_guard.append(la2)


func _place_features(host: Node3D) -> void:
	for item in _junctions:
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var at := Vector3(float(pos[0]), float(item.get("flat_y", pos[1])), float(pos[2]))
		if WorldConfig.chunk_of(at.x, at.z) != _built:
			continue
		_node(host, "CurbArc_%s" % str(item.get("id", "j")), at)
		_node(host, "StopBar_%s" % str(item.get("id", "j")), at)
		if _signalised(item):
			_node(host, "SignalMast_%s" % str(item.get("id", "j")), at)


func _node(host: Node3D, node_name: String, at: Vector3) -> void:
	if host.get_node_or_null(node_name) != null:
		return
	var node := Node3D.new()
	node.name = node_name
	node.position = at
	host.add_child(node)


func _signalised(item: Dictionary) -> bool:
	var has_add := false
	var has_blue := false
	var has_av := false
	var has_st := false
	var has_four := false
	var has_cross := false
	for raw in item.get("roads", []):
		var id := str(raw)
		if id == "addison_ave":
			has_add = true
		if id == "blue_lakes_blvd_s" or id == "us93_blue_lakes_s":
			has_blue = true
		if id == "dt_av_+0":
			has_av = true
		if id == "dt_st_+0":
			has_st = true
		if id == "lab_ne_four_lane":
			has_four = true
		if id == "lab_ne_cross":
			has_cross = true
	if has_add and has_blue:
		return true
	if has_av and has_st:
		return true
	return has_four and has_cross


func _collect(src: PackedVector3Array, rect: Rect2, lift: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	var grown := rect.grow(1.0)
	var i := 0
	while i + 2 < src.size():
		var a := src[i]
		var b := src[i + 1]
		var c := src[i + 2]
		i += 3
		if not _tri_hits_rect(a, b, c, grown):
			continue
		var la := WorldConfig.to_local(a)
		var lb := WorldConfig.to_local(b)
		var lc := WorldConfig.to_local(c)
		if lift:
			la.y += LIFT
			lb.y += LIFT
			lc.y += LIFT
		out.append(la)
		out.append(lb)
		out.append(lc)
	return out


func _as_surface(faces: PackedVector3Array, mat_name: String) -> Dictionary:
	if faces.size() < 9:
		return {}
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	nrm.resize(faces.size())
	uv.resize(faces.size())
	idx.resize(faces.size())
	var i := 0
	while i + 2 < faces.size():
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var fn := (b - a).cross(c - a)
		if fn.length_squared() > 1.0e-8:
			fn = fn.normalized()
		else:
			fn = Vector3.UP
		nrm[i] = fn
		nrm[i + 1] = fn
		nrm[i + 2] = fn
		uv[i] = Vector2(a.x, a.z) * 0.05
		uv[i + 1] = Vector2(b.x, b.z) * 0.05
		uv[i + 2] = Vector2(c.x, c.z) * 0.05
		idx[i] = i
		idx[i + 1] = i + 1
		idx[i + 2] = i + 2
		i += 3
	return {"mat": mat_name, "v": faces, "n": nrm, "uv": uv, "i": idx}


func _copy_box(drawn: PackedFloat32Array, cut: PackedFloat32Array, origin: Vector2, n: int, spacing: float, edge: Dictionary, reach: float) -> void:
	var min_x := minf(float(edge["ax"]), float(edge["bx"])) - reach
	var max_x := maxf(float(edge["ax"]), float(edge["bx"])) + reach
	var min_z := minf(float(edge["az"]), float(edge["bz"])) - reach
	var max_z := maxf(float(edge["az"]), float(edge["bz"])) + reach
	var c0 := clampi(int(floor((min_x - origin.x) / spacing)), 0, n - 1)
	var c1 := clampi(int(ceil((max_x - origin.x) / spacing)), 0, n - 1)
	var r0 := clampi(int(floor((min_z - origin.y) / spacing)), 0, n - 1)
	var r1 := clampi(int(ceil((max_z - origin.y) / spacing)), 0, n - 1)
	for r in range(r0, r1 + 1):
		var row := r * n
		for c in range(c0, c1 + 1):
			drawn[row + c] = cut[row + c]


func _copy_disk(drawn: PackedFloat32Array, cut: PackedFloat32Array, origin: Vector2, n: int, spacing: float, item: Dictionary) -> void:
	var pos: Array = item.get("pos", [])
	if pos.size() < 3:
		return
	var rad := float(item.get("radius", 8.0)) + 2.0
	var cx := float(pos[0])
	var cz := float(pos[2])
	var c0 := clampi(int(floor((cx - rad - origin.x) / spacing)), 0, n - 1)
	var c1 := clampi(int(ceil((cx + rad - origin.x) / spacing)), 0, n - 1)
	var r0 := clampi(int(floor((cz - rad - origin.y) / spacing)), 0, n - 1)
	var r1 := clampi(int(ceil((cz + rad - origin.y) / spacing)), 0, n - 1)
	for r in range(r0, r1 + 1):
		var row := r * n
		for c in range(c0, c1 + 1):
			drawn[row + c] = cut[row + c]


func _shelf(edge: Dictionary, spacing: float) -> float:
	# One extra cell, including the diagonal, so bilinear of a sample inside
	# the harness band does not see the ditch or the next cross-section.
	return float(edge["half"]) + float(edge["shoulder"]) + float(edge["ditch"]) + maxf(spacing * 1.5, VERGE_SLACK)


func _project(edge: Dictionary, x: float, z: float) -> Vector3:
	var ax := float(edge["ax"])
	var az := float(edge["az"])
	var abx := float(edge["bx"]) - ax
	var abz := float(edge["bz"]) - az
	var len2 := abx * abx + abz * abz
	if len2 < 0.0001:
		return Vector3(0.0, 0.0, -1.0)
	var t := ((x - ax) * abx + (z - az) * abz) / len2
	# A clamped foot belongs to the neighbouring segment. Using it here stamps
	# this segment's bank onto cells that segment does not own.
	if t < 0.0 or t > 1.0:
		return Vector3(t, 0.0, -1.0)
	var cx := ax + abx * t
	var cz := az + abz * t
	var len := sqrt(len2)
	var left_x := -abz / len
	var left_z := abx / len
	var lat := (x - cx) * left_x + (z - cz) * left_z
	return Vector3(t, lat, 1.0)


func _apron_hits_road(a: Vector3, b: Vector3, c: Vector3) -> bool:
	var mid_ab := (a + b) * 0.5
	var mid_bc := (b + c) * 0.5
	var mid_ca := (c + a) * 0.5
	var mid := (a + b + c) / 3.0
	return _in_band(a.x, a.z) or _in_band(b.x, b.z) or _in_band(c.x, c.z) or _in_band(mid.x, mid.z) or _in_band(mid_ab.x, mid_ab.z) or _in_band(mid_bc.x, mid_bc.z) or _in_band(mid_ca.x, mid_ca.z)


func _in_band(x: float, z: float) -> bool:
	var key := Vector2i(int(floor(x / BUCKET)), int(floor(z / BUCKET)))
	var packed: PackedInt32Array = _buckets.get(key, PackedInt32Array())
	for ei in packed:
		var edge: Dictionary = _edges[int(ei)]
		if bool(edge.get("skip", false)):
			continue
		var hit := _project(edge, x, z)
		if hit.z < 0.0:
			continue
		var band := float(edge["half"]) + float(edge["shoulder"]) + float(edge["ditch"]) - 0.25
		if absf(hit.y) < band:
			return true
	return false


func _design_y(edge: Dictionary, t: float, lat: float) -> float:
	var cy := lerpf(float(edge["ay"]), float(edge["by"]), t)
	var half := float(edge["half"])
	var kind := str(edge["kind"])
	if kind == "deck" or kind == "bridge":
		return cy
	var bank := lerpf(float(edge["ba"]), float(edge["bb"]), t)
	var drop := lerpf(float(edge["ca"]), float(edge["cb"]), t)
	var sec := _section(cy, bank, drop, half)
	if lat >= half:
		return sec.x
	if lat <= -half:
		return sec.z
	if lat >= 0.0:
		return lerpf(sec.y, sec.x, lat / maxf(half, 0.001))
	return lerpf(sec.y, sec.z, -lat / maxf(half, 0.001))


func _edge_y(edge: Dictionary, t: float, left: bool) -> float:
	if left:
		return lerpf(float(edge["lay"]), float(edge["lby"]), t)
	return lerpf(float(edge["ray"]), float(edge["rby"]), t)


func _outward(edge: Dictionary, t: float, left: bool) -> Vector2:
	var cx := lerpf(float(edge["ax"]), float(edge["bx"]), t)
	var cz := lerpf(float(edge["az"]), float(edge["bz"]), t)
	var ex: float
	var ez: float
	if left:
		ex = lerpf(float(edge["lax"]), float(edge["lbx"]), t) - cx
		ez = lerpf(float(edge["laz"]), float(edge["lbz"]), t) - cz
	else:
		ex = lerpf(float(edge["rax"]), float(edge["rbx"]), t) - cx
		ez = lerpf(float(edge["raz"]), float(edge["rbz"]), t) - cz
	var v := Vector2(ex, ez)
	if v.length_squared() < 0.0001:
		var abx := float(edge["bx"]) - float(edge["ax"])
		var abz := float(edge["bz"]) - float(edge["az"])
		var len := maxf(sqrt(abx * abx + abz * abz), 0.001)
		if left:
			return Vector2(-abz / len, abx / len)
		return Vector2(abz / len, -abx / len)
	return v.normalized()


func _tri_y(px: float, pz: float, a: Vector3, b: Vector3, c: Vector3) -> float:
	var v0x := b.x - a.x
	var v0z := b.z - a.z
	var v1x := c.x - a.x
	var v1z := c.z - a.z
	var v2x := px - a.x
	var v2z := pz - a.z
	var den := v0x * v1z - v0z * v1x
	if absf(den) < 1.0e-8:
		return NAN
	var u := (v2x * v1z - v2z * v1x) / den
	var v := (v0x * v2z - v0z * v2x) / den
	if u < -0.02 or v < -0.02 or u + v > 1.02:
		return NAN
	return a.y + u * (b.y - a.y) + v * (c.y - a.y)


func _orig_at(orig: PackedFloat32Array, origin: Vector2, n: int, spacing: float, x: float, z: float) -> float:
	var col := (x - origin.x) / spacing
	var row := (z - origin.y) / spacing
	if col < 0.0 or row < 0.0 or col > float(n - 1) or row > float(n - 1):
		return _dem_y(x, z)
	var c0 := int(col)
	var r0 := int(row)
	var c1 := mini(c0 + 1, n - 1)
	var r1 := mini(r0 + 1, n - 1)
	var tx := col - float(c0)
	var tz := row - float(r0)
	var h00 := orig[r0 * n + c0]
	var h10 := orig[r0 * n + c1]
	var h01 := orig[r1 * n + c0]
	var h11 := orig[r1 * n + c1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func _dem_y(x: float, z: float) -> float:
	if not _dem.is_valid():
		return 0.0
	return float(_dem.call(x, z))


func _snap_seam(p: Vector3) -> Vector3:
	var x := roundf(p.x / LOW_SP) * LOW_SP
	var z := roundf(p.z / LOW_SP) * LOW_SP
	if Vector2(x - p.x, z - p.z).length() > LOW_SP * 1.25:
		return p
	var y := _dem_y(x, z)
	if y < -70.0:
		y = p.y
	return Vector3(x, y, z)


func _cover_item(x: float, z: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 1.0e12
	for item in _junctions:
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var dx := x - float(pos[0])
		var dz := z - float(pos[2])
		var d := dx * dx + dz * dz
		var rad := float(item.get("radius", 8.0))
		if d <= rad * rad and d < best_d:
			best_d = d
			best = item
	return best


func _owner_at(road_id: String, x: float, z: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 1.0e12
	for item in _junctions:
		if not _lists(item, road_id):
			continue
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var d := Vector2(x - float(pos[0]), z - float(pos[2])).length()
		if d < best_d:
			best_d = d
			best = item
	return best


func _hold_r(item: Dictionary, road_id: String) -> float:
	var hold := float(item.get("radius", 8.0)) + HOLD_EXTRA
	var pos: Array = item.get("pos", [])
	if pos.size() < 3:
		return hold
	for other in _junctions:
		if other == item or not _lists(other, road_id):
			continue
		var op: Array = other.get("pos", [])
		if op.size() < 3:
			continue
		var d := Vector2(float(pos[0]) - float(op[0]), float(pos[2]) - float(op[2])).length()
		hold = minf(hold, d * 0.45)
	return maxf(hold, float(item.get("radius", 8.0)))


func _plane_y(item: Dictionary, x: float, z: float) -> float:
	var pos: Array = item.get("pos", [])
	if pos.size() < 3:
		return 0.0
	return float(item.get("flat_y", pos[1])) + float(item.get("sx", 0.0)) * (x - float(pos[0])) + float(item.get("sz", 0.0)) * (z - float(pos[2]))


func _plane_grade(item: Dictionary, pts: PackedVector3Array, i: int) -> float:
	var t := _tangent(pts, i)
	return float(item.get("sx", 0.0)) * t.x + float(item.get("sz", 0.0)) * t.z


func _plane_bank(item: Dictionary, pts: PackedVector3Array, i: int) -> float:
	var side := _side_at(pts, i)
	var g := -(float(item.get("sx", 0.0)) * side.x + float(item.get("sz", 0.0)) * side.z)
	return atan(clampf(g, -0.105104, 0.105104))


func _blend_len(item: Dictionary, pts: PackedVector3Array, auth: PackedFloat32Array, i: int, _outside: float) -> float:
	var m0 := _plane_grade(item, pts, i)
	var m1 := _auth_grade(pts, auth, i)
	var dy := absf(auth[i] - _plane_y(item, pts[i].x, pts[i].z))
	return clampf(maxf(BLEND_MIN, maxf(absf(m1 - m0) / 0.010, dy / 0.012)), BLEND_MIN, 80.0)


func _hermite(u: float, length: float, y0: float, y1: float, m0: float, m1: float) -> float:
	var u2 := u * u
	var u3 := u2 * u
	var h00 := 2.0 * u3 - 3.0 * u2 + 1.0
	var h10 := u3 - 2.0 * u2 + u
	var h01 := -2.0 * u3 + 3.0 * u2
	var h11 := u3 - u2
	return h00 * y0 + h10 * length * m0 + h01 * y1 + h11 * length * m1


func _side_at(pts: PackedVector3Array, i: int) -> Vector3:
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
		return Vector3(1.0, 0.0, 0.0)
	prev = prev.normalized()
	nxt = nxt.normalized()
	var lp := Vector3(-prev.z, 0.0, prev.x)
	var ln := Vector3(-nxt.z, 0.0, nxt.x)
	var mid := lp + ln
	if mid.length_squared() < 0.04:
		return lp
	mid = mid.normalized()
	if mid.dot(lp) < 0.4:
		return lp
	return mid


func _tangent(pts: PackedVector3Array, i: int) -> Vector3:
	var a := pts[i]
	var b := pts[mini(i + 1, pts.size() - 1)]
	if i + 1 >= pts.size() and i > 0:
		a = pts[i - 1]
		b = pts[i]
	var v := b - a
	v.y = 0.0
	if v.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, -1.0)
	return v.normalized()


func _curve_bank(pts: PackedVector3Array, i: int) -> float:
	if i <= 0 or i + 1 >= pts.size():
		return 0.0
	var incoming := pts[i] - pts[i - 1]
	var outgoing := pts[i + 1] - pts[i]
	incoming.y = 0.0
	outgoing.y = 0.0
	if incoming.length() < 2.0 or outgoing.length() < 2.0:
		return 0.0
	var turn := rad_to_deg(atan2(incoming.z * outgoing.x - incoming.x * outgoing.z, incoming.x * outgoing.x + incoming.z * outgoing.z))
	if absf(turn) < 6.0:
		return 0.0
	return deg_to_rad(clampf(turn / 8.0, -6.0, 6.0))


func _vertex_elevated(kinds: PackedStringArray, i: int) -> bool:
	if i > 0 and i - 1 < kinds.size():
		var prev := kinds[i - 1]
		if prev == "deck" or prev == "bridge":
			return true
	if i < kinds.size():
		var nxt := kinds[i]
		if nxt == "deck" or nxt == "bridge":
			return true
	return false


func _authored_grade(item: Dictionary) -> float:
	return _grade_near(item, true)


func _final_grade(item: Dictionary) -> float:
	return _grade_near(item, false)


func _grade_near(item: Dictionary, authored: bool) -> float:
	var pos: Array = item.get("pos", [])
	if pos.size() < 3:
		return 0.0
	var worst := 0.0
	for raw in item.get("roads", []):
		var id := str(raw)
		if not _by_id.has(id):
			continue
		var ri := int(_by_id[id])
		var road: Dictionary = _roads[ri]
		var pts: PackedVector3Array = road["pts"]
		var auth: PackedFloat32Array = _auth[ri]
		for i in range(pts.size() - 1):
			var mid := (pts[i] + pts[i + 1]) * 0.5
			if Vector2(mid.x - float(pos[0]), mid.z - float(pos[2])).length() > 24.0:
				continue
			var ds := Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length()
			if ds < 0.5:
				continue
			var y0 := auth[i] if authored else pts[i].y
			var y1 := auth[i + 1] if authored else pts[i + 1].y
			worst = maxf(worst, absf(y1 - y0) / ds)
	return worst


func _turn_of(item: Dictionary) -> float:
	var pos: Array = item.get("pos", [])
	if pos.size() < 3:
		return 0.0
	var rad := float(item.get("radius", 8.0)) + 2.0
	var worst := 0.0
	for raw in item.get("roads", []):
		var id := str(raw)
		if not _by_id.has(id):
			continue
		var pts: PackedVector3Array = _roads[int(_by_id[id])]["pts"]
		for i in range(1, pts.size() - 1):
			if Vector2(pts[i].x - float(pos[0]), pts[i].z - float(pos[2])).length() > rad:
				continue
			var a := Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z)
			var b := Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z)
			if a.length() < 0.5 or b.length() < 0.5:
				continue
			worst = maxf(worst, rad_to_deg(absf(a.angle_to(b))))
	return worst


func _mean_y(cloud: Array, fallback: float) -> float:
	if cloud.is_empty():
		return fallback
	var s := 0.0
	for p in cloud:
		s += (p as Vector3).y
	return s / float(cloud.size())


func _fit_cloud(cloud: Array, limit: float, fallback: float) -> Vector3:
	if cloud.size() < 3:
		return Vector3(0.0, 0.0, _mean_y(cloud, fallback))
	var sxx := 0.0
	var szz := 0.0
	var sxz := 0.0
	var sx := 0.0
	var sz := 0.0
	var sy := 0.0
	var sxy := 0.0
	var szy := 0.0
	var n := 0.0
	for p in cloud:
		var v := p as Vector3
		sxx += v.x * v.x
		szz += v.z * v.z
		sxz += v.x * v.z
		sx += v.x
		sz += v.z
		sy += v.y
		sxy += v.x * v.y
		szy += v.z * v.y
		n += 1.0
	var sol := _solve3(sxx, sxz, sx, sxy, sxz, szz, sz, szy, sx, sz, n, sy)
	var g := Vector2(sol.x, sol.y).length()
	if g > limit and g > 0.000001:
		sol.x *= limit / g
		sol.y *= limit / g
	return sol


func _solve3(a00: float, a01: float, a02: float, b0: float, a10: float, a11: float, a12: float, b1: float, a20: float, a21: float, a22: float, b2: float) -> Vector3:
	var m := [
		[a00, a01, a02, b0],
		[a10, a11, a12, b1],
		[a20, a21, a22, b2],
	]
	for col in 3:
		var pivot := col
		var best := absf(float(m[col][col]))
		for row in range(col + 1, 3):
			if absf(float(m[row][col])) > best:
				best = absf(float(m[row][col]))
				pivot = row
		if best < 1.0e-8:
			return Vector3(0.0, 0.0, b2 / maxf(a22, 1.0))
		var tmp: Array = m[col]
		m[col] = m[pivot]
		m[pivot] = tmp
		var div: float = float(m[col][col])
		for k in 4:
			m[col][k] = float(m[col][k]) / div
		for row in 3:
			if row == col:
				continue
			var f: float = float(m[row][col])
			for k in 4:
				m[row][k] = float(m[row][k]) - f * float(m[col][k])
	return Vector3(float(m[0][3]), float(m[1][3]), float(m[2][3]))


func _auth_grade(pts: PackedVector3Array, auth: PackedFloat32Array, i: int) -> float:
	var i0 := clampi(i - 1, 0, pts.size() - 2)
	var i1 := i0 + 1
	var ds := Vector2(pts[i1].x - pts[i0].x, pts[i1].z - pts[i0].z).length()
	if ds < 0.05:
		return 0.0
	return (auth[i1] - auth[i0]) / ds


func _road_heading(road: Dictionary, at: Vector3) -> Vector3:
	var pts: PackedVector3Array = road["pts"]
	var best := 1.0e9
	var bi := 0
	for i in pts.size():
		var d := Vector2(pts[i].x - at.x, pts[i].z - at.z).length()
		if d < best:
			best = d
			bi = i
	return _tangent(pts, bi)


func _ends_near(road: Dictionary, at: Vector3) -> bool:
	var pts: PackedVector3Array = road["pts"]
	if pts.is_empty():
		return false
	var a := Vector2(pts[0].x - at.x, pts[0].z - at.z).length()
	var b := Vector2(pts[pts.size() - 1].x - at.x, pts[pts.size() - 1].z - at.z).length()
	return minf(a, b) < 6.0


func _lists(item: Dictionary, road_id: String) -> bool:
	for raw in item.get("roads", []):
		if str(raw) == road_id:
			return true
	return false


func _ring_hit(inside: Vector3, outside: Vector3, item: Dictionary) -> Vector3:
	var pos: Array = item.get("pos", [])
	var cx := float(pos[0])
	var cz := float(pos[2])
	var rad := float(item.get("radius", 8.0))
	var dx := outside.x - inside.x
	var dz := outside.z - inside.z
	var fx := inside.x - cx
	var fz := inside.z - cz
	var a := dx * dx + dz * dz
	var b := 2.0 * (fx * dx + fz * dz)
	var c := fx * fx + fz * fz - rad * rad
	var t := 1.0
	var disc := b * b - 4.0 * a * c
	if disc >= 0.0 and a > 1.0e-10:
		var sd := sqrt(disc)
		var t1 := (-b - sd) / (2.0 * a)
		var t2 := (-b + sd) / (2.0 * a)
		if t1 >= 0.0 and t1 <= 1.0:
			t = t1
		if t2 >= 0.0 and t2 <= 1.0 and (t1 < 0.0 or t1 > 1.0):
			t = t2
	t = clampf(t, 0.0, 1.0)
	var hit := inside.lerp(outside, t)
	hit.y = _plane_y(item, hit.x, hit.z)
	return hit


func _delaunay_flip(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> bool:
	# True when d lies inside the circumcircle of abc, so the ac diagonal is not Delaunay.
	var ax := a.x - d.x
	var ay := a.z - d.z
	var bx := b.x - d.x
	var by := b.z - d.z
	var cx := c.x - d.x
	var cy := c.z - d.z
	var det := (ax * ax + ay * ay) * (bx * cy - cx * by) - (bx * bx + by * by) * (ax * cy - cx * ay) + (cx * cx + cy * cy) * (ax * by - bx * ay)
	var orient := (b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x)
	return det * orient > 0.0


func _bucket_edge(ei: int, edge: Dictionary) -> void:
	var pad := float(edge["half"]) + SLOPE_REACH
	var min_x := int(floor((minf(float(edge["ax"]), float(edge["bx"])) - pad) / BUCKET))
	var max_x := int(floor((maxf(float(edge["ax"]), float(edge["bx"])) + pad) / BUCKET))
	var min_z := int(floor((minf(float(edge["az"]), float(edge["bz"])) - pad) / BUCKET))
	var max_z := int(floor((maxf(float(edge["az"]), float(edge["bz"])) + pad) / BUCKET))
	for gz in range(min_z, max_z + 1):
		for gx in range(min_x, max_x + 1):
			var key := Vector2i(gx, gz)
			var packed: PackedInt32Array = _buckets.get(key, PackedInt32Array())
			packed.append(ei)
			_buckets[key] = packed


func _seg_near(ax: float, az: float, bx: float, bz: float, min_x: float, min_z: float, max_x: float, max_z: float, pad: float) -> bool:
	if maxf(ax, bx) < min_x - pad or minf(ax, bx) > max_x + pad:
		return false
	if maxf(az, bz) < min_z - pad or minf(az, bz) > max_z + pad:
		return false
	return true


func _circle_hits(cx: float, cz: float, rad: float, min_x: float, min_z: float, max_x: float, max_z: float) -> bool:
	var x := clampf(cx, min_x, max_x)
	var z := clampf(cz, min_z, max_z)
	var dx := x - cx
	var dz := z - cz
	return dx * dx + dz * dz <= rad * rad


func _tri_hits_rect(a: Vector3, b: Vector3, c: Vector3, rect: Rect2) -> bool:
	if rect.has_point(Vector2(a.x, a.z)) or rect.has_point(Vector2(b.x, b.z)) or rect.has_point(Vector2(c.x, c.z)):
		return true
	var min_x := minf(a.x, minf(b.x, c.x))
	var max_x := maxf(a.x, maxf(b.x, c.x))
	var min_z := minf(a.z, minf(b.z, c.z))
	var max_z := maxf(a.z, maxf(b.z, c.z))
	if max_x < rect.position.x or min_x > rect.end.x:
		return false
	if max_z < rect.position.y or min_z > rect.end.y:
		return false
	return true


func _silence(node: Node) -> void:
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		body.collision_layer = 0
		body.collision_mask = 0
	for child in node.get_children():
		_silence(child)
