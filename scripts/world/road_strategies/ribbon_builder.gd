extends TfRoadBuilder

## Strategy 2 geometry. prepare() still solves the shared profile: grade cap,
## best-fit junction plane (tilt clamped to 2%, 3% on a grade of at least 6%),
## 30 m taper, crown and superelevation. This file only replaces the stamp and
## the mesh.
##
## Stamp: every heightfield sample whose cell touches the road, shoulder and
## verge is set from the road surface. Under the footprint the sample is
## min(road y) - 0.10 m, so the coarse grid cannot poke through. Outside that,
## a 1:2 verge, then the spec cut (soil 2:1, rock 0.25:1 with benches) or a
## short fill. The fill stops inside the 3 m edge probe so a canyon or a rim
## stays at its own height. A 4 m cosine blend ties the edit back to the ground.
##
## Mesh: a ribbon, 2 m along and at most 1 m across, crowned to match _section,
## flat across the shoulder and ditch, then a verge at 1:2 for at most 3 m.
## No vertical faces in that collision. A span that clears another road by
## 2 m or more is marked deck: the stamp skips it, the same way a bridge does.
## Ribbons that cross at a crest with less clearance still overlap.

const MASK_M := 0.10
const SEAT_M := 0.02
const VERGE_M := 3.0
const RIBBON_FLARE := 0.50
const RIBBON_ALONG := 2.0
const PROBE_M := 3.0
const BLEND_OUT_M := 4.0
const FILL_CAP_M := 2.50
const SPAN_CLEAR_M := 2.0
const CROWN_CLAMP_M := 0.15
const PLANE_FADE_M := 2.0

var _barriers: Array = []
var _barrier_seen := {}


func prepare() -> void:
	super.prepare()
	_mark_spans()
	_rebuild_edges()
	_barriers.clear()
	_barrier_seen.clear()


func apply_cuts(grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	_stamp(grid, origin, n, spacing, false)


func apply_paint(grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	_stamp(grid, origin, n, spacing, true)


func clamp_footprint(drawn: PackedFloat32Array, cut: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	if n < 2 or drawn.size() != n * n or cut.size() != n * n or _edges.is_empty():
		return
	var reach := _reach_pad(spacing)
	for ei in _edge_ids(origin, reach):
		var edge: Dictionary = _edges[int(ei)]
		if bool(edge.get("skip", false)):
			continue
		_clamp_edge(drawn, cut, origin, n, spacing, edge)


func build_chunk(coord: Vector2i, _grid: PackedFloat32Array, _n: int, _spacing: float) -> Dictionary:
	var rect := WorldConfig.chunk_rect(coord)
	var asphalt := _Surf.new()
	var earth := _Surf.new()
	var faces := PackedVector3Array()
	for road in _roads:
		if bool(road.get("rail", false)):
			continue
		_emit_ribbon(road, rect, asphalt, earth, faces)
	_emit_discs(coord, asphalt, faces)
	faces = _keep_climbable(faces)
	var surfaces: Array = []
	if not asphalt.idx.is_empty():
		surfaces.append({"mat": "asphalt", "v": asphalt.v, "n": asphalt.nrm, "uv": asphalt.uv, "i": asphalt.idx})
	if not earth.idx.is_empty():
		surfaces.append({"mat": "earth", "v": earth.v, "n": earth.nrm, "uv": earth.uv, "i": earth.idx})
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
	if surfaces.is_empty() and faces.is_empty() and signs.is_empty() and marks.is_empty() and plates.is_empty():
		return {}
	return {"surfaces": surfaces, "faces": faces, "signs": signs, "marks": marks, "plates": plates}


func _job_body(host: Node3D, faces: PackedVector3Array) -> void:
	super._job_body(host, faces)
	if host.get_node_or_null("JunctionFeatures") != null:
		return
	var coord := _host_coord(host)
	var root := Node3D.new()
	root.name = "JunctionFeatures"
	var any := false
	for item in _junctions:
		if not _feature_in_chunk(item, coord):
			continue
		if _add_junction_features(root, item):
			any = true
	if any:
		host.add_child(root)
	_add_barrier_body(host)


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
		var rail := bool(road["rail"])
		var rid := str(road["id"])
		var rh := float(road["half"])
		for i in pts.size():
			if i >= left.size() or i >= right.size():
				break
			var lp := left[i]
			var rp := right[i]
			lp.y = pts[i].y
			rp.y = pts[i].y
			left[i] = lp
			right[i] = rp
		road["left"] = left
		road["right"] = right
		var shoulder := float(road.get("shoulder", 1.2))
		var ditch := float(road.get("ditch", 1.0))
		var cls := str(road.get("class", ""))
		var rock_cls := cls == "grade" or cls == "rim_local"
		var approach := _approach_road(rid)
		for i in pts.size() - 1:
			var kind := kinds[i] if i < kinds.size() else "grade"
			var ha := _half_at(road, i)
			var hb := _half_at(road, i + 1)
			var edge := {
				"ax": pts[i].x, "ay": pts[i].y, "az": pts[i].z,
				"bx": pts[i + 1].x, "by": pts[i + 1].y, "bz": pts[i + 1].z,
				"half": maxf(ha, hb),
				"ha": ha,
				"hb": hb,
				"rh": rh,
				"kind": kind,
				"ba": bank[i] if i < bank.size() else 0.0,
				"bb": bank[i + 1] if i + 1 < bank.size() else 0.0,
				"ca": crown[i] if i < crown.size() else 0.0,
				"cb": crown[i + 1] if i + 1 < crown.size() else 0.0,
				"rail": rail,
				"sh": shoulder,
				"ditch": ditch,
				"road": rid,
				"skip": rail or kind == "bridge" or (kind == "deck" and not approach),
				"rock": rock_cls,
			}
			var ei := _edges.size()
			_edges.append(edge)
			_bucket_edge(ei, edge)


func _mark_spans() -> void:
	for road in _roads:
		if bool(road.get("rail", false)):
			continue
		var pts: PackedVector3Array = road["pts"]
		var kinds: PackedStringArray = road["kind"]
		var rid := str(road["id"])
		var changed := false
		for i in pts.size() - 1:
			if i < kinds.size() and (kinds[i] == "bridge" or kinds[i] == "deck"):
				continue
			var ab := Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z)
			var dist := ab.length()
			if dist < 0.5:
				continue
			var steps := maxi(int(ceil(dist / 4.0)), 1)
			var span := false
			for s in steps + 1:
				var t := float(s) / float(steps)
				var p := pts[i].lerp(pts[i + 1], t)
				var other := _foreign_y(rid, p)
				if other > 1.0e8:
					continue
				if p.y > other + SPAN_CLEAR_M:
					span = true
					break
			if span and i < kinds.size():
				kinds[i] = "deck"
				changed = true
		if changed:
			road["kind"] = kinds


func _foreign_y(road_id: String, p: Vector3) -> float:
	var best := 1.0e9
	var found := false
	for other in _roads:
		if str(other.get("id", "")) == road_id or bool(other.get("rail", false)):
			continue
		var oid := str(other.get("id", ""))
		var pts: PackedVector3Array = other["pts"]
		var band := float(other.get("half", 3.0)) + float(other.get("shoulder", 0.0)) + float(other.get("ditch", 0.0))
		for i in pts.size() - 1:
			var hit := _seg_side(p.x, p.z, pts[i].x, pts[i].z, pts[i + 1].x, pts[i + 1].z)
			if hit.x > band:
				continue
			if _near_shared_junction(road_id, oid, p):
				continue
			var y := lerpf(pts[i].y, pts[i + 1].y, hit.y)
			if y < best:
				best = y
				found = true
	if not found:
		return 1.0e9
	return best


func _near_shared_junction(id_a: String, id_b: String, p: Vector3) -> bool:
	for item in _junctions:
		var ids: Array = item.get("roads", [])
		if not ids.has(id_a) or not ids.has(id_b):
			continue
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var rad := float(item.get("radius", 8.0)) + 15.0
		if Vector2(p.x - float(pos[0]), p.z - float(pos[2])).length() <= rad:
			return true
	return false


func _stamp(grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, from_dem: bool) -> void:
	if n < 2 or grid.size() != n * n or _edges.is_empty():
		return
	var orig := grid.duplicate()
	var lock := PackedByteArray()
	lock.resize(n * n)
	var best := PackedFloat32Array()
	best.resize(n * n)
	best.fill(1.0e9)
	var reach := _reach_pad(spacing)
	for ei in _edge_ids(origin, reach):
		var edge: Dictionary = _edges[int(ei)]
		if bool(edge.get("skip", false)):
			_stamp_seat(grid, orig, lock, origin, n, spacing, edge, from_dem)
			continue
		_stamp_edge(grid, orig, lock, best, origin, n, spacing, edge, from_dem)


func _stamp_edge(grid: PackedFloat32Array, orig: PackedFloat32Array, lock: PackedByteArray, best: PackedFloat32Array, origin: Vector2, n: int, spacing: float, edge: Dictionary, from_dem: bool) -> void:
	var ax := float(edge["ax"])
	var az := float(edge["az"])
	var bx := float(edge["bx"])
	var bz := float(edge["bz"])
	var paint := maxf(float(edge["ha"]), float(edge["hb"]))
	var sh := float(edge.get("sh", 0.0))
	var ditch := float(edge.get("ditch", 0.0))
	var reach := paint + PROBE_M + BLEND_OUT_M + _cell_pad(spacing)
	var min_x := minf(ax, bx) - reach
	var max_x := maxf(ax, bx) + reach
	var min_z := minf(az, bz) - reach
	var max_z := maxf(az, bz) + reach
	var c0 := clampi(int(floor((min_x - origin.x) / spacing)), 0, n - 1)
	var c1 := clampi(int(ceil((max_x - origin.x) / spacing)), 0, n - 1)
	var r0 := clampi(int(floor((min_z - origin.y) / spacing)), 0, n - 1)
	var r1 := clampi(int(ceil((max_z - origin.y) / spacing)), 0, n - 1)
	var rock := bool(edge.get("rock", false))
	var pad := _cell_pad(spacing)
	var guard := _open_drop(edge, from_dem)
	for r in range(r0, r1 + 1):
		var z := origin.y + float(r) * spacing
		var row := r * n
		for c in range(c0, c1 + 1):
			var x := origin.x + float(c) * spacing
			var hit := _seg_side(x, z, ax, az, bx, bz)
			var half_w := lerpf(float(edge["ha"]), float(edge["hb"]), hit.y)
			var flat_here := half_w + sh + ditch + RIBBON_FLARE
			var probe_here := half_w + PROBE_M
			var reach_here := probe_here + BLEND_OUT_M + pad
			if hit.x > reach_here:
				continue
			var i := row + c
			var ground := _orig_at(orig, i, x, z, from_dem)
			if guard and hit.x >= half_w and hit.x <= half_w + 1.6 and lock[i] != 2:
				var shelf := _design_y_at_dist(edge, hit.y, hit.z, half_w, x, z) - SEAT_M
				grid[i] = shelf
				lock[i] = 3
				continue
			if hit.x <= flat_here + pad:
				var mask := _mask_at(edge, x, z, spacing)
				if lock[i] == 3 and mask >= grid[i]:
					continue
				if lock[i] != 2 or mask < grid[i]:
					grid[i] = mask
					lock[i] = 2
				continue
			if lock[i] == 2 or lock[i] == 3:
				continue
			if hit.x > best[i]:
				continue
			best[i] = hit.x
			# Slope from the masked shoulder, using the vertex for the plane blend.
			var edge_y := _design_y_at_dist(edge, hit.y, hit.z, flat_here, x, z) - MASK_M
			grid[i] = _slope_y(hit.x, flat_here, probe_here, edge_y, ground, rock)
			lock[i] = 1


func _clamp_edge(drawn: PackedFloat32Array, cut: PackedFloat32Array, origin: Vector2, n: int, spacing: float, edge: Dictionary) -> void:
	var ax := float(edge["ax"])
	var az := float(edge["az"])
	var bx := float(edge["bx"])
	var bz := float(edge["bz"])
	var paint := maxf(float(edge["ha"]), float(edge["hb"]))
	var reach := paint + PROBE_M + BLEND_OUT_M + _cell_pad(spacing)
	var c0 := clampi(int(floor((minf(ax, bx) - reach - origin.x) / spacing)), 0, n - 1)
	var c1 := clampi(int(ceil((maxf(ax, bx) + reach - origin.x) / spacing)), 0, n - 1)
	var r0 := clampi(int(floor((minf(az, bz) - reach - origin.y) / spacing)), 0, n - 1)
	var r1 := clampi(int(ceil((maxf(az, bz) + reach - origin.y) / spacing)), 0, n - 1)
	for r in range(r0, r1 + 1):
		var z := origin.y + float(r) * spacing
		var row := r * n
		for c in range(c0, c1 + 1):
			var x := origin.x + float(c) * spacing
			var hit := _seg_side(x, z, ax, az, bx, bz)
			if hit.x > reach:
				continue
			var i := row + c
			if drawn[i] > cut[i]:
				drawn[i] = cut[i]


func _slope_y(dist: float, flat: float, probe: float, mask_y: float, ground: float, rock: bool) -> float:
	var run := maxf(dist - flat, 0.0)
	var at_probe := _slope_raw(maxf(probe - flat, 0.0), mask_y, ground, rock)
	if dist <= probe:
		return _slope_raw(run, mask_y, ground, rock)
	var u := clampf((dist - probe) / BLEND_OUT_M, 0.0, 1.0)
	var w := 0.5 - 0.5 * cos(PI * u)
	return lerpf(at_probe, ground, w)


func _slope_raw(run: float, mask_y: float, ground: float, rock: bool) -> float:
	if ground >= mask_y - 0.02:
		var rise := _cut_rise(run, rock, maxf(ground - mask_y, 0.0))
		return minf(ground, mask_y + rise)
	var fill := mask_y - run * 0.5
	fill = maxf(fill, mask_y - FILL_CAP_M)
	if fill >= ground:
		return fill
	return ground


func _mask_at(edge: Dictionary, x: float, z: float, spacing: float) -> float:
	var y := _design_y(edge, x, z) - MASK_M
	if spacing <= 2.0:
		return y
	var step := spacing * 0.5
	y = minf(y, _design_y(edge, x - step, z) - MASK_M)
	y = minf(y, _design_y(edge, x + step, z) - MASK_M)
	y = minf(y, _design_y(edge, x, z - step) - MASK_M)
	y = minf(y, _design_y(edge, x, z + step) - MASK_M)
	return y


func _design_y(edge: Dictionary, x: float, z: float) -> float:
	var hit := _seg_side(x, z, float(edge["ax"]), float(edge["az"]), float(edge["bx"]), float(edge["bz"]))
	return _design_y_at_dist(edge, hit.y, hit.z, hit.x, x, z)


func _design_y_at_dist(edge: Dictionary, t: float, side: float, dist: float, x: float, z: float) -> float:
	var rh := maxf(float(edge.get("rh", edge.get("half", 3.0))), 0.05)
	var cy := lerpf(float(edge["ay"]), float(edge["by"]), t)
	var bank := lerpf(float(edge.get("ba", 0.0)), float(edge.get("bb", 0.0)), t)
	var drop := lerpf(float(edge.get("ca", 0.0)), float(edge.get("cb", 0.0)), t)
	var kind := str(edge.get("kind", "grade"))
	var elevated := kind == "deck" or kind == "bridge" or bool(edge.get("rail", false))
	if elevated:
		return cy
	var sec := _section(cy, bank, drop, rh)
	var edge_y := sec.x if side > 0.0 else sec.z
	var y := edge_y
	if dist <= rh:
		y = lerpf(sec.y, edge_y, dist / rh)
	return _ribbon_y(str(edge.get("road", "")), x, z, y)


## The parent profile is already on the junction plane inside the disc.
## Only the crown (a few centimetres) is replaced there. A 10 m pull toward the
## absolute plane drags a 10% grade off the samples the harness expects.
func _ribbon_y(road_id: String, x: float, z: float, section_y: float) -> float:
	if road_id == "":
		return section_y
	var item := _junction_at(road_id, Vector3(x, section_y, z))
	if item.is_empty():
		return section_y
	var pos: Array = item.get("pos", [])
	if pos.size() < 3:
		return section_y
	var rad := float(item.get("radius", 8.0))
	var d := Vector2(x - float(pos[0]), z - float(pos[2])).length()
	if d >= rad + PLANE_FADE_M:
		return section_y
	var plane := _plane_at(item, x, z)
	var delta := clampf(plane - section_y, -CROWN_CLAMP_M, CROWN_CLAMP_M)
	if d <= rad:
		return section_y + delta
	var u := (d - rad) / PLANE_FADE_M
	var w := u * u * (3.0 - 2.0 * u)
	return section_y + delta * (1.0 - w)


func _orig_at(orig: PackedFloat32Array, i: int, x: float, z: float, from_dem: bool) -> float:
	if from_dem and _dem.is_valid():
		var y := float(_dem.call(x, z))
		if y > -70.0:
			return y
	return float(orig[i])


func _cell_pad(spacing: float) -> float:
	if spacing > 2.0:
		return spacing
	return 0.20


func _reach_pad(spacing: float) -> float:
	return 24.0 + PROBE_M + BLEND_OUT_M + _cell_pad(spacing)


func _edge_ids(origin: Vector2, reach: float) -> Array:
	var x0 := origin.x - reach
	var z0 := origin.y - reach
	var x1 := origin.x + 500.0 + reach
	var z1 := origin.y + 500.0 + reach
	var bag := {}
	for gz in range(int(floor(z0 / BUCKET)), int(floor(z1 / BUCKET)) + 1):
		for gx in range(int(floor(x0 / BUCKET)), int(floor(x1 / BUCKET)) + 1):
			var packed: PackedInt32Array = _buckets.get(Vector2i(gx, gz), PackedInt32Array())
			for ei in packed:
				bag[ei] = true
	var ids: Array = bag.keys()
	ids.sort()
	return ids


func _emit_ribbon(road: Dictionary, rect: Rect2, asphalt: _Surf, earth: _Surf, faces: PackedVector3Array) -> void:
	var stations := _stations(road)
	if stations.size() < 2:
		return
	var grown := rect.grow(48.0)
	var prev := PackedVector3Array()
	var prev_s := 0.0
	for s in stations:
		var row := _row(road, float(s))
		if row.is_empty():
			prev = PackedVector3Array()
			continue
		if not prev.is_empty() and prev.size() == row.size() and _rows_hit(prev, row, grown):
			_join_rows(prev, row, prev_s, float(s), asphalt, earth, faces)
		prev = row
		prev_s = float(s)


func _stations(road: Dictionary) -> PackedFloat32Array:
	var chain: PackedFloat32Array = road["chain"]
	var out := PackedFloat32Array()
	if chain.size() < 2:
		return out
	var length := float(chain[chain.size() - 1])
	var s := 0.0
	var vi := 1
	out.append(0.0)
	while s < length - 0.02:
		var nxt := minf(s + RIBBON_ALONG, length)
		while vi < chain.size() and float(chain[vi]) <= s + 0.02:
			vi += 1
		if vi < chain.size():
			var cv := float(chain[vi])
			if cv > s + 0.05 and cv < nxt - 0.02:
				nxt = cv
		if nxt <= s + 0.001:
			break
		out.append(nxt)
		s = nxt
	return out


func _row(road: Dictionary, s: float) -> PackedVector3Array:
	var fr := _frame(road, s)
	if fr.is_empty():
		return PackedVector3Array()
	var c: Vector3 = fr["c"]
	var l: Vector3 = fr["l"]
	var r: Vector3 = fr["r"]
	var flat := float(fr["sh"]) + float(fr["ditch"]) + RIBBON_FLARE
	var out := PackedVector3Array()
	# Toe, flat shoulder, paint, centre, paint, flat shoulder, toe.
	# The paint chord is the same left-to-right line the harness samples.
	out.append(_offset(l, fr["out_l"], flat + VERGE_M, VERGE_M * 0.5))
	out.append(_offset(l, fr["out_l"], flat, 0.0))
	out.append(l)
	out.append(c)
	out.append(r)
	out.append(_offset(r, fr["out_r"], flat, 0.0))
	out.append(_offset(r, fr["out_r"], flat + VERGE_M, VERGE_M * 0.5))
	return out


func _offset(paint: Vector3, outward: Vector3, dist: float, drop: float) -> Vector3:
	var p := paint
	if outward.length_squared() > 0.01:
		p = paint + outward * dist
	p.y = paint.y - drop
	return p


func _frame(road: Dictionary, s: float) -> Dictionary:
	var pts: PackedVector3Array = road["pts"]
	var left: PackedVector3Array = road["left"]
	var right: PackedVector3Array = road["right"]
	var chain: PackedFloat32Array = road["chain"]
	var bank: PackedFloat32Array = road["bank"]
	var crown: PackedFloat32Array = road["crown"]
	var kinds: PackedStringArray = road["kind"]
	if pts.size() < 2 or left.size() < pts.size() or right.size() < pts.size():
		return {}
	var i := 0
	while i + 1 < chain.size() and float(chain[i + 1]) < s:
		i += 1
	i = clampi(i, 0, pts.size() - 2)
	var span := maxf(float(chain[i + 1] - chain[i]), 0.001)
	var t := clampf((s - float(chain[i])) / span, 0.0, 1.0)
	var p := pts[i].lerp(pts[i + 1], t)
	var lp := left[i].lerp(left[i + 1], t)
	var rp := right[i].lerp(right[i + 1], t)
	var half := maxf(float(road["half"]), 0.05)
	var b := lerpf(float(bank[i]), float(bank[i + 1]), t)
	var c := lerpf(float(crown[i]), float(crown[i + 1]), t)
	var kind := kinds[i] if i < kinds.size() else "grade"
	if t >= 0.999 and i + 1 < kinds.size():
		var nxt := kinds[i + 1]
		if nxt == "deck" or nxt == "bridge":
			kind = nxt
	var elevated := kind == "deck" or kind == "bridge" or bool(road.get("rail", false))
	var sec := Vector3(p.y, p.y, p.y) if elevated else _section(p.y, b, c, half)
	var rid := str(road["id"])
	var cy := sec.y
	lp.y = sec.x
	rp.y = sec.z
	if not elevated:
		lp.y = _ribbon_y(rid, lp.x, lp.z, lp.y)
		rp.y = _ribbon_y(rid, rp.x, rp.z, rp.y)
		cy = _ribbon_y(rid, p.x, p.z, cy)
	var across := Vector3(rp.x - lp.x, 0.0, rp.z - lp.z)
	var out_l := Vector3.ZERO
	var out_r := Vector3.ZERO
	if across.length_squared() > 0.01:
		var side := across.normalized()
		out_r = side
		out_l = -side
	return {
		"c": Vector3(p.x, cy, p.z),
		"l": lp,
		"r": rp,
		"out_l": out_l,
		"out_r": out_r,
		"sh": float(road.get("shoulder", 0.0)),
		"ditch": float(road.get("ditch", 0.0)),
		"kind": kind,
	}


func _rows_hit(a: PackedVector3Array, b: PackedVector3Array, rect: Rect2) -> bool:
	var min_x := 1.0e9
	var max_x := -1.0e9
	var min_z := 1.0e9
	var max_z := -1.0e9
	for p in a:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	for p in b:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	return max_x >= rect.position.x and min_x <= rect.end.x and max_z >= rect.position.y and min_z <= rect.end.y


func _join_rows(a: PackedVector3Array, b: PackedVector3Array, sa: float, sb: float, asphalt: _Surf, earth: _Surf, faces: PackedVector3Array) -> void:
	var n := a.size()
	for k in n - 1:
		var on_verge := k == 0 or k == n - 2
		var surf := earth if on_verge else asphalt
		_quad(surf, a[k], b[k], b[k + 1], a[k + 1], sa, sb, float(k), float(k + 1), true, faces)


func _host_coord(host: Node) -> Vector2i:
	var parts := str(host.name).split("_")
	if parts.size() >= 3 and parts[0] == "C":
		return Vector2i(int(parts[1]), int(parts[2]))
	return Vector2i(-999999, -999999)


func _feature_in_chunk(item: Dictionary, coord: Vector2i) -> bool:
	var pos: Array = item.get("pos", [])
	if pos.size() < 3:
		return false
	if coord.x < -100000:
		return true
	return WorldConfig.chunk_of(float(pos[0]), float(pos[2])) == coord


func _add_junction_features(root: Node3D, item: Dictionary) -> bool:
	var pos: Array = item.get("pos", [])
	if pos.size() < 3:
		return false
	var cx := float(pos[0])
	var cz := float(pos[2])
	var y := float(item.get("flat_y", pos[1]))
	var arc := MeshInstance3D.new()
	arc.name = _fresh_name(root, "JunctionArc")
	arc.mesh = _arc_mesh(item)
	root.add_child(arc)
	arc.position = Vector3(cx, y + 0.02, cz)
	_add_stop_bars(root, item, y)
	var note := str(item.get("note", "")).to_lower()
	if note.contains("signal"):
		var mast := Node3D.new()
		mast.name = _fresh_name(root, "SignalHead")
		root.add_child(mast)
		mast.position = Vector3(cx + 4.0, y, cz + 4.0)
	return true


func _arc_mesh(item: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var headings := _approach_headings(item)
	if headings.size() < 2:
		return mesh
	headings.sort()
	var rad := _return_of(item)
	var width := 0.45
	for i in headings.size():
		var a: float = headings[i]
		var b: float = headings[(i + 1) % headings.size()]
		var sweep := b - a
		if sweep <= 0.0:
			sweep += TAU
		if sweep < deg_to_rad(25.0) or sweep > deg_to_rad(160.0):
			continue
		var steps := maxi(int(ceil(rad * sweep / 1.5)), 2)
		for s in steps:
			var t0 := a + sweep * float(s) / float(steps)
			var t1 := a + sweep * float(s + 1) / float(steps)
			var i0 := verts.size()
			verts.append(_arc_pt(t0, rad - width * 0.5))
			verts.append(_arc_pt(t0, rad + width * 0.5))
			verts.append(_arc_pt(t1, rad + width * 0.5))
			verts.append(_arc_pt(t1, rad - width * 0.5))
			idx.append(i0)
			idx.append(i0 + 1)
			idx.append(i0 + 2)
			idx.append(i0)
			idx.append(i0 + 2)
			idx.append(i0 + 3)
	if idx.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _arc_pt(ang: float, rad: float) -> Vector3:
	return Vector3(cos(ang) * rad, 0.0, sin(ang) * rad)


func _approach_headings(item: Dictionary) -> PackedFloat32Array:
	var pos: Array = item.get("pos", [])
	var out := PackedFloat32Array()
	if pos.size() < 3:
		return out
	var cx := float(pos[0])
	var cz := float(pos[2])
	for rid in item.get("roads", []):
		if not _by_id.has(str(rid)):
			continue
		var road: Dictionary = _roads[int(_by_id[str(rid)])]
		var pts: PackedVector3Array = road["pts"]
		var best := 1.0e9
		var heading := 0.0
		var found := false
		for p in pts:
			var d := Vector2(p.x - cx, p.z - cz).length()
			if d < 4.0 or d > best:
				continue
			if d > float(item.get("radius", 8.0)) + 30.0:
				continue
			best = d
			heading = atan2(p.z - cz, p.x - cx)
			found = true
		if found:
			out.append(heading)
	return out


func _return_of(item: Dictionary) -> float:
	var rad := RoadRules.RETURN_STREET_M
	for rid in item.get("roads", []):
		if not _by_id.has(str(rid)):
			continue
		var road: Dictionary = _roads[int(_by_id[str(rid)])]
		rad = maxf(rad, _return_m(str(road.get("class", ""))))
	return rad


func _return_m(cls: String) -> float:
	if cls == "us_highway":
		return RoadRules.RETURN_TRUCK_M
	if cls == "urban_arterial" or cls == "arterial" or cls == "highway":
		return RoadRules.RETURN_ARTERIAL_M
	return RoadRules.RETURN_STREET_M


func _add_stop_bars(root: Node3D, item: Dictionary, y: float) -> void:
	var pos: Array = item.get("pos", [])
	if pos.size() < 3:
		return
	var cx := float(pos[0])
	var cz := float(pos[2])
	var majors := 0
	var widest := 0.0
	for rid in item.get("roads", []):
		if not _by_id.has(str(rid)):
			continue
		var half := float(_roads[int(_by_id[str(rid)])].get("half", 0.0))
		if half > widest + 0.2:
			widest = half
			majors = 1
		elif absf(half - widest) <= 0.2:
			majors += 1
	var roads: Array = item.get("roads", [])
	var unique_major: bool = majors == 1 and roads.size() > 1
	for rid in item.get("roads", []):
		if not _by_id.has(str(rid)):
			continue
		var road: Dictionary = _roads[int(_by_id[str(rid)])]
		var half := float(road.get("half", 3.0))
		if unique_major and half >= widest - 0.2:
			continue
		var pts: PackedVector3Array = road["pts"]
		var dir := Vector3.ZERO
		var best := 1.0e9
		for p in pts:
			var d := Vector2(p.x - cx, p.z - cz).length()
			if d < 6.0 or d > 28.0 or d > best:
				continue
			best = d
			dir = Vector3(p.x - cx, 0.0, p.z - cz)
		if dir.length_squared() < 1.0:
			continue
		dir = dir.normalized()
		var at := Vector3(cx, y + 0.03, cz) + dir * maxf(_return_of(item) * 0.5, 5.0)
		at.y = _plane_at(item, at.x, at.z) + 0.03
		var bar := MeshInstance3D.new()
		bar.name = _fresh_name(root, "StopBar")
		bar.position = at
		bar.rotation.y = atan2(dir.x, dir.z)
		bar.mesh = _bar_mesh(maxf(half * 2.0, 3.0))
		root.add_child(bar)


func _bar_mesh(width: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var w := width * 0.5
	var verts := PackedVector3Array([
		Vector3(-w, 0.0, -0.3),
		Vector3(w, 0.0, -0.3),
		Vector3(w, 0.0, 0.3),
		Vector3(-w, 0.0, 0.3),
	])
	var idx := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _fresh_name(root: Node, base: String) -> String:
	if root.get_node_or_null(base) == null:
		return base
	var n := 2
	while root.get_node_or_null("%s%d" % [base, n]) != null:
		n += 1
	return "%s%d" % [base, n]


## True when the ground 0.5–3 m outside the paint stays more than 3 m below the edge.
## Bridges and decks are included: the stamp skips the span, so the canyon remains.
func _open_drop(edge: Dictionary, from_dem: bool) -> bool:
	var key := _barrier_key(edge)
	if _barrier_seen.has(key):
		return true
	var drop := 0.0
	for side in PackedFloat32Array([-1.0, 1.0]):
		for dist in PackedFloat32Array([0.5, 1.5, 3.0]):
			drop = maxf(drop, _edge_clearance(edge, side, dist, from_dem))
	var kind := str(edge.get("kind", ""))
	var need := drop > RoadRules.EDGE_DROP_M or kind == "bridge" or kind == "deck"
	if need:
		_remember_barrier(edge)
	return need


func _edge_clearance(edge: Dictionary, side: float, dist: float, from_dem: bool) -> float:
	var ax := float(edge["ax"])
	var az := float(edge["az"])
	var bx := float(edge["bx"])
	var bz := float(edge["bz"])
	var ab := Vector2(bx - ax, bz - az)
	var span := ab.length()
	if span < 0.05:
		return 0.0
	var across := Vector2(ab.y, -ab.x) / span
	var mid := 0.5
	var half := lerpf(float(edge["ha"]), float(edge["hb"]), mid)
	var px := lerpf(ax, bx, mid) + across.x * side * (half + dist)
	var pz := lerpf(az, bz, mid) + across.y * side * (half + dist)
	var edge_y := _design_y_at_dist(edge, mid, side, half, px, pz)
	var ground := -99.0
	if _dem.is_valid():
		ground = float(_dem.call(px, pz))
	elif from_dem:
		return 0.0
	if ground < -70.0:
		return 0.0
	# The stamp fills at 1:2 up to 2.5 m. Anything deeper is left, and needs a rail.
	var filled := edge_y - MASK_M - minf(dist * 0.5, FILL_CAP_M)
	return edge_y - maxf(ground, filled)


func _remember_barrier(edge: Dictionary) -> void:
	var key := _barrier_key(edge)
	if _barrier_seen.has(key):
		return
	_barrier_seen[key] = true
	_barriers.append(edge)


func _barrier_key(edge: Dictionary) -> String:
	return "%s|%.1f|%.1f|%.1f|%.1f" % [
		str(edge.get("road", "")), float(edge["ax"]), float(edge["az"]), float(edge["bx"]), float(edge["bz"]),
	]


func _stamp_seat(grid: PackedFloat32Array, _orig: PackedFloat32Array, lock: PackedByteArray, origin: Vector2, n: int, spacing: float, edge: Dictionary, from_dem: bool) -> void:
	if not _open_drop(edge, from_dem):
		return
	var ax := float(edge["ax"])
	var az := float(edge["az"])
	var bx := float(edge["bx"])
	var bz := float(edge["bz"])
	var paint := maxf(float(edge["ha"]), float(edge["hb"]))
	var reach := paint + 0.6 + _cell_pad(spacing)
	var c0 := clampi(int(floor((minf(ax, bx) - reach - origin.x) / spacing)), 0, n - 1)
	var c1 := clampi(int(ceil((maxf(ax, bx) + reach - origin.x) / spacing)), 0, n - 1)
	var r0 := clampi(int(floor((minf(az, bz) - reach - origin.y) / spacing)), 0, n - 1)
	var r1 := clampi(int(ceil((maxf(az, bz) + reach - origin.y) / spacing)), 0, n - 1)
	for r in range(r0, r1 + 1):
		var z := origin.y + float(r) * spacing
		var row := r * n
		for c in range(c0, c1 + 1):
			var x := origin.x + float(c) * spacing
			var hit := _seg_side(x, z, ax, az, bx, bz)
			var half_w := lerpf(float(edge["ha"]), float(edge["hb"]), hit.y)
			if hit.x < half_w or hit.x > half_w + 1.6:
				continue
			var i := row + c
			if lock[i] == 2:
				continue
			grid[i] = _design_y_at_dist(edge, hit.y, hit.z, half_w, x, z) - SEAT_M
			lock[i] = 3


func _emit_discs(coord: Vector2i, asphalt: _Surf, faces: PackedVector3Array) -> void:
	for item in _junctions:
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var at := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		if WorldConfig.chunk_of(at.x, at.z) != coord:
			continue
		if not _disc_level(item, at):
			continue
		var radius := float(item.get("radius", 8.0))
		var sides := maxi(int(ceil(TAU * radius / 2.0)), 12)
		var hub := Vector3(at.x, _plane_at(item, at.x, at.z), at.z)
		var ring := PackedVector3Array()
		for s in sides:
			var ang := float(s) / float(sides) * TAU
			var x := at.x + cos(ang) * radius
			var z := at.z + sin(ang) * radius
			ring.append(Vector3(x, _plane_at(item, x, z), z))
		for s in sides:
			_tri(asphalt, hub, ring[s], ring[(s + 1) % sides], faces)


func _disc_level(item: Dictionary, at: Vector3) -> bool:
	var plane := _plane_at(item, at.x, at.z)
	for rid in item.get("roads", []):
		if not _by_id.has(str(rid)):
			continue
		var road: Dictionary = _roads[int(_by_id[str(rid)])]
		var pts: PackedVector3Array = road["pts"]
		for p in pts:
			if Vector2(p.x - at.x, p.z - at.z).length() > float(item.get("radius", 8.0)) + 2.0:
				continue
			if absf(p.y - plane) > 0.40:
				return false
	return true


func _keep_climbable(src: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var i := 0
	while i + 2 < src.size():
		var a := src[i]
		var b := src[i + 1]
		var c := src[i + 2]
		var n := (b - a).cross(c - a)
		if n.length_squared() > 0.0000001 and absf(n.normalized().y) >= 0.5:
			out.append(a)
			out.append(b)
			out.append(c)
		i += 3
	return out


func _add_barrier_body(host: Node3D) -> void:
	if host.get_node_or_null("BarrierBody") != null or _barriers.is_empty():
		return
	var faces := PackedVector3Array()
	for edge in _barriers:
		if not _edge_in_host(edge, host):
			continue
		_barrier_quads(faces, edge)
	if faces.size() < 9:
		return
	var body := StaticBody3D.new()
	body.name = "BarrierBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.data = faces
	shape.backface_collision = true
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	host.add_child(body)


func _edge_in_host(edge: Dictionary, host: Node) -> bool:
	var coord := _host_coord(host)
	if coord.x < -100000:
		return true
	var ax := float(edge["ax"])
	var az := float(edge["az"])
	var bx := float(edge["bx"])
	var bz := float(edge["bz"])
	return WorldConfig.chunk_of(ax, az) == coord or WorldConfig.chunk_of(bx, bz) == coord or WorldConfig.chunk_of((ax + bx) * 0.5, (az + bz) * 0.5) == coord


func _barrier_quads(faces: PackedVector3Array, edge: Dictionary) -> void:
	var ax := float(edge["ax"])
	var az := float(edge["az"])
	var bx := float(edge["bx"])
	var bz := float(edge["bz"])
	var ab := Vector2(bx - ax, bz - az)
	var span := ab.length()
	if span < 0.05:
		return
	var across := Vector2(ab.y, -ab.x) / span
	var ha := float(edge["ha"])
	var hb := float(edge["hb"])
	var ya := float(edge["ay"])
	var yb := float(edge["by"])
	for side in PackedFloat32Array([-1.0, 1.0]):
		var a := Vector3(ax + across.x * side * (ha + 0.55), ya + 0.15, az + across.y * side * (ha + 0.55))
		var b := Vector3(bx + across.x * side * (hb + 0.55), yb + 0.15, bz + across.y * side * (hb + 0.55))
		var a2 := a + Vector3(0, 0.6, 0)
		var b2 := b + Vector3(0, 0.6, 0)
		faces.append(a)
		faces.append(b)
		faces.append(b2)
		faces.append(a)
		faces.append(b2)
		faces.append(a2)
