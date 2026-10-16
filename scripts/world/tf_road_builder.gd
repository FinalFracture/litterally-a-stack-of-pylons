class_name TfRoadBuilder
extends RefCounted

## Twin Falls roads, rail, street signs and landmark models, one chunk at a time.
## prepare() is main-thread. apply_cuts() and build_chunk() only read that data,
## so the terrain worker may call them. jobs() runs on the main thread and puts
## one mesh, one collision body, the signs and the landmark instances under host.
##
## One height per cross-section: the smoothed centreline, plus a 2% crown on
## straights or a bank of at most 6 deg on curves. Cuts lower the heightfield
## under the carriageway and lay back at 1.5:1. Fills are 2:1 skirts in the
## dry-ground material, not raised ground. Deck and bridge stay on their
## authored grade. The Perrine model is the landmark, not a second deck.

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
## 2% crown. Banking replaces it once a curve exceeds about 1.5 deg.
const CROWN_RATE := 0.02
const BANK_MAX_DEG := 6.0
## Longitudinal cap. Canyon Springs Grade is authored at this limit.
const GRADE_CAP := 0.10
## Cut 1.5:1 (34 deg). Fill skirt 2:1 (27 deg). Reach covers a 24 m cut.
const CUT_H_PER_V := 1.5
const FILL_H_PER_V := 2.0
const EARTH_REACH_M := 36.0
const CUT_CLEAR_M := 0.08
## Flat cut past the paint. A 4 m terrain quad that straddles the edge would
## otherwise tilt up through the asphalt. The 1.5:1 slope starts outside this.
const SHOULDER_M := 6.5
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
var _crossings: Array = []


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
	_finish_profiles()
	_build_mats()


## Lower the carriageway of cut (and high grade) segments. Never raises a cell.
func apply_cuts(grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	if n < 2 or grid.size() != n * n or _edges.is_empty():
		return
	var reach := EARTH_REACH_M + SHOULDER_M
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
		"earth": _Surf.new(),
		"panel": _Surf.new(),
	}
	var faces := PackedVector3Array()
	for road in _roads:
		_emit_road(road, rect, grid, n, spacing, coord, surfs, faces)
	_emit_junctions(coord, surfs["asphalt"], faces, grid, n, spacing)
	_emit_crossings(coord, surfs["panel"], faces)
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
## boat-ramp head on one grade, so the old drop to y=-8 does not leave a step.
func _extend_grade(pts: PackedVector3Array) -> PackedVector3Array:
	var end := pts[pts.size() - 1]
	var out := pts.duplicate()
	var run: Array[Vector3] = [
		Vector3(end.x, end.y, end.z - 25.0),
		Vector3(2448.0, end.y, -6680.0),
		Vector3(2446.0, end.y, -6735.0),
		Vector3(2445.0, end.y, -6745.0),
		RAMP_TOP,
	]
	var dist := PackedFloat32Array()
	dist.resize(run.size())
	var walked := 0.0
	var prev := end
	for i in run.size():
		walked += Vector2(run[i].x - prev.x, run[i].z - prev.z).length()
		dist[i] = walked
		prev = run[i]
	if walked < 1.0:
		return out
	for i in run.size():
		var p := run[i]
		p.y = lerpf(end.y, RAMP_TOP.y, dist[i] / walked)
		out.append(p)
	return out


## Junction heights, the 10% cap, crown/bank, then the cut edges and rail crossings.
func _finish_profiles() -> void:
	_match_junctions()
	for road in _roads:
		_cap_grade(road)
	for item in _junctions:
		item["flat_y"] = _major_y(item)
	for road in _roads:
		_store_bank(road)
	_rebuild_edges()
	_find_crossings()


func _match_junctions() -> void:
	for item in _junctions:
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var major := _major_id(item)
		if major == "":
			continue
		var major_half := 0.0
		if _by_id.has(major):
			major_half = float((_roads[int(_by_id[major])] as Dictionary)["half"])
		var minor_half := 0.0
		for id in item.get("roads", []):
			if str(id) == major or not _by_id.has(str(id)):
				continue
			minor_half = maxf(minor_half, float((_roads[int(_by_id[str(id)])] as Dictionary)["half"]))
		var radius := major_half + 1.2
		if minor_half > 0.0:
			radius = maxf(radius, sqrt(major_half * major_half + minor_half * minor_half) + 1.8)
		item["radius"] = radius
		var jx := float(pos[0])
		var jz := float(pos[2])
		var major_y := _major_y(item)
		for id in item.get("roads", []):
			if str(id) == major or not _by_id.has(str(id)):
				continue
			_set_join_vertex(_roads[int(_by_id[str(id)])], jx, jz, major_y)


func _set_join_vertex(road: Dictionary, x: float, z: float, y: float) -> void:
	var pts: PackedVector3Array = road["pts"]
	var best := 1.0e9
	var bi := -1
	for i in pts.size():
		var d := Vector2(pts[i].x - x, pts[i].z - z).length()
		if d < best:
			best = d
			bi = i
	if bi < 0 or best > 4.0 or _vertex_locked(road, bi):
		return
	var p := pts[bi]
	p.y = y
	pts[bi] = p
	road["pts"] = pts
	var pins: Dictionary = road.get("pins", {})
	pins[bi] = true
	road["pins"] = pins


## Grade pins. The Perrine joint stays at 142.76 and the boat-ramp head stays put.
## Other deck vertices may move so a 10% cap can run through a switchback.
func _vertex_locked(road: Dictionary, i: int) -> bool:
	var kinds: PackedStringArray = road["kind"]
	var pts: PackedVector3Array = road["pts"]
	if i < kinds.size() and kinds[i] == "bridge":
		return true
	if i > 0 and kinds[i - 1] == "bridge":
		return true
	if _near_bridge(pts[i]):
		return true
	if str(road["id"]) == "canyon_springs_grade" and i == pts.size() - 1:
		return true
	return false


func _near_bridge(p: Vector3) -> bool:
	if not _by_id.has("us93_perrine_bridge"):
		return false
	var road: Dictionary = _roads[int(_by_id["us93_perrine_bridge"])]
	var pts: PackedVector3Array = road["pts"]
	for q in pts:
		if Vector2(p.x - q.x, p.z - q.z).length() <= 2.0:
			return true
	return false


## A deck or bridge span is flat. Its vertices take no crown, so the next span
## does not open a lip where the crown fades in.
func _flat_span(road: Dictionary, i: int) -> bool:
	var kinds: PackedStringArray = road["kind"]
	if i < kinds.size() and (kinds[i] == "deck" or kinds[i] == "bridge"):
		return true
	if i > 0 and (kinds[i - 1] == "deck" or kinds[i - 1] == "bridge"):
		return true
	return false


## Pull any segment steeper than GRADE_CAP back onto the cone. Pinned vertices stay.
func _cap_grade(road: Dictionary) -> void:
	var pts: PackedVector3Array = road["pts"]
	if pts.size() < 2:
		return
	var pin: Dictionary = road.get("pins", {})
	for i in pts.size():
		if _vertex_locked(road, i):
			pin[i] = true
	for _pass in 8:
		for i in range(1, pts.size()):
			_enforce_grade(road, pts, i - 1, i, pin)
		for i in range(pts.size() - 2, -1, -1):
			_enforce_grade(road, pts, i + 1, i, pin)
	road["pts"] = pts
	road["pins"] = pin


## GRADE_CAP * ds / ds prints 10.00008%. A 1 mm slack printed 10.02% on a short deck.
func _grade_drop(ds: float) -> float:
	var limit := GRADE_CAP * ds
	var n := 0
	while n < 4 and limit > 0.0 and limit / ds > GRADE_CAP:
		limit *= 0.999999
		n += 1
	return limit


func _enforce_grade(road: Dictionary, pts: PackedVector3Array, ia: int, ib: int, pin: Dictionary) -> void:
	var ds := Vector2(pts[ib].x - pts[ia].x, pts[ib].z - pts[ia].z).length()
	if ds < 0.05:
		return
	var dy := pts[ib].y - pts[ia].y
	if absf(dy) / ds <= GRADE_CAP:
		return
	if pin.has(ia) and pin.has(ib):
		_release_grade_pin(road, ia, ib, pin)
	var limit := _grade_drop(ds)
	var clamped := clampf(dy, -limit, limit)
	if not pin.has(ib):
		var pb := pts[ib]
		pb.y = pts[ia].y + clamped
		var n := 0
		while n < 4 and absf(pb.y - pts[ia].y) / ds > GRADE_CAP:
			pb.y -= signf(clamped) * maxf(ds * 0.000001, 0.00001)
			n += 1
		pts[ib] = pb
	elif not pin.has(ia):
		var pa := pts[ia]
		pa.y = pts[ib].y - clamped
		var n2 := 0
		while n2 < 4 and absf(pts[ib].y - pa.y) / ds > GRADE_CAP:
			pa.y += signf(clamped) * maxf(ds * 0.000001, 0.00001)
			n2 += 1
		pts[ia] = pa


## Junction pins can hold a deck segment 0.9 mm over the cap. Bridge joints and the ramp stay.
func _release_grade_pin(road: Dictionary, ia: int, ib: int, pin: Dictionary) -> void:
	var kinds: PackedStringArray = road["kind"]
	var i0 := mini(ia, ib)
	if i0 < kinds.size() and kinds[i0] == "bridge":
		return
	if pin.has(ib) and not _vertex_locked(road, ib):
		pin.erase(ib)
	elif pin.has(ia) and not _vertex_locked(road, ia):
		pin.erase(ia)


func _store_bank(road: Dictionary) -> void:
	var pts: PackedVector3Array = road["pts"]
	var bank := PackedFloat32Array()
	var crown := PackedFloat32Array()
	bank.resize(pts.size())
	crown.resize(pts.size())
	var rail := bool(road["rail"])
	var half := float(road["half"])
	for i in pts.size():
		var b := 0.0 if rail else _bank_vertex(road, i)
		bank[i] = b
		if rail or absf(b) > deg_to_rad(1.0) or _vertex_locked(road, i) or _flat_span(road, i) or _inside_junction(str(road["id"]), pts[i]):
			crown[i] = 0.0
		else:
			crown[i] = CROWN_RATE * half
	if bank.size() >= 3:
		var sm := bank.duplicate()
		for i in range(1, bank.size() - 1):
			if absf(bank[i]) < 0.00001:
				sm[i] = 0.0
			else:
				sm[i] = clampf((bank[i - 1] + bank[i] + bank[i + 1]) / 3.0, deg_to_rad(-BANK_MAX_DEG), deg_to_rad(BANK_MAX_DEG))
		bank = sm
	road["bank"] = bank
	road["crown"] = crown


func _bank_vertex(road: Dictionary, i: int) -> float:
	var pts: PackedVector3Array = road["pts"]
	if i <= 0 or i + 1 >= pts.size():
		return 0.0
	if _inside_junction(str(road["id"]), pts[i]):
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
	return deg_to_rad(clampf(turn / 8.0, -BANK_MAX_DEG, BANK_MAX_DEG))


func _inside_junction(road_id: String, p: Vector3) -> bool:
	for item in _junctions:
		var ids: Array = item.get("roads", [])
		if not ids.has(road_id):
			continue
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var rad := float(item.get("radius", 8.0))
		if Vector2(p.x - float(pos[0]), p.z - float(pos[2])).length() <= rad + 3.0:
			return true
	return false


func _rebuild_edges() -> void:
	_edges.clear()
	_buckets.clear()
	for road in _roads:
		var pts: PackedVector3Array = road["pts"]
		var left: PackedVector3Array = road["left"]
		var right: PackedVector3Array = road["right"]
		var bank: PackedFloat32Array = road["bank"]
		var crown: PackedFloat32Array = road["crown"]
		var kinds: PackedStringArray = road["kind"]
		var half := float(road["half"])
		var rail := bool(road["rail"])
		for i in pts.size():
			var lp := left[i]
			var rp := right[i]
			lp.y = pts[i].y
			rp.y = pts[i].y
			left[i] = lp
			right[i] = rp
		road["left"] = left
		road["right"] = right
		for i in pts.size() - 1:
			var edge := {
				"ax": pts[i].x, "ay": pts[i].y, "az": pts[i].z,
				"bx": pts[i + 1].x, "by": pts[i + 1].y, "bz": pts[i + 1].z,
				"half": half,
				"kind": kinds[i],
				"ba": bank[i], "bb": bank[i + 1],
				"ca": crown[i], "cb": crown[i + 1],
				"rail": rail,
			}
			var ei := _edges.size()
			_edges.append(edge)
			_bucket_edge(ei, edge)


func _find_crossings() -> void:
	_crossings.clear()
	var rails: Array = []
	for road in _roads:
		if bool(road["rail"]):
			rails.append(road)
	for road in _roads:
		if bool(road["rail"]):
			continue
		var pts: PackedVector3Array = road["pts"]
		for i in pts.size() - 1:
			for rail in rails:
				var rp: PackedVector3Array = rail["pts"]
				for j in rp.size() - 1:
					var hit := _xz_cross(pts[i], pts[i + 1], rp[j], rp[j + 1])
					if hit.x < 0.0:
						continue
					var dir := pts[i + 1] - pts[i]
					dir.y = 0.0
					if dir.length_squared() < 0.01:
						continue
					dir = dir.normalized()
					var rdir := rp[j + 1] - rp[j]
					rdir.y = 0.0
					if rdir.length_squared() < 0.01:
						continue
					rdir = rdir.normalized()
					var sin_t := absf(dir.x * rdir.z - dir.z * rdir.x)
					var gauge := _gauge_half * 2.0
					var zone := gauge / maxf(sin_t, 0.25) + 3.2
					var road_y := lerpf(pts[i].y, pts[i + 1].y, hit.y)
					_crossings.append({
						"x": hit.z,
						"z": hit.w,
						"y": road_y,
						"road": str(road["id"]),
						"half": float(road["half"]),
						"along": zone * 0.5,
						"dir": dir,
					})


## Returns (valid, t_on_ab, x, z). valid is -1 when the segments miss.
func _xz_cross(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> Vector4:
	var rx := b.x - a.x
	var rz := b.z - a.z
	var sx := d.x - c.x
	var sz := d.z - c.z
	var den := rx * sz - rz * sx
	if absf(den) < 0.0000001:
		return Vector4(-1.0, 0.0, 0.0, 0.0)
	var qpx := c.x - a.x
	var qpz := c.z - a.z
	var t := (qpx * sz - qpz * sx) / den
	var u := (qpx * rz - qpz * rx) / den
	if t < 0.0 or t > 1.0 or u < 0.0 or u > 1.0:
		return Vector4(-1.0, 0.0, 0.0, 0.0)
	return Vector4(1.0, t, a.x + rx * t, a.z + rz * t)


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
	var pad: float = float(edge["half"]) + EARTH_REACH_M + 4.0
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
	return _join_breaks(min_x, min_z, max_x, max_z, limit, ground_at)


## Junction disc and its shoulder. A 16 m triangle across the corner pokes through the patch.
func _join_breaks(min_x: float, min_z: float, max_x: float, max_z: float, limit: float, ground_at: Callable) -> bool:
	for item in _junctions:
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var jx := float(pos[0])
		var jz := float(pos[2])
		var flat_r := float(item.get("radius", 8.0)) + SHOULDER_M
		var reach := flat_r + EARTH_REACH_M
		if jx + reach < min_x or jx - reach > max_x or jz + reach < min_z or jz - reach > max_z:
			continue
		var road_y := float(item.get("flat_y", float(pos[1]))) - CUT_CLEAR_M
		# The disc itself, not the 4 m probe. A corner triangle still crosses the patch.
		if _disc_hits_rect(jx, jz, flat_r, min_x, min_z, max_x, max_z):
			return true
		var steps := 4
		for iz in steps + 1:
			for ix in steps + 1:
				var x := lerpf(min_x, max_x, float(ix) / float(steps))
				var z := lerpf(min_z, max_z, float(iz) / float(steps))
				var dist := Vector2(x - jx, z - jz).length()
				if dist > reach:
					continue
				var ground := float(ground_at.call(x, z))
				if ground < -70.0:
					continue
				var target := road_y if dist <= flat_r else road_y + (dist - flat_r) / CUT_H_PER_V
				if dist <= flat_r and ground > target + 0.05:
					return true
				if ground - target > limit:
					return true
	return false


func _edge_drops(edge: Dictionary, min_x: float, min_z: float, max_x: float, max_z: float, limit: float, ground_at: Callable) -> bool:
	var ax := float(edge["ax"])
	var az := float(edge["az"])
	var bx := float(edge["bx"])
	var bz := float(edge["bz"])
	var reach := float(edge["half"]) + EARTH_REACH_M
	if maxf(ax, bx) + reach < min_x or minf(ax, bx) - reach > max_x:
		return false
	if maxf(az, bz) + reach < min_z or minf(az, bz) - reach > max_z:
		return false
	# A 16 m quad crosses the asphalt when the centreline misses the 4 m probe.
	# Bridge spans stay coarse; the deck is a hundred metres up.
	var kind := str(edge["kind"])
	if kind != "bridge":
		var flat := float(edge["half"]) + SHOULDER_M
		if _seg_hits_rect(ax, az, bx, bz, min_x - flat, min_z - flat, max_x + flat, max_z + flat):
			return true
	var steps := 4
	for iz in steps + 1:
		for ix in steps + 1:
			var x := lerpf(min_x, max_x, float(ix) / float(steps))
			var z := lerpf(min_z, max_z, float(iz) / float(steps))
			var hit := _seg_side(x, z, ax, az, bx, bz)
			if hit.x > reach:
				continue
			var ground := float(ground_at.call(x, z))
			if ground < -70.0:
				continue
			var target := _cut_target(edge, hit.x, hit.y, hit.z)
			# The carriageway and its shoulder have to survive the 16 m merge.
			if hit.x <= float(edge["half"]) + SHOULDER_M and ground > target + 0.05:
				return true
			if ground - target > limit:
				return true
	return false


## After the simplified triangles raise the heightmap, put the footprint back on the cut.
## A 16 m quad's plane is what drawn_height_at samples through the asphalt.
func clamp_footprint(drawn: PackedFloat32Array, cut: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	if n < 2 or drawn.size() != n * n or cut.size() != n * n or _edges.is_empty():
		return
	var reach := EARTH_REACH_M + SHOULDER_M
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
				_clamp_edge(drawn, cut, origin, n, spacing, _edges[ei])
	_clamp_joins(drawn, cut, origin, n, spacing)


func _clamp_edge(drawn: PackedFloat32Array, cut: PackedFloat32Array, origin: Vector2, n: int, spacing: float, edge: Dictionary) -> void:
	if str(edge["kind"]) == "bridge":
		return
	var ax := float(edge["ax"])
	var az := float(edge["az"])
	var bx := float(edge["bx"])
	var bz := float(edge["bz"])
	var flat_r := float(edge["half"]) + SHOULDER_M
	var min_x := minf(ax, bx) - flat_r
	var max_x := maxf(ax, bx) + flat_r
	var min_z := minf(az, bz) - flat_r
	var max_z := maxf(az, bz) + flat_r
	var c0 := clampi(int(floor((min_x - origin.x) / spacing)), 0, n - 1)
	var c1 := clampi(int(ceil((max_x - origin.x) / spacing)), 0, n - 1)
	var r0 := clampi(int(floor((min_z - origin.y) / spacing)), 0, n - 1)
	var r1 := clampi(int(ceil((max_z - origin.y) / spacing)), 0, n - 1)
	for r in range(r0, r1 + 1):
		var z := origin.y + float(r) * spacing
		var row := r * n
		for c in range(c0, c1 + 1):
			var x := origin.x + float(c) * spacing
			var hit := _seg_side(x, z, ax, az, bx, bz)
			if hit.x > flat_r:
				continue
			var i := row + c
			if drawn[i] > cut[i]:
				drawn[i] = cut[i]


func _clamp_joins(drawn: PackedFloat32Array, cut: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	for item in _junctions:
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var jx := float(pos[0])
		var jz := float(pos[2])
		var flat_r := float(item.get("radius", 8.0)) + SHOULDER_M
		if jx < origin.x - flat_r or jx > origin.x + 500.0 + flat_r:
			continue
		if jz < origin.y - flat_r or jz > origin.y + 500.0 + flat_r:
			continue
		var c0 := clampi(int(floor((jx - flat_r - origin.x) / spacing)), 0, n - 1)
		var c1 := clampi(int(ceil((jx + flat_r - origin.x) / spacing)), 0, n - 1)
		var r0 := clampi(int(floor((jz - flat_r - origin.y) / spacing)), 0, n - 1)
		var r1 := clampi(int(ceil((jz + flat_r - origin.y) / spacing)), 0, n - 1)
		for r in range(r0, r1 + 1):
			var z := origin.y + float(r) * spacing
			var row := r * n
			for c in range(c0, c1 + 1):
				var x := origin.x + float(c) * spacing
				if Vector2(x - jx, z - jz).length() > flat_r:
					continue
				var i := row + c
				if drawn[i] > cut[i]:
					drawn[i] = cut[i]


func _disc_hits_rect(x: float, z: float, rad: float, min_x: float, min_z: float, max_x: float, max_z: float) -> bool:
	var cx := clampf(x, min_x, max_x)
	var cz := clampf(z, min_z, max_z)
	var dx := x - cx
	var dz := z - cz
	return dx * dx + dz * dz <= rad * rad


func _seg_hits_rect(ax: float, az: float, bx: float, bz: float, min_x: float, min_z: float, max_x: float, max_z: float) -> bool:
	var span := Vector2(0.0, 1.0)
	var dx := bx - ax
	var dz := bz - az
	span = _clip_plane(-dx, ax - min_x, span)
	if span.x > span.y:
		return false
	span = _clip_plane(dx, max_x - ax, span)
	if span.x > span.y:
		return false
	span = _clip_plane(-dz, az - min_z, span)
	if span.x > span.y:
		return false
	span = _clip_plane(dz, max_z - az, span)
	return span.x <= span.y


func _cut_edge(grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, edge: Dictionary) -> void:
	var ax := float(edge["ax"])
	var az := float(edge["az"])
	var bx := float(edge["bx"])
	var bz := float(edge["bz"])
	var reach := float(edge["half"]) + EARTH_REACH_M
	var min_x := minf(ax, bx) - reach
	var max_x := maxf(ax, bx) + reach
	var min_z := minf(az, bz) - reach
	var max_z := maxf(az, bz) + reach
	var c0 := clampi(int(floor((min_x - origin.x) / spacing)), 0, n - 1)
	var c1 := clampi(int(ceil((max_x - origin.x) / spacing)), 0, n - 1)
	var r0 := clampi(int(floor((min_z - origin.y) / spacing)), 0, n - 1)
	var r1 := clampi(int(ceil((max_z - origin.y) / spacing)), 0, n - 1)
	for r in range(r0, r1 + 1):
		var z := origin.y + float(r) * spacing
		var row := r * n
		for c in range(c0, c1 + 1):
			var x := origin.x + float(c) * spacing
			var hit := _seg_side(x, z, ax, az, bx, bz)
			if hit.x > reach:
				continue
			var target := _cut_target(edge, hit.x, hit.y, hit.z)
			var i := row + c
			if grid[i] > target:
				grid[i] = target


## Left, centre, right heights. Bank lowers the inside edge. Crown lowers both edges.
func _section(cy: float, bank: float, drop: float, half: float) -> Vector3:
	var max_dy := tan(deg_to_rad(BANK_MAX_DEG)) * half
	var dy := clampf(tan(bank) * half, -max_dy, max_dy)
	var crown_k := clampf(1.0 - absf(bank) / deg_to_rad(1.5), 0.0, 1.0)
	var crown := drop * crown_k
	return Vector3(cy - dy - crown, cy, cy + dy - crown)


func _cut_target(edge: Dictionary, dist: float, t: float, side: float) -> float:
	var cy := lerpf(float(edge["ay"]), float(edge["by"]), t)
	var bank := lerpf(float(edge.get("ba", 0.0)), float(edge.get("bb", 0.0)), t)
	var drop := lerpf(float(edge.get("ca", 0.0)), float(edge.get("cb", 0.0)), t)
	var half := float(edge["half"])
	var kind := str(edge["kind"])
	var flat := bool(edge.get("rail", false)) or kind == "deck" or kind == "bridge"
	var sec := Vector3(cy, cy, cy) if flat else _section(cy, bank, drop, half)
	var low := minf(sec.x, sec.z) - CUT_CLEAR_M
	var flat_r := half + SHOULDER_M
	if dist <= flat_r:
		return low
	var edge_y := sec.x if side > 0.0 else sec.z
	return edge_y - CUT_CLEAR_M + (dist - flat_r) / CUT_H_PER_V


## Distance, t, and side (+1 is the miter's left).
func _seg_side(px: float, pz: float, ax: float, az: float, bx: float, bz: float) -> Vector3:
	var abx := bx - ax
	var abz := bz - az
	var len2 := abx * abx + abz * abz
	var t := 0.0
	if len2 > 0.0001:
		t = clampf(((px - ax) * abx + (pz - az) * abz) / len2, 0.0, 1.0)
	var dx := px - (ax + abx * t)
	var dz := pz - (az + abz * t)
	var side := 1.0
	if abz * dx - abx * dz >= 0.0:
		side = -1.0
	return Vector3(sqrt(dx * dx + dz * dz), t, side)


func _emit_road(road: Dictionary, rect: Rect2, grid: PackedFloat32Array, n: int, spacing: float, _coord: Vector2i, surfs: Dictionary, faces: PackedVector3Array) -> void:
	var pts: PackedVector3Array = road["pts"]
	var left: PackedVector3Array = road["left"]
	var right: PackedVector3Array = road["right"]
	var chain: PackedFloat32Array = road["chain"]
	var kinds: PackedStringArray = road["kind"]
	var bank: PackedFloat32Array = road["bank"]
	var crown: PackedFloat32Array = road["crown"]
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
		var full_len := Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length()
		var seg_len := full_len * (t1 - t0)
		var pieces := maxi(int(ceil(seg_len / 4.0)), 1)
		# Perrine spans overlap the next span by 2 m. The overlap is a separate
		# sheet that starts flush and falls away, so the mesh boundary sits
		# under the next surface instead of standing on the lane.
		var overlap := 2.0 if _perrine_road(road_id) and full_len > 1.0 else 0.0
		var dt := overlap / full_len
		for p in pieces:
			var a0 := t0 + (t1 - t0) * float(p) / float(pieces)
			var b0 := t0 + (t1 - t0) * float(p + 1) / float(pieces)
			var a := a0
			var b := b0
			if p == 0:
				a -= dt
			if p == pieces - 1:
				b += dt
			if a < a0 - 0.0000001:
				_emit_span(road_id, kind, rail, lanes, half, lift, left[i], left[i + 1], right[i], right[i + 1], bank[i], bank[i + 1], crown[i], crown[i + 1], chain[i], chain[i + 1], a, a0, grid, origin, n, spacing, surfs, faces, -1)
			if b0 - a0 > 0.0000001:
				_emit_span(road_id, kind, rail, lanes, half, lift, left[i], left[i + 1], right[i], right[i + 1], bank[i], bank[i + 1], crown[i], crown[i + 1], chain[i], chain[i + 1], a0, b0, grid, origin, n, spacing, surfs, faces, 0)
			if b > b0 + 0.0000001:
				_emit_span(road_id, kind, rail, lanes, half, lift, left[i], left[i + 1], right[i], right[i + 1], bank[i], bank[i + 1], crown[i], crown[i + 1], chain[i], chain[i + 1], b0, b, grid, origin, n, spacing, surfs, faces, 1)


func _emit_span(road_id: String, kind: String, rail: bool, lanes: int, half: float, lift: float, left_a: Vector3, left_b: Vector3, right_a: Vector3, right_b: Vector3, bank_a: float, bank_b: float, crown_a: float, crown_b: float, chain_a: float, chain_b: float, t0: float, t1: float, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, surfs: Dictionary, faces: PackedVector3Array, ramp_end: int = 0) -> void:
	var l0 := left_a.lerp(left_b, t0)
	var l1 := left_a.lerp(left_b, t1)
	var r0 := right_a.lerp(right_b, t0)
	var r1 := right_a.lerp(right_b, t1)
	var flat := rail or kind == "deck" or kind == "bridge"
	var s0 := _section(l0.y + lift, lerpf(bank_a, bank_b, t0), lerpf(crown_a, crown_b, t0), half) if not flat else Vector3(l0.y + lift, l0.y + lift, l0.y + lift)
	var s1 := _section(l1.y + lift, lerpf(bank_a, bank_b, t1), lerpf(crown_a, crown_b, t1), half) if not flat else Vector3(l1.y + lift, l1.y + lift, l1.y + lift)
	l0.y = s0.x
	l1.y = s1.x
	r0.y = s0.z
	r1.y = s1.z
	var m0 := l0.lerp(r0, 0.5)
	var m1 := l1.lerp(r1, 0.5)
	m0.y = s0.y
	m1.y = s1.y
	# ramp_end -1: outer edge is t0. +1: outer edge is t1. The inner edge stays
	# on the carriageway height so the sheet welds to it. The outer edge drops
	# 30 cm. The approach is already ~10 cm below the deck 2 m out, so a 10 cm
	# drop leaves the boundary on the lane and the cone stops on it.
	if ramp_end < 0:
		var inner_y := s1.y
		l0.y = inner_y - 0.30
		r0.y = inner_y - 0.30
		m0.y = inner_y - 0.30
	elif ramp_end > 0:
		var inner_y := s0.y
		l1.y = inner_y - 0.30
		r1.y = inner_y - 0.30
		m1.y = inner_y - 0.30
	if ramp_end != 0:
		_solid_quad(faces, l0, m0, m1, l1)
		_solid_quad(faces, m0, r0, r1, m1)
		return
	var c0 := chain_a + (chain_b - chain_a) * t0
	var c1 := chain_a + (chain_b - chain_a) * t1
	# The v4 model is the deck. A second asphalt sheet hides the lanes and
	# puts the ray on the sheet instead of the deck. Keep the walk surface.
	if kind == "bridge" and not rail:
		_solid_quad(faces, l0, m0, m1, l1)
		_solid_quad(faces, m0, r0, r1, m1)
		return
	if rail:
		var on_panel := _rail_on_panel(m0) and _rail_on_panel(m1)
		if not on_panel:
			var ball: _Surf = surfs["ballast"]
			_quad(ball, l0, m0, m1, l1, c0, c1, 0.0, half, true, faces)
			_quad(ball, m0, r0, r1, m1, c0, c1, half, half * 2.0, true, faces)
		_rails(surfs["rail"], l0, r0, r1, l1, c0, c1)
		if kind == "trestle":
			_trestle(surfs["basalt"], l0, r0, r1, l1, grid, origin, n, spacing, faces)
		if kind != "deck" and kind != "bridge":
			_skirts(surfs["earth"], l0, r0, l1, r1, grid, origin, n, spacing)
		return
	var top: _Surf = surfs["asphalt"]
	_quad(top, l0, m0, m1, l1, c0, c1, 0.0, half, true, faces)
	_quad(top, m0, r0, r1, m1, c0, c1, half, half * 2.0, true, faces)
	_paint_lines(road_id, surfs, l0, r0, l1, r1, half, lanes, c0, c1)
	if kind != "deck" and kind != "bridge":
		_skirts(surfs["earth"], l0, r0, l1, r1, grid, origin, n, spacing)
	# The apron is above the canyon lip. A thin ribbon lets the cone fall through.
	if _perrine_road(road_id) and kind != "bridge":
		_close_span(surfs, l0, r0, l1, r1, grid, origin, n, spacing, faces, kind, t0 >= 0.0, t1 <= 1.0)
	if GUARD_ROADS.has(road_id):
		var rim := road_id == "rim_road_south"
		_guard_edge(surfs["guard"], l0, l1, r0, grid, origin, n, spacing, faces, rim)
		_guard_edge(surfs["guard"], r0, r1, l0, grid, origin, n, spacing, faces, rim)


func _paint_lines(road_id: String, surfs: Dictionary, l0: Vector3, r0: Vector3, l1: Vector3, r1: Vector3, half: float, lanes: int, c0: float, c1: float) -> void:
	var a := l0.lerp(r0, 0.5)
	var b := l1.lerp(r1, 0.5)
	var keep := _open_spans(road_id, a, b)
	for win in keep:
		var u0 := float(win.x)
		var u1 := float(win.y)
		if u1 - u0 < 0.04:
			continue
		var ll0 := l0.lerp(l1, u0)
		var ll1 := l0.lerp(l1, u1)
		var rr0 := r0.lerp(r1, u0)
		var rr1 := r0.lerp(r1, u1)
		var ca := lerpf(c0, c1, u0)
		var cb := lerpf(c0, c1, u1)
		if lanes >= 2:
			_line(surfs["yellow"], ll0, rr0, ll1, rr1, half, 0.0, LINE_W, 0.01, ca, cb, false)
		_line(surfs["white"], ll0, rr0, ll1, rr1, half, -(half - 0.22), LINE_W, 0.01, ca, cb, false)
		_line(surfs["white"], ll0, rr0, ll1, rr1, half, half - 0.22, LINE_W, 0.01, ca, cb, false)
		if lanes > 2:
			var lane_w := half * 2.0 / float(lanes)
			var k := 1
			while float(k) * lane_w < half - 0.45:
				_line(surfs["white"], ll0, rr0, ll1, rr1, half, float(k) * lane_w, LINE_W, 0.01, ca, cb, true)
				_line(surfs["white"], ll0, rr0, ll1, rr1, half, -float(k) * lane_w, LINE_W, 0.01, ca, cb, true)
				k += 1


func _perrine_road(road_id: String) -> bool:
	return road_id == "us93_south_approach" or road_id == "us93_north" or road_id == "us93_perrine_bridge"


## Solid volume under a floating approach. Deck spans and anything more than 6 m
## up are bridge structure. Shorter lifts stay earth, with collision either way.
func _close_span(surfs: Dictionary, l0: Vector3, r0: Vector3, l1: Vector3, r1: Vector3, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, faces: PackedVector3Array, kind: String, cap0: bool = true, cap1: bool = true) -> void:
	if n < 2:
		return
	var tops: Array[Vector3] = [l0, r0, r1, l1]
	var bots: Array[Vector3] = []
	var gap := 0.0
	for p in tops:
		var g := _ground(grid, origin, n, spacing, p.x, p.z)
		if g < -70.0:
			return
		gap = maxf(gap, p.y - g)
		bots.append(Vector3(p.x, minf(g, p.y - 0.2), p.z))
	if gap < 0.35:
		return
	var bl0: Vector3 = bots[0]
	var br0: Vector3 = bots[1]
	var br1: Vector3 = bots[2]
	var bl1: Vector3 = bots[3]
	_solid_both(faces, bl0, br0, br1, bl1)
	_solid_both(faces, l0, l1, bl1, bl0)
	_solid_both(faces, r1, r0, br0, br1)
	# End caps stop 12 cm under the ribbon. The cone base is 2.8 cm tall, and a
	# cap flush with the deck edge still catches its front face.
	if cap0:
		var c0l := l0
		var c0r := r0
		c0l.y -= 0.12
		c0r.y -= 0.12
		_solid_both(faces, c0l, bl0, br0, c0r)
	if cap1:
		var c1l := l1
		var c1r := r1
		c1l.y -= 0.12
		c1r.y -= 0.12
		_solid_both(faces, c1l, c1r, br1, bl1)
	if kind == "deck" or gap > 6.0:
		var panel: _Surf = surfs["panel"]
		_earth_quad(panel, l0, l1, bl1, bl0)
		_earth_quad(panel, r1, r0, br0, br1)
		_earth_quad(panel, l0, bl0, br0, r0)
		_earth_quad(panel, l1, r1, br1, bl1)


func _skirts(surf: _Surf, l0: Vector3, r0: Vector3, l1: Vector3, r1: Vector3, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	if n < 2:
		return
	_skirt_side(surf, l0, l1, r0, grid, origin, n, spacing)
	_skirt_side(surf, r0, r1, l0, grid, origin, n, spacing)


## 2:1 embankment from the road edge down to the heightfield. No collision, so a
## centreline ray still lands on the carriageway. The top starts just outside the edge.
func _skirt_side(surf: _Surf, a: Vector3, b: Vector3, other: Vector3, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	var outward := Vector3(a.x - other.x, 0.0, a.z - other.z)
	if outward.length_squared() < 0.01:
		return
	outward = outward.normalized()
	var toe_a := _fill_toe(a, outward, grid, origin, n, spacing)
	var toe_b := _fill_toe(b, outward, grid, origin, n, spacing)
	if toe_a.x < 0.4 and toe_b.x < 0.4:
		return
	var da := maxf(toe_a.x, 0.4)
	var db := maxf(toe_b.x, 0.4)
	var top_a := a + outward * 0.2
	var top_b := b + outward * 0.2
	var bot_a := Vector3(a.x, minf(toe_a.y, a.y), a.z) + outward * da
	var bot_b := Vector3(b.x, minf(toe_b.y, b.y), b.z) + outward * db
	if toe_a.x < 0.4:
		bot_a.y = top_a.y
	if toe_b.x < 0.4:
		bot_b.y = top_b.y
	_earth_quad(surf, top_a, top_b, bot_b, bot_a)


## How far out the 2:1 slope meets the ground. x is the run, y is the ground height.
func _fill_toe(edge: Vector3, outward: Vector3, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> Vector2:
	var g0 := _ground(grid, origin, n, spacing, edge.x, edge.z)
	if g0 < -70.0 or g0 >= edge.y - 0.2:
		return Vector2(0.0, g0)
	var dist := 1.0
	var prev_d := 0.0
	var prev_g := g0
	while dist <= EARTH_REACH_M:
		var g := _ground(grid, origin, n, spacing, edge.x + outward.x * dist, edge.z + outward.z * dist)
		var slope_y := edge.y - dist / FILL_H_PER_V
		if g < -70.0:
			return Vector2(dist, slope_y)
		if g >= slope_y:
			var slope_prev := edge.y - prev_d / FILL_H_PER_V
			var gy := g - prev_g
			var sy := slope_y - slope_prev
			var den := gy - sy
			var u := 1.0 if absf(den) < 0.0001 else clampf((slope_prev - prev_g) / den, 0.0, 1.0)
			var meet := lerpf(prev_d, dist, u)
			return Vector2(meet, _ground(grid, origin, n, spacing, edge.x + outward.x * meet, edge.z + outward.z * meet))
		prev_d = dist
		prev_g = g
		dist += 2.0
	return Vector2(EARTH_REACH_M, edge.y - EARTH_REACH_M / FILL_H_PER_V)


func _rails(surf: _Surf, l0: Vector3, r0: Vector3, r1: Vector3, l1: Vector3, c0: float, c1: float) -> void:
	var across := Vector3(r0.x - l0.x, 0.0, r0.z - l0.z)
	if across.length_squared() < 0.01:
		return
	var side := across.normalized()
	var mid0 := l0.lerp(r0, 0.5)
	var mid1 := l1.lerp(r1, 0.5)
	for off_v in [_gauge_half, -_gauge_half]:
		var shift := side * float(off_v)
		var hw := side * 0.06
		var a := mid0 + shift
		var b := mid1 + shift
		a.y += _rail_lift(mid0)
		b.y += _rail_lift(mid1)
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


func _emit_junctions(coord: Vector2i, surf: _Surf, faces: PackedVector3Array, _grid: PackedFloat32Array, _n: int, _spacing: float) -> void:
	for item in _junctions:
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		# The Perrine joints are collinear. A flat disc at deck height sits on
		# the 5% approach and leaves a lip the cone cannot climb.
		if _bridge_joint(item):
			continue
		var at := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		if WorldConfig.chunk_of(at.x, at.z) != coord:
			continue
		var radius := float(item.get("radius", 8.0))
		var centre_y := float(item.get("flat_y", at.y)) + _joint_lift(item)
		# One flat disc. Every ring sits on the major-road height so a terrain
		# triangle cannot show in the corner and the two roads share a plane.
		var rings := maxi(int(ceil(radius / 2.0)), 1)
		var sides := maxi(int(ceil(TAU * radius / 2.0)), 12)
		var prev := PackedVector3Array()
		prev.append(WorldConfig.to_local(Vector3(at.x, centre_y, at.z)))
		for ring in rings:
			var rad := radius * float(ring + 1) / float(rings)
			var ring_pts := PackedVector3Array()
			for s in sides:
				var ang := float(s) / float(sides) * TAU
				ring_pts.append(WorldConfig.to_local(Vector3(at.x + cos(ang) * rad, centre_y, at.z + sin(ang) * rad)))
			for s in sides:
				var nxt := (s + 1) % sides
				if prev.size() == 1:
					_tri(surf, prev[0], ring_pts[s], ring_pts[nxt], faces)
				else:
					_tri(surf, prev[s], ring_pts[s], ring_pts[nxt], faces)
					_tri(surf, prev[s], ring_pts[nxt], prev[nxt], faces)
			prev = ring_pts


func _emit_crossings(coord: Vector2i, surf: _Surf, faces: PackedVector3Array) -> void:
	for item in _crossings:
		var at := Vector3(float(item["x"]), float(item["y"]), float(item["z"]))
		if WorldConfig.chunk_of(at.x, at.z) != coord:
			continue
		var dir: Vector3 = item["dir"]
		var side := Vector3(-dir.z, 0.0, dir.x)
		var along := float(item["along"])
		var half := float(item["half"]) + 0.35
		var y := at.y + 0.02
		var c := Vector3(at.x, y, at.z)
		var a := c - dir * along - side * half
		var b := c - dir * along + side * half
		var d := c + dir * along + side * half
		var e := c + dir * along - side * half
		_quad(surf, a, b, d, e, 0.0, along * 2.0, 0.0, half * 2.0, true, faces)


func _open_spans(road_id: String, a: Vector3, b: Vector3) -> Array:
	var keep: Array = [Vector2(0.0, 1.0)]
	for item in _junctions:
		var ids: Array = item.get("roads", [])
		if not ids.has(road_id):
			continue
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var hit := _circle_t(a, b, Vector3(float(pos[0]), 0.0, float(pos[2])), float(item.get("radius", 8.0)))
		if hit.x < hit.y:
			keep = _subtract_interval(keep, hit.x, hit.y)
	for item in _crossings:
		if str(item["road"]) != road_id:
			continue
		var hit2 := _panel_t(a, b, item)
		if hit2.x < hit2.y:
			keep = _subtract_interval(keep, hit2.x, hit2.y)
	return keep


func _subtract_interval(keep: Array, t0: float, t1: float) -> Array:
	if t1 < t0:
		var swap := t0
		t0 = t1
		t1 = swap
	var out: Array = []
	for item in keep:
		var span: Vector2 = item
		if t1 <= span.x or t0 >= span.y:
			out.append(span)
			continue
		if t0 > span.x + 0.001:
			out.append(Vector2(span.x, t0))
		if t1 < span.y - 0.001:
			out.append(Vector2(t1, span.y))
	return out


func _circle_t(a: Vector3, b: Vector3, c: Vector3, radius: float) -> Vector2:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var w := Vector2(a.x - c.x, a.z - c.z)
	var aa := d.length_squared()
	var bb := 2.0 * w.dot(d)
	var cc := w.length_squared() - radius * radius
	if aa < 0.0001:
		if cc <= 0.0:
			return Vector2(0.0, 1.0)
		return Vector2(1.0, 0.0)
	var disc := bb * bb - 4.0 * aa * cc
	if disc < 0.0:
		return Vector2(1.0, 0.0)
	var s := sqrt(disc)
	var t0 := clampf((-bb - s) / (2.0 * aa), 0.0, 1.0)
	var t1 := clampf((-bb + s) / (2.0 * aa), 0.0, 1.0)
	if t1 <= t0 + 0.0001:
		return Vector2(1.0, 0.0)
	return Vector2(t0, t1)


func _panel_t(a: Vector3, b: Vector3, item: Dictionary) -> Vector2:
	var dir: Vector3 = item["dir"]
	var cx := float(item["x"])
	var cz := float(item["z"])
	var along := float(item["along"])
	var half := float(item["half"]) + 1.0
	var la := absf((a.x - cx) * (-dir.z) + (a.z - cz) * dir.x)
	var lb := absf((b.x - cx) * (-dir.z) + (b.z - cz) * dir.x)
	if la > half and lb > half:
		return Vector2(1.0, 0.0)
	var da := (a.x - cx) * dir.x + (a.z - cz) * dir.z
	var db := (b.x - cx) * dir.x + (b.z - cz) * dir.z
	if absf(db - da) < 0.001:
		if absf(da) <= along:
			return Vector2(0.0, 1.0)
		return Vector2(1.0, 0.0)
	var inv := 1.0 / (db - da)
	var t_hi := (along - da) * inv
	var t_lo := (-along - da) * inv
	var t0 := clampf(minf(t_hi, t_lo), 0.0, 1.0)
	var t1 := clampf(maxf(t_hi, t_lo), 0.0, 1.0)
	if t1 <= t0 + 0.0001:
		return Vector2(1.0, 0.0)
	return Vector2(t0, t1)


func _rail_on_panel(p: Vector3) -> bool:
	for item in _crossings:
		var d := Vector2(p.x - float(item["x"]), p.z - float(item["z"])).length()
		if d <= maxf(float(item["half"]), float(item["along"])) + 0.6:
			return true
	return false


func _rail_lift(p: Vector3) -> float:
	var lift := 0.18
	for item in _crossings:
		var d := Vector2(p.x - float(item["x"]), p.z - float(item["z"])).length()
		var flush_r := maxf(float(item["half"]), float(item["along"])) + 0.4
		var flush := float(item["y"]) - p.y + 0.012
		if d <= flush_r:
			return flush
		if d < flush_r + 5.0:
			lift = minf(lift, lerpf(flush, 0.18, (d - flush_r) / 5.0))
	return lift


func _earth_quad(surf: _Surf, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n := (b - a).cross(d - a)
	if n.length_squared() < 0.000001:
		return
	if n.y < 0.0:
		n = -n
	# Bias toward the sky so a 2:1 face does not shade as a black wall.
	n = (n.normalized() + Vector3(0.0, 1.15, 0.0)).normalized()
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
	shape.margin = 0.0
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
	# water height and the deck lands on 142.76. File yaw +1.7 aims local +Z at
	# the south road end. A centreline ray hits the median, so flush checks use a lane.
	if str(mark["id"]) == "centennial_park_ramp":
		# v2 pivot is the top edge. Local -Z runs downhill into the river.
		at = RAMP_TOP
		yaw_deg = 0.0
	var fp: Vector2 = mark.get("fp", Vector2(4.0, 4.0))
	_finish_mark(host, inst, at, yaw_deg, fp, bool(mark.get("seat", false)))
	if str(mark["id"]) == "perrine_bridge":
		_apply_named_slots(inst, BRIDGE_SLOTS)
		_bridge_extras(inst, host)
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
	# Imported -colonly nodes already have CollisionShape3D, but they do not
	# cover every visual mesh (v4 bridge abutments, piers, arch, rails).
	if root.get_node_or_null("LandmarkBody") != null:
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
		# Skip -colonly leftovers; the importer already made StaticBody3D nodes.
		# bridge_rail has an end plate across the lanes, 2 cm above the deck.
		# The side boxes below are the rail collision, so that plate is not used.
		var mesh_name := str(mi.name)
		if mi.mesh != null and not mesh_name.contains("col") and mesh_name != "bridge_rail":
			var shape := mi.mesh.create_trimesh_shape()
			if shape != null:
				var col := CollisionShape3D.new()
				col.name = str(mi.name)
				col.shape = shape
				col.transform = _mesh_xf(root, mi)
				body.add_child(col)
	for child in node.get_children():
		if child == body:
			continue
		_collect_meshes(root, child, body)


## v4 colonly rails stop at 1.07 m. A 1.1 m box on each deck edge keeps a
## cone from sliding off the 148 m lane. Thin steel arch springs get a
## solid box so a cone cannot walk through the piers.
func _bridge_extras(root: Node3D, host: Node3D) -> void:
	var body := root.get_node_or_null("LandmarkBody") as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = "LandmarkBody"
		body.collision_layer = 1
		body.collision_mask = 0
		root.add_child(body)
	for side in [-1.0, 1.0]:
		var box := BoxShape3D.new()
		box.size = Vector3(0.40, 1.12, 457.0)
		var col := CollisionShape3D.new()
		col.name = "Rail_%s" % ("W" if side < 0.0 else "E")
		col.shape = box
		col.position = Vector3(side * 9.65, 148.56, 0.0)
		body.add_child(col)
	for sz in [-151.8, 151.8]:
		for sx in [-7.9, 7.9]:
			var pier := BoxShape3D.new()
			pier.size = Vector3(1.6, 8.0, 2.6)
			var col := CollisionShape3D.new()
			col.name = "Pier"
			col.shape = pier
			col.position = Vector3(sx, 63.6, sz)
			body.add_child(col)
	# Arch shells are open cards. A box chain along each lower chord is solid.
	var arch := PackedVector3Array([
		Vector3(0.0, 59.6, -151.0),
		Vector3(0.0, 84.0, -125.0),
		Vector3(0.0, 112.3, -90.0),
		Vector3(0.0, 125.6, -60.0),
		Vector3(0.0, 137.2, -30.0),
		Vector3(0.0, 139.4, 0.0),
		Vector3(0.0, 137.2, 30.0),
		Vector3(0.0, 125.6, 60.0),
		Vector3(0.0, 112.3, 90.0),
		Vector3(0.0, 84.0, 125.0),
		Vector3(0.0, 59.6, 151.0),
	])
	for side in [-8.15, 8.15]:
		for i in arch.size() - 1:
			var a := arch[i]
			var b := arch[i + 1]
			a.x = side
			b.x = side
			_solid_beam(body, a, b, 1.5)
	# Concrete shells stop at local y 134 and float off the wall. The base
	# follows the low side of the footprint so neither edge hangs in the air.
	for ez in [-228.5, 228.5]:
		var min_g := 1.0e9
		var hits := 0
		for ox in [-9.6, -4.8, 0.0, 4.8, 9.6]:
			for oz in [-4.8, 0.0, 4.8]:
				var world_p := root.to_global(Vector3(ox, 134.2, ez + oz))
				var h := _terrain_at(host, world_p.x, world_p.z)
				if h < -70.0:
					continue
				hits += 1
				min_g = minf(min_g, h)
		var foot_y := 126.0
		if hits > 0:
			var probe := root.to_global(Vector3(0.0, 134.2, ez))
			var local_g := root.to_local(Vector3(probe.x, min_g, probe.z))
			foot_y = minf(local_g.y - 1.5, 132.0)
		var height := 134.2 - foot_y
		if height < 0.4:
			continue
		var size := Vector3(19.7, height, 10.0)
		var centre := Vector3(0.0, (134.2 + foot_y) * 0.5, ez)
		var foot := BoxShape3D.new()
		foot.size = size
		var pad := CollisionShape3D.new()
		pad.name = "NorthAbutment" if ez < 0.0 else "SouthAbutment"
		pad.shape = foot
		pad.position = centre
		body.add_child(pad)
		var mesh := BoxMesh.new()
		mesh.size = size
		var mi := MeshInstance3D.new()
		mi.name = pad.name
		mi.mesh = mesh
		mi.position = centre
		var mat := load("res://materials/twin_falls/bridge_deck_concrete.tres") as Material
		if mat != null:
			mi.material_override = mat
		root.add_child(mi)
	# South pier boxes (local z -151.8, 1.6 x 2.6) and the steel shoes bottom
	# near local y 59.6. A 0.5 m foot left most of that footprint in the air.
	# The column covers the box and the inboard steel, and stops 5 cm outside
	# it. North piers stay the short boxes above. Chord shoes share that z band
	# but stop short of the pier ray at local z -151.8, so each foot ray meets
	# its own column.
	_ground_rect(root, body, host, -7.725, -151.8, 59.90, 2.05, 2.70, "WestPierFoot")
	_ground_rect(root, body, host, 7.725, -151.8, 59.90, 2.05, 2.70, "EastPierFoot")
	_ground_rect(root, body, host, -8.175, -151.0, 59.90, 1.65, 1.20, "WestChordFoot")
	# West face stays east of the foot ray's start (local x 6.85) so the ray
	# meets the face instead of beginning inside the column.
	_ground_rect(root, body, host, 8.075, -151.0, 59.90, 1.95, 1.20, "EastChordFoot")
	_ground_column(root, body, host, Vector3(3351.10, 54.6, -6956.60), 1.35, 0.16, "WestSole")
	_ground_column(root, body, host, Vector3(3367.15, 54.6, -6957.08), 1.35, 0.16, "EastSole")
	_sink_rail_plates(root)
	_bury_deck_lips(root)


## Bridge-local column down to the lowest of 25 samples on its footprint.
## Top y is local. The bottom is buried a metre so the uphill edge stays shut.
func _ground_rect(root: Node3D, body: StaticBody3D, host: Node, cx: float, cz: float, top_y: float, size_x: float, size_z: float, node_name: String) -> void:
	var ground := 1.0e9
	var hits := 0
	var hx := size_x * 0.5
	var hz := size_z * 0.5
	for ix in 5:
		for iz in 5:
			var lx := cx + lerpf(-hx, hx, float(ix) / 4.0)
			var lz := cz + lerpf(-hz, hz, float(iz) / 4.0)
			var w := root.to_global(Vector3(lx, top_y, lz))
			var h := _terrain_at(host, w.x, w.z)
			if h < -70.0:
				continue
			hits += 1
			ground = minf(ground, h)
	if hits == 0:
		return
	var top_w := root.to_global(Vector3(cx, top_y, cz))
	if ground > top_w.y - 0.4:
		return
	var bot_l := root.to_local(Vector3(top_w.x, ground - 1.0, top_w.z))
	var height := top_y - bot_l.y
	if height < 0.4:
		return
	var box := BoxShape3D.new()
	box.size = Vector3(size_x, height, size_z)
	var col := CollisionShape3D.new()
	col.name = node_name
	col.shape = box
	col.position = Vector3(cx, (top_y + bot_l.y) * 0.5, cz)
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = box.size
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = col.position
	var mat := load("res://materials/twin_falls/bridge_deck_concrete.tres") as Material
	if mat != null:
		mi.material_override = mat
	root.add_child(mi)


## Column from a world point down into the terrain. Used where a pier or chord
## ends in the air. Size is in bridge-local metres.
func _ground_column(root: Node3D, body: StaticBody3D, host: Node, top_world: Vector3, size_x: float, size_z: float, node_name: String) -> void:
	var ground := 1.0e9
	var hits := 0
	var hx := size_x * 0.5
	var hz := size_z * 0.5
	for ox in [-hx, 0.0, hx]:
		for oz in [-hz, 0.0, hz]:
			var h := _terrain_at(host, top_world.x + ox, top_world.z + oz)
			if h < -70.0:
				continue
			hits += 1
			ground = minf(ground, h)
	if hits == 0 or ground > top_world.y - 0.4:
		return
	# Lowest sample under the footprint, buried a metre, so the uphill edge
	# is not a gap under the sole.
	var bot_world := Vector3(top_world.x, ground - 1.0, top_world.z)
	var top_l := root.to_local(top_world)
	var bot_l := root.to_local(bot_world)
	var height := top_l.y - bot_l.y
	if height < 0.4:
		return
	var box := BoxShape3D.new()
	box.size = Vector3(size_x, height, size_z)
	var col := CollisionShape3D.new()
	col.name = node_name
	col.shape = box
	col.position = (top_l + bot_l) * 0.5
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = box.size
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = col.position
	var mat := load("res://materials/twin_falls/bridge_deck_concrete.tres") as Material
	if mat != null:
		mi.material_override = mat
	root.add_child(mi)


## The rail mesh carries five plates across the lanes at local y 148.02, 2 cm
## above the deck. Drop those verts under the road. The side rails stay.
func _sink_rail_plates(root: Node3D) -> void:
	var mi := root.find_child("bridge_rail", true, false) as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	var src := mi.mesh
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var changed := false
	for i in verts.size():
		var p := verts[i]
		if p.y < 148.25:
			p.y = 147.90
			verts[i] = p
			changed = true
	if not changed:
		return
	arrays[Mesh.ARRAY_VERTEX] = verts
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := src.surface_get_material(0)
	if mat != null:
		out.surface_set_material(0, mat)
	mi.mesh = out


## Deck-end walls and a second copy of the deck slab sit on the driving line.
## The slab drops a few centimetres so the road body is the surface a cone
## rides. A wall across the lanes stops 14 cm under that surface.
func _bury_deck_lips(root: Node3D) -> void:
	var cols: Array[CollisionShape3D] = []
	_gather_cols(root, cols)
	for col in cols:
		if col.shape == null:
			continue
		col.shape.margin = 0.0
		if not (col.shape is ConcavePolygonShape3D):
			continue
		var src := col.shape as ConcavePolygonShape3D
		var data := src.data
		if data.size() < 3:
			continue
		var to_root := root.global_transform.affine_inverse() * col.global_transform
		var back := to_root.affine_inverse()
		var changed := false
		var i := 0
		while i + 2 < data.size():
			var a := to_root * data[i]
			var b := to_root * data[i + 1]
			var c := to_root * data[i + 2]
			var min_x := minf(a.x, minf(b.x, c.x))
			var max_x := maxf(a.x, maxf(b.x, c.x))
			var min_y := minf(a.y, minf(b.y, c.y))
			var max_y := maxf(a.y, maxf(b.y, c.y))
			var min_z := minf(a.z, minf(b.z, c.z))
			var max_z := maxf(a.z, maxf(b.z, c.z))
			var across := max_x - min_x > 4.0
			var end_wall := across and absf(min_z) > 220.0 and absf(max_z) > 220.0 and max_z - min_z < 1.5 and max_y > 147.90
			var deck_top := across and max_z - min_z > 5.0 and max_y - min_y < 0.04 and max_y >= 147.97 and max_y <= 148.03
			var plate := across and max_z - min_z < 1.5 and max_y - min_y < 0.05 and max_y > 148.005 and max_y < 148.25
			if end_wall or plate:
				for k in 3:
					var p := to_root * data[i + k]
					if p.y > 147.86:
						p.y = 147.86
						data[i + k] = back * p
						changed = true
			elif deck_top:
				for k in 3:
					var p2 := to_root * data[i + k]
					p2.y -= 0.06
					data[i + k] = back * p2
				changed = true
			i += 3
		if changed:
			var copy := src.duplicate() as ConcavePolygonShape3D
			copy.data = data
			col.shape = copy


func _gather_cols(node: Node, into: Array[CollisionShape3D]) -> void:
	if node is CollisionShape3D:
		into.append(node as CollisionShape3D)
	for child in node.get_children():
		_gather_cols(child, into)


func _solid_beam(body: StaticBody3D, a: Vector3, b: Vector3, thick: float) -> void:
	var delta := b - a
	var length := delta.length()
	if length < 0.2:
		return
	var zaxis := delta / length
	var xaxis := zaxis.cross(Vector3.UP)
	if xaxis.length_squared() < 0.01:
		xaxis = Vector3.RIGHT
	xaxis = xaxis.normalized()
	var yaxis := xaxis.cross(zaxis).normalized()
	var box := BoxShape3D.new()
	box.size = Vector3(thick, thick, length)
	var col := CollisionShape3D.new()
	col.name = "Steel"
	col.shape = box
	col.transform = Transform3D(Basis(xaxis, yaxis, zaxis), (a + b) * 0.5)
	body.add_child(col)


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
	# Same dry-ground tile as the terrain shader (world triplanar, 4 m repeat).
	var earth := _textured("res://materials/twin_falls_terrain/textures/dry_ground_01_albedo_2k.jpg", "", 0.94)
	earth.uv1_triplanar = true
	earth.uv1_world_triplanar = true
	earth.uv1_scale = Vector3(0.25, 0.25, 0.25)
	earth.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["earth"] = earth
	var panel := _textured("res://materials/twin_falls/hero/concrete_wall_008_albedo_2k.jpg", "", 0.72)
	panel.uv1_triplanar = true
	panel.uv1_world_triplanar = true
	panel.uv1_scale = Vector3(0.35, 0.35, 0.35)
	panel.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["panel"] = panel


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
	for item in _junctions:
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var jx := float(pos[0])
		var jz := float(pos[2])
		var rad := float(item.get("radius", 8.0))
		var road_y := float(item.get("flat_y", float(pos[1]))) - CUT_CLEAR_M
		var flat_r := rad + SHOULDER_M
		var reach := flat_r + EARTH_REACH_M
		if jx < origin.x - reach or jx > origin.x + 500.0 + reach:
			continue
		if jz < origin.y - reach or jz > origin.y + 500.0 + reach:
			continue
		var c0 := clampi(int(floor((jx - reach - origin.x) / spacing)), 0, n - 1)
		var c1 := clampi(int(ceil((jx + reach - origin.x) / spacing)), 0, n - 1)
		var r0 := clampi(int(floor((jz - reach - origin.y) / spacing)), 0, n - 1)
		var r1 := clampi(int(ceil((jz + reach - origin.y) / spacing)), 0, n - 1)
		for r in range(r0, r1 + 1):
			var z := origin.y + float(r) * spacing
			var row := r * n
			for c in range(c0, c1 + 1):
				var x := origin.x + float(c) * spacing
				var dist := Vector2(x - jx, z - jz).length()
				if dist > reach:
					continue
				var target := road_y if dist <= flat_r else road_y + (dist - flat_r) / CUT_H_PER_V
				var idx := row + c
				if grid[idx] > target:
					grid[idx] = target


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
func _bridge_joint(item: Dictionary) -> bool:
	for id in item.get("roads", []):
		if str(id) == "us93_perrine_bridge":
			return true
	return false


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
