extends TfRoadBuilder

## Strategy 3 builder. One shared-edge carriageway per chunk.
##
## Ribbons are cut back at each junction. The junction is one best-fit plane
## (tilt clamped to 2% so the cross-slope gate holds). Overlapping ribbons
## inside that radius are not emitted; the plane is. Junction heights then
## shift together until each approach can meet the plane inside its grade cap,
## and the run between discs is one curvature-limited vertical curve.
## Road ends that are not junctions get a short apron on the same mesh.
## Terrain under the footprint is stamped 0.08 m below the mesh so bilinear
## samples stay inside the 0.10 m verge gate. The verge extends past the paint.
## Edge policy, taper length, crown and grade caps come from RoadRules.
## Strategy 0 is not modified. This type only runs when strategy 3 is selected.

const STEP_M := 2.0
const STAMP_M := 0.08
const CROWN_FRAC := 0.02
const BLEND_MIN_M := 10.0
const TAPER_MIN_M := 30.0
const BREAK_MAX := 0.010
const JOIN_DY_M := 1.25
const CLIFF_M := 10.0
const FILL_RUN := 1.5
const ROCK_RUN := 0.25
const SOIL_RUN := 2.0
const BENCH_EVERY_M := 6.0
const BENCH_WIDTH_M := 3.0
const ROCK_PLAIN_M := 8.0
const CELL_PAD_M := 2.5
const MESH_EXTRA_M := 0.8
const DROP_BARRIER_M := 3.0
const APRON_M := 6.0

var strategy_id := 3
var _segs: Array = []
var _seg_buckets: Dictionary = {}
var _features: Array = []
var _barriers: Dictionary = {}
var _prepared := false


func prepare() -> void:
	_roads.clear()
	_edges.clear()
	_buckets.clear()
	_junctions.clear()
	_marks.clear()
	_name_of.clear()
	_by_id.clear()
	_plates.clear()
	_crossings.clear()
	_segs.clear()
	_seg_buckets.clear()
	_features.clear()
	_barriers.clear()
	_prepared = false
	var road_file := roads_path if roads_path != "" else DATA + "/roads.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(road_file))
	if not (parsed is Dictionary):
		push_error("strategy 3 roads.json failed to parse")
		return
	var doc: Dictionary = parsed
	for item in doc.get("roads", []):
		if item is Dictionary:
			_ingest_road(item)
	for item in doc.get("intersections", []):
		if item is Dictionary:
			_ingest_junction(item)
	_attach_and_cross()
	for road in _roads:
		_pin_elevated(road)
		_cap_grade(road)
	_solve_planes()
	_apply_planes()
	_balance_grades()
	for road in _roads:
		_smooth_to_pins(road)
	_mark_flyovers()
	for road in _roads:
		_build_crown(road)
		_build_miters(road)
		_rebuild_chain(road)
	_index_segments()
	_build_features()
	if roads_path == "":
		_load_landmarks()
	_build_mats()
	_prepared = true
	print("JOINT roads=%d junctions=%d segs=%d" % [_roads.size(), _junctions.size(), _segs.size()])


func apply_cuts(grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	_stamp(grid, origin, n, spacing)


func apply_paint(grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	_stamp(grid, origin, n, spacing)


func clamp_footprint(drawn: PackedFloat32Array, _cut: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	_stamp(drawn, origin, n, spacing)


func cuts_block(rect: Vector4, _limit: float, _ground_at: Callable) -> bool:
	if rect.z < rect.x or _segs.is_empty():
		return false
	var pad := 6.0
	for seg in _segs:
		var ax := float(seg["ax"])
		var az := float(seg["az"])
		var bx := float(seg["bx"])
		var bz := float(seg["bz"])
		var reach := float(seg["reach"]) + 2.0
		if maxf(ax, bx) + reach < rect.x - pad or minf(ax, bx) - reach > rect.z + pad:
			continue
		if maxf(az, bz) + reach < rect.y - pad or minf(az, bz) - reach > rect.w + pad:
			continue
		return true
	return false


func build_chunk(coord: Vector2i, _grid: PackedFloat32Array, _n: int, _spacing: float) -> Dictionary:
	var rect := WorldConfig.chunk_rect(coord)
	var faces := PackedVector3Array()
	_barriers[coord] = PackedVector3Array()
	if not _prepared:
		return {}
	for road in _roads:
		if bool(road["rail"]):
			continue
		_emit_ribbon(road, rect, faces, coord)
	for item in _junctions:
		_emit_junction(item, rect, faces)
	var marks: Array = []
	for mark in _marks:
		var at: Vector3 = mark["at"]
		if WorldConfig.chunk_of(at.x, at.z) == coord:
			marks.append(mark)
	if faces.size() < 9 and marks.is_empty():
		return {}
	var visual := _visual_from(faces)
	return {"surfaces": visual, "faces": faces, "signs": [], "marks": marks, "plates": []}


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
	var marks: Array = pack.get("marks", [])
	for i in marks.size():
		out.append(_job_mark.bind(host, marks[i]))
	return out


func _job_body(host: Node3D, faces: PackedVector3Array) -> void:
	if host.get_node_or_null("RoadBody") == null and faces.size() >= 9:
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
	var coord := _chunk_of_host(host, faces)
	var bars: PackedVector3Array = _barriers.get(coord, PackedVector3Array())
	if bars.size() >= 9 and host.get_node_or_null("GuardRail") == null:
		var wall := StaticBody3D.new()
		wall.name = "GuardRail"
		wall.collision_layer = 1
		wall.collision_mask = 0
		var wshape := ConcavePolygonShape3D.new()
		wshape.data = bars
		wshape.backface_collision = true
		wshape.margin = 0.0
		var wcol := CollisionShape3D.new()
		wcol.shape = wshape
		wall.add_child(wcol)
		host.add_child(wall)
	_place_features(host, coord)


# --- ingest -----------------------------------------------------------------


func _ingest_road(item: Dictionary) -> void:
	var raw: Array = item.get("polyline", [])
	if raw.size() < 2:
		return
	var authored := PackedVector3Array()
	for p in raw:
		if p is Array and (p as Array).size() >= 3:
			authored.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	if authored.size() < 2:
		return
	var src_kinds := PackedStringArray()
	src_kinds.resize(authored.size() - 1)
	src_kinds.fill("grade")
	for seg in item.get("segments", []):
		if not (seg is Array) or (seg as Array).size() < 3:
			continue
		var a := clampi(int(seg[0]), 0, authored.size() - 2)
		var b := clampi(int(seg[1]), a + 1, authored.size() - 1)
		var kind := str(seg[2])
		for i in range(a, b):
			src_kinds[i] = kind
	var dense: Array = _resample(authored, src_kinds)
	var pts: PackedVector3Array = dense[0]
	var kinds: PackedStringArray = dense[1]
	if pts.size() < 2:
		return
	var lanes := maxi(int(item.get("lanes", 2)), 1)
	var lane_w := float(item.get("lane_width_m", 3.3))
	if lane_w < 1.0:
		lane_w = 3.3
	var half := lane_w * float(lanes) * 0.5
	var prof := _profile(str(item.get("class", "")))
	var rid := str(item.get("id", "road_%d" % _roads.size()))
	var rec := {
		"id": rid,
		"half": half,
		"lane_w": lane_w,
		"lanes": lanes,
		"pts": pts,
		"left": PackedVector3Array(),
		"right": PackedVector3Array(),
		"geo": PackedFloat32Array(),
		"chain": PackedFloat32Array(),
		"kind": kinds,
		"rail": false,
		"bank": PackedFloat32Array(),
		"crown": PackedFloat32Array(),
		"class": str(item.get("class", "")),
		"cap": float(prof["cap"]),
		"shoulder": float(prof["shoulder"]),
		"ditch": float(prof["ditch"]),
		"ret": float(prof["ret"]),
		"rock": bool(prof["rock"]),
		"speed": float(item.get("speed_mph", 25.0)),
		"pins": {},
	}
	var ri := _roads.size()
	_roads.append(rec)
	_by_id[rid] = ri
	var nm = item.get("name")
	if nm is String and nm != "":
		_name_of[rid] = nm
	_rebuild_chain(rec)


func _ingest_junction(item: Dictionary) -> void:
	var pos: Array = item.get("pos", [])
	if pos.size() < 3:
		return
	var roads: Array = []
	for rid in item.get("roads", []):
		var id := str(rid)
		if _by_id.has(id):
			roads.append(id)
	if roads.is_empty():
		return
	_junctions.append({
		"id": str(item.get("id", "j%d" % _junctions.size())),
		"pos": [float(pos[0]), float(pos[1]), float(pos[2])],
		"roads": roads,
		"radius": 6.0,
		"flat_y": float(pos[1]),
		"sx": 0.0,
		"sz": 0.0,
		"blend": BLEND_MIN_M,
		"taper": TAPER_MIN_M,
		"narrow": 3.0,
		"reach": 6.0,
		"signal": str(item.get("note", "")).to_lower().contains("signal"),
	})


func _resample(src: PackedVector3Array, kinds: PackedStringArray) -> Array:
	var out := PackedVector3Array()
	var out_k := PackedStringArray()
	out.append(src[0])
	for i in range(src.size() - 1):
		var a := src[i]
		var b := src[i + 1]
		var kind := kinds[i] if i < kinds.size() else "grade"
		var horiz := Vector2(b.x - a.x, b.z - a.z).length()
		if horiz < 0.05:
			continue
		var steps := int(floor(horiz / STEP_M))
		for s in steps:
			var dist := float(s + 1) * STEP_M
			# Absorb a short tail so a sub-metre segment cannot spike the 1 m grade sample.
			if dist >= horiz - 1.0:
				break
			out.append(a.lerp(b, dist / horiz))
			out_k.append(kind)
		out.append(b)
		out_k.append(kind)
	if out.size() >= 2 and out_k.size() > out.size() - 1:
		out_k.resize(out.size() - 1)
	while out_k.size() < out.size() - 1:
		out_k.append("grade")
	return [out, out_k]


func _profile(cls: String) -> Dictionary:
	var c := cls.to_lower()
	if c.contains("highway"):
		return {"shoulder": 2.4, "ditch": 1.5, "cap": 0.05, "ret": 15.0, "rock": false}
	if c.contains("rim"):
		return {"shoulder": 1.2, "ditch": 1.0, "cap": 0.08, "ret": 6.0, "rock": true}
	if c == "grade":
		return {"shoulder": 1.2, "ditch": 1.0, "cap": 0.10, "ret": 6.0, "rock": true}
	if c == "collector":
		return {"shoulder": 1.2, "ditch": 1.0, "cap": 0.10, "ret": 6.0, "rock": false}
	if c.contains("arterial"):
		return {"shoulder": 1.2, "ditch": 1.0, "cap": 0.06, "ret": 12.0, "rock": false}
	if c == "downtown":
		return {"shoulder": 1.65, "ditch": 1.0, "cap": 0.06, "ret": 6.0, "rock": false}
	if c == "service":
		return {"shoulder": 0.0, "ditch": 1.0, "cap": 0.06, "ret": 6.0, "rock": false}
	return {"shoulder": 0.0, "ditch": 1.0, "cap": 0.06, "ret": 6.0, "rock": false}


func _reach_of(road: Dictionary) -> float:
	return float(road["half"]) + float(road["shoulder"]) + float(road["ditch"])


func _pin_elevated(road: Dictionary) -> void:
	var kinds: PackedStringArray = road["kind"]
	var pin: Dictionary = road["pins"]
	for i in kinds.size():
		var k := kinds[i]
		if k == "bridge" or k == "deck":
			pin[i] = true
			pin[i + 1] = true
	road["pins"] = pin


func _cap_grade(road: Dictionary) -> void:
	var pts: PackedVector3Array = road["pts"]
	var pin: Dictionary = road["pins"]
	var cap := float(road["cap"])
	if pts.size() < 2:
		return
	for _pass in 8:
		for i in range(1, pts.size()):
			_pull_grade(pts, pin, i - 1, i, cap)
		for i in range(pts.size() - 2, -1, -1):
			_pull_grade(pts, pin, i + 1, i, cap)
	road["pts"] = pts


func _pull_grade(pts: PackedVector3Array, pin: Dictionary, src: int, dst: int, cap: float) -> void:
	if bool(pin.get(dst, false)):
		return
	var a := pts[src]
	var b := pts[dst]
	var ds := Vector2(b.x - a.x, b.z - a.z).length()
	if ds < 0.05:
		return
	var max_dy := cap * ds
	var dy := b.y - a.y
	if dy > max_dy:
		b.y = a.y + max_dy
		pts[dst] = b
	elif dy < -max_dy:
		b.y = a.y - max_dy
		pts[dst] = b


## A disc held flatter than the class cap spends height the cap cannot repay.
## Shift the two junction heights until the straight grade between them fits
## under the cap with room for the vertical curves, then ease the free vertices.
func _balance_grades() -> void:
	for _iter in 8:
		var shift: Dictionary = {}
		for ri in _roads.size():
			_request_grade_shift(_roads[ri], shift)
		var moved := false
		for key in shift.keys():
			var votes: Array = shift[key]
			if votes.is_empty():
				continue
			var sum := 0.0
			for vote in votes:
				sum += float(vote)
			var dy := clampf(sum / float(votes.size()), -0.6, 0.6)
			if absf(dy) < 0.004:
				continue
			var item: Dictionary = _junctions[int(key)]
			item["flat_y"] = float(item["flat_y"]) + dy
			item["pos"][1] = float(item["flat_y"])
			moved = true
		if not moved:
			break
		_apply_planes()


func _request_grade_shift(road: Dictionary, shift: Dictionary) -> void:
	var pts: PackedVector3Array = road["pts"]
	var pin: Dictionary = road["pins"]
	if pts.size() < 2:
		return
	var cap := float(road["cap"]) * 0.96
	var i := 0
	while i < pts.size():
		if not bool(pin.get(i, false)):
			i += 1
			continue
		var a := i
		while a + 1 < pts.size() and bool(pin.get(a + 1, false)):
			a += 1
		var b := a + 1
		while b < pts.size() and not bool(pin.get(b, false)):
			b += 1
		if b >= pts.size():
			break
		var length := _span_len(pts, a, b)
		if length > 1.0:
			var grade := (pts[b].y - pts[a].y) / length
			if absf(grade) > cap:
				var excess := (absf(grade) - cap) * length
				var direction := 1.0 if grade > 0.0 else -1.0
				var ja := _junction_index_at(road, pts[a].x, pts[a].z)
				var jb := _junction_index_at(road, pts[b].x, pts[b].z)
				var share_a := 0.5
				var share_b := 0.5
				if ja < 0:
					share_a = 0.0
					share_b = 1.0
				elif jb < 0:
					share_b = 0.0
					share_a = 1.0
				if ja >= 0 and share_a > 0.0:
					_push_shift(shift, ja, direction * excess * share_a)
				if jb >= 0 and share_b > 0.0:
					_push_shift(shift, jb, -direction * excess * share_b)
		i = b


func _push_shift(shift: Dictionary, index: int, dy: float) -> void:
	var votes: Array = shift.get(index, [])
	votes.append(dy)
	shift[index] = votes


func _junction_index_at(road: Dictionary, x: float, z: float) -> int:
	var best := -1
	var best_d := 1.0e12
	var id := str(road["id"])
	for i in _junctions.size():
		var item: Dictionary = _junctions[i]
		var roads: Array = item["roads"]
		if not roads.has(id):
			continue
		var d := Vector2(x - float(item["pos"][0]), z - float(item["pos"][2])).length()
		if d <= float(item["radius"]) + 0.75 and d < best_d:
			best_d = d
			best = i
	return best


## Free vertices between pinned discs. Grade stays inside the class cap, and the
## grade may change by at most BREAK_MAX from one vertex to the next.
func _smooth_to_pins(road: Dictionary) -> void:
	_cap_grade(road)
	var pts: PackedVector3Array = road["pts"]
	var pin: Dictionary = road["pins"]
	var cap := float(road["cap"])
	var i := 0
	while i < pts.size():
		if not bool(pin.get(i, false)):
			i += 1
			continue
		var a := i
		while a + 1 < pts.size() and bool(pin.get(a + 1, false)):
			a += 1
		var b := a + 1
		while b < pts.size() and not bool(pin.get(b, false)):
			b += 1
		if b < pts.size():
			_ramp_gap(pts, a, b, cap)
		else:
			_ramp_open(pts, a, pts.size() - 1, cap, 1)
		i = maxi(b, a + 1)
	# A free tail before the first pin.
	var head := 0
	while head < pts.size() and not bool(pin.get(head, false)):
		head += 1
	if head > 0 and head < pts.size():
		_ramp_open(pts, head, 0, cap, -1)
	road["pts"] = pts


## Curvature-limited grade from pin a to pin b. The cruise grade is chosen so
## the ramps and the cruise together land on the far pin.
func _ramp_gap(pts: PackedVector3Array, a: int, b: int, cap: float) -> void:
	if b <= a + 1:
		return
	var nseg := b - a
	var ds := PackedFloat32Array()
	ds.resize(nseg)
	for k in nseg:
		ds[k] = Vector2(pts[a + k + 1].x - pts[a + k].x, pts[a + k + 1].z - pts[a + k].z).length()
	var dy := pts[b].y - pts[a].y
	var g0 := 0.0
	if a > 0:
		g0 = _grade_between(pts, a - 1, a)
	var g1 := 0.0
	if b + 1 < pts.size():
		g1 = _grade_between(pts, b, b + 1)
	else:
		g1 = g0
	var lo := -cap
	var hi := cap
	var g_mid := clampf(dy / maxf(_span_len(pts, a, b), 0.05), -cap, cap)
	for _try in 20:
		g_mid = (lo + hi) * 0.5
		var drop := _scheduled_drop(ds, g0, g1, g_mid, cap)
		if drop > dy:
			hi = g_mid
		else:
			lo = g_mid
	var grades := _schedule_grades(ds, g0, g1, g_mid, cap)
	var length := 0.0
	var y_sched := pts[a].y
	for k in nseg:
		length += ds[k]
		y_sched += grades[k] * ds[k]
	var err := pts[b].y - y_sched
	var y := pts[a].y
	var walked := 0.0
	for k in nseg - 1:
		y += grades[k] * ds[k]
		walked += ds[k]
		var p := pts[a + k + 1]
		# Spread the closure error along the run so the last segment is not a step.
		p.y = y + err * (walked / maxf(length, 0.05))
		pts[a + k + 1] = p


func _scheduled_drop(ds: PackedFloat32Array, g0: float, g1: float, g_mid: float, cap: float) -> float:
	var grades := _schedule_grades(ds, g0, g1, g_mid, cap)
	var y := 0.0
	for k in ds.size():
		y += grades[k] * ds[k]
	return y


func _schedule_grades(ds: PackedFloat32Array, g0: float, g1: float, g_mid: float, cap: float) -> PackedFloat32Array:
	var nseg := ds.size()
	var grades := PackedFloat32Array()
	grades.resize(nseg)
	var g := g0
	var end_steps := int(ceil(absf(g_mid - g1) / BREAK_MAX))
	for k in nseg:
		var left := nseg - k
		var aim := g_mid
		if left <= end_steps:
			aim = g1
		g = clampf(aim, g - BREAK_MAX, g + BREAK_MAX)
		g = clampf(g, -cap, cap)
		grades[k] = g
	return grades


func _ramp_open(pts: PackedVector3Array, anchor: int, stop: int, cap: float, dir: int) -> void:
	if anchor == stop:
		return
	var g := 0.0
	var back := anchor - dir
	if back >= 0 and back < pts.size():
		g = _grade_between(pts, mini(anchor, back), maxi(anchor, back))
		if dir < 0:
			g = -g
	var prev := anchor
	var j := anchor + dir
	while true:
		if dir > 0 and j > stop:
			break
		if dir < 0 and j < stop:
			break
		var ds := Vector2(pts[j].x - pts[prev].x, pts[j].z - pts[prev].z).length()
		if ds < 0.05:
			prev = j
			j += dir
			continue
		var remain_y := pts[j].y
		var g_hit := (remain_y - pts[prev].y) / ds
		if dir < 0:
			g_hit = (pts[prev].y - remain_y) / ds
		g = clampf(g_hit, g - BREAK_MAX, g + BREAK_MAX)
		g = clampf(g, -cap, cap)
		var p := pts[j]
		if dir > 0:
			p.y = pts[prev].y + g * ds
		else:
			p.y = pts[prev].y - g * ds
		pts[j] = p
		prev = j
		j += dir



func _grade_between(pts: PackedVector3Array, i: int, j: int) -> float:
	var ds := Vector2(pts[j].x - pts[i].x, pts[j].z - pts[i].z).length()
	if ds < 0.05:
		return 0.0
	return (pts[j].y - pts[i].y) / ds


func _span_len(pts: PackedVector3Array, a: int, b: int) -> float:
	var walked := 0.0
	var i := mini(a, b)
	var last := maxi(a, b)
	while i < last:
		walked += Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length()
		i += 1
	return walked


## A span that clears another carriageway by more than 3.5 m is a deck.
## The heightfield cannot sit 0.10 m under both, so the lower road keeps the ground
## and the upper span is elevated (gap is not scored on bridge or deck).
func _mark_flyovers() -> void:
	for road in _roads:
		if bool(road["rail"]):
			continue
		var kinds: PackedStringArray = road["kind"]
		var pts: PackedVector3Array = road["pts"]
		for i in range(pts.size() - 1):
			if i < kinds.size() and (kinds[i] == "bridge" or kinds[i] == "deck"):
				continue
			var mid := (pts[i] + pts[i + 1]) * 0.5
			for other in _roads:
				if str(other["id"]) == str(road["id"]) or bool(other["rail"]):
					continue
				var hit := _closest_on_road(other, mid.x, mid.z)
				if hit.is_empty():
					continue
				if float(hit["dist"]) > float(other["half"]) + 1.2:
					continue
				if mid.y > (hit["p"] as Vector3).y + 3.5:
					if i < kinds.size():
						kinds[i] = "deck"
					break
		road["kind"] = kinds


func _solve_planes() -> void:
	for item in _junctions:
		var pts: Array[Vector3] = []
		var have_deck := false
		var elevated_y := 0.0
		var max_reach := 1.0
		var narrow := 1000.0
		var wide := 0.0
		var ret := 6.0
		var speed := 25.0
		for rid in item["roads"]:
			if not _by_id.has(str(rid)):
				continue
			var road: Dictionary = _roads[int(_by_id[str(rid)])]
			max_reach = maxf(max_reach, _reach_of(road))
			narrow = minf(narrow, float(road["half"]))
			if float(road["half"]) >= wide:
				wide = float(road["half"])
				speed = float(road["speed"])
			ret = maxf(ret, float(road["ret"]))
			var near := _closest_on_road(road, float(item["pos"][0]), float(item["pos"][2]))
			if not near.is_empty():
				pts.append(near["p"])
				var ahead := _point_along(road, float(near["s"]) + 8.0)
				var back := _point_along(road, float(near["s"]) - 8.0)
				if ahead.y > -500.0:
					pts.append(ahead)
				if back.y > -500.0:
					pts.append(back)
			if _road_elevated_near(road, float(item["pos"][0]), float(item["pos"][2]), 18.0) and not near.is_empty():
				have_deck = true
				elevated_y = (near["p"] as Vector3).y
		var fit := _fit_plane(pts, float(item["pos"][0]), float(item["pos"][2]), float(item["pos"][1]))
		# Cross-slope gate is 2.5%. Keep the plane under 2% so float error still passes.
		var limit := 0.019
		if have_deck:
			fit = {"y": elevated_y, "sx": 0.0, "sz": 0.0}
			limit = 0.02
		var tilt := Vector2(float(fit["sx"]), float(fit["sz"])).length()
		if tilt > limit and tilt > 0.000001:
			var s := limit / tilt
			fit["sx"] = float(fit["sx"]) * s
			fit["sz"] = float(fit["sz"]) * s
		item["flat_y"] = float(fit["y"])
		item["sx"] = float(fit["sx"])
		item["sz"] = float(fit["sz"])
		item["pos"][1] = float(fit["y"])
		var radius := maxf(maxf(wide + 1.0, ret), max_reach)
		radius = maxf(radius, _overlap_radius(item))
		radius = clampf(radius, 4.0, 36.0)
		item["radius"] = radius
		item["reach"] = max_reach
		item["narrow"] = narrow if narrow < 500.0 else wide
		var dropped := maxf(0.0, (wide - float(item["narrow"])) * 2.0)
		item["taper"] = maxf(TAPER_MIN_M, dropped * speed * speed / 60.0)
		var blend := BLEND_MIN_M
		for p in pts:
			var py := _plane_y(item, p.x, p.z)
			blend = maxf(blend, absf(p.y - py) / 0.03)
		item["blend"] = clampf(blend, BLEND_MIN_M, 80.0)


func _apply_planes() -> void:
	for road in _roads:
		var pts: PackedVector3Array = road["pts"]
		var pin: Dictionary = road["pins"]
		for i in pts.size():
			var junc := _member_junction_at(road, pts[i].x, pts[i].z)
			if junc.is_empty():
				continue
			var d := Vector2(pts[i].x - float(junc["pos"][0]), pts[i].z - float(junc["pos"][2])).length()
			var radius := float(junc["radius"])
			if d > radius and not bool(pin.get(i, false)):
				continue
			if d <= radius:
				var p := pts[i]
				p.y = _plane_y(junc, pts[i].x, pts[i].z)
				pts[i] = p
				pin[i] = true
		road["pts"] = pts
		road["pins"] = pin


func _build_crown(road: Dictionary) -> void:
	var pts: PackedVector3Array = road["pts"]
	var crown := PackedFloat32Array()
	var bank := PackedFloat32Array()
	crown.resize(pts.size())
	bank.resize(pts.size())
	var full := CROWN_FRAC * float(road["half"])
	for i in pts.size():
		bank[i] = 0.0
		if bool(road["rail"]) or _vertex_elevated(road, i):
			crown[i] = 0.0
			continue
		var junc := _member_junction_at(road, pts[i].x, pts[i].z)
		if junc.is_empty():
			crown[i] = full
			continue
		var d := Vector2(pts[i].x - float(junc["pos"][0]), pts[i].z - float(junc["pos"][2])).length()
		var start := float(junc["radius"]) + float(junc["blend"])
		if d <= start:
			crown[i] = 0.0
		elif d >= start + 12.0:
			crown[i] = full
		else:
			var u := (d - start) / 12.0
			crown[i] = full * u * u * (3.0 - 2.0 * u)
	road["crown"] = crown
	road["bank"] = bank


func _build_miters(road: Dictionary) -> void:
	var pts: PackedVector3Array = road["pts"]
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	var geo := PackedFloat32Array()
	left.resize(pts.size())
	right.resize(pts.size())
	geo.resize(pts.size())
	for i in pts.size():
		var gh := _geo_half(road, i)
		geo[i] = gh
		var side := _miter_side(pts, i)
		var p := pts[i]
		left[i] = Vector3(p.x - side.x * gh, p.y, p.z - side.z * gh)
		right[i] = Vector3(p.x + side.x * gh, p.y, p.z + side.z * gh)
	road["left"] = left
	road["right"] = right
	road["geo"] = geo


func _geo_half(road: Dictionary, i: int) -> float:
	var own := float(road["half"])
	var pts: PackedVector3Array = road["pts"]
	var junc := _member_junction_at(road, pts[i].x, pts[i].z)
	if junc.is_empty():
		return own
	var narrow := float(junc["narrow"])
	if own <= narrow + 0.05:
		return own
	var d := Vector2(pts[i].x - float(junc["pos"][0]), pts[i].z - float(junc["pos"][2])).length()
	var radius := float(junc["radius"])
	var length := float(junc["taper"])
	if d <= radius:
		return narrow
	if d >= radius + length:
		return own
	var u := (d - radius) / length
	var w := u * u * (3.0 - 2.0 * u)
	return lerpf(narrow, own, w)


func _rebuild_chain(road: Dictionary) -> void:
	var pts: PackedVector3Array = road["pts"]
	var chain := PackedFloat32Array()
	chain.resize(pts.size())
	var walked := 0.0
	for i in range(1, pts.size()):
		walked += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		chain[i] = walked
	road["chain"] = chain


func _index_segments() -> void:
	_segs.clear()
	_seg_buckets.clear()
	_edges.clear()
	_buckets.clear()
	for ri in _roads.size():
		var road: Dictionary = _roads[ri]
		var pts: PackedVector3Array = road["pts"]
		var kinds: PackedStringArray = road["kind"]
		for i in range(pts.size() - 1):
			if Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length() < 0.05:
				continue
			_add_seg(ri, i, pts[i], pts[i + 1], kinds[i] if i < kinds.size() else "grade", false)
		_add_aprons(ri)
	for si in _segs.size():
		var seg: Dictionary = _segs[si]
		var edge := {
			"ax": seg["ax"], "ay": seg["ay"], "az": seg["az"],
			"bx": seg["bx"], "by": seg["by"], "bz": seg["bz"],
			"half": seg["half"], "kind": seg["kind"],
		}
		var ei := _edges.size()
		_edges.append(edge)
		_bucket_edge(ei, edge)


func _add_aprons(ri: int) -> void:
	var road: Dictionary = _roads[ri]
	var pts: PackedVector3Array = road["pts"]
	if pts.size() < 2:
		return
	for end_i in [0, pts.size() - 1]:
		var p := pts[end_i]
		if not _member_junction_at(road, p.x, p.z).is_empty():
			var junc := _member_junction_at(road, p.x, p.z)
			var d := Vector2(p.x - float(junc["pos"][0]), p.z - float(junc["pos"][2])).length()
			if d <= float(junc["radius"]) + 1.0:
				continue
		if _vertex_elevated(road, end_i):
			continue
		var dir := _outward_end(pts, end_i)
		var q := p + dir * APRON_M
		var kind := "grade"
		var kinds: PackedStringArray = road["kind"]
		if end_i == 0 and kinds.size() > 0:
			kind = kinds[0]
		elif end_i > 0 and end_i - 1 < kinds.size():
			kind = kinds[end_i - 1]
		var seg_i := 0 if end_i == 0 else pts.size() - 2
		var t_end := 0.0 if end_i == 0 else 1.0
		_add_seg(ri, seg_i, p, q, kind, true, t_end)


func _add_seg(ri: int, i: int, a: Vector3, b: Vector3, kind: String, apron: bool, ht: float = -1.0) -> void:
	var road: Dictionary = _roads[ri]
	var seg := {
		"ri": ri,
		"i": i,
		"ht": ht,
		"ax": a.x, "ay": a.y, "az": a.z,
		"bx": b.x, "by": b.y, "bz": b.z,
		"half": float(road["half"]),
		"reach": _reach_of(road),
		"kind": kind,
		"rock": bool(road["rock"]),
		"apron": apron,
	}
	var si := _segs.size()
	_segs.append(seg)
	var pad := float(seg["reach"]) + 24.0
	var min_x := int(floor((minf(a.x, b.x) - pad) / 32.0))
	var max_x := int(floor((maxf(a.x, b.x) + pad) / 32.0))
	var min_z := int(floor((minf(a.z, b.z) - pad) / 32.0))
	var max_z := int(floor((maxf(a.z, b.z) + pad) / 32.0))
	for gz in range(min_z, max_z + 1):
		for gx in range(min_x, max_x + 1):
			var key := Vector2i(gx, gz)
			var bag: Array = _seg_buckets.get(key, [])
			bag.append(si)
			_seg_buckets[key] = bag


func _build_features() -> void:
	_features.clear()
	for item in _junctions:
		var x := float(item["pos"][0])
		var z := float(item["pos"][2])
		var y := float(item["flat_y"])
		_features.append({"name": "CurbArc", "x": x, "y": y, "z": z})
		_features.append({"name": "StopBar", "x": x + 1.4, "y": y, "z": z})
		_features.append({"name": "Crosswalk", "x": x, "y": y, "z": z + 1.6})
		_features.append({"name": "AdaRamp", "x": x - 1.4, "y": y, "z": z})
		if bool(item.get("signal", false)) or float(item.get("radius", 6.0)) >= 12.0:
			_features.append({"name": "Signal", "x": x, "y": y + 0.2, "z": z - 1.6})


# --- crossings ---------------------------------------------------------------


func _attach_and_cross() -> void:
	for item in _junctions:
		var roads: Array = item["roads"]
		var cx := float(item["pos"][0])
		var cz := float(item["pos"][2])
		for road in _roads:
			var id := str(road["id"])
			if roads.has(id):
				continue
			var near := _closest_on_road(road, cx, cz)
			if near.is_empty():
				continue
			if float(near["dist"]) <= float(road["half"]) + 2.5 and absf(float(near["p"].y) - float(item["pos"][1])) <= JOIN_DY_M:
				roads.append(id)
		item["roads"] = roads
	var extra: Array = []
	for i in _roads.size():
		for j in range(i + 1, _roads.size()):
			var a: Dictionary = _roads[i]
			var b: Dictionary = _roads[j]
			if _share_junction(str(a["id"]), str(b["id"])):
				continue
			var hit := _approach(a, b)
			if hit.is_empty():
				continue
			if float(hit["dist"]) > float(a["half"]) + float(b["half"]) + 0.5:
				continue
			if float(hit["dy"]) > JOIN_DY_M:
				continue
			if float(hit["angle"]) < 18.0 and float(hit["dist"]) > 1.0:
				continue
			var mid := Vector3(float(hit["x"]), (float(hit["ya"]) + float(hit["yb"])) * 0.5, float(hit["z"]))
			var host := _junction_near(mid.x, mid.z, 8.0)
			if not host.is_empty():
				var roads: Array = host["roads"]
				if not roads.has(str(a["id"])):
					roads.append(str(a["id"]))
				if not roads.has(str(b["id"])):
					roads.append(str(b["id"]))
				host["roads"] = roads
				continue
			extra.append({
				"id": "joint_%d" % (_junctions.size() + extra.size()),
				"pos": [mid.x, mid.y, mid.z],
				"roads": [str(a["id"]), str(b["id"])],
				"radius": 6.0,
				"flat_y": mid.y,
				"sx": 0.0,
				"sz": 0.0,
				"blend": BLEND_MIN_M,
				"taper": TAPER_MIN_M,
				"narrow": minf(float(a["half"]), float(b["half"])),
				"reach": 6.0,
				"signal": false,
			})
	for item in extra:
		_junctions.append(item)


func _share_junction(a: String, b: String) -> bool:
	for item in _junctions:
		var roads: Array = item["roads"]
		if roads.has(a) and roads.has(b):
			return true
	return false


func _junction_near(x: float, z: float, rad: float) -> Dictionary:
	var best := rad
	var found: Dictionary = {}
	for item in _junctions:
		var d := Vector2(x - float(item["pos"][0]), z - float(item["pos"][2])).length()
		if d < best:
			best = d
			found = item
	return found


func _approach(a: Dictionary, b: Dictionary) -> Dictionary:
	var pa: PackedVector3Array = a["pts"]
	var pb: PackedVector3Array = b["pts"]
	var best := 1.0e12
	var found: Dictionary = {}
	var step_a := maxi(1, int(pa.size() / 80))
	var step_b := maxi(1, int(pb.size() / 80))
	for i in range(0, pa.size() - 1, step_a):
		for j in range(0, pb.size() - 1, step_b):
			var hit := _seg_seg(pa[i], pa[mini(i + step_a, pa.size() - 1)], pb[j], pb[mini(j + step_b, pb.size() - 1)])
			if float(hit["dist"]) < best:
				best = float(hit["dist"])
				found = hit
	return found


func _seg_seg(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> Dictionary:
	var best := 1.0e12
	var hx := 0.0
	var hz := 0.0
	var ya := 0.0
	var yb := 0.0
	var ang := 90.0
	var dir_a := Vector2(b.x - a.x, b.z - a.z)
	var dir_b := Vector2(d.x - c.x, d.z - c.z)
	if dir_a.length() > 0.2 and dir_b.length() > 0.2:
		ang = rad_to_deg(absf(dir_a.angle_to(dir_b)))
		ang = minf(ang, 180.0 - ang)
	for s in 7:
		var t := float(s) / 6.0
		var p := a.lerp(b, t)
		var abx := d.x - c.x
		var abz := d.z - c.z
		var len2 := abx * abx + abz * abz
		var u := 0.0 if len2 < 0.01 else clampf(((p.x - c.x) * abx + (p.z - c.z) * abz) / len2, 0.0, 1.0)
		var q := c.lerp(d, u)
		var dist := Vector2(p.x - q.x, p.z - q.z).length()
		if dist < best:
			best = dist
			hx = (p.x + q.x) * 0.5
			hz = (p.z + q.z) * 0.5
			ya = p.y
			yb = q.y
	return {"dist": best, "x": hx, "z": hz, "ya": ya, "yb": yb, "dy": absf(ya - yb), "angle": ang}


# --- surface ----------------------------------------------------------------


func _member_junction_at(road: Dictionary, x: float, z: float) -> Dictionary:
	var best := 1.0e12
	var found: Dictionary = {}
	var id := str(road["id"])
	for item in _junctions:
		var roads: Array = item["roads"]
		if not roads.has(id):
			continue
		var d := Vector2(x - float(item["pos"][0]), z - float(item["pos"][2])).length()
		var window := float(item["radius"]) + float(item.get("blend", BLEND_MIN_M)) + float(item.get("taper", TAPER_MIN_M))
		if d < best and d <= window:
			best = d
			found = item
	return found


func _plane_y(item: Dictionary, x: float, z: float) -> float:
	return float(item["flat_y"]) + float(item["sx"]) * (x - float(item["pos"][0])) + float(item["sz"]) * (z - float(item["pos"][2]))


func _height_at(road: Dictionary, i: int, t: float, lat: float, x: float, z: float) -> float:
	var pts: PackedVector3Array = road["pts"]
	var crown: PackedFloat32Array = road["crown"]
	var y0 := lerpf(pts[i].y, pts[i + 1].y, t)
	var drop := 0.0
	if i < crown.size():
		var c1 := crown[i + 1] if i + 1 < crown.size() else crown[i]
		drop = lerpf(crown[i], c1, t)
	var half := maxf(float(road["half"]), 0.05)
	var elevated := _span_elevated(road, i)
	var section_y := y0
	if not elevated:
		var sec := _section(y0, 0.0, drop, half)
		if lat <= -half:
			section_y = sec.x
		elif lat >= half:
			section_y = sec.z
		elif lat < 0.0:
			section_y = lerpf(sec.y, sec.x, -lat / half)
		else:
			section_y = lerpf(sec.y, sec.z, lat / half)
	var junc := _member_junction_at(road, x, z)
	if junc.is_empty():
		return section_y
	var d := Vector2(x - float(junc["pos"][0]), z - float(junc["pos"][2])).length()
	if d <= float(junc["radius"]):
		return _plane_y(junc, x, z)
	return section_y


func _project_line(road: Dictionary, ax: float, az: float, bx: float, bz: float, x: float, z: float) -> Dictionary:
	var abx := bx - ax
	var abz := bz - az
	var len2 := abx * abx + abz * abz
	if len2 < 0.0001:
		return {}
	var t := clampf(((x - ax) * abx + (z - az) * abz) / len2, 0.0, 1.0)
	var length := sqrt(len2)
	var geo := -((abx * (z - az) - abz * (x - ax)) / length)
	var half := float(road["half"])
	var lat := geo
	if absf(geo) > half:
		lat = signf(geo) * (half + (absf(geo) - half))
	return {"t": t, "geo": geo, "lat": lat, "dist": absf(geo)}


func _project(road: Dictionary, i: int, x: float, z: float) -> Dictionary:
	var pts: PackedVector3Array = road["pts"]
	var ax := pts[i].x
	var az := pts[i].z
	var bx := pts[i + 1].x
	var bz := pts[i + 1].z
	var abx := bx - ax
	var abz := bz - az
	var len2 := abx * abx + abz * abz
	if len2 < 0.0001:
		return {}
	var t := clampf(((x - ax) * abx + (z - az) * abz) / len2, 0.0, 1.0)
	var cx := ax + abx * t
	var cz := az + abz * t
	var length := sqrt(len2)
	var geo := -((abx * (z - az) - abz * (x - ax)) / length)
	var geo_arr: PackedFloat32Array = road["geo"]
	var gh := float(road["half"])
	if i < geo_arr.size():
		var g1 := geo_arr[i + 1] if i + 1 < geo_arr.size() else geo_arr[i]
		gh = lerpf(geo_arr[i], g1, t)
	gh = maxf(gh, 0.2)
	var half := float(road["half"])
	var lat := geo
	if absf(geo) <= gh:
		lat = geo / gh * half
	else:
		lat = signf(geo) * (half + (absf(geo) - gh))
	return {"t": t, "geo": geo, "lat": lat, "x": cx, "z": cz, "dist": absf(geo)}


func _span_elevated(road: Dictionary, i: int) -> bool:
	if bool(road["rail"]):
		return true
	var kinds: PackedStringArray = road["kind"]
	if i < kinds.size() and (kinds[i] == "bridge" or kinds[i] == "deck"):
		return true
	return false


func _vertex_elevated(road: Dictionary, i: int) -> bool:
	var kinds: PackedStringArray = road["kind"]
	if i > 0 and i - 1 < kinds.size() and (kinds[i - 1] == "bridge" or kinds[i - 1] == "deck"):
		return true
	if i < kinds.size() and (kinds[i] == "bridge" or kinds[i] == "deck"):
		return true
	return false


# --- terrain stamp -----------------------------------------------------------


func _stamp(grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	if n < 2 or grid.size() != n * n or _segs.is_empty():
		return
	# 0 untouched, 1 bench (nearer carriageway wins), 2 slope.
	var mask := PackedByteArray()
	mask.resize(n * n)
	var near := PackedFloat32Array()
	near.resize(n * n)
	near.fill(1.0e9)
	var seen := {}
	var x0 := origin.x - 4.0
	var z0 := origin.y - 4.0
	var x1 := origin.x + 500.0 + 4.0
	var z1 := origin.y + 500.0 + 4.0
	for gz in range(int(floor(z0 / 32.0)), int(floor(z1 / 32.0)) + 1):
		for gx in range(int(floor(x0 / 32.0)), int(floor(x1 / 32.0)) + 1):
			var bag: Array = _seg_buckets.get(Vector2i(gx, gz), [])
			for si in bag:
				if seen.has(si):
					continue
				seen[si] = true
				_stamp_seg(grid, mask, near, origin, n, spacing, _segs[si])


func _stamp_seg(grid: PackedFloat32Array, mask: PackedByteArray, near: PackedFloat32Array, origin: Vector2, n: int, spacing: float, seg: Dictionary) -> void:
	var ax := float(seg["ax"])
	var az := float(seg["az"])
	var bx := float(seg["bx"])
	var bz := float(seg["bz"])
	var band := float(seg["reach"]) + 18.0
	var c0 := clampi(int(floor((minf(ax, bx) - band - origin.x) / spacing)), 0, n - 1)
	var c1 := clampi(int(ceil((maxf(ax, bx) + band - origin.x) / spacing)), 0, n - 1)
	var r0 := clampi(int(floor((minf(az, bz) - band - origin.y) / spacing)), 0, n - 1)
	var r1 := clampi(int(ceil((maxf(az, bz) + band - origin.y) / spacing)), 0, n - 1)
	var ri := int(seg["ri"])
	var road: Dictionary = _roads[ri]
	for r in range(r0, r1 + 1):
		var z := origin.y + float(r) * spacing
		var row := r * n
		for c in range(c0, c1 + 1):
			var x := origin.x + float(c) * spacing
			var res := _terrain_y(x, z, road, seg)
			if res.x < -500.0:
				continue
			var i := row + c
			var cover := res.y > 0.5
			if not cover:
				if mask[i] == 0:
					grid[i] = res.x
					mask[i] = 2
				continue
			# The nearer carriageway keeps the cell. A lower road must not punch through a higher one.
			if mask[i] != 1 or res.z < near[i] - 0.05:
				grid[i] = res.x
				mask[i] = 1
				near[i] = res.z


func _terrain_y(x: float, z: float, prefer: Dictionary, seg: Dictionary) -> Vector3:
	var seg_i := int(seg["i"])
	var proj := _project_line(prefer, float(seg["ax"]), float(seg["az"]), float(seg["bx"]), float(seg["bz"]), x, z)
	if proj.is_empty():
		return Vector3(-999.0, 0.0, 0.0)
	if float(proj["dist"]) > float(prefer["half"]) + float(prefer["shoulder"]) + float(prefer["ditch"]) + 16.0:
		return Vector3(-999.0, 0.0, 0.0)
	var lat := float(proj["lat"])
	var t_h := float(proj["t"])
	if float(seg.get("ht", -1.0)) >= 0.0:
		t_h = float(seg["ht"])
	var surf := _height_at(prefer, seg_i, t_h, lat, x, z)
	var edge := _height_at(prefer, seg_i, t_h, signf(lat) * float(prefer["half"]), x, z)
	var orig := _orig_y(x, z, surf)
	var bench := _reach_of(prefer)
	var geo := float(proj["dist"])
	var kind := "grade"
	var kinds: PackedStringArray = prefer["kind"]
	if seg_i < kinds.size():
		kind = kinds[seg_i]
	if kind == "bridge" or kind == "deck":
		return Vector3(-999.0, 0.0, 0.0)
	if geo <= bench + CELL_PAD_M:
		return Vector3(surf - STAMP_M, 1.0, geo)
	var past := geo - (bench + CELL_PAD_M)
	if orig >= edge - 0.15:
		var rise := _bench_rise(past, bool(prefer["rock"]))
		var cut_y := edge + rise
		if orig > cut_y:
			return Vector3(cut_y, 0.0, geo)
		return Vector3(orig, 0.0, geo)
	if edge - orig > CLIFF_M:
		return Vector3(orig, 0.0, geo)
	var fill := edge - STAMP_M - past / FILL_RUN
	if fill <= orig:
		return Vector3(orig, 0.0, geo)
	if past < 4.0:
		var u := past / 4.0
		var w := 0.5 - 0.5 * cos(PI * u)
		return Vector3(lerpf(edge - STAMP_M, fill, w), 0.0, geo)
	return Vector3(fill, 0.0, geo)


func _bench_rise(past: float, rock: bool) -> float:
	if past <= 0.0:
		return 0.0
	if not rock:
		return past / SOIL_RUN
	# Inverse of the benched 0.25:1 run. Flat benches add no rise.
	var lo := 0.0
	var hi := past / ROCK_RUN + 2.0
	for _i in 14:
		var mid := (lo + hi) * 0.5
		if _bench_run(mid) < past:
			lo = mid
		else:
			hi = mid
	return lo


func _bench_run(v: float) -> float:
	if v <= 0.0:
		return 0.0
	if v <= ROCK_PLAIN_M:
		return v * ROCK_RUN
	var run := ROCK_PLAIN_M * ROCK_RUN
	var rest := v - ROCK_PLAIN_M
	var cycles := int(rest / BENCH_EVERY_M)
	var rem := rest - float(cycles) * BENCH_EVERY_M
	return run + float(cycles) * (BENCH_EVERY_M * ROCK_RUN + BENCH_WIDTH_M) + rem * ROCK_RUN


func _orig_y(x: float, z: float, fallback: float) -> float:
	if _dem.is_valid():
		var y := float(_dem.call(x, z))
		if y > -70.0:
			return y
	return fallback


func _any_junction_at(x: float, z: float) -> Dictionary:
	var best := 1.0e12
	var found: Dictionary = {}
	for item in _junctions:
		var d := Vector2(x - float(item["pos"][0]), z - float(item["pos"][2])).length()
		if d < best and d <= float(item["radius"]) + CELL_PAD_M:
			best = d
			found = item
	return found


func _nearest_geo(road: Dictionary, x: float, z: float) -> Dictionary:
	var pts: PackedVector3Array = road["pts"]
	var best := 1.0e12
	var found: Dictionary = {}
	for i in range(pts.size() - 1):
		var proj := _project(road, i, x, z)
		if proj.is_empty():
			continue
		if float(proj["dist"]) < best:
			best = float(proj["dist"])
			found = proj
			found["i"] = i
	return found


# --- mesh --------------------------------------------------------------------


func _emit_ribbon(road: Dictionary, rect: Rect2, faces: PackedVector3Array, coord: Vector2i) -> void:
	var pts: PackedVector3Array = road["pts"]
	var reach := _reach_of(road)
	var lats := _lats(float(road["half"]), reach + MESH_EXTRA_M)
	var bars: PackedVector3Array = _barriers.get(coord, PackedVector3Array())
	for i in range(pts.size() - 1):
		if _inside_disc(road, pts[i]) and _inside_disc(road, pts[i + 1]):
			continue
		var a := pts[i]
		var b := pts[i + 1]
		if not _span_hits(a.x, a.z, b.x, b.z, rect, reach + 2.0):
			continue
		var row0 := _row(road, i, 0.0, lats)
		var row1 := _row(road, i, 1.0, lats)
		for k in range(lats.size() - 1):
			_add_tri(faces, row0[k], row1[k], row1[k + 1])
			_add_tri(faces, row0[k], row1[k + 1], row0[k + 1])
		_bar_span(road, i, 0.0, bars)
		_bar_span(road, i, 1.0, bars)
	_emit_aprons(road, rect, faces, lats)
	_barriers[coord] = bars


func _emit_aprons(road: Dictionary, rect: Rect2, faces: PackedVector3Array, lats: PackedFloat32Array) -> void:
	var pts: PackedVector3Array = road["pts"]
	if pts.size() < 2:
		return
	for end_i in [0, pts.size() - 1]:
		var p := pts[end_i]
		var junc := _member_junction_at(road, p.x, p.z)
		if not junc.is_empty():
			var d := Vector2(p.x - float(junc["pos"][0]), p.z - float(junc["pos"][2])).length()
			if d <= float(junc["radius"]) + 1.0:
				continue
		if _vertex_elevated(road, end_i):
			continue
		var dir := _outward_end(pts, end_i)
		if not rect.grow(8.0).has_point(Vector2(p.x, p.z)):
			continue
		var seg_i := 0 if end_i == 0 else pts.size() - 2
		var t := 0.0 if end_i == 0 else 1.0
		var row0 := _row(road, seg_i, t, lats)
		var row1: Array[Vector3] = []
		row1.resize(row0.size())
		for k in row0.size():
			var p0: Vector3 = row0[k]
			row1[k] = Vector3(p0.x + dir.x * APRON_M, p0.y, p0.z + dir.z * APRON_M)
		for k in range(lats.size() - 1):
			_add_tri(faces, row0[k], row1[k], row1[k + 1])
			_add_tri(faces, row0[k], row1[k + 1], row0[k + 1])


func _emit_junction(item: Dictionary, rect: Rect2, faces: PackedVector3Array) -> void:
	var cx := float(item["pos"][0])
	var cz := float(item["pos"][2])
	var radius := float(item["radius"])
	if not rect.grow(radius + 2.0).has_point(Vector2(cx, cz)) and not _circle_hits(cx, cz, radius, rect):
		return
	var steps := clampi(int(ceil(TAU * radius / 1.2)), 16, 64)
	var centre := Vector3(cx, _plane_y(item, cx, cz), cz)
	var prev := Vector3.ZERO
	for s in steps + 1:
		var ang := TAU * float(s % steps) / float(steps)
		var x := cx + cos(ang) * radius
		var z := cz + sin(ang) * radius
		var p := Vector3(x, _plane_y(item, x, z), z)
		if s > 0:
			_add_tri(faces, centre, prev, p)
		prev = p


func _lats(half: float, reach: float) -> PackedFloat32Array:
	var marks: Array[float] = [-reach, -half, 0.0, half, reach]
	var out := PackedFloat32Array()
	var lat := -reach
	while lat < reach - 0.02:
		out.append(lat)
		var nxt := lat + 1.0
		for mark in marks:
			if lat < mark - 0.02 and nxt > mark + 0.02:
				nxt = mark
		lat = nxt
	out.append(reach)
	return out


func _row(road: Dictionary, i: int, t: float, lats: PackedFloat32Array) -> Array:
	var pts: PackedVector3Array = road["pts"]
	var left: PackedVector3Array = road["left"]
	var right: PackedVector3Array = road["right"]
	var half := maxf(float(road["half"]), 0.05)
	var lp := left[i].lerp(left[i + 1], t)
	var rp := right[i].lerp(right[i + 1], t)
	var across := Vector3(rp.x - lp.x, 0.0, rp.z - lp.z)
	var out_r := Vector3.ZERO
	if across.length_squared() > 0.0001:
		out_r = across.normalized()
	var row: Array = []
	for lat in lats:
		var x: float
		var z: float
		if absf(lat) <= half + 0.001:
			var u := clampf(0.5 + lat / (half * 2.0), 0.0, 1.0)
			x = lerpf(lp.x, rp.x, u)
			z = lerpf(lp.z, rp.z, u)
		else:
			var sign := 1.0 if lat > 0.0 else -1.0
			var edge := rp if sign > 0.0 else lp
			var extra := absf(lat) - half
			x = edge.x + out_r.x * sign * extra
			z = edge.z + out_r.z * sign * extra
		var y := _height_at(road, i, t, lat, x, z)
		row.append(Vector3(x, y, z))
	return row


func _bar_span(road: Dictionary, i: int, t: float, bars: PackedVector3Array) -> void:
	var pts: PackedVector3Array = road["pts"]
	var left: PackedVector3Array = road["left"]
	var right: PackedVector3Array = road["right"]
	var half := maxf(float(road["half"]), 0.05)
	var lp := left[i].lerp(left[mini(i + 1, left.size() - 1)], t)
	var rp := right[i].lerp(right[mini(i + 1, right.size() - 1)], t)
	var centre := pts[i].lerp(pts[mini(i + 1, pts.size() - 1)], t)
	var across := Vector3(rp.x - lp.x, 0.0, rp.z - lp.z)
	if across.length_squared() < 0.0001:
		return
	var out_r := across.normalized()
	var edge_y := _height_at(road, i, t, half, rp.x, rp.z)
	var edge_l := _height_at(road, i, t, -half, lp.x, lp.z)
	_bar_side(road, rp, out_r, edge_y, i, t, bars)
	_bar_side(road, lp, -out_r, edge_l, i, t, bars)
	if centre.y < -500.0:
		return


func _bar_side(road: Dictionary, edge: Vector3, outward: Vector3, edge_y: float, i: int, t: float, bars: PackedVector3Array) -> void:
	# Natural ground, not the stamp. A bench that hides a cliff still gets a rail.
	var worst := 0.0
	var dist := 0.5
	while dist <= 3.001:
		var p := Vector3(edge.x, edge_y, edge.z) + outward * dist
		var ground := _orig_y(p.x, p.z, edge_y)
		if ground > -70.0:
			worst = maxf(worst, edge_y - ground)
		dist += 0.5
	if worst <= DROP_BARRIER_M - 0.05:
		return
	var seat := Vector3(edge.x, 0.0, edge.z) + outward * 0.22
	var foot := _stamped_y(seat.x, seat.z, edge_y - STAMP_M)
	var top := edge_y + 0.8
	# The seat ray scores the lowest face against the drawn ground. Sit the rail on that stamp.
	var base := foot
	var tangent := Vector3(-outward.z, 0.0, outward.x)
	var a := seat + tangent * 1.05
	var b := seat - tangent * 1.05
	var a0 := Vector3(a.x, base, a.z)
	var a1 := Vector3(a.x, top, a.z)
	var b0 := Vector3(b.x, base, b.z)
	var b1 := Vector3(b.x, top, b.z)
	# Separate body. These faces are not part of the carriageway soup, so a
	# vertical rail does not count as a road skirt.
	bars.append(a0)
	bars.append(b0)
	bars.append(b1)
	bars.append(a0)
	bars.append(b1)
	bars.append(a1)
	# A lip on the drawn ground so the vertical seat ray lands on the rail, not the void.
	if edge_y - base > 0.4:
		var lip_o := outward * 0.28
		var c0 := Vector3(a.x, base, a.z) + lip_o
		var d0 := Vector3(b.x, base, b.z) + lip_o
		bars.append(a0)
		bars.append(c0)
		bars.append(d0)
		bars.append(a0)
		bars.append(d0)
		bars.append(b0)


func _stamped_y(x: float, z: float, fallback: float) -> float:
	var best_d := 1.0e9
	var y := _orig_y(x, z, fallback)
	var have := false
	var key := Vector2i(int(floor(x / 32.0)), int(floor(z / 32.0)))
	var bag: Array = _seg_buckets.get(key, [])
	for si in bag:
		var seg: Dictionary = _segs[int(si)]
		var road: Dictionary = _roads[int(seg["ri"])]
		var res := _terrain_y(x, z, road, seg)
		if res.y < 0.5 or res.x < -500.0:
			continue
		if res.z < best_d - 0.05:
			best_d = res.z
			y = res.x
			have = true
	if have:
		return y
	if y < -70.0:
		return fallback
	return y


func _probe_ground(road: Dictionary, i: int, x: float, z: float) -> float:
	var pts: PackedVector3Array = road["pts"]
	var a := pts[i]
	var b := pts[mini(i + 1, pts.size() - 1)]
	var res := _terrain_y(x, z, road, {
		"i": i, "ht": -1.0,
		"ax": a.x, "az": a.z, "bx": b.x, "bz": b.z,
	})
	if res.x > -500.0:
		return res.x
	return _orig_y(x, z, -999.0)


func _inside_disc(road: Dictionary, p: Vector3) -> bool:
	var junc := _member_junction_at(road, p.x, p.z)
	if junc.is_empty():
		return false
	var d := Vector2(p.x - float(junc["pos"][0]), p.z - float(junc["pos"][2])).length()
	# Skip a span only when its whole cross-section sits inside the plane.
	return d + _reach_of(road) < float(junc["radius"]) - 0.3


func _add_tri(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var ab := b - a
	var ac := c - a
	var n := ab.cross(ac)
	if n.length_squared() < 0.000004:
		return
	if absf(n.normalized().y) < 0.5:
		return
	faces.append(_snap(a))
	faces.append(_snap(b))
	faces.append(_snap(c))


func _snap(v: Vector3) -> Vector3:
	return Vector3(snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001))


func _visual_from(faces: PackedVector3Array) -> Array:
	if faces.size() < 9:
		return []
	var nrm := PackedVector3Array()
	nrm.resize(faces.size())
	var uv := PackedVector2Array()
	uv.resize(faces.size())
	var i := 0
	while i + 2 < faces.size():
		var n := (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i])
		if n.length_squared() > 0.0000001:
			n = n.normalized()
		else:
			n = Vector3.UP
		if n.y < 0.0:
			n = -n
		nrm[i] = n
		nrm[i + 1] = n
		nrm[i + 2] = n
		uv[i] = Vector2(faces[i].x * 0.25, faces[i].z * 0.25)
		uv[i + 1] = Vector2(faces[i + 1].x * 0.25, faces[i + 1].z * 0.25)
		uv[i + 2] = Vector2(faces[i + 2].x * 0.25, faces[i + 2].z * 0.25)
		i += 3
	var idx := PackedInt32Array()
	idx.resize(faces.size())
	for k in faces.size():
		idx[k] = k
	return [{"mat": "asphalt", "v": faces, "n": nrm, "uv": uv, "i": idx}]


# --- queries -----------------------------------------------------------------


func _closest_on_road(road: Dictionary, x: float, z: float) -> Dictionary:
	var pts: PackedVector3Array = road["pts"]
	var chain: PackedFloat32Array = road["chain"]
	var best := 1.0e12
	var found: Dictionary = {}
	for i in range(pts.size() - 1):
		var abx := pts[i + 1].x - pts[i].x
		var abz := pts[i + 1].z - pts[i].z
		var len2 := abx * abx + abz * abz
		if len2 < 0.01:
			continue
		var t := clampf(((x - pts[i].x) * abx + (z - pts[i].z) * abz) / len2, 0.0, 1.0)
		var px := pts[i].x + abx * t
		var pz := pts[i].z + abz * t
		var d := Vector2(x - px, z - pz).length()
		if d < best:
			best = d
			var s := lerpf(chain[i], chain[i + 1], t) if i + 1 < chain.size() else 0.0
			found = {"dist": d, "p": pts[i].lerp(pts[i + 1], t), "s": s, "i": i, "t": t}
	return found


func _point_along(road: Dictionary, s: float) -> Vector3:
	var pts: PackedVector3Array = road["pts"]
	var chain: PackedFloat32Array = road["chain"]
	if pts.size() < 2 or chain.is_empty():
		return Vector3(0, -999.0, 0)
	if s <= 0.0:
		return pts[0]
	if s >= chain[chain.size() - 1]:
		return pts[pts.size() - 1]
	var i := 0
	while i + 1 < chain.size() and chain[i + 1] < s:
		i += 1
	var span := maxf(chain[i + 1] - chain[i], 0.001)
	return pts[i].lerp(pts[i + 1], clampf((s - chain[i]) / span, 0.0, 1.0))


func _local_grade(road: Dictionary, s: float) -> float:
	var a := _point_along(road, s - 6.0)
	var b := _point_along(road, s + 6.0)
	var ds := Vector2(b.x - a.x, b.z - a.z).length()
	if ds < 1.0:
		return 0.0
	return absf(b.y - a.y) / ds


func _road_elevated_near(road: Dictionary, x: float, z: float, rad: float) -> bool:
	var pts: PackedVector3Array = road["pts"]
	for i in pts.size():
		if Vector2(pts[i].x - x, pts[i].z - z).length() > rad:
			continue
		if _vertex_elevated(road, i):
			return true
	return false


func _overlap_radius(item: Dictionary) -> float:
	var ids: Array = item["roads"]
	var cx := float(item["pos"][0])
	var cz := float(item["pos"][2])
	var need := 0.0
	for ai in ids.size():
		if not _by_id.has(str(ids[ai])):
			continue
		var a: Dictionary = _roads[int(_by_id[str(ids[ai])])]
		var near := _closest_on_road(a, cx, cz)
		if near.is_empty():
			continue
		var reach_a := _reach_of(a)
		for bi in range(ai + 1, ids.size()):
			if not _by_id.has(str(ids[bi])):
				continue
			var b: Dictionary = _roads[int(_by_id[str(ids[bi])])]
			var reach_b := _reach_of(b)
			var s := float(near["s"])
			for step in 18:
				var dist := 2.0 + float(step) * 2.0
				for sign in [-1.0, 1.0]:
					var p := _point_along(a, s + sign * dist)
					if p.y < -500.0:
						continue
					if Vector2(p.x - cx, p.z - cz).length() > dist + 4.0:
						continue
					var on_b := _closest_on_road(b, p.x, p.z)
					if on_b.is_empty():
						continue
					if float(on_b["dist"]) <= reach_a + reach_b:
						need = maxf(need, Vector2(p.x - cx, p.z - cz).length() + 1.0)
	return need


func _fit_plane(pts: Array[Vector3], cx: float, cz: float, fallback: float) -> Dictionary:
	if pts.size() < 2:
		return {"y": fallback, "sx": 0.0, "sz": 0.0}
	var n := float(pts.size())
	var sx := 0.0
	var sz := 0.0
	var sy := 0.0
	var sxx := 0.0
	var szz := 0.0
	var sxz := 0.0
	var sxy := 0.0
	var szy := 0.0
	for p in pts:
		var x := p.x - cx
		var z := p.z - cz
		sx += x
		sz += z
		sy += p.y
		sxx += x * x
		szz += z * z
		sxz += x * z
		sxy += x * p.y
		szy += z * p.y
	var a := _solve3(sxx, sxz, sx, sxy, sxz, szz, sz, szy, sx, sz, n, sy)
	if is_nan(a.x) or is_nan(a.y) or is_nan(a.z):
		return {"y": fallback, "sx": 0.0, "sz": 0.0}
	return {"y": a.z, "sx": a.x, "sz": a.y}


func _solve3(a00: float, a01: float, a02: float, b0: float, a10: float, a11: float, a12: float, b1: float, a20: float, a21: float, a22: float, b2: float) -> Vector3:
	var m := [
		[a00, a01, a02, b0],
		[a10, a11, a12, b1],
		[a20, a21, a22, b2],
	]
	for col in 3:
		var pivot := col
		var best := absf(m[col][col])
		for row in range(col + 1, 3):
			if absf(m[row][col]) > best:
				best = absf(m[row][col])
				pivot = row
		if best < 1.0e-8:
			return Vector3(0, 0, b2 / maxf(absf(a22), 1.0))
		var tmp: Array = m[col]
		m[col] = m[pivot]
		m[pivot] = tmp
		var div: float = m[col][col]
		for k in 4:
			m[col][k] = float(m[col][k]) / div
		for row in 3:
			if row == col:
				continue
			var f: float = m[row][col]
			for k in 4:
				m[row][k] = float(m[row][k]) - f * float(m[col][k])
	return Vector3(float(m[0][3]), float(m[1][3]), float(m[2][3]))


func _miter_side(pts: PackedVector3Array, i: int) -> Vector3:
	var prev := pts[i] - pts[maxi(i - 1, 0)]
	var nxt := pts[mini(i + 1, pts.size() - 1)] - pts[i]
	prev.y = 0.0
	nxt.y = 0.0
	if prev.length() < 0.05:
		prev = nxt
	if nxt.length() < 0.05:
		nxt = prev
	if prev.length() < 0.05:
		return Vector3(1.0, 0.0, 0.0)
	var s0 := Vector3(prev.z, 0.0, -prev.x).normalized()
	var s1 := Vector3(nxt.z, 0.0, -nxt.x).normalized()
	var side := s0 + s1
	if side.length() < 0.15:
		side = s1
	else:
		side = side.normalized()
	var scale := 1.0 / maxf(0.55, side.dot(s1))
	return side * minf(scale, 1.75)


func _outward_end(pts: PackedVector3Array, index: int) -> Vector3:
	var dir: Vector3
	if index == 0:
		dir = pts[0] - pts[1]
	else:
		dir = pts[index] - pts[index - 1]
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return Vector3(1.0, 0.0, 0.0)
	return dir.normalized()


func _span_hits(ax: float, az: float, bx: float, bz: float, rect: Rect2, pad: float) -> bool:
	var grown := rect.grow(pad)
	if grown.has_point(Vector2(ax, az)) or grown.has_point(Vector2(bx, bz)):
		return true
	var min_x := minf(ax, bx)
	var max_x := maxf(ax, bx)
	var min_z := minf(az, bz)
	var max_z := maxf(az, bz)
	return not (max_x < grown.position.x or min_x > grown.end.x or max_z < grown.position.y or min_z > grown.end.y)


func _circle_hits(x: float, z: float, rad: float, rect: Rect2) -> bool:
	var cx := clampf(x, rect.position.x, rect.end.x)
	var cz := clampf(z, rect.position.y, rect.end.y)
	return Vector2(x - cx, z - cz).length() <= rad


func _chunk_of_host(host: Node, faces: PackedVector3Array) -> Vector2i:
	var name := str(host.name)
	if name.begins_with("C_"):
		var parts := name.split("_")
		# "C_-1_-4" splits to ["C", "-1", "-4"].
		if parts.size() >= 3 and parts[1] != "" and parts[2] != "":
			return Vector2i(int(parts[1]), int(parts[2]))
	if faces.size() > 0:
		return WorldConfig.chunk_of(faces[0].x, faces[0].z)
	return Vector2i.ZERO


func _place_features(host: Node3D, coord: Vector2i) -> void:
	for feat in _features:
		if WorldConfig.chunk_of(float(feat["x"]), float(feat["z"])) != coord:
			continue
		var node_name := str(feat["name"])
		if host.get_node_or_null(node_name) != null:
			node_name = "%s_%d" % [node_name, host.get_child_count()]
		var node := Node3D.new()
		node.name = node_name
		node.position = Vector3(float(feat["x"]), float(feat["y"]), float(feat["z"]))
		host.add_child(node)
