class_name TwinFallsTerrainGenerator
extends ChunkGenerator

## Twin Falls heightfield. ChunkStreamer coords are Godot x/z (z = -north).
## Tile c_<cx>_<cz> uses cz as the north index: world chunk (cx, gz) reads cz = -gz - 1.
## Collision uses the same tile as the mesh source: 129 samples on plain ground,
## the 513-sample (1 m) tiles_hi grid on canyon chunks. Five gentle south flags
## (SKIP_HI) stay on the coarse grid. The visual mesh simplifies flats, but a
## floor block stays a 4 m quad. Subdividing flats to hold a 0.3 m error
## lost more than 5% fps, so FLAT_ERR_M stays open and that pass is idle.
## The heightmap is then resampled from those drawn triangles, so the ground
## you stand on is the ground you see. The river bed is carved under the ribbon.

const DATA := "res://world/twin_falls/data"
const HI_N := 513
const LOW_N := 129
const CELLS := 128
const HI_SP := 500.0 / 512.0
const LOW_SP := 500.0 / 128.0
const TRIS_PER_PART := 4000
## Ribbon half-width in twin_falls_world. The floor stand stays outside that strip.
const RIVER_HALF_M := 20.0
const STAND_CLEAR_M := 36.0
## Open on purpose. 0.3 m forced 2 m floor cells and lost more than 5% fps.
const FLAT_ERR_M := 10000.0
## Carved depth at the water.json centreline. Banks ease back to the DEM.
const BED_DEPTH_M := 1.5
const WATER_CELL := 64.0
const SKIP_HI := {
	"6_0": true,
	"3_2": true,
	"2_3": true,
	"0_4": true,
	"1_4": true,
}

var spawn := Vector3(3320.0, 143.073, -6531.5)
## Godot yaw: 0 looks north (-Z), positive turns left. From spawn.json.
var spawn_yaw := 0.0
var water_pts: Array[Vector3] = []

const _RoadBuilder := preload("res://scripts/world/tf_road_builder.gd")
var _roads

var _mat: ShaderMaterial
var _hi: Dictionary = {}
var _lock := Mutex.new()
var _cache: Dictionary = {}
## Drawn heightmaps, keyed by Godot chunk "x_z". Collision and the camera read these.
var _drawn: Dictionary = {}
var _wbuckets: Dictionary = {}


class ChunkPay:
	extends RefCounted
	var parts: Array = []
	var heights := PackedFloat32Array()
	var map_n := LOW_N
	var spacing := LOW_SP
	var center := Vector3.ZERO
	var tris := 0
	var content_hash := ""
	var roads: Dictionary = {}


class Build:
	extends RefCounted
	var grid: PackedFloat32Array
	var n := 0
	var spacing := 1.0
	var origin := Vector2.ZERO
	var dc := Vector2i.ZERO
	var hi := false
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var indices := PackedInt32Array()
	var vindex: PackedInt32Array
	var water_d: PackedFloat32Array
	var water_y: PackedFloat32Array
	var water_empty := true
	var talus: PackedFloat32Array
	var road_break: Dictionary = {}


func _init() -> void:
	generator_name = "twin_falls_terrain"


func material() -> ShaderMaterial:
	return _mat


func prepare() -> void:
	_load_meta()
	_roads = _RoadBuilder.new()
	_roads.prepare()
	_mat = ShaderMaterial.new()
	var shader := load("res://shaders/twin_falls_terrain.gdshader") as Shader
	if shader == null:
		push_error("Twin Falls terrain shader failed to load.")
		return
	_mat.shader = shader
	var tex := "res://materials/twin_falls_terrain/textures/"
	_mat.set_shader_parameter("dry_alb", load(tex + "dry_ground_01_albedo_2k.jpg"))
	_mat.set_shader_parameter("bas_alb", load(tex + "tf_basalt_albedo_2k.jpg"))
	_mat.set_shader_parameter("tal_alb", load(tex + "tf_talus_albedo_2k.jpg"))
	_mat.set_shader_parameter("wet_alb", load(tex + "tf_wetbank_albedo_2k.jpg"))


func generate(coord: Vector2i, world_seed: int, floor_box: Dictionary = {}) -> ChunkData:
	var t0 := Time.get_ticks_usec()
	var data := ChunkData.new()
	data.coord = coord
	data.world_seed = world_seed
	data.chunk_seed = WorldConfig.chunk_seed(world_seed, coord)
	data.generator_name = generator_name
	_publish_floor(floor_box)
	var dc := _data_of(coord)
	if dc.x < 0:
		data.content_hash = "out"
		data.gen_usec = Time.get_ticks_usec() - t0
		return data
	var hi := _is_hi(dc.x, dc.y)
	var pay := _build(coord, dc, hi)
	data.payload = pay
	data.spawn = spawn
	data.stats = {"hi": hi, "tris": pay.tris, "parts": pay.parts.size()}
	data.content_hash = pay.content_hash
	data.gen_usec = Time.get_ticks_usec() - t0
	return data


func build_jobs(data: ChunkData, host: Node3D) -> Array[Callable]:
	var jobs: Array[Callable] = []
	var pay := data.payload as ChunkPay
	if pay == null:
		return jobs
	# Boot already placed a raw heightmap. This job replaces it with the drawn one.
	jobs.append(_job_body.bind(host, pay))
	for i in pay.parts.size():
		jobs.append(_job_part.bind(host, pay, i))
	if _roads != null and not pay.roads.is_empty():
		jobs.append_array(_roads.jobs(host, pay.roads))
	return jobs


func _ground_job(coord: Vector2i, host: Node3D) -> void:
	if host.get_node_or_null("TerrainBody") != null:
		return
	var dc := _data_of(coord)
	if dc.x < 0:
		return
	var hi := _is_hi(dc.x, dc.y)
	var n := HI_N if hi else LOW_N
	var spacing := HI_SP if hi else LOW_SP
	var heights := _heights(dc.x, dc.y, hi)
	if heights.size() != n * n:
		return
	_add_body(host, heights, _center_of(coord), n, spacing)


func height_at(x: float, z: float) -> float:
	var cx := int(floor(x / 500.0))
	var zn := -z
	var cz := int(floor(zn / 500.0))
	if cx < 0 or cx > 9 or cz < 0 or cz > 15:
		return -80.0
	var grid := _heights(cx, cz, false)
	if grid.size() != LOW_N * LOW_N:
		return -80.0
	var col := (x - float(cx) * 500.0) / LOW_SP
	# Row 0 is the north edge of the tile.
	var row := (float(cz + 1) * 500.0 - zn) / LOW_SP
	return _bilinear(grid, LOW_N, col, row)


## A stand on the canyon floor of the spawn chunk, clear of the river ribbon.
## The offset is perpendicular to the centreline. A pure Z nudge stays inside the
## strip wherever the river is not running due east.
func canyon_stand() -> Vector3:
	var best := Vector3(3359.0, -4.0, -6770.0)
	var best_score := 1.0e12
	var found := false
	var n := water_pts.size()
	for i in n:
		var p: Vector3 = water_pts[i]
		if p.x < 3050.0 or p.x > 3480.0:
			continue
		if p.z > -6550.0 or p.z < -6980.0:
			continue
		var prev: Vector3 = water_pts[maxi(i - 1, 0)]
		var next: Vector3 = water_pts[mini(i + 1, n - 1)]
		var dir := Vector2(next.x - prev.x, next.z - prev.z)
		if dir.length_squared() < 1.0:
			dir = Vector2.RIGHT
		dir = dir.normalized()
		var perp := Vector2(-dir.y, dir.x)
		for side_v in [1.0, -1.0]:
			var side := float(side_v)
			var stand := Vector3(p.x + perp.x * side * STAND_CLEAR_M, 0.0, p.z + perp.y * side * STAND_CLEAR_M)
			if water_nearest(stand.x, stand.z).x < RIVER_HALF_M + 8.0:
				continue
			var h := height_at(stand.x, stand.z)
			if h > p.y + 14.0 or h < p.y - 2.0:
				continue
			stand.y = h + 0.45
			# Prefer the south bank (larger Godot z, toward the rim spawn).
			var south := 0.0 if stand.z > p.z else 80.0
			var score := absf(stand.x - spawn.x) + absf(h - p.y) * 4.0 + south
			if score < best_score:
				best_score = score
				best = stand
				found = true
	if found:
		return best
	return _fallback_stand()


func _fallback_stand() -> Vector3:
	var anchor := Vector3(spawn.x, -5.2, -6808.0)
	var best_d := 1.0e12
	for p in water_pts:
		var d := absf(p.x - spawn.x)
		if d < best_d:
			best_d = d
			anchor = p
	var stand := Vector3(anchor.x, 0.0, anchor.z + STAND_CLEAR_M)
	stand.y = height_at(stand.x, stand.z) + 0.45
	return stand


## Horizontal distance (m) to the water.json centreline, and the water height there.
func water_nearest(x: float, z: float) -> Vector2:
	var best_d := 9999.0
	var best_y := -6.0
	var n := water_pts.size()
	for i in range(n - 1):
		var hit := _seg_dist(x, z, water_pts[i], water_pts[i + 1])
		if hit.x < best_d:
			best_d = hit.x
			best_y = hit.y
	return Vector2(best_d, best_y)


func covers(coord: Vector2i) -> bool:
	return _data_of(coord).x >= 0


func _publish_floor(floor_box: Dictionary) -> void:
	if floor_box.is_empty() or not floor_box.has("mutex"):
		return
	var lock: Mutex = floor_box["mutex"]
	lock.lock()
	floor_box["spawn"] = spawn
	floor_box["cols"] = []
	floor_box["ready"] = true
	lock.unlock()


func _build(coord: Vector2i, dc: Vector2i, hi: bool) -> ChunkPay:
	var b := Build.new()
	b.n = HI_N if hi else LOW_N
	b.spacing = HI_SP if hi else LOW_SP
	b.grid = _heights(dc.x, dc.y, hi)
	b.origin = WorldConfig.chunk_origin(coord)
	b.dc = dc
	b.hi = hi
	b.vindex = PackedInt32Array()
	b.vindex.resize(b.n * b.n)
	b.vindex.fill(-1)
	var field := _water_field(b.origin)
	b.water_d = field["d"]
	b.water_y = field["y"]
	b.water_empty = bool(field["empty"])
	b.talus = _talus_field(b)
	if b.grid.size() == b.n * b.n:
		# Detach from the height cache. Carve and the mesh must not rewrite the DEM.
		b.grid = b.grid.duplicate()
		_carve_bed(b)
		if _roads != null:
			_roads.apply_cuts(b.grid, b.origin, b.n, b.spacing)
		if hi:
			_emit_hi(b)
		else:
			_emit_low(b)
	var pay := ChunkPay.new()
	# Sample the simplified triangles so the heightmap matches the drawn surface.
	var drawn := _collision_from_mesh(b)
	_store_drawn(coord, drawn, b.n, b.spacing)
	pay.heights = drawn
	pay.map_n = b.n
	pay.spacing = b.spacing
	pay.center = _center_of(coord)
	pay.tris = b.indices.size() / 3
	pay.parts = _split(b.verts, b.norms, b.cols, b.indices)
	if _roads != null and b.grid.size() == b.n * b.n:
		pay.roads = _roads.build_chunk(coord, b.grid, b.n, b.spacing)
	var g := pay.heights
	var h0 := g[0] if not g.is_empty() else 0.0
	var h1 := g[g.size() / 2] if not g.is_empty() else 0.0
	var h2 := g[g.size() - 1] if not g.is_empty() else 0.0
	pay.content_hash = "%d_%d_%d_%.2f_%.2f_%.2f_%d" % [dc.x, dc.y, int(hi), h0, h1, h2, pay.tris]
	return pay


func _emit_low(b: Build) -> void:
	_emit_blocks(b, 1)


func _emit_hi(b: Build) -> void:
	_emit_blocks(b, 4)


## Flat 16 m blocks, 4 m everywhere else, 2 m on cliffs and on floor cells that
## would miss the samples by more than FLAT_ERR_M. Edges copy the finer side.
func _emit_blocks(b: Build, step: int) -> void:
	for r in range(0, CELLS, 4):
		for c in range(0, CELLS, 4):
			if _merge_ok(b, c, r):
				_emit_coarse(b, c, r, step)
			else:
				for dy in 4:
					for dx in 4:
						_emit_cell(b, c + dx, r + dy, step)


func _emit_cell(b: Build, c: int, r: int, step: int) -> void:
	if step == 4 and _level_at(b.dc.x, b.dc.y, c, r) >= 2:
		var c0 := c * 4
		var r0 := r * 4
		for rr in 2:
			for cc in 2:
				var cs := c0 + cc * 2
				var rs := r0 + rr * 2
				_quad(b, cs, rs, cs + 2, rs + 2)
		return
	var north := _edge_fine(b, c, r - 1, step)
	var south := _edge_fine(b, c, r + 1, step)
	var west := _edge_fine(b, c - 1, r, step)
	var east := _edge_fine(b, c + 1, r, step)
	if north or south or west or east:
		if step == 4:
			_fan_hi(b, c, r, north, east, south, west)
		else:
			_fan_low(b, c, r, north, east, south, west)
	else:
		_quad(b, c * step, r * step, (c + 1) * step, (r + 1) * step)


func _emit_coarse(b: Build, c: int, r: int, step: int) -> void:
	var c0 := c * step
	var r0 := r * step
	var span := 4 * step
	var north := not _merge_ok(b, c, r - 4)
	var south := not _merge_ok(b, c, r + 4)
	var west := not _merge_ok(b, c - 4, r)
	var east := not _merge_ok(b, c + 4, r)
	if not north and not south and not west and not east:
		_quad(b, c0, r0, c0 + span, r0 + span)
		return
	var pts: Array[int] = []
	_coarse_edge(b, pts, c0, r0, step, 0, north)
	_coarse_edge(b, pts, c0 + span, r0, 0, step, east)
	_coarse_edge(b, pts, c0 + span, r0 + span, -step, 0, south)
	_coarse_edge(b, pts, c0, r0 + span, 0, -step, west)
	_fan(b, pts, _vert(b, c0 + span / 2, r0 + span / 2))


func _coarse_edge(b: Build, pts: Array[int], c: int, r: int, dc: int, dr: int, detailed: bool) -> void:
	pts.append(_vert(b, c, r))
	if not detailed:
		return
	for k in range(1, 4):
		pts.append(_vert(b, c + dc * k, r + dr * k))


func _fan_low(b: Build, c: int, r: int, north: bool, east: bool, south: bool, west: bool) -> void:
	var pts: Array[int] = []
	_low_edge(b, pts, c, r, 1, 0, north, b.dc.x, b.dc.y + 1, c * 4, 512, 1, 0)
	_low_edge(b, pts, c + 1, r, 0, 1, east, b.dc.x + 1, b.dc.y, 0, r * 4, 0, 1)
	_low_edge(b, pts, c + 1, r + 1, -1, 0, south, b.dc.x, b.dc.y - 1, (c + 1) * 4, 0, -1, 0)
	_low_edge(b, pts, c, r + 1, 0, -1, west, b.dc.x - 1, b.dc.y, 512, (r + 1) * 4, 0, -1)
	_fan(b, pts, _center_vert(b, c, r, c + 1, r + 1))


func _low_edge(b: Build, pts: Array[int], c: int, r: int, dc: int, dr: int, detailed: bool, ocx: int, ocz: int, hi_c: int, hi_r: int, dhc: int, dhr: int) -> void:
	pts.append(_vert(b, c, r))
	if not detailed:
		return
	pts.append(_push_foreign(b, ocx, ocz, hi_c + dhc * 2, hi_r + dhr * 2))


func _fan_hi(b: Build, cx: int, cy: int, north: bool, east: bool, south: bool, west: bool) -> void:
	var c0 := cx * 4
	var r0 := cy * 4
	var pts: Array[int] = []
	_hi_edge(b, pts, c0, r0, 1, 0, north)
	_hi_edge(b, pts, c0 + 4, r0, 0, 1, east)
	_hi_edge(b, pts, c0 + 4, r0 + 4, -1, 0, south)
	_hi_edge(b, pts, c0, r0 + 4, 0, -1, west)
	_fan(b, pts, _vert(b, c0 + 2, r0 + 2))


func _hi_edge(b: Build, pts: Array[int], c: int, r: int, dc: int, dr: int, detailed: bool) -> void:
	pts.append(_vert(b, c, r))
	if not detailed:
		return
	pts.append(_vert(b, c + dc * 2, r + dr * 2))


func _fan(b: Build, pts: Array[int], center: int) -> void:
	if pts.size() < 3:
		return
	for i in pts.size():
		var j := (i + 1) % pts.size()
		b.indices.append(center)
		b.indices.append(pts[i])
		b.indices.append(pts[j])


func _quad(b: Build, c0: int, r0: int, c1: int, r1: int) -> void:
	var nw := _vert(b, c0, r0)
	var ne := _vert(b, c1, r0)
	var sw := _vert(b, c0, r1)
	var se := _vert(b, c1, r1)
	b.indices.append(nw)
	b.indices.append(ne)
	b.indices.append(se)
	b.indices.append(nw)
	b.indices.append(se)
	b.indices.append(sw)


func _center_vert(b: Build, c0: int, r0: int, c1: int, r1: int) -> int:
	var x := ( _x(b, c0) + _x(b, c1) ) * 0.5
	var z := ( _z(b, r0) + _z(b, r1) ) * 0.5
	var h := (_h(b, c0, r0) + _h(b, c1, r0) + _h(b, c0, r1) + _h(b, c1, r1)) * 0.25
	var nrm := (_normal_at(b, c0, r0) + _normal_at(b, c1, r1)).normalized()
	if nrm.length_squared() < 0.1:
		nrm = Vector3.UP
	return _commit(b, x, z, h, nrm)


func _vert(b: Build, c: int, r: int) -> int:
	var k := r * b.n + c
	var have := b.vindex[k]
	if have >= 0:
		return have
	var id := _commit(b, _x(b, c), _z(b, r), _h(b, c, r), _normal_at(b, c, r))
	b.vindex[k] = id
	return id


func _push_foreign(b: Build, cx: int, cz: int, hi_c: int, hi_r: int) -> int:
	var grid := _heights(cx, cz, true)
	var h := grid[hi_r * HI_N + hi_c]
	var origin := _data_origin(cx, cz)
	var x := origin.x + float(hi_c) * HI_SP
	var z := origin.y + float(hi_r) * HI_SP
	var sp := HI_SP
	var hl := grid[hi_r * HI_N + clampi(hi_c - 1, 0, 512)]
	var hr := grid[hi_r * HI_N + clampi(hi_c + 1, 0, 512)]
	var hu := grid[clampi(hi_r - 1, 0, 512) * HI_N + hi_c]
	var hd := grid[clampi(hi_r + 1, 0, 512) * HI_N + hi_c]
	var nrm := Vector3(-(hr - hl) / (2.0 * sp), 1.0, -(hd - hu) / (2.0 * sp)).normalized()
	return _commit(b, x, z, h, nrm)


func _commit(b: Build, x: float, z: float, h: float, nrm: Vector3) -> int:
	var slope := rad_to_deg(acos(clampf(nrm.y, 0.0, 1.0)))
	var cliff := _talus_at(b, x, z)
	var wy := _water_sample(b, x, z)
	var masks := _masks(slope, cliff, wy.x, h - wy.y)
	var id := b.verts.size()
	b.verts.append(WorldConfig.to_local(Vector3(x, h, z)))
	b.norms.append(nrm)
	b.cols.append(masks)
	return id


func _masks(slope_deg: float, cliff: float, dist: float, above: float) -> Color:
	var basalt := smoothstep(34.0, 50.0, slope_deg)
	var wet := 0.0
	if dist < 40.0 and above < 10.0 and above > -1.5:
		wet = (1.0 - smoothstep(4.0, 26.0, dist)) * (1.0 - smoothstep(0.3, 5.0, maxf(above, 0.0)))
	wet *= (1.0 - basalt)
	var talus := cliff * (1.0 - basalt) * (1.0 - wet)
	var dry := (1.0 - basalt) * (1.0 - wet) * (1.0 - talus)
	return Color(dry, basalt, talus, wet)


func _talus_field(b: Build) -> PackedFloat32Array:
	var n := 65
	var out := PackedFloat32Array()
	out.resize(n * n)
	if b.grid.is_empty():
		return out
	var step := 500.0 / float(n - 1)
	var sp := maxf(b.spacing, 1.0)
	for r in n:
		for c in n:
			var x := b.origin.x + float(c) * step
			var z := b.origin.y + float(r) * step
			var h := _sample_world(b, x, z)
			var dx := (_sample_world(b, x + sp, z) - _sample_world(b, x - sp, z)) / (2.0 * sp)
			var dz := (_sample_world(b, x, z + sp) - _sample_world(b, x, z - sp)) / (2.0 * sp)
			var ny := 1.0 / sqrt(dx * dx + dz * dz + 1.0)
			var slope := rad_to_deg(acos(clampf(ny, 0.0, 1.0)))
			out[r * n + c] = _cliff(b, x, z, h, slope)
	return out


func _talus_at(b: Build, x: float, z: float) -> float:
	if b.talus.size() != 65 * 65:
		return 0.0
	var step := 500.0 / 64.0
	var fx := clampf((x - b.origin.x) / step, 0.0, 63.999)
	var fz := clampf((z - b.origin.y) / step, 0.0, 63.999)
	var c0 := int(fx)
	var r0 := int(fz)
	var tx := fx - float(c0)
	var tz := fz - float(r0)
	var n := 65
	var h00 := b.talus[r0 * n + c0]
	var h10 := b.talus[r0 * n + c0 + 1]
	var h01 := b.talus[(r0 + 1) * n + c0]
	var h11 := b.talus[(r0 + 1) * n + c0 + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func _cliff(b: Build, x: float, z: float, h: float, slope_deg: float) -> float:
	if slope_deg > 46.0:
		return 0.0
	var rise := 0.0
	var step := 0.0
	var rad := 14.0
	for k in 4:
		var ang := float(k) * TAU / 4.0
		var sx := x + cos(ang) * rad
		var sz := z + sin(ang) * rad
		var sh := _sample_world(b, sx, sz)
		rise = maxf(rise, sh - h)
		var hx := _sample_world(b, sx + b.spacing, sz) - _sample_world(b, sx - b.spacing, sz)
		var hz := _sample_world(b, sx, sz + b.spacing) - _sample_world(b, sx, sz - b.spacing)
		step = maxf(step, maxf(absf(hx), absf(hz)))
	if rise < 4.0 or step < 1.4:
		return 0.0
	return smoothstep(4.0, 16.0, rise) * smoothstep(1.4, 4.0, step)


func _sample_world(b: Build, x: float, z: float) -> float:
	var col := (x - b.origin.x) / b.spacing
	var row := (z - b.origin.y) / b.spacing
	if col >= 0.0 and row >= 0.0 and col <= float(b.n - 1) and row <= float(b.n - 1):
		return _bilinear(b.grid, b.n, col, row)
	return height_at(x, z)


func _normal_at(b: Build, c: int, r: int) -> Vector3:
	var hl := _h(b, c - 1, r)
	var hr := _h(b, c + 1, r)
	var hu := _h(b, c, r - 1)
	var hd := _h(b, c, r + 1)
	var dx := (hr - hl) / (2.0 * b.spacing)
	var dz := (hd - hu) / (2.0 * b.spacing)
	return Vector3(-dx, 1.0, -dz).normalized()


func _h(b: Build, c: int, r: int) -> float:
	return b.grid[clampi(r, 0, b.n - 1) * b.n + clampi(c, 0, b.n - 1)]


func _x(b: Build, c: int) -> float:
	return b.origin.x + float(c) * b.spacing


func _z(b: Build, r: int) -> float:
	return b.origin.y + float(r) * b.spacing


func _water_sample(b: Build, x: float, z: float) -> Vector2:
	if b.water_empty:
		return Vector2(9999.0, -6.0)
	var step := 500.0 / 32.0
	var fx := clampf((x - b.origin.x) / step, 0.0, 31.999)
	var fz := clampf((z - b.origin.y) / step, 0.0, 31.999)
	var c0 := int(fx)
	var r0 := int(fz)
	var tx := fx - float(c0)
	var tz := fz - float(r0)
	var d00 := b.water_d[r0 * 33 + c0]
	var d10 := b.water_d[r0 * 33 + c0 + 1]
	var d01 := b.water_d[(r0 + 1) * 33 + c0]
	var d11 := b.water_d[(r0 + 1) * 33 + c0 + 1]
	var y00 := b.water_y[r0 * 33 + c0]
	var y10 := b.water_y[r0 * 33 + c0 + 1]
	var y01 := b.water_y[(r0 + 1) * 33 + c0]
	var y11 := b.water_y[(r0 + 1) * 33 + c0 + 1]
	var dist := lerpf(lerpf(d00, d10, tx), lerpf(d01, d11, tx), tz)
	var wy := lerpf(lerpf(y00, y10, tx), lerpf(y01, y11, tx), tz)
	return Vector2(dist, wy)


func _water_field(origin: Vector2) -> Dictionary:
	var dist := PackedFloat32Array()
	var wy := PackedFloat32Array()
	dist.resize(33 * 33)
	wy.resize(33 * 33)
	dist.fill(9999.0)
	var min_x := origin.x - 60.0
	var max_x := origin.x + 560.0
	var min_z := origin.y - 60.0
	var max_z := origin.y + 560.0
	var segs: Array[int] = []
	for i in water_pts.size() - 1:
		var a := water_pts[i]
		var b := water_pts[i + 1]
		if maxf(a.x, b.x) < min_x or minf(a.x, b.x) > max_x:
			continue
		if maxf(a.z, b.z) < min_z or minf(a.z, b.z) > max_z:
			continue
		segs.append(i)
	if segs.is_empty():
		return {"d": dist, "y": wy, "empty": true}
	var step := 500.0 / 32.0
	for r in 33:
		for c in 33:
			var x := origin.x + float(c) * step
			var z := origin.y + float(r) * step
			var best_d := 9999.0
			var best_y := -6.0
			for si in segs:
				var hit := _seg_dist(x, z, water_pts[si], water_pts[si + 1])
				if hit.x < best_d:
					best_d = hit.x
					best_y = hit.y
			dist[r * 33 + c] = best_d
			wy[r * 33 + c] = best_y
	return {"d": dist, "y": wy, "empty": false}


func _seg_dist(x: float, z: float, a: Vector3, b: Vector3) -> Vector2:
	var abx := b.x - a.x
	var abz := b.z - a.z
	var len2 := abx * abx + abz * abz
	var t := 0.0
	if len2 > 0.0001:
		t = clampf(((x - a.x) * abx + (z - a.z) * abz) / len2, 0.0, 1.0)
	var dx := x - (a.x + abx * t)
	var dz := z - (a.z + abz * t)
	return Vector2(sqrt(dx * dx + dz * dz), lerpf(a.y, b.y, t))


func _split(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, indices: PackedInt32Array) -> Array:
	var parts: Array = []
	var tris := indices.size() / 3
	var start := 0
	while start < tris:
		var count := mini(TRIS_PER_PART, tris - start)
		parts.append(_compact(verts, norms, cols, indices, start, count))
		start += count
	return parts


func _compact(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, indices: PackedInt32Array, start: int, count: int) -> Dictionary:
	var remap := PackedInt32Array()
	remap.resize(verts.size())
	remap.fill(-1)
	var pv := PackedVector3Array()
	var pn := PackedVector3Array()
	var pc := PackedColorArray()
	var pi := PackedInt32Array()
	pi.resize(count * 3)
	var used := 0
	for t in count:
		var base := (start + t) * 3
		for k in 3:
			var src := indices[base + k]
			var dst := remap[src]
			if dst < 0:
				dst = used
				used += 1
				remap[src] = dst
				pv.append(verts[src])
				pn.append(norms[src])
				pc.append(cols[src])
			pi[t * 3 + k] = dst
	return {"v": pv, "n": pn, "c": pc, "i": pi}


func _job_body(host: Node3D, pay: ChunkPay) -> void:
	if pay.heights.size() != pay.map_n * pay.map_n:
		return
	var existing := host.get_node_or_null("TerrainBody") as StaticBody3D
	if existing != null:
		_retarget_body(existing, pay.heights, pay.map_n)
		return
	_add_body(host, pay.heights, pay.center, pay.map_n, pay.spacing)


func _job_part(host: Node3D, pay: ChunkPay, index: int) -> void:
	var part: Dictionary = pay.parts[index]
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = part["v"]
	arrays[Mesh.ARRAY_NORMAL] = part["n"]
	arrays[Mesh.ARRAY_COLOR] = part["c"]
	arrays[Mesh.ARRAY_INDEX] = part["i"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var inst := MeshInstance3D.new()
	inst.name = "Terrain_%d" % index
	inst.add_to_group("terrain_mesh")
	inst.mesh = mesh
	inst.material_override = _mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	host.add_child(inst)


func _add_body(host: Node3D, heights: PackedFloat32Array, center: Vector3, map_n: int, spacing: float) -> void:
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	shape.map_width = map_n
	shape.map_depth = map_n
	shape.map_data = heights
	var col := CollisionShape3D.new()
	col.shape = shape
	col.scale = Vector3(spacing, 1.0, spacing)
	col.position = center
	body.add_child(col)
	host.add_child(body)


func _retarget_body(body: StaticBody3D, heights: PackedFloat32Array, map_n: int) -> void:
	for child in body.get_children():
		if not (child is CollisionShape3D):
			continue
		var col := child as CollisionShape3D
		var shape := HeightMapShape3D.new()
		shape.map_width = map_n
		shape.map_depth = map_n
		shape.map_data = heights
		col.shape = shape
		return


## True when a 16 m block may collapse to two triangles. River blocks stay split
## so the carved channel survives. Both chunks use this, including across the seam.
func _merge_ok(b: Build, cell_c: int, cell_r: int) -> bool:
	if not _block_merged(b.dc, cell_c, cell_r):
		return false
	var rect := _block_rect(b.dc, cell_c, cell_r)
	if rect.z < rect.x:
		return false
	if _rect_hits_river(rect):
		return false
	# A road cut has to survive the 16 m collapse, on both sides of a chunk seam.
	return not _road_breaks(b, cell_c, cell_r)


## Shared by both chunks: DEM height versus the road cut, not this chunk's grid.
func _road_breaks(b: Build, cell_c: int, cell_r: int) -> bool:
	if _roads == null:
		return false
	var key := Vector2i(cell_c, cell_r)
	if b.road_break.has(key):
		return bool(b.road_break[key])
	var rect := _block_rect(b.dc, cell_c, cell_r)
	var breaks: bool = _roads.cuts_block(rect, 0.25, Callable(self, "_dem_at"))
	b.road_break[key] = breaks
	return breaks


func _dem_at(x: float, z: float) -> float:
	var cx := int(floor(x / 500.0))
	var cz := int(floor((-z) / 500.0))
	if cx < 0 or cx > 9 or cz < 0 or cz > 15:
		return -80.0
	var hi := _is_hi(cx, cz)
	var n := HI_N if hi else LOW_N
	var sp := HI_SP if hi else LOW_SP
	var grid := _heights(cx, cz, hi)
	if grid.size() != n * n:
		return -80.0
	var origin := _data_origin(cx, cz)
	var col := (x - origin.x) / sp
	var row := (z - origin.y) / sp
	if col < -0.01 or row < -0.01 or col > float(n - 1) + 0.01 or row > float(n - 1) + 0.01:
		return height_at(x, z)
	return _bilinear(grid, n, col, row)


func _edge_fine(b: Build, cell_c: int, cell_r: int, step: int) -> bool:
	if step == 4:
		return _level_at(b.dc.x, b.dc.y, cell_c, cell_r) >= 2
	return _neighbor_steep(b.dc, cell_c, cell_r)


## World rect of a 4-cell block. x = min x, y = min z, z = max x, w = max z.
## An invalid block (off the DEM) has z < x.
func _block_rect(dc: Vector2i, cell_c: int, cell_r: int) -> Vector4:
	var c := cell_c
	var r := cell_r
	var cx := dc.x
	var cz := dc.y
	if c < 0:
		cx -= 1
		c += CELLS
	elif c >= CELLS:
		cx += 1
		c -= CELLS
	if r < 0:
		cz += 1
		r += CELLS
	elif r >= CELLS:
		cz -= 1
		r -= CELLS
	if cx < 0 or cz < 0 or cx > 9 or cz > 15 or c < 0 or r < 0 or c >= CELLS or r >= CELLS:
		return Vector4(0.0, 0.0, -1.0, -1.0)
	var cell_m := 500.0 / float(CELLS)
	var x0 := float(cx) * 500.0 + float(c) * cell_m
	var z0 := -float(cz + 1) * 500.0 + float(r) * cell_m
	return Vector4(x0, z0, x0 + 4.0 * cell_m, z0 + 4.0 * cell_m)


func _rect_hits_river(rect: Vector4) -> bool:
	if water_pts.size() < 2:
		return false
	var limit := RIVER_HALF_M + 2.0
	for j in 3:
		for i in 3:
			var x := lerpf(rect.x, rect.z, float(i) * 0.5)
			var z := lerpf(rect.y, rect.w, float(j) * 0.5)
			if _water_at(x, z).x <= limit:
				return true
	return false


func _carve_bed(b: Build) -> void:
	if b.water_empty or water_pts.size() < 2:
		return
	if not _chunk_near_river(b.origin):
		return
	var pad := RIVER_HALF_M + 8.0
	var min_x := b.origin.x - pad
	var max_x := b.origin.x + 500.0 + pad
	var min_z := b.origin.y - pad
	var max_z := b.origin.y + 500.0 + pad
	var band_min_x := 1.0e12
	var band_max_x := -1.0e12
	var band_min_z := 1.0e12
	var band_max_z := -1.0e12
	var near := false
	for i in water_pts.size() - 1:
		var a: Vector3 = water_pts[i]
		var p: Vector3 = water_pts[i + 1]
		if maxf(a.x, p.x) < min_x or minf(a.x, p.x) > max_x:
			continue
		if maxf(a.z, p.z) < min_z or minf(a.z, p.z) > max_z:
			continue
		near = true
		band_min_x = minf(band_min_x, minf(a.x, p.x) - pad)
		band_max_x = maxf(band_max_x, maxf(a.x, p.x) + pad)
		band_min_z = minf(band_min_z, minf(a.z, p.z) - pad)
		band_max_z = maxf(band_max_z, maxf(a.z, p.z) + pad)
	if not near:
		return
	var n := b.n
	var c0 := clampi(int(floor((band_min_x - b.origin.x) / b.spacing)) - 1, 0, n - 1)
	var c1 := clampi(int(ceil((band_max_x - b.origin.x) / b.spacing)) + 1, 0, n - 1)
	var r0 := clampi(int(floor((band_min_z - b.origin.y) / b.spacing)) - 1, 0, n - 1)
	var r1 := clampi(int(ceil((band_max_z - b.origin.y) / b.spacing)) + 1, 0, n - 1)
	for r in range(r0, r1 + 1):
		var z := _z(b, r)
		for c in range(c0, c1 + 1):
			var x := _x(b, c)
			var hit := _water_at(x, z)
			if hit.x >= RIVER_HALF_M:
				continue
			var t := clampf(hit.x / RIVER_HALF_M, 0.0, 1.0)
			var fall := t * t * (3.0 - 2.0 * t)
			var i := r * n + c
			var original := b.grid[i]
			var target := lerpf(hit.y - BED_DEPTH_M, original, fall)
			b.grid[i] = minf(original, target)


func _chunk_near_river(origin: Vector2) -> bool:
	var samples: Array[Vector2] = [
		origin + Vector2(250.0, 250.0),
		origin,
		origin + Vector2(500.0, 0.0),
		origin + Vector2(0.0, 500.0),
		origin + Vector2(500.0, 500.0),
	]
	for p in samples:
		if _water_at(p.x, p.y).x < 420.0:
			return true
	return false


## Height at each grid point of the drawn triangles. Uncovered points keep the grid.
func _collision_from_mesh(b: Build) -> PackedFloat32Array:
	var n := b.n
	var out := b.grid.duplicate()
	if b.indices.is_empty() or n < 2:
		return out
	var seen := PackedByteArray()
	seen.resize(n * n)
	var origin := b.origin
	var sp := b.spacing
	var tris := b.indices.size() / 3
	for t in tris:
		var ia := b.indices[t * 3]
		var ib := b.indices[t * 3 + 1]
		var ic := b.indices[t * 3 + 2]
		var pa := WorldConfig.to_world(b.verts[ia])
		var pb := WorldConfig.to_world(b.verts[ib])
		var pc := WorldConfig.to_world(b.verts[ic])
		var min_x := minf(pa.x, minf(pb.x, pc.x))
		var max_x := maxf(pa.x, maxf(pb.x, pc.x))
		var min_z := minf(pa.z, minf(pb.z, pc.z))
		var max_z := maxf(pa.z, maxf(pb.z, pc.z))
		var gc0 := clampi(int(floor((min_x - origin.x) / sp)), 0, n - 1)
		var gc1 := clampi(int(ceil((max_x - origin.x) / sp)), 0, n - 1)
		var gr0 := clampi(int(floor((min_z - origin.y) / sp)), 0, n - 1)
		var gr1 := clampi(int(ceil((max_z - origin.y) / sp)), 0, n - 1)
		var denom := (pb.z - pc.z) * (pa.x - pc.x) + (pc.x - pb.x) * (pa.z - pc.z)
		if absf(denom) < 0.00000001:
			continue
		var inv := 1.0 / denom
		for r in range(gr0, gr1 + 1):
			var z := origin.y + float(r) * sp
			for c in range(gc0, gc1 + 1):
				var x := origin.x + float(c) * sp
				var wa := ((pb.z - pc.z) * (x - pc.x) + (pc.x - pb.x) * (z - pc.z)) * inv
				var wb := ((pc.z - pa.z) * (x - pc.x) + (pa.x - pc.x) * (z - pc.z)) * inv
				var wc := 1.0 - wa - wb
				if wa < -0.0002 or wb < -0.0002 or wc < -0.0002:
					continue
				var y := wa * pa.y + wb * pb.y + wc * pc.y
				var idx := r * n + c
				if seen[idx] == 0 or y > out[idx]:
					out[idx] = y
					seen[idx] = 1
	return out


func _store_drawn(coord: Vector2i, heights: PackedFloat32Array, n: int, spacing: float) -> void:
	if heights.is_empty() or n < 2:
		return
	var rec := {
		"h": heights,
		"n": n,
		"sp": spacing,
		"o": WorldConfig.chunk_origin(coord),
	}
	_lock.lock()
	_drawn["%d_%d" % [coord.x, coord.y]] = rec
	_lock.unlock()


## Height of the drawn ground. Falls back to the coarse DEM before the chunk is built.
func drawn_height_at(x: float, z: float) -> float:
	var coord := WorldConfig.chunk_of(x, z)
	var key := "%d_%d" % [coord.x, coord.y]
	_lock.lock()
	var has: bool = _drawn.has(key)
	var rec: Dictionary = _drawn.get(key, {})
	_lock.unlock()
	if not has:
		return height_at(x, z)
	var o: Vector2 = rec["o"]
	var sp: float = rec["sp"]
	var n: int = int(rec["n"])
	var grid: PackedFloat32Array = rec["h"]
	var col := (x - o.x) / sp
	var row := (z - o.y) / sp
	if col < 0.0 or row < 0.0 or col > float(n - 1) or row > float(n - 1):
		return height_at(x, z)
	return _bilinear(grid, n, col, row)


## Spawn and respawn stay off the ribbon and above the water surface.
func dry_ground(x: float, z: float, fallback_y: float) -> Vector3:
	if _on_dry_ground(x, z):
		var h := height_at(x, z)
		var y := h + 0.2 if h > -70.0 else fallback_y
		return Vector3(x, y, z)
	var anchor := _water_anchor(x, z)
	var away := Vector2(x - anchor.x, z - anchor.z)
	if away.length_squared() < 1.0:
		away = Vector2(0.0, 1.0)
	else:
		away = away.normalized()
	for extra in [3.0, 8.0, 16.0, 28.0, 48.0]:
		var sx := anchor.x + away.x * (RIVER_HALF_M + float(extra))
		var sz := anchor.z + away.y * (RIVER_HALF_M + float(extra))
		if _on_dry_ground(sx, sz):
			var bank := height_at(sx, sz)
			return Vector3(sx, bank + 0.2, sz)
	return canyon_stand()


func _on_dry_ground(x: float, z: float) -> bool:
	if water_pts.size() < 2:
		return true
	var w := _water_at(x, z)
	if w.x <= RIVER_HALF_M + 0.75:
		return false
	var h := height_at(x, z)
	if h < -70.0:
		return true
	return h >= w.y - 0.2


func _water_anchor(x: float, z: float) -> Vector3:
	var best_d := 9999.0
	var best := Vector3(x, -6.0, z)
	var n := water_pts.size()
	for i in n - 1:
		var a: Vector3 = water_pts[i]
		var p: Vector3 = water_pts[i + 1]
		var abx := p.x - a.x
		var abz := p.z - a.z
		var len2 := abx * abx + abz * abz
		var t := 0.0
		if len2 > 0.0001:
			t = clampf(((x - a.x) * abx + (z - a.z) * abz) / len2, 0.0, 1.0)
		var px := a.x + abx * t
		var pz := a.z + abz * t
		var d := sqrt((x - px) * (x - px) + (z - pz) * (z - pz))
		if d < best_d:
			best_d = d
			best = Vector3(px, lerpf(a.y, p.y, t), pz)
	return best


func _index_water() -> void:
	_wbuckets.clear()
	var n := water_pts.size()
	for i in n - 1:
		var a: Vector3 = water_pts[i]
		var p: Vector3 = water_pts[i + 1]
		var min_x := int(floor(minf(a.x, p.x) / WATER_CELL)) - 1
		var max_x := int(floor(maxf(a.x, p.x) / WATER_CELL)) + 1
		var min_z := int(floor(minf(a.z, p.z) / WATER_CELL)) - 1
		var max_z := int(floor(maxf(a.z, p.z) / WATER_CELL)) + 1
		for gz in range(min_z, max_z + 1):
			for gx in range(min_x, max_x + 1):
				var key := Vector2i(gx, gz)
				var packed: PackedInt32Array = _wbuckets.get(key, PackedInt32Array())
				packed.append(i)
				_wbuckets[key] = packed


func _water_at(x: float, z: float) -> Vector2:
	if water_pts.size() < 2:
		return Vector2(9999.0, -6.0)
	if _wbuckets.is_empty():
		return water_nearest(x, z)
	var best_d := 9999.0
	var best_y := -6.0
	var gx := int(floor(x / WATER_CELL))
	var gz := int(floor(z / WATER_CELL))
	var n := water_pts.size() - 1
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var packed: PackedInt32Array = _wbuckets.get(Vector2i(gx + dx, gz + dz), PackedInt32Array())
			for i in packed:
				if i < 0 or i >= n:
					continue
				var hit := _seg_dist(x, z, water_pts[i], water_pts[i + 1])
				if hit.x < best_d:
					best_d = hit.x
					best_y = hit.y
	return Vector2(best_d, best_y)


## Vertical error of one quad against the samples. The split matches _quad (diagonal NW-SE).
func _grid_quad_error(grid: PackedFloat32Array, n: int, c0: int, r0: int, c1: int, r1: int) -> float:
	var dc := float(c1 - c0)
	var dr := float(r1 - r0)
	if dc < 1.0 or dr < 1.0:
		return 0.0
	var h00 := grid[r0 * n + c0]
	var h10 := grid[r0 * n + c1]
	var h01 := grid[r1 * n + c0]
	var h11 := grid[r1 * n + c1]
	var worst := 0.0
	for r in range(r0, r1 + 1):
		var tz := float(r - r0) / dr
		var row := r * n
		for c in range(c0, c1 + 1):
			var tx := float(c - c0) / dc
			var h: float = grid[row + c]
			var plane: float
			if tx >= tz:
				plane = (1.0 - tx) * h00 + (tx - tz) * h10 + tz * h11
			else:
				plane = (1.0 - tz) * h00 + tx * h11 + (tz - tx) * h01
			worst = maxf(worst, absf(h - plane))
	return worst


func _block_merged(dc: Vector2i, c: int, r: int) -> bool:
	var ncx := dc.x
	var ncz := dc.y
	if c < 0:
		ncx -= 1
		c += CELLS
	elif c >= CELLS:
		ncx += 1
		c -= CELLS
	if r < 0:
		ncz += 1
		r += CELLS
	elif r >= CELLS:
		ncz -= 1
		r -= CELLS
	if ncx < 0 or ncz < 0 or ncx > 9 or ncz > 15:
		return true
	if c % 4 != 0 or r % 4 != 0:
		return false
	var levels := _levels_for(ncx, ncz)
	for dy in 4:
		for dx in 4:
			if levels[(r + dy) * CELLS + (c + dx)] != 0:
				return false
	for dy in range(-1, 5):
		for dx in range(-1, 5):
			if dx >= 0 and dx <= 3 and dy >= 0 and dy <= 3:
				continue
			if _level_at(ncx, ncz, c + dx, r + dy) != 0:
				return false
	return true


func _level_at(cx: int, cz: int, c: int, r: int) -> int:
	if c < 0:
		cx -= 1
		c += CELLS
	elif c >= CELLS:
		cx += 1
		c -= CELLS
	if r < 0:
		cz += 1
		r += CELLS
	elif r >= CELLS:
		cz -= 1
		r -= CELLS
	if cx < 0 or cz < 0 or cx > 9 or cz > 15:
		return 0
	var levels := _levels_for(cx, cz)
	return int(levels[r * CELLS + c])


func _levels_for(cx: int, cz: int) -> PackedByteArray:
	var key := "lv_%d_%d" % [cx, cz]
	_lock.lock()
	if _cache.has(key):
		var hit: PackedByteArray = _cache[key]
		_lock.unlock()
		return hit
	_lock.unlock()
	var levels := PackedByteArray()
	levels.resize(CELLS * CELLS)
	if cx < 0 or cz < 0 or cx > 9 or cz > 15:
		return levels
	var dc := Vector2i(cx, cz)
	for r in CELLS:
		for c in CELLS:
			if _is_cell_steep(cx, cz, c, r):
				levels[r * CELLS + c] = 2
	for r2 in CELLS:
		for c2 in CELLS:
			if levels[r2 * CELLS + c2] != 0:
				continue
			if _neighbor_steep(dc, c2, r2 - 1) or _neighbor_steep(dc, c2, r2 + 1) or _neighbor_steep(dc, c2 - 1, r2) or _neighbor_steep(dc, c2 + 1, r2):
				levels[r2 * CELLS + c2] = 1
	# Open floor whose 4 m quad would skip a dip or hump. Cliffs are already level 2.
	# An open cap cannot trip, so skip the scan.
	if _is_hi(cx, cz) and FLAT_ERR_M < 50.0:
		var grid := _heights(cx, cz, true)
		if grid.size() == HI_N * HI_N:
			for r3 in CELLS:
				for c3 in CELLS:
					if levels[r3 * CELLS + c3] != 0:
						continue
					if _grid_quad_error(grid, HI_N, c3 * 4, r3 * 4, c3 * 4 + 4, r3 * 4 + 4) > FLAT_ERR_M:
						levels[r3 * CELLS + c3] = 2
	_lock.lock()
	_cache[key] = levels
	_lock.unlock()
	return levels


func _neighbor_steep(dc: Vector2i, cell_x: int, cell_y: int) -> bool:
	var cx := dc.x
	var cz := dc.y
	if cell_x < 0:
		cx -= 1
		cell_x += CELLS
	elif cell_x >= CELLS:
		cx += 1
		cell_x -= CELLS
	if cell_y < 0:
		cz += 1
		cell_y += CELLS
	elif cell_y >= CELLS:
		cz -= 1
		cell_y -= CELLS
	return _is_cell_steep(cx, cz, cell_x, cell_y)


func _is_cell_steep(cx: int, cz: int, cell_x: int, cell_y: int) -> bool:
	if cx < 0 or cz < 0 or cx > 9 or cz > 15:
		return false
	if cell_x < 0 or cell_y < 0 or cell_x >= CELLS or cell_y >= CELLS:
		return false
	if not _is_hi(cx, cz):
		return false
	var mask := _steep_mask(cx, cz)
	return mask[cell_y * CELLS + cell_x] != 0


func _steep_mask(cx: int, cz: int) -> PackedByteArray:
	var key := "s_%d_%d" % [cx, cz]
	_lock.lock()
	if _cache.has(key):
		var hit: PackedByteArray = _cache[key]
		_lock.unlock()
		return hit
	_lock.unlock()
	var grid := _heights(cx, cz, true)
	var mask := PackedByteArray()
	mask.resize(CELLS * CELLS)
	if grid.size() != HI_N * HI_N:
		return mask
	for cy in CELLS:
		var r0 := cy * 4
		for cx2 in CELLS:
			var c0 := cx2 * 4
			var steep := false
			var hmin := 10000.0
			var hmax := -10000.0
			for r in range(r0, r0 + 5):
				var row := r * HI_N
				for c in range(c0, c0 + 5):
					var h := grid[row + c]
					hmin = minf(hmin, h)
					hmax = maxf(hmax, h)
					if c < c0 + 4 and absf(grid[row + c + 1] - h) > 1.35:
						steep = true
					if r < r0 + 4 and absf(grid[(r + 1) * HI_N + c] - h) > 1.35:
						steep = true
			if hmax - hmin > 6.0:
				steep = true
			if steep:
				mask[cy * CELLS + cx2] = 1
	_lock.lock()
	_cache[key] = mask
	_lock.unlock()
	return mask


func _is_hi(cx: int, cz: int) -> bool:
	if SKIP_HI.has("%d_%d" % [cx, cz]):
		return false
	return _hi.has("%d_%d" % [cx, cz])


func _data_of(coord: Vector2i) -> Vector2i:
	var cz := -coord.y - 1
	if coord.x < 0 or coord.x > 9 or cz < 0 or cz > 15:
		return Vector2i(-1, -1)
	return Vector2i(coord.x, cz)


func _center_of(coord: Vector2i) -> Vector3:
	var o := WorldConfig.chunk_origin(coord)
	return Vector3(o.x + 250.0, 0.0, o.y + 250.0)


func _data_origin(cx: int, cz: int) -> Vector2:
	return Vector2(float(cx) * 500.0, -float(cz + 1) * 500.0)


func _bilinear(grid: PackedFloat32Array, n: int, col: float, row: float) -> float:
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


func _heights(cx: int, cz: int, hi: bool) -> PackedFloat32Array:
	var key := "%d_%d_%d" % [cx, cz, int(hi)]
	_lock.lock()
	if _cache.has(key):
		var hit: PackedFloat32Array = _cache[key]
		_lock.unlock()
		return hit
	_lock.unlock()
	var folder := "tiles_hi" if hi else "tiles"
	var decoded := _decode_png("%s/%s/c_%d_%d.png" % [DATA, folder, cx, cz])
	_lock.lock()
	_cache[key] = decoded
	_lock.unlock()
	return decoded


func _decode_png(path: String) -> PackedFloat32Array:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("Missing height tile %s" % path)
		return PackedFloat32Array()
	var pos := 8
	var idat := PackedByteArray()
	var w := 0
	var h := 0
	while pos + 12 <= bytes.size():
		var length := _be32(bytes, pos)
		var kind := bytes.slice(pos + 4, pos + 8).get_string_from_ascii()
		if kind == "IHDR":
			w = _be32(bytes, pos + 8)
			h = _be32(bytes, pos + 12)
		elif kind == "IDAT":
			idat.append_array(bytes.slice(pos + 8, pos + 8 + length))
		elif kind == "IEND":
			break
		pos += 12 + length
	var raw_size := h * (1 + w * 2)
	var raw := idat.decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != raw_size:
		push_error("Height tile %s inflated %d, expected %d." % [path, raw.size(), raw_size])
		return PackedFloat32Array()
	return _unfilter(raw, w, h)


func _unfilter(raw: PackedByteArray, w: int, h: int) -> PackedFloat32Array:
	var stride := w * 2
	var prev := PackedByteArray()
	prev.resize(stride)
	var out := PackedFloat32Array()
	out.resize(w * h)
	var row_bytes := stride + 1
	for y in h:
		var filter := raw[y * row_bytes]
		var cur := PackedByteArray()
		cur.resize(stride)
		for i in stride:
			var x := int(raw[y * row_bytes + 1 + i])
			var a := int(cur[i - 2]) if i >= 2 else 0
			var b := int(prev[i])
			var c := int(prev[i - 2]) if i >= 2 else 0
			var val := x
			if filter == 1:
				val = (x + a) & 255
			elif filter == 2:
				val = (x + b) & 255
			elif filter == 3:
				val = (x + ((a + b) >> 1)) & 255
			elif filter == 4:
				val = (x + _paeth(a, b, c)) & 255
			cur[i] = val
		prev = cur
		var row := y * w
		for x2 in w:
			var sample := (int(cur[x2 * 2]) << 8) | int(cur[x2 * 2 + 1])
			out[row + x2] = float(sample) * 0.01 - 50.0
	return out


func _paeth(a: int, b: int, c: int) -> int:
	var p := a + b - c
	var pa := absi(p - a)
	var pb := absi(p - b)
	var pc := absi(p - c)
	if pa <= pb and pa <= pc:
		return a
	if pb <= pc:
		return b
	return c


func _be32(b: PackedByteArray, i: int) -> int:
	return (int(b[i]) << 24) | (int(b[i + 1]) << 16) | (int(b[i + 2]) << 8) | int(b[i + 3])


func _load_meta() -> void:
	var canyon: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA + "/canyon_chunks.json"))
	if canyon is Dictionary:
		for item in (canyon as Dictionary).get("chunks", []):
			if item is Dictionary:
				var key := "%d_%d" % [int(item["cx"]), int(item["cz"])]
				_hi[key] = true
	var spawned: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA + "/spawn.json"))
	if spawned is Dictionary:
		var s: Dictionary = (spawned as Dictionary).get("spawn", {})
		spawn = Vector3(float(s["x"]), float(s["y"]), float(s["godot_z"]))
		if s.has("yaw_deg"):
			spawn_yaw = deg_to_rad(float(s["yaw_deg"]))
	var water: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA + "/water.json"))
	if water is Dictionary:
		for item2 in (water as Dictionary).get("vertices", []):
			if item2 is Dictionary:
				water_pts.append(Vector3(float(item2["x"]), float(item2["y"]), float(item2["godot_z"])))
	_index_water()
