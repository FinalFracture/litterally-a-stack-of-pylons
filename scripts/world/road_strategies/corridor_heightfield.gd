extends TfRoadBuilder

## Strategy 4. A ±25 m corridor is rewritten onto a 0.5 m heightfield and that
## heightfield is the road. There is no carriageway ribbon. The same profile,
## crown, junction plane, taper and barrier-or-slope rule as the shared builder
## are sampled onto the grid. Strategy 0 does not use this script.
##
## A heightfield has one height per column, so a 76° cut is a run of steep
## posts (about 2.0 m of rise on a 0.5 m cell) and cannot overhang. A cut that
## has not daylit by 21 m is blended back to the original ground over the last
## 4 m of the corridor, and those posts get steeper than 76°. Benches are flat
## steps in that same grid. steep_line() reports the columns this build wrote.

const CELL := 0.5
const CHUNK_M := 500.0
const CORRIDOR_M := 25.0
## One cell past the sampled verge so a ray on the verge bilinear-samples flat
## ground, not the first slope cell. The slope still starts at the verge.
## The 4 m blend and the 46° rock test are the parent's BLEND_M and ROCK_DEG.
const VERGE_MARGIN_M := 0.8
## Past the shoulder and ditch, far enough that a vertical ray on the verge
## does not meet the box. The edge probe still reaches it (it starts at the
## paint edge and walks 3.2 m).
const BARRIER_PAST_M := 1.05

var _barrier_pending: Array = []
var _mu := Mutex.new()
var steep_max_rise := 0.0
var steep_max_deg := 0.0
var steep_ge70 := 0
var steep_ge76 := 0
var steep_benches := 0
var steep_modified := 0


func prepare() -> void:
	super.prepare()
	_barrier_pending = []
	steep_max_rise = 0.0
	steep_max_deg = 0.0
	steep_ge70 = 0
	steep_ge76 = 0
	steep_benches = 0
	steep_modified = 0


## The coarse mesh keeps the lidar. The driving surface is refine_corridor().
func apply_cuts(_grid: PackedFloat32Array, _origin: Vector2, _n: int, _spacing: float) -> void:
	pass


func apply_paint(_grid: PackedFloat32Array, _origin: Vector2, _n: int, _spacing: float) -> void:
	pass


func clamp_footprint(_drawn: PackedFloat32Array, _cut: PackedFloat32Array, _origin: Vector2, _n: int, _spacing: float) -> void:
	pass


## No ribbon. Collision is the heightfield the generator stores from refine_corridor().
func build_chunk(_coord: Vector2i, _grid: PackedFloat32Array, _n: int, _spacing: float) -> Dictionary:
	return {}


func clear_barriers() -> void:
	_mu.lock()
	_barrier_pending = []
	_mu.unlock()


func take_barriers() -> Array:
	_mu.lock()
	var out := _barrier_pending.duplicate()
	_mu.unlock()
	return out


func steep_line() -> String:
	return "STEEP max_rise_m=%.3f max_deg=%.2f cells_ge70=%d cells_ge76=%d bench_cells=%d modified=%d" % [
		steep_max_rise, steep_max_deg, steep_ge70, steep_ge76, steep_benches, steep_modified,
	]


## Whole chunk at 0.5 m so one HeightMapShape3D can hold the corridor and the
## coarse ground around it. Cells outside ±25 m are the coarse surface sampled
## onto that grid, which is what keeps the chunk edge continuous.
func refine_corridor(base: PackedFloat32Array, bn: int, bsp: float, origin: Vector2) -> Dictionary:
	if base.size() != bn * bn or bn < 2 or bsp <= 0.0:
		return {}
	var t0 := Time.get_ticks_usec()
	var n := int(round(CHUNK_M / CELL)) + 1
	var grid := _upsample(base, bn, n)
	var orig := grid.duplicate()
	var near := PackedFloat32Array()
	near.resize(n * n)
	near.fill(100000.0)
	var tier := PackedByteArray()
	tier.resize(n * n)
	var owner := PackedInt32Array()
	owner.resize(n * n)
	owner.fill(-1)
	var road_i := 0
	for road in _roads:
		if not bool(road.get("rail", false)):
			_stamp_road(road, road_i, grid, orig, near, tier, owner, n, origin)
		road_i += 1
	_stamp_junctions(grid, n, origin)
	var stats := _measure_steep(grid, orig, n)
	_place_barriers(grid, orig, n, origin)
	_mu.lock()
	steep_max_rise = maxf(steep_max_rise, float(stats["rise"]))
	steep_max_deg = maxf(steep_max_deg, float(stats["deg"]))
	steep_ge70 += int(stats["ge70"])
	steep_ge76 += int(stats["ge76"])
	steep_benches += int(stats["benches"])
	steep_modified += int(stats["modified"])
	_mu.unlock()
	var ms := (Time.get_ticks_usec() - t0) / 1000
	print("CORRIDOR n=%d modified=%d steep_deg=%.1f ms=%d" % [n, int(stats["modified"]), float(stats["deg"]), ms])
	return {"h": grid, "n": n, "sp": CELL}


func _upsample(base: PackedFloat32Array, bn: int, dn: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(dn * dn)
	var scale := float(bn - 1) / float(dn - 1)
	var max_i := bn - 1
	for r in dn:
		var rowf := float(r) * scale
		var r0 := int(rowf)
		if r0 >= max_i:
			r0 = max_i - 1
		var r1 := r0 + 1
		var tz := rowf - float(r0)
		var base_r := r * dn
		var row0 := r0 * bn
		var row1 := r1 * bn
		for c in dn:
			var colf := float(c) * scale
			var c0 := int(colf)
			if c0 >= max_i:
				c0 = max_i - 1
			var c1 := c0 + 1
			var tx := colf - float(c0)
			var h00 := base[row0 + c0]
			var h10 := base[row0 + c1]
			var h01 := base[row1 + c0]
			var h11 := base[row1 + c1]
			out[base_r + c] = lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)
	return out


func _stamp_road(road: Dictionary, road_i: int, grid: PackedFloat32Array, orig: PackedFloat32Array, near: PackedFloat32Array, tier: PackedByteArray, owner: PackedInt32Array, n: int, origin: Vector2) -> void:
	var pts: PackedVector3Array = road["pts"]
	var left: PackedVector3Array = road["left"]
	var right: PackedVector3Array = road["right"]
	var bank: PackedFloat32Array = road["bank"]
	var crown: PackedFloat32Array = road["crown"]
	var kinds: PackedStringArray = road["kind"]
	if pts.size() < 2 or left.size() != pts.size() or right.size() != pts.size():
		return
	var shoulder := float(road.get("shoulder", 0.0))
	var ditch := float(road.get("ditch", 0.0))
	var nominal := maxf(float(road.get("half", 3.0)), 0.5)
	var cls := str(road.get("class", ""))
	var rock_cls := cls == "grade" or cls == "rim_local"
	var rid := str(road.get("id", ""))
	var flat_reach := shoulder + ditch + VERGE_MARGIN_M
	var x_min := origin.x - 1.0
	var x_max := origin.x + CHUNK_M + 1.0
	var z_min := origin.y - 1.0
	var z_max := origin.y + CHUNK_M + 1.0
	for i in pts.size() - 1:
		var kind := kinds[i] if i < kinds.size() else "grade"
		# The Perrine deck is the bridge mesh. Lab spans have no mesh, so they
		# are written into the heightfield like every other segment.
		if roads_path == "" and (kind == "bridge" or (kind == "deck" and not _approach_road(rid))):
			continue
		var ax := pts[i].x
		var az := pts[i].z
		var bx := pts[i + 1].x
		var bz := pts[i + 1].z
		if maxf(ax, bx) < x_min - CORRIDOR_M or minf(ax, bx) > x_max + CORRIDOR_M:
			continue
		if maxf(az, bz) < z_min - CORRIDOR_M or minf(az, bz) > z_max + CORRIDOR_M:
			continue
		var elevated := kind == "deck" or kind == "bridge"
		var reach := CORRIDOR_M + nominal
		var c0 := clampi(int(floor((minf(ax, bx) - reach - origin.x) / CELL)), 0, n - 1)
		var c1 := clampi(int(ceil((maxf(ax, bx) + reach - origin.x) / CELL)), 0, n - 1)
		var r0 := clampi(int(floor((minf(az, bz) - reach - origin.y) / CELL)), 0, n - 1)
		var r1 := clampi(int(ceil((maxf(az, bz) + reach - origin.y) / CELL)), 0, n - 1)
		var l0 := left[i]
		var l1 := left[i + 1]
		var rgt0 := right[i]
		var rgt1 := right[i + 1]
		var ba := bank[i] if i < bank.size() else 0.0
		var bb := bank[i + 1] if i + 1 < bank.size() else ba
		var ca := crown[i] if i < crown.size() else 0.0
		var cb := crown[i + 1] if i + 1 < crown.size() else ca
		var ay := pts[i].y
		var by := pts[i + 1].y
		for r in range(r0, r1 + 1):
			var z := origin.y + float(r) * CELL
			var row := r * n
			for c in range(c0, c1 + 1):
				var x := origin.x + float(c) * CELL
				var hit := _seg_side(x, z, ax, az, bx, bz)
				var dist := hit.x
				if dist > CORRIDOR_M:
					continue
				var idx := row + c
				var t := hit.y
				var cy := lerpf(ay, by, t)
				var bk := lerpf(ba, bb, t)
				var cr := lerpf(ca, cb, t)
				var sec := Vector3(cy, cy, cy) if elevated else _section(cy, bk, cr, nominal)
				var lp := l0.lerp(l1, t)
				var rp := rgt0.lerp(rgt1, t)
				var abx := rp.x - lp.x
				var abz := rp.z - lp.z
				var len2 := abx * abx + abz * abz
				var u := 0.5
				if len2 > 0.0001:
					u = ((x - lp.x) * abx + (z - lp.z) * abz) / len2
				var edge_y := sec.x if u < 0.5 else sec.z
				var y := edge_y
				var outer := 0.0
				var here := 3
				if u < 0.0 or u > 1.0:
					var ex := lp.x if u < 0.0 else rp.x
					var ez := lp.z if u < 0.0 else rp.z
					var dx := x - ex
					var dz := z - ez
					outer = sqrt(dx * dx + dz * dz)
					if outer <= flat_reach:
						here = 2
						y = edge_y
					else:
						here = 1
						var prev_s := int(tier[idx])
						if prev_s >= 2 or (prev_s == 1 and dist >= near[idx]):
							continue
						var past := outer - flat_reach
						var ground := orig[idx]
						var rock := rock_cls or _steep_orig(orig, n, origin, x, z)
						if ground > edge_y + 0.05:
							var cut: Vector3 = _cut_stamp(edge_y, past, ground, rock)
							y = cut.x if cut.z >= 0.5 else ground
						else:
							var fill: Vector3 = _fill_stamp(edge_y, past, ground)
							y = fill.x if fill.z >= 0.5 else ground
				elif u < 0.5:
					y = lerpf(sec.y, sec.x, (0.5 - u) / 0.5)
				else:
					y = lerpf(sec.y, sec.z, (u - 0.5) / 0.5)
				if dist > CORRIDOR_M - BLEND_M and outer > flat_reach:
					var blend_u := clampf((dist - (CORRIDOR_M - BLEND_M)) / BLEND_M, 0.0, 1.0)
					var w := 0.5 - 0.5 * cos(PI * blend_u)
					y = lerpf(y, orig[idx], w)
				# 3 paint, 2 verge, 1 slope. A carriageway beats a closer verge.
				# The same tier keeps the nearer centreline. Two roads that
				# cross at different heights still share the nearer cell:
				# a heightfield has only one height there.
				var prev := int(tier[idx])
				var take := prev == 0 or here > prev
				if not take and here == prev:
					take = dist < near[idx]
				if not take:
					continue
				tier[idx] = here
				owner[idx] = road_i
				near[idx] = dist
				grid[idx] = y


func _steep_orig(orig: PackedFloat32Array, n: int, origin: Vector2, x: float, z: float) -> bool:
	var hx := _gy(orig, n, origin, x + 2.0, z) - _gy(orig, n, origin, x - 2.0, z)
	var hz := _gy(orig, n, origin, x, z + 2.0) - _gy(orig, n, origin, x, z - 2.0)
	var dx := hx / 4.0
	var dz := hz / 4.0
	var ny := 1.0 / sqrt(dx * dx + dz * dz + 1.0)
	return rad_to_deg(acos(clampf(ny, 0.0, 1.0))) >= ROCK_DEG


func _stamp_junctions(grid: PackedFloat32Array, n: int, origin: Vector2) -> void:
	for item in _junctions:
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var radius := float(item.get("radius", 8.0)) + 0.6
		var cx := float(pos[0])
		var cz := float(pos[2])
		if cx + radius < origin.x or cx - radius > origin.x + CHUNK_M:
			continue
		if cz + radius < origin.y or cz - radius > origin.y + CHUNK_M:
			continue
		var c0 := clampi(int(floor((cx - radius - origin.x) / CELL)), 0, n - 1)
		var c1 := clampi(int(ceil((cx + radius - origin.x) / CELL)), 0, n - 1)
		var r0 := clampi(int(floor((cz - radius - origin.y) / CELL)), 0, n - 1)
		var r1 := clampi(int(ceil((cz + radius - origin.y) / CELL)), 0, n - 1)
		var rad2 := radius * radius
		for r in range(r0, r1 + 1):
			var z := origin.y + float(r) * CELL
			var dz := z - cz
			var row := r * n
			for c in range(c0, c1 + 1):
				var x := origin.x + float(c) * CELL
				var dx := x - cx
				if dx * dx + dz * dz > rad2:
					continue
				grid[row + c] = _plane_at(item, x, z)


func _gy(grid: PackedFloat32Array, n: int, origin: Vector2, x: float, z: float) -> float:
	var col := clampf((x - origin.x) / CELL, 0.0, float(n - 1))
	var row := clampf((z - origin.y) / CELL, 0.0, float(n - 1))
	return _bilerp(grid, n, col, row)


func _bilerp(grid: PackedFloat32Array, n: int, col: float, row: float) -> float:
	var max_i := n - 1
	var c0 := clampi(int(col), 0, max_i)
	var r0 := clampi(int(row), 0, max_i)
	var c1 := mini(c0 + 1, max_i)
	var r1 := mini(r0 + 1, max_i)
	var tx := clampf(col - float(c0), 0.0, 1.0)
	var tz := clampf(row - float(r0), 0.0, 1.0)
	var h00 := grid[r0 * n + c0]
	var h10 := grid[r0 * n + c1]
	var h01 := grid[r1 * n + c0]
	var h11 := grid[r1 * n + c1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func _measure_steep(grid: PackedFloat32Array, orig: PackedFloat32Array, n: int) -> Dictionary:
	var rise := 0.0
	var ge70 := 0
	var ge76 := 0
	var benches := 0
	var modified := 0
	var limit70 := tan(deg_to_rad(70.0)) * CELL
	var limit76 := tan(deg_to_rad(76.0)) * CELL
	for r in n:
		var row := r * n
		for c in n:
			var i := row + c
			if absf(grid[i] - orig[i]) > 0.02:
				modified += 1
			if c + 1 < n:
				var pair := absf(grid[i] - grid[i + 1])
				if absf(grid[i] - orig[i]) > 0.02 or absf(grid[i + 1] - orig[i + 1]) > 0.02:
					if pair > rise:
						rise = pair
					if pair >= limit70:
						ge70 += 1
					if pair >= limit76:
						ge76 += 1
			if r + 1 < n:
				var down := row + n + c
				var pair_z := absf(grid[i] - grid[down])
				if absf(grid[i] - orig[i]) > 0.02 or absf(grid[down] - orig[down]) > 0.02:
					if pair_z > rise:
						rise = pair_z
					if pair_z >= limit70:
						ge70 += 1
					if pair_z >= limit76:
						ge76 += 1
			if c > 1 and c < n - 2 and orig[i] - grid[i] > 6.0:
				var flat := absf(grid[i] - grid[i - 1]) < 0.15 and absf(grid[i] - grid[i + 1]) < 0.15
				var step := absf(grid[i] - grid[i - 2]) > 1.2 or absf(grid[i + 2] - grid[i]) > 1.2
				if flat and step:
					benches += 1
	var deg := rad_to_deg(atan(rise / CELL)) if rise > 0.0 else 0.0
	return {"rise": rise, "deg": deg, "ge70": ge70, "ge76": ge76, "benches": benches, "modified": modified}


func _place_barriers(grid: PackedFloat32Array, orig: PackedFloat32Array, n: int, origin: Vector2) -> void:
	for road in _roads:
		if bool(road.get("rail", false)):
			continue
		var chain: PackedFloat32Array = road["chain"]
		if chain.size() < 2:
			continue
		var length := float(chain[chain.size() - 1])
		var count := int(floor(length / 2.0)) + 1
		var sev := PackedByteArray()
		sev.resize(count * 2)
		var cursor := 0
		for k in count:
			var s := minf(float(k) * 2.0, length)
			while cursor + 1 < chain.size() and float(chain[cursor + 1]) < s - 0.001:
				cursor += 1
			var pose := _station(road, s, cursor)
			if pose.is_empty():
				continue
			sev[k * 2] = _side_severity(road, pose, true, grid, orig, n, origin)
			sev[k * 2 + 1] = _side_severity(road, pose, false, grid, orig, n, origin)
		var dil := sev.duplicate()
		var rad := 8
		for k in count:
			for side in 2:
				var here := int(sev[k * 2 + side])
				if here == 0:
					continue
				var a := maxi(k - rad, 0)
				var b := mini(k + rad, count - 1)
				for j in range(a, b + 1):
					var at := j * 2 + side
					if int(dil[at]) < here:
						dil[at] = here
		cursor = 0
		for k in count:
			var s2 := minf(float(k) * 2.0, length)
			while cursor + 1 < chain.size() and float(chain[cursor + 1]) < s2 - 0.001:
				cursor += 1
			if int(dil[k * 2]) == 0 and int(dil[k * 2 + 1]) == 0:
				continue
			var pose2 := _station(road, s2, cursor)
			if pose2.is_empty():
				continue
			if int(dil[k * 2]) > 0:
				_emit_barrier(road, pose2, true, int(dil[k * 2]) == 2, grid, n, origin)
			if int(dil[k * 2 + 1]) > 0:
				_emit_barrier(road, pose2, false, int(dil[k * 2 + 1]) == 2, grid, n, origin)


## 0 none, 1 guardrail, 2 concrete. Section 4: drop > 3 m, or a fill steeper
## than 3:1 and taller than 3 m. Rim class or a drop over 10 m is concrete.
func _side_severity(road: Dictionary, pose: Dictionary, left: bool, grid: PackedFloat32Array, orig: PackedFloat32Array, n: int, origin: Vector2) -> int:
	var edge: Vector3 = pose["edge_l"] if left else pose["edge_r"]
	var outward: Vector3 = pose["out_l"] if left else pose["out_r"]
	if outward.length_squared() < 0.01:
		return 0
	var shoulder := float(road.get("shoulder", 0.0))
	var spec := edge + outward * shoulder
	var worst := 0.0
	var dist := 0.5
	while dist <= 3.001:
		var p := spec + outward * dist
		var g := _gy(grid, n, origin, p.x, p.z)
		worst = maxf(worst, edge.y - g)
		dist += 0.5
	# Thickness of the fill under this edge. 1.5:1 is steeper than 3:1.
	var natural := _gy(orig, n, origin, edge.x, edge.z)
	var fill_h := edge.y - natural
	if fill_h < 0.0:
		fill_h = 0.0
	var need := worst > 3.0 or fill_h > 3.0
	if not need:
		return 0
	var tall := maxf(worst, fill_h)
	var rim := str(road.get("class", "")) == "rim_local" or bool(pose.get("elevated", false))
	if rim or tall > 10.0:
		return 2
	return 1


func _emit_barrier(road: Dictionary, pose: Dictionary, left: bool, concrete: bool, grid: PackedFloat32Array, n: int, origin: Vector2) -> void:
	var edge: Vector3 = pose["edge_l"] if left else pose["edge_r"]
	var outward: Vector3 = pose["out_l"] if left else pose["out_r"]
	var tangent: Vector3 = pose["tangent"]
	if outward.length_squared() < 0.01 or tangent.length_squared() < 0.01:
		return
	var reach := float(road.get("shoulder", 0.0)) + float(road.get("ditch", 0.0))
	var lateral := reach + BARRIER_PAST_M
	if bool(pose.get("elevated", false)):
		lateral = 0.45
	# Keep the box off the verge samples. The harness stops at shoulder + ditch.
	var at := edge + outward * lateral
	if at.x < origin.x - 20.0 or at.x > origin.x + CHUNK_M + 20.0:
		return
	if at.z < origin.y - 20.0 or at.z > origin.y + CHUNK_M + 20.0:
		return
	var ground := _gy(grid, n, origin, at.x, at.z)
	var h := 0.8 if concrete else 0.7
	var top := maxf(ground + h, edge.y + 0.62)
	var height := maxf(top - ground, h)
	var side := Vector3(-tangent.z, 0.0, tangent.x)
	if side.length_squared() < 0.01:
		return
	side = side.normalized()
	var basis := Basis(tangent, Vector3.UP, side)
	var xf := Transform3D(basis, Vector3(at.x, ground + height * 0.5, at.z))
	var box := {"xf": xf, "size": Vector3(2.35, height, 0.30)}
	_mu.lock()
	_barrier_pending.append(box)
	_mu.unlock()


func _station(road: Dictionary, s: float, i: int) -> Dictionary:
	var pts: PackedVector3Array = road["pts"]
	var left: PackedVector3Array = road["left"]
	var right: PackedVector3Array = road["right"]
	var chain: PackedFloat32Array = road["chain"]
	var bank: PackedFloat32Array = road["bank"]
	var crown: PackedFloat32Array = road["crown"]
	var kinds: PackedStringArray = road["kind"]
	if i < 0 or i + 1 >= pts.size():
		return {}
	var span := maxf(float(chain[i + 1]) - float(chain[i]), 0.001)
	var t := clampf((s - float(chain[i])) / span, 0.0, 1.0)
	var cy := lerpf(pts[i].y, pts[i + 1].y, t)
	var bk := lerpf(bank[i], bank[i + 1], t) if i + 1 < bank.size() else 0.0
	var cr := lerpf(crown[i], crown[i + 1], t) if i + 1 < crown.size() else 0.0
	var kind := kinds[i] if i < kinds.size() else "grade"
	var elevated := kind == "deck" or kind == "bridge"
	var half := maxf(float(road.get("half", 3.0)), 0.5)
	var sec := Vector3(cy, cy, cy) if elevated else _section(cy, bk, cr, half)
	var lp := left[i].lerp(left[i + 1], t)
	var rp := right[i].lerp(right[i + 1], t)
	lp.y = sec.x
	rp.y = sec.z
	var across := Vector3(rp.x - lp.x, 0.0, rp.z - lp.z)
	if across.length_squared() < 0.01:
		return {}
	var out_r := across.normalized()
	var tangent := pts[i + 1] - pts[i]
	tangent.y = 0.0
	if tangent.length_squared() < 0.0001:
		return {}
	tangent = tangent.normalized()
	return {
		"edge_l": lp,
		"edge_r": rp,
		"out_l": -out_r,
		"out_r": out_r,
		"tangent": tangent,
		"elevated": elevated,
	}
