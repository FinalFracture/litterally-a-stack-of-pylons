class_name TfRoadBuilder
extends RefCounted

## Twin Falls roads, rail, street signs and landmark models, one chunk at a time.
## prepare() is main-thread. apply_cuts() and build_chunk() only read that data,
## so the terrain worker may call them. jobs() runs on the main thread and puts
## one mesh, one collision body, the signs and the landmark instances under host.
##
## One pipeline from roads.json. The profile is smoothed inside the class grade
## cap, then each junction gets one plane (tilt clamped) and the roads blend
## into it. Ordinary segments, including the Perrine approach slabs, stamp the
## strategy-11 seam: a 2 m bench at the road-edge height, then a 4 m linear
## blend back to the lidar. A cut or fill deeper than that walkable lip keeps
## the engineered face after it (soil 2:1, rock 0.25:1, fill 1.5:1). No ditch
## and no junction disc. The ribbon sits 0.02 m above the carriageway. Collision
## is the same plane flared past the paint. The bridge span itself is not stamped.
## The terrain mesh draws the bench and the blend at about 1 m. A 4 m quad
## cannot show that shoulder, which is why the stamp alone does not read.
## The mesh reads that stamp. It does not search the segments again per vertex.

const DATA := "res://world/twin_falls/data"
const BUCKET := 64.0
const BLEND_M := 4.0
## Strategy 11. Flat ground at the road edge, then the linear blend above.
## A lip steeper than this over those 4 m is not walkable, so the rest of a
## deep cut or fill uses the engineered face.
const BENCH_M := 2.0
const SEAM_GRADE := 0.90
## Visual carriageway sits at the pave height until this far inside the paint,
## so the shoulder quad does not dip into the 0.5 m bed beside the ribbon.
const VISUAL_BED_INSET_M := 1.2
const SHAVE_M := 0.02
const LIFT_M := 0.03
## Ribbon above the graded heightfield. Deck, bridge, and the last 4 m of an
## approach (blended) stay at DECK_LIFT_M so the joint is flush.
const SURFACE_LIFT := 0.02
## Collision extends past the paint and across the centre seam. The visual edge
## stays on the paint line. A zero-margin ray on that line misses the triangle.
const FLARE_M := 0.40
const SEAM_M := 0.25
const ALONG_M := 0.20
## Junction blend. Each vertex may change grade by this much, which is the
## along-step the report measures between 1 m samples.
const BLEND_LIP := 0.008
const BLEND_GRADE := 0.16
const BLEND_WINDOW := 120.0
## Two discs closer than this share one vertical curve. Curvature stays under
## the 0.02 m along-step the report measures on 1 m samples.
const GAP_MAX_M := 24.0
const GAP_CURV := 0.016
## Guard only once the drop inside 3 m would fail the report. Gentler ground stays open.
const BARRIER_DROP_M := 2.5
## A cliff this steep is basalt, not walkable talus. Soil cuts stay at 2:1.
const ROCK_DEG := 46.0
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
## Legacy cut 1.5:1. Approach fill skirts stay 2:1. The ordinary stamp uses
## 1.5:1 fill, 2:1 soil and 0.25:1 rock, and reaches a deep canyon cut.
const CUT_H_PER_V := 1.5
const FILL_H_PER_V := 2.0
const STAMP_FILL_H := 1.5
const SOIL_CUT_H := 2.0
const ROCK_CUT_H := 0.25
const EARTH_REACH_M := 56.0
const CUT_CLEAR_M := 0.08
## Keep the terrain bed below the driving surface so the asphalt owns the
## collision and no heightfield triangle can poke through it.
const ROAD_BED_DEPTH_M := 0.5
## Flat cut past the paint. A 4 m terrain quad that straddles the edge would
## otherwise tilt up through the asphalt. The 1.5:1 slope starts outside this.
const SHOULDER_M := 6.5
## Deck-approach parapet. Sits just outside the paint and runs into the abutment.
const PARA_H := 0.80
const PARA_T := 0.32
const ABUT_HALF := 9.85
const APPROACH_FILL_M := 360.0
## Keep the parapet until stepping off the edge is a short drop.
const PARA_DROP_M := 0.5
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
## A lane drop or a class widening tapers over at least this run.
const TAPER_M := 30.0
## Map-edge exit. The cone is pushed past the last vertex, so the carriageway
## has to continue on solid ground. A berm closes the end.
const EXIT_PAD_M := 18.0
const EXIT_BERM_M := 15.5
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
## Unstamped ground outside the chunk being built. Guards need the neighbour
## canyon, which this chunk's grid clamps away.
var _dem: Callable = Callable()
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


## Stamp every segment except deck, bridge, and rail. Those only lower.
## `lift` is optional. When the caller has resized it to n*n, a 1 marks a
## winning write in the outer metre of the paint, where the mesh sits at the
## pave height and the collision grid keeps the 0.5 m bed. Empty skips that.
func apply_cuts(grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, lift: PackedByteArray) -> void:
	if n < 2 or grid.size() != n * n or _edges.is_empty():
		return
	var orig := grid.duplicate()
	var lock := PackedByteArray()
	lock.resize(n * n)
	var best := PackedFloat32Array()
	best.resize(n * n)
	best.fill(100000.0)
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
				_cut_edge(grid, orig, lock, best, lift, origin, n, spacing, _edges[ei])


## 1 m carriageway stamp. The coarse heightfield is upsampled first; this only
## rewrites the paint, so the 56 m earthwork is not scanned again.
func apply_paint(grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	if n < 2 or grid.size() != n * n or _edges.is_empty():
		return
	var best := PackedFloat32Array()
	best.resize(n * n)
	best.fill(100000.0)
	var lock := PackedByteArray()
	lock.resize(n * n)
	var seen := {}
	var reach := 16.0
	var x0 := origin.x - reach
	var z0 := origin.y - reach
	var x1 := origin.x + 500.0 + reach
	var z1 := origin.y + 500.0 + reach
	for gz in range(int(floor(z0 / BUCKET)), int(floor(z1 / BUCKET)) + 1):
		for gx in range(int(floor(x0 / BUCKET)), int(floor(x1 / BUCKET)) + 1):
			var packed: PackedInt32Array = _buckets.get(Vector2i(gx, gz), PackedInt32Array())
			for ei in packed:
				if seen.has(ei):
					continue
				seen[ei] = true
				_paint_edge(grid, best, lock, origin, n, spacing, _edges[ei])


func _paint_edge(grid: PackedFloat32Array, best: PackedFloat32Array, lock: PackedByteArray, origin: Vector2, n: int, spacing: float, edge: Dictionary) -> void:
	if bool(edge.get("skip", false)):
		return
	var ax := float(edge["ax"])
	var az := float(edge["az"])
	var bx := float(edge["bx"])
	var bz := float(edge["bz"])
	var band := float(edge["half"]) + BENCH_M + 0.5
	var min_x := minf(ax, bx) - band
	var max_x := maxf(ax, bx) + band
	var min_z := minf(az, bz) - band
	var max_z := maxf(az, bz) + band
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
			var half_w := lerpf(float(edge.get("ha", edge["half"])), float(edge.get("hb", edge["half"])), hit.y)
			if hit.x > half_w + BENCH_M:
				continue
			var i := row + c
			if lock[i] == 1 and hit.x >= best[i] - 0.001:
				continue
			var y := _paint_height(edge, hit.x, hit.y, hit.z, x, z)
			if y < -70.0:
				continue
			if hit.x <= half_w:
				y -= ROAD_BED_DEPTH_M
			best[i] = hit.x
			grid[i] = y
			lock[i] = 1


## Cells whose centres sit in the bench or the blend. Includes a one-cell halo
## so a neighbour chunk can fan the shared edge. Keys are Vector2i cell coords
## in this chunk's 128-cell grid, from -1 to 128.
func mark_seam_cells(origin: Vector2) -> Dictionary:
	var out := {}
	if _edges.is_empty():
		return out
	var cell := 500.0 / 128.0
	var pad := 20.0
	var x0 := origin.x - pad
	var z0 := origin.y - pad
	var x1 := origin.x + 500.0 + pad
	var z1 := origin.y + 500.0 + pad
	var seen := {}
	var gz0 := int(floor(z0 / BUCKET))
	var gz1 := int(floor(z1 / BUCKET))
	var gx0 := int(floor(x0 / BUCKET))
	var gx1 := int(floor(x1 / BUCKET))
	for gz in range(gz0, gz1 + 1):
		for gx in range(gx0, gx1 + 1):
			var packed: PackedInt32Array = _buckets.get(Vector2i(gx, gz), PackedInt32Array())
			for ei in packed:
				if seen.has(ei):
					continue
				seen[ei] = true
				var edge: Dictionary = _edges[ei]
				if bool(edge.get("skip", false)):
					continue
				_mark_edge_cells(out, edge, origin, cell)
	return out


func _mark_edge_cells(out: Dictionary, edge: Dictionary, origin: Vector2, cell: float) -> void:
	var half := maxf(float(edge.get("ha", edge["half"])), float(edge.get("hb", edge["half"])))
	var band := half + maxf(float(edge.get("sh", 0.0)), BENCH_M) + BLEND_M + cell * 0.75
	var ax := float(edge["ax"])
	var az := float(edge["az"])
	var bx := float(edge["bx"])
	var bz := float(edge["bz"])
	var c0 := clampi(int(floor((minf(ax, bx) - band - origin.x) / cell)), -1, 128)
	var c1 := clampi(int(floor((maxf(ax, bx) + band - origin.x) / cell)), -1, 128)
	var r0 := clampi(int(floor((minf(az, bz) - band - origin.y) / cell)), -1, 128)
	var r1 := clampi(int(floor((maxf(az, bz) + band - origin.y) / cell)), -1, 128)
	for r in range(r0, r1 + 1):
		var z := origin.y + (float(r) + 0.5) * cell
		for c in range(c0, c1 + 1):
			var x := origin.x + (float(c) + 0.5) * cell
			var hit := _seg_side(x, z, ax, az, bx, bz)
			if hit.x <= band:
				out[Vector2i(c, r)] = true


## One pass of the bench and the blend onto a 1 m grid the caller already sized.
## `heights` stores the visual surface: the outer metre of the paint stays at
## the pave height, and the rest of the carriageway keeps the 0.5 m bed.
## `wrote` is 1 where a stamp claimed the cell. `lift` is 1 only in that outer
## metre, so collision can subtract the bed without dipping the shoulder quad.
## Reach stays on the shoulder. The 56 m earthwork is already in the coarse grid.
## Lock rules match _cut_edge: paint nearest-wins, then the shoulder, then a
## cut lowers and a fill raises only ground that has not been cut.
func stamp_seam_band(heights: PackedFloat32Array, wrote: PackedByteArray, lift: PackedByteArray, origin: Vector2, n: int, spacing: float) -> void:
	if n < 2 or heights.size() != n * n or wrote.size() != n * n or lift.size() != n * n or _edges.is_empty():
		return
	var lock := PackedByteArray()
	lock.resize(n * n)
	var best := PackedFloat32Array()
	best.resize(n * n)
	best.fill(100000.0)
	var known := PackedByteArray()
	known.resize(n * n)
	var origs := PackedFloat32Array()
	origs.resize(n * n)
	var seen := {}
	var pad := 24.0
	var gz0 := int(floor((origin.y - pad) / BUCKET))
	var gz1 := int(floor((origin.y + 500.0 + pad) / BUCKET))
	var gx0 := int(floor((origin.x - pad) / BUCKET))
	var gx1 := int(floor((origin.x + 500.0 + pad) / BUCKET))
	for gz in range(gz0, gz1 + 1):
		for gx in range(gx0, gx1 + 1):
			var packed: PackedInt32Array = _buckets.get(Vector2i(gx, gz), PackedInt32Array())
			for ei in packed:
				if seen.has(ei):
					continue
				seen[ei] = true
				_stamp_band_edge(heights, wrote, lift, lock, best, known, origs, origin, n, spacing, _edges[ei])


func _stamp_band_edge(heights: PackedFloat32Array, wrote: PackedByteArray, lift: PackedByteArray, lock: PackedByteArray, best: PackedFloat32Array, known: PackedByteArray, origs: PackedFloat32Array, origin: Vector2, n: int, spacing: float, edge: Dictionary) -> void:
	if bool(edge.get("skip", false)):
		return
	var ax := float(edge["ax"])
	var az := float(edge["az"])
	var bx := float(edge["bx"])
	var bz := float(edge["bz"])
	var half_max := maxf(float(edge.get("ha", edge["half"])), float(edge.get("hb", edge["half"])))
	var band := half_max + maxf(float(edge.get("sh", 0.0)), BENCH_M) + BLEND_M + spacing
	var c0 := clampi(int(floor((minf(ax, bx) - band - origin.x) / spacing)), 0, n - 1)
	var c1 := clampi(int(ceil((maxf(ax, bx) + band - origin.x) / spacing)), 0, n - 1)
	var r0 := clampi(int(floor((minf(az, bz) - band - origin.y) / spacing)), 0, n - 1)
	var r1 := clampi(int(ceil((maxf(az, bz) + band - origin.y) / spacing)), 0, n - 1)
	var rock := bool(edge.get("rock", false))
	for r in range(r0, r1 + 1):
		var z := origin.y + float(r) * spacing
		var row := r * n
		for c in range(c0, c1 + 1):
			var x := origin.x + float(c) * spacing
			var hit := _seg_side(x, z, ax, az, bx, bz)
			var half_w := lerpf(float(edge.get("ha", edge["half"])), float(edge.get("hb", edge["half"])), hit.y)
			var reach := half_w + maxf(float(edge.get("sh", 0.0)), BENCH_M) + BLEND_M + spacing
			if hit.x > reach:
				continue
			if _past_bridge_end(x, z, ax, az, bx, bz):
				continue
			var i := row + c
			var orig := _band_orig(known, origs, i, x, z)
			if orig < -70.0:
				continue
			var stamp := _stamp_at(edge, hit.x, hit.y, hit.z, orig, rock, spacing, x, z)
			if stamp.z < 0.5:
				continue
			var shown := _shown_y(stamp.x, hit.x, half_w)
			if stamp.y > 0.5:
				var on_paint := hit.x <= half_w + maxf(spacing, 1.0)
				if on_paint:
					if lock[i] != 2 or hit.x < best[i] - 0.001:
						best[i] = hit.x
						heights[i] = shown
						lock[i] = 2
						wrote[i] = 1
						lift[i] = _inset_lift(hit.x, half_w)
					continue
				if lock[i] == 2:
					continue
				if hit.x < best[i] - 0.001:
					if lock[i] == 1 and shown < heights[i] - 0.05:
						continue
					best[i] = hit.x
					heights[i] = shown
					lock[i] = 1
					wrote[i] = 1
					lift[i] = _inset_lift(hit.x, half_w)
				continue
			if lock[i] != 0:
				continue
			var cur := orig
			if wrote[i] == 1:
				cur = heights[i]
			if shown < orig - 0.001:
				if wrote[i] == 0 or heights[i] > shown:
					heights[i] = shown
					wrote[i] = 1
					lift[i] = 0
			elif shown > orig + 0.001 and cur >= orig - 0.001 and cur < shown:
				heights[i] = shown
				wrote[i] = 1
				lift[i] = 0


func _band_orig(known: PackedByteArray, origs: PackedFloat32Array, i: int, x: float, z: float) -> float:
	if known[i] == 1:
		return origs[i]
	var y := -80.0
	if _dem.is_valid():
		y = float(_dem.call(x, z))
	known[i] = 1
	origs[i] = y
	return y


## Visual carriageway. The bed is kept only inside the paint, past the inset,
## so the quad beside the ribbon stays at the road-edge height.
func _shown_y(raw: float, dist: float, half_w: float) -> float:
	if dist <= half_w - VISUAL_BED_INSET_M:
		return raw - ROAD_BED_DEPTH_M
	return raw


func _inset_lift(dist: float, half_w: float) -> int:
	if dist <= half_w and dist > half_w - VISUAL_BED_INSET_M:
		return 1
	return 0


## Crowned surface, or the junction plane where the carriageways share one.
func _paint_height(edge: Dictionary, dist: float, t: float, side: float, x: float, z: float) -> float:
	var half := lerpf(float(edge.get("ha", edge["half"])), float(edge.get("hb", edge["half"])), t)
	var cy := lerpf(float(edge["ay"]), float(edge["by"]), t)
	var ax := float(edge["ax"])
	var az := float(edge["az"])
	var bx := float(edge["bx"])
	var bz := float(edge["bz"])
	var px := lerpf(ax, bx, t)
	var pz := lerpf(az, bz, t)
	for item in _junctions:
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var rad := float(item.get("radius", 8.0)) + half + 0.4
		if Vector2(px - float(pos[0]), pz - float(pos[2])).length() > rad:
			continue
		if Vector2(x - float(pos[0]), z - float(pos[2])).length() > rad:
			continue
		if dist <= half:
			return _plane_at(item, x, z)
		var dx := bx - ax
		var dz := bz - az
		var length := Vector2(dx, dz).length()
		if length > 0.001:
			var edge_x := px - dz / length * side * half
			var edge_z := pz + dx / length * side * half
			return _plane_at(item, edge_x, edge_z)
		return _plane_at(item, x, z)
	var bank := lerpf(float(edge.get("ba", 0.0)), float(edge.get("bb", 0.0)), t)
	var drop := lerpf(float(edge.get("ca", 0.0)), float(edge.get("cb", 0.0)), t)
	var sec := _section(cy, bank, drop, half)
	var edge_y := sec.x if side > 0.0 else sec.z
	if dist <= half and half > 0.01:
		return lerpf(sec.y, edge_y, dist / half)
	return edge_y


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
	_emit_exits(coord, faces)
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
	var lane_w := float(item.get("lane_width_m", 3.35))
	var width := lane_w * float(maxi(lanes, 1))
	if rail:
		lanes = 0
		lane_w = 0.0
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
	var rid := str(item.get("id", ""))
	if not rail and not _approach_road(rid) and rid != "us93_perrine_bridge":
		var dense := _densify(pts, kinds, 4.0)
		pts = dense[0] as PackedVector3Array
		kinds = dense[1] as PackedStringArray
	var miters := _miters(pts, half)
	var chain := PackedFloat32Array()
	chain.resize(pts.size())
	var walked := 0.0
	for i in range(1, pts.size()):
		walked += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		chain[i] = walked
	var cls := str(item.get("class", ""))
	var rec := {
		"id": str(item.get("id", "")),
		"half": half,
		"lane_w": lane_w,
		"lanes": lanes,
		"pts": pts,
		"left": miters[0],
		"right": miters[1],
		"chain": chain,
		"kind": kinds,
		"rail": rail,
		"advisory": _advisory_of(item, pts.size() - 1),
		"class": cls,
		"cap": _class_cap(cls),
		"shoulder": _class_shoulder(cls),
		"ditch": _class_ditch(cls),
	}
	var ri := _roads.size()
	_roads.append(rec)
	_by_id[rec["id"]] = ri
	var nm = item.get("name")
	if nm is String and nm != "":
		_name_of[rec["id"]] = nm
	for i in pts.size() - 1:
		var edge := {
			"road": str(rec["id"]),
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
	var prev := pts[pts.size() - 2] if pts.size() >= 2 else end + Vector3(0.0, 0.0, 1.0)
	var heading := Vector2(end.x - prev.x, end.z - prev.z)
	if heading.length() < 0.5:
		heading = Vector2(0.0, -1.0)
	else:
		heading = heading.normalized()
	var target := Vector2(RAMP_TOP.x, RAMP_TOP.z)
	var total := maxf(target.distance_to(Vector2(end.x, end.z)), 1.0)
	var out := pts.duplicate()
	# Hold the last heading through the joint. A dogleg there twists the
	# cross-section and the across-step fails at the ramp end.
	var cursor := Vector2(end.x, end.z)
	var walked := 0.0
	var guard := 0
	while guard < 48:
		guard += 1
		var to := target - cursor
		var remain := to.length()
		if remain < 6.0:
			break
		var step := minf(8.0, remain)
		var dir := heading
		if walked >= 24.0:
			dir = dir.lerp(to / remain, 0.22).normalized()
			heading = dir
		cursor += dir * step
		walked += step
		var p := Vector3(cursor.x, lerpf(end.y, RAMP_TOP.y, clampf(walked / total, 0.0, 1.0)), cursor.y)
		out.append(p)
	var tail: Vector3 = out[out.size() - 1]
	if Vector2(tail.x - RAMP_TOP.x, tail.z - RAMP_TOP.z).length() > 1.0:
		out.append(RAMP_TOP)
	else:
		out[out.size() - 1] = RAMP_TOP
	return out


## Junction heights, the 10% cap, one plane per junction, crown/bank, then cuts.
func _finish_profiles() -> void:
	_match_junctions()
	for road in _roads:
		_cap_grade(road)
	for item in _junctions:
		item["flat_y"] = _major_y(item)
	_assign_junction_planes()
	_blend_junctions()
	_apply_tapers()
	for road in _roads:
		_store_bank(road)
	_rebuild_edges()
	_find_crossings()


## Best-fit plane through the junction, tilt clamped. Bridge ends stay horizontal
## at the deck so the span and the patch are the same plane.
func _assign_junction_planes() -> void:
	for item in _junctions:
		var limit := 0.02
		if _junction_grade(item) >= 0.06:
			limit = 0.03
		item["tilt_lim"] = limit
		# Follow the major road, clamped. A flat disc between two close junctions
		# at different heights cannot ease within the along-step limit.
		if _bridge_joint(item) or _junction_turn(item) > 25.0:
			item["sx"] = 0.0
			item["sz"] = 0.0
			continue
		var slope := _major_slope(item)
		var g := slope.length()
		if g > limit and g > 0.000001:
			slope = slope * (limit / g)
		item["sx"] = slope.x
		item["sz"] = slope.y


## Degrees of heading change inside the disc. A corner on a tilted plane breaks the along step.
func _junction_turn(item: Dictionary) -> float:
	var pos: Array = item.get("pos", [])
	if pos.size() < 3:
		return 0.0
	var x := float(pos[0])
	var z := float(pos[2])
	var rad := float(item.get("radius", 8.0)) + 2.0
	var worst := 0.0
	for rid in item.get("roads", []):
		if not _by_id.has(str(rid)):
			continue
		var road: Dictionary = _roads[int(_by_id[str(rid)])]
		var pts: PackedVector3Array = road["pts"]
		for i in range(1, pts.size() - 1):
			if Vector2(pts[i].x - x, pts[i].z - z).length() > rad:
				continue
			var a := Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z)
			var b := Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z)
			if a.length() < 0.5 or b.length() < 0.5:
				continue
			var ang := rad_to_deg(absf(a.angle_to(b)))
			worst = maxf(worst, ang)
	return worst


func _junction_grade(item: Dictionary) -> float:
	var pos: Array = item.get("pos", [])
	if pos.size() < 3:
		return 0.0
	var x := float(pos[0])
	var z := float(pos[2])
	var worst := 0.0
	for rid in item.get("roads", []):
		if not _by_id.has(str(rid)):
			continue
		var road: Dictionary = _roads[int(_by_id[str(rid)])]
		var pts: PackedVector3Array = road["pts"]
		for i in pts.size() - 1:
			var ab := Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z)
			var ds := ab.length()
			if ds < 0.5:
				continue
			var mid := pts[i].lerp(pts[i + 1], 0.5)
			if Vector2(mid.x - x, mid.z - z).length() > 40.0:
				continue
			worst = maxf(worst, absf(pts[i + 1].y - pts[i].y) / ds)
	return worst


func _major_slope(item: Dictionary) -> Vector2:
	var major := _major_id(item)
	if major == "" or not _by_id.has(major):
		return Vector2.ZERO
	var pos: Array = item.get("pos", [])
	if pos.size() < 3:
		return Vector2.ZERO
	var x := float(pos[0])
	var z := float(pos[2])
	var road: Dictionary = _roads[int(_by_id[major])]
	var pts: PackedVector3Array = road["pts"]
	var best := 1.0e12
	var slope := Vector2.ZERO
	for i in pts.size() - 1:
		var abx := pts[i + 1].x - pts[i].x
		var abz := pts[i + 1].z - pts[i].z
		var len2 := abx * abx + abz * abz
		if len2 < 0.04:
			continue
		var t := clampf(((x - pts[i].x) * abx + (z - pts[i].z) * abz) / len2, 0.0, 1.0)
		var px := pts[i].x + abx * t
		var pz := pts[i].z + abz * t
		var d := Vector2(x - px, z - pz).length()
		if d >= best:
			continue
		best = d
		var ds := sqrt(len2)
		var g := (pts[i + 1].y - pts[i].y) / ds
		slope = Vector2(abx / ds * g, abz / ds * g)
	return slope


func _plane_at(item: Dictionary, x: float, z: float) -> float:
	var pos: Array = item.get("pos", [])
	var fallback := 0.0
	if pos.size() >= 3:
		fallback = float(pos[1])
	var y := float(item.get("flat_y", fallback))
	return y + float(item.get("sx", 0.0)) * (x - float(pos[0])) + float(item.get("sz", 0.0)) * (z - float(pos[2]))


## How far this point sits outside the nearest junction disc on this road.
func _blend_dist(road_id: String, p: Vector3) -> float:
	var best := 1.0e9
	for item in _junctions:
		var ids: Array = item.get("roads", [])
		if not ids.has(road_id):
			continue
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var d := Vector2(p.x - float(pos[0]), p.z - float(pos[2])).length()
		best = minf(best, d - float(item.get("radius", 8.0)))
	return best


func _junction_at(road_id: String, p: Vector3) -> Dictionary:
	var best := 1.0e9
	var found: Dictionary = {}
	for item in _junctions:
		var ids: Array = item.get("roads", [])
		if not ids.has(road_id):
			continue
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var d := Vector2(p.x - float(pos[0]), p.z - float(pos[2])).length()
		if d < best:
			best = d
			found = item
	return found


## Insert samples only inside the blend window so a grade change can ease off
## without densifying a whole highway.
## Where a through road changes width, taper the wider carriageway down to the
## narrower one over TAPER_M. The joint itself has one width.
func _apply_tapers() -> void:
	for road in _roads:
		var pts: PackedVector3Array = road["pts"]
		var halves := PackedFloat32Array()
		halves.resize(pts.size())
		halves.fill(float(road["half"]))
		road["halves"] = halves
	for item in _junctions:
		_taper_junction(item)
	for road in _roads:
		if bool(road["rail"]):
			continue
		var halves: PackedFloat32Array = road["halves"]
		var miters: Array = _miters(road["pts"], float(road["half"]), halves)
		road["left"] = miters[0]
		road["right"] = miters[1]


func _taper_junction(item: Dictionary) -> void:
	var pos: Array = item.get("pos", [])
	if pos.size() < 3:
		return
	var at := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	var roads: Array = []
	for id in item.get("roads", []):
		if not _by_id.has(str(id)):
			continue
		var road: Dictionary = _roads[int(_by_id[str(id)])]
		if bool(road["rail"]):
			continue
		roads.append(road)
	for i in roads.size():
		for j in range(i + 1, roads.size()):
			var a: Dictionary = roads[i]
			var b: Dictionary = roads[j]
			var da := _road_dir(a, at)
			var db := _road_dir(b, at)
			if absf(da.dot(db)) < 0.85:
				continue
			# A side street crossing a through road is not a lane drop. Only the
			# carriageway that ends here narrows down to the other one.
			var ha := float(a["half"])
			var hb := float(b["half"])
			if absf(ha - hb) < 0.15:
				continue
			if ha > hb and _road_ends_at(a, at):
				_taper_road(a, at, hb)
			elif hb > ha and _road_ends_at(b, at):
				_taper_road(b, at, ha)


func _road_ends_at(road: Dictionary, at: Vector3) -> bool:
	var pts: PackedVector3Array = road["pts"]
	if pts.is_empty():
		return false
	var a := Vector2(pts[0].x - at.x, pts[0].z - at.z).length()
	var b := Vector2(pts[pts.size() - 1].x - at.x, pts[pts.size() - 1].z - at.z).length()
	return minf(a, b) < 6.0


func _taper_road(road: Dictionary, at: Vector3, narrow: float) -> void:
	var pts: PackedVector3Array = road["pts"]
	var chain: PackedFloat32Array = road["chain"]
	var halves: PackedFloat32Array = road["halves"]
	if pts.is_empty() or chain.size() != pts.size() or halves.size() != pts.size():
		return
	var wide := float(road["half"])
	var best := 1.0e9
	var bi := 0
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
		if dist > TAPER_M:
			continue
		var u := clampf(dist / TAPER_M, 0.0, 1.0)
		var h := lerpf(narrow, wide, u)
		halves[i] = minf(float(halves[i]), h)
	road["halves"] = halves


func _half_at(road: Dictionary, i: int) -> float:
	var halves: Variant = road.get("halves", null)
	if halves is PackedFloat32Array:
		var arr: PackedFloat32Array = halves
		if i >= 0 and i < arr.size():
			return float(arr[i])
	return float(road.get("half", 3.0))


func _blend_junctions() -> void:
	for road in _roads:
		if bool(road["rail"]):
			continue
		_densify_blend(road)
		_apply_blend(road)
		_spread_kinks(road)
		var half := float(road["half"])
		var miters: Array = _miters(road["pts"], half)
		road["left"] = miters[0]
		road["right"] = miters[1]
		_rebuild_chain(road)


func _densify_blend(road: Dictionary) -> void:
	var pts: PackedVector3Array = road["pts"]
	var kinds: PackedStringArray = road["kind"]
	var adv: PackedInt32Array = road["advisory"]
	var out := PackedVector3Array()
	var out_k := PackedStringArray()
	var out_a := PackedInt32Array()
	out.append(pts[0])
	var id := str(road["id"])
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var kind := "grade"
		if i < kinds.size():
			kind = kinds[i]
		var advis := 0
		if i < adv.size():
			advis = int(adv[i])
		var dist := Vector2(b.x - a.x, b.z - a.z).length()
		if kind != "bridge" and dist > 1.05:
			var cursor := 0.0
			while cursor < dist - 0.4:
				var here := a.lerp(b, cursor / dist)
				var near := _blend_dist(id, here) <= BLEND_WINDOW
				var step := 1.0 if near else 16.0
				var nxt := cursor + step
				if nxt > dist - 0.4:
					break
				var mid := a.lerp(b, nxt / dist)
				if near or _blend_dist(id, mid) <= BLEND_WINDOW:
					out.append(mid)
					out_k.append(kind)
					out_a.append(advis)
				cursor = nxt
		out.append(b)
		out_k.append(kind)
		out_a.append(advis)
	road["pts"] = out
	road["kind"] = out_k
	road["advisory"] = out_a


func _rebuild_chain(road: Dictionary) -> void:
	var pts: PackedVector3Array = road["pts"]
	var chain := PackedFloat32Array()
	chain.resize(pts.size())
	var walked := 0.0
	for i in range(1, pts.size()):
		walked += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		chain[i] = walked
	road["chain"] = chain


## Pull carriageway vertices inside each disc onto that junction's plane, then
## ease back to the capped profile. The ease is local: once height and grade
## meet the original, the rest of the road is left exactly as the cap left it.
func _apply_blend(road: Dictionary) -> void:
	var pts: PackedVector3Array = road["pts"]
	if pts.size() < 2:
		return
	var orig := PackedFloat32Array()
	orig.resize(pts.size())
	var fixed := PackedByteArray()
	fixed.resize(pts.size())
	var id := str(road["id"])
	for i in pts.size():
		orig[i] = pts[i].y
		var item := _junction_at(id, pts[i])
		if item.is_empty():
			continue
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var d := Vector2(pts[i].x - float(pos[0]), pts[i].z - float(pos[2])).length()
		if d > float(item.get("radius", 8.0)) + 0.2:
			continue
		var p := pts[i]
		p.y = _plane_at(item, p.x, p.z)
		pts[i] = p
		fixed[i] = 1
	_ease_from_fixed(pts, orig, fixed)
	road["pts"] = pts


func _ease_from_fixed(pts: PackedVector3Array, orig: PackedFloat32Array, fixed: PackedByteArray) -> void:
	var n := pts.size()
	var first := 0
	while first < n and fixed[first] == 0:
		first += 1
	if first >= n:
		return
	var locked := PackedByteArray()
	locked.resize(n)
	if first > 0:
		_ease(pts, orig, locked, first, 0, -1)
	var run := first
	while run < n:
		while run + 1 < n and fixed[run + 1] == 1:
			run += 1
		var nxt := run + 1
		while nxt < n and fixed[nxt] == 0:
			nxt += 1
		if nxt >= n:
			_ease(pts, orig, locked, run, n - 1, 1)
			break
		if nxt <= run + 1:
			run = nxt
			continue
		# Close junctions share one curve. A long gap eases back to the capped
		# profile from each disc so the middle of the road is not rebuilt.
		var fwd := pts.duplicate()
		var back := pts.duplicate()
		var lock_f := PackedByteArray()
		var lock_b := PackedByteArray()
		lock_f.resize(pts.size())
		lock_b.resize(pts.size())
		_ease(fwd, orig, lock_f, run, nxt - 1, 1)
		_ease(back, orig, lock_b, nxt, run + 1, -1)
		var span := maxf(_chain_len(pts, run, nxt), 0.5)
		var walked := 0.0
		var prev_i := run
		for j in range(run + 1, nxt):
			walked += Vector2(pts[j].x - pts[prev_i].x, pts[j].z - pts[prev_i].z).length()
			var u := clampf(walked / span, 0.0, 1.0)
			var w := u * u * (3.0 - 2.0 * u)
			var p := pts[j]
			p.y = lerpf(fwd[j].y, back[j].y, w)
			pts[j] = p
			prev_i = j
		run = nxt


## Curvature-limited curve from one disc edge to the next. Used when the two
## junctions are too close for each side to rejoin the original profile.
func _meet(pts: PackedVector3Array, a: int, b: int) -> void:
	if b <= a + 1:
		return
	var g := 0.0
	if a > 0:
		g = _grade_of(pts, a - 1, a)
	var gb := 0.0
	if b + 1 < pts.size():
		gb = _grade_of(pts, b, b + 1)
	var prev := a
	for j in range(a + 1, b):
		var ds := Vector2(pts[j].x - pts[prev].x, pts[j].z - pts[prev].z).length()
		if ds < 0.05:
			var p0 := pts[j]
			p0.y = pts[prev].y
			pts[j] = p0
			prev = j
			continue
		var remain := _chain_len(pts, prev, b)
		var g_hit := (pts[b].y - pts[prev].y) / remain
		var u := clampf(1.0 - remain / maxf(_chain_len(pts, a, b), 0.5), 0.0, 1.0)
		var g_want := lerpf(g_hit, gb, u * u)
		g = clampf(g_want, g - BLEND_LIP, g + BLEND_LIP)
		g = clampf(g, -BLEND_GRADE, BLEND_GRADE)
		var p := pts[j]
		p.y = pts[prev].y + g * ds
		pts[j] = p
		prev = j


func _chain_len(pts: PackedVector3Array, a: int, b: int) -> float:
	var walked := 0.0
	var i := mini(a, b)
	var last := maxi(a, b)
	while i < last:
		walked += Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length()
		i += 1
	return walked


func _grade_of(pts: PackedVector3Array, i: int, j: int) -> float:
	var ds := Vector2(pts[j].x - pts[i].x, pts[j].z - pts[i].z).length()
	if ds < 0.05:
		return 0.0
	return (pts[j].y - pts[i].y) / ds


## Cubic between two disc edges. End heights and grades stay on the planes.
func _hermite_gap(pts: PackedVector3Array, a: int, b: int) -> void:
	if b <= a + 1:
		return
	var g0 := 0.0
	if a > 0:
		g0 = _grade_of(pts, a - 1, a)
	var g1 := 0.0
	if b + 1 < pts.size():
		g1 = _grade_of(pts, b, b + 1)
	var length := _chain_len(pts, a, b)
	if length < 0.5:
		return
	var walked := 0.0
	for j in range(a + 1, b):
		walked += Vector2(pts[j].x - pts[j - 1].x, pts[j].z - pts[j - 1].z).length()
		var u := clampf(walked / length, 0.0, 1.0)
		var u2 := u * u
		var u3 := u2 * u
		var h00 := 2.0 * u3 - 3.0 * u2 + 1.0
		var h10 := u3 - 2.0 * u2 + u
		var h01 := -2.0 * u3 + 3.0 * u2
		var h11 := u3 - u2
		var p := pts[j]
		p.y = h00 * pts[a].y + h10 * g0 * length + h01 * pts[b].y + h11 * g1 * length
		pts[j] = p


## A short gap between two discs cannot ease back to the capped profile from
## both ends. Fit one vertical curve that keeps both end heights and both end
## grades, with curvature under the along-step limit.
func _bridge_close_gaps(road: Dictionary, pts: PackedVector3Array, fixed: PackedByteArray) -> void:
	var n := pts.size()
	var run := 0
	while run < n and fixed[run] == 0:
		run += 1
	while run < n:
		while run + 1 < n and fixed[run + 1] == 1:
			run += 1
		var nxt := run + 1
		while nxt < n and fixed[nxt] == 0:
			nxt += 1
		if nxt >= n:
			break
		if nxt > run + 1 and _gap_has_lip(pts, run, nxt):
			_bridge_gap(pts, run, nxt)
		run = nxt


func _gap_has_lip(pts: PackedVector3Array, a: int, b: int) -> bool:
	var prev := 0.0
	if a > 0:
		prev = _grade_of(pts, a - 1, a)
	var i := a
	while i < b:
		var g := _grade_of(pts, i, i + 1)
		if absf(g - prev) > 0.018:
			return true
		prev = g
		i += 1
	if b + 1 < pts.size() and absf(_grade_of(pts, b, b + 1) - prev) > 0.018:
		return true
	return false


func _bridge_gap(pts: PackedVector3Array, a: int, b: int) -> bool:
	var length := _chain_len(pts, a, b)
	if length < 0.5 or length > GAP_MAX_M:
		return false
	var g0 := 0.0
	if a > 0:
		g0 = _grade_of(pts, a - 1, a)
	var g1 := 0.0
	if b + 1 < pts.size():
		g1 = _grade_of(pts, b, b + 1)
	var y0 := pts[a].y
	var y1 := pts[b].y
	var solved := _solve_gap(length, g0, g1, y1 - y0)
	if solved.is_empty():
		return false
	var c := float(solved["c"])
	var t_switch := float(solved["t"])
	var station := PackedFloat32Array()
	station.resize(b - a + 1)
	station[0] = 0.0
	for i in range(a + 1, b + 1):
		var ds := Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		station[i - a] = station[i - a - 1] + ds
	var trial := pts.duplicate()
	var y := y0
	for i in range(a + 1, b + 1):
		y += _gap_dy(station[i - a - 1], station[i - a], g0, c, t_switch)
		if i == b:
			break
		var p := trial[i]
		p.y = y
		trial[i] = p
	var residual := y1 - y
	if absf(residual) > 0.025:
		return false
	if absf(residual) > 0.00001:
		for i in range(a + 1, b):
			var u := station[i - a] / length
			var p := trial[i]
			p.y += residual * u
			trial[i] = p
	if not _gap_grades_ok(trial, a, b, g0, g1):
		return false
	for i in range(a + 1, b):
		pts[i] = trial[i]
	return true


func _gap_grades_ok(pts: PackedVector3Array, a: int, b: int, g0: float, g1: float) -> bool:
	var prev := g0
	var i := a
	while i < b:
		var g := _grade_of(pts, i, i + 1)
		if absf(g) > BLEND_GRADE + 0.001:
			return false
		if absf(g - prev) > 0.019:
			return false
		prev = g
		i += 1
	return absf(g1 - prev) <= 0.019


func _gap_dy(s0: float, s1: float, g0: float, c: float, t_switch: float) -> float:
	var ds := s1 - s0
	if ds <= 0.000001:
		return 0.0
	if t_switch <= s0 or t_switch >= s1:
		var mid := 0.5 * (s0 + s1)
		var g := g0 + c * mid
		if mid > t_switch:
			g = g0 + 2.0 * c * t_switch - c * mid
		return g * ds
	var g_s0 := g0 + c * s0
	var g_t := g0 + c * t_switch
	var g_s1 := g0 + 2.0 * c * t_switch - c * s1
	var left := 0.5 * (g_s0 + g_t) * (t_switch - s0)
	var right := 0.5 * (g_t + g_s1) * (s1 - t_switch)
	return left + right


func _solve_gap(length: float, g0: float, g1: float, height: float) -> Dictionary:
	var need := absf(g1 - g0) / maxf(length, 0.001)
	if need > GAP_CURV + 0.0001:
		return {}
	var best: Dictionary = {}
	var best_err := 1.0e9
	for sign in [-1.0, 1.0]:
		var lo := maxf(need, 0.000001)
		var hi := GAP_CURV
		var h_lo := _gap_height(length, g0, g1, sign * lo)
		var h_hi := _gap_height(length, g0, g1, sign * hi)
		if h_lo.is_empty() or h_hi.is_empty():
			continue
		var e_lo := float(h_lo["h"]) - height
		var e_hi := float(h_hi["h"]) - height
		if e_lo * e_hi > 0.0:
			if absf(e_lo) < best_err:
				best_err = absf(e_lo)
				best = h_lo
			if absf(e_hi) < best_err:
				best_err = absf(e_hi)
				best = h_hi
			continue
		var pick := h_lo
		for _step in 22:
			var mid := 0.5 * (lo + hi)
			var h_mid := _gap_height(length, g0, g1, sign * mid)
			if h_mid.is_empty():
				break
			pick = h_mid
			var e_mid := float(h_mid["h"]) - height
			if e_lo * e_mid <= 0.0:
				hi = mid
				e_hi = e_mid
			else:
				lo = mid
				e_lo = e_mid
		var err := absf(float(pick["h"]) - height)
		if err < best_err:
			best_err = err
			best = pick
	if best.is_empty() or best_err > 0.008:
		return {}
	return best


func _gap_height(length: float, g0: float, g1: float, c: float) -> Dictionary:
	if absf(c) < 1.0e-9:
		if absf(g1 - g0) > 0.0001:
			return {}
		return {"h": g0 * length, "t": 0.0, "c": 0.0}
	var t := (g1 - g0 + c * length) / (2.0 * c)
	if t < -0.05 or t > length + 0.05:
		return {}
	t = clampf(t, 0.0, length)
	var g_mid := g0 + c * t
	if maxf(absf(g0), maxf(absf(g1), absf(g_mid))) > BLEND_GRADE + 0.0001:
		return {}
	var tail := length - t
	var h := g0 * t + 0.5 * c * t * t + g_mid * tail - 0.5 * c * tail * tail
	return {"h": h, "t": t, "c": c}


## An authored kink is a lip even on a long straight segment. Spread it over
## 2 m samples without moving a junction disc or a bridge pin.
func _spread_kinks(road: Dictionary) -> void:
	_densify_kinks(road)
	_collapse_short(road)
	var pts: PackedVector3Array = road["pts"]
	var fixed := _fixed_profile(road, pts)
	for _round in 24:
		var moved := false
		for i in range(1, pts.size() - 1):
			if fixed[i] == 1:
				continue
			var ds0 := Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
			var ds1 := Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length()
			if ds0 < 0.05 or ds1 < 0.05:
				continue
			if fixed[i - 1] == 1 or fixed[i + 1] == 1:
				continue
			var g0 := (pts[i].y - pts[i - 1].y) / ds0
			var g1 := (pts[i + 1].y - pts[i].y) / ds1
			var delta := g1 - g0
			if absf(delta) <= BLEND_LIP:
				continue
			var target := clampf(delta, -BLEND_LIP, BLEND_LIP)
			var y := (pts[i - 1].y / ds0 + pts[i + 1].y / ds1 - target) / (1.0 / ds0 + 1.0 / ds1)
			var p := pts[i]
			if absf(p.y - y) < 0.0001:
				continue
			p.y = y
			pts[i] = p
			moved = true
		if not moved:
			break
	_bridge_close_gaps(road, pts, fixed)
	road["pts"] = pts


func _densify_kinks(road: Dictionary) -> void:
	var pts: PackedVector3Array = road["pts"]
	var kinds: PackedStringArray = road["kind"]
	var adv: PackedInt32Array = road["advisory"]
	var hot := PackedByteArray()
	hot.resize(pts.size())
	for i in range(1, pts.size() - 1):
		var ds0 := Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		var ds1 := Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length()
		if ds0 < 0.05 or ds1 < 0.05:
			continue
		var g0 := (pts[i].y - pts[i - 1].y) / ds0
		var g1 := (pts[i + 1].y - pts[i].y) / ds1
		if absf(g1 - g0) > BLEND_LIP:
			hot[i] = 1
	var out := PackedVector3Array()
	var out_k := PackedStringArray()
	var out_a := PackedInt32Array()
	out.append(pts[0])
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var kind := "grade"
		if i < kinds.size():
			kind = kinds[i]
		var advis := 0
		if i < adv.size():
			advis = int(adv[i])
		var dist := Vector2(b.x - a.x, b.z - a.z).length()
		if dist > 1.05 and (hot[i] == 1 or hot[i + 1] == 1):
			var cursor := 1.0
			while cursor < dist - 1.0:
				var t := cursor / dist
				out.append(a.lerp(b, t))
				out_k.append(kind)
				out_a.append(advis)
				cursor += 1.0
		out.append(b)
		out_k.append(kind)
		out_a.append(advis)
	road["pts"] = out
	road["kind"] = out_k
	road["advisory"] = out_a


## A sub-metre segment turns a small height change into a grade spike the 1 m sample sees.
func _collapse_short(road: Dictionary) -> void:
	var pts: PackedVector3Array = road["pts"]
	var kinds: PackedStringArray = road["kind"]
	var adv: PackedInt32Array = road["advisory"]
	if pts.size() < 3:
		return
	var fixed := _fixed_profile(road, pts)
	var out := PackedVector3Array()
	var out_k := PackedStringArray()
	var out_a := PackedInt32Array()
	out.append(pts[0])
	for i in range(1, pts.size() - 1):
		var prev: Vector3 = out[out.size() - 1]
		var dist := Vector2(pts[i].x - prev.x, pts[i].z - prev.z).length()
		if dist < 0.75 and fixed[i] == 0:
			continue
		out.append(pts[i])
		var ki := i - 1
		if ki < kinds.size():
			out_k.append(kinds[ki])
		else:
			out_k.append("grade")
		if ki < adv.size():
			out_a.append(int(adv[ki]))
		else:
			out_a.append(0)
	out.append(pts[pts.size() - 1])
	var last := pts.size() - 2
	if last >= 0 and last < kinds.size():
		out_k.append(kinds[last])
	else:
		out_k.append("grade")
	if last >= 0 and last < adv.size():
		out_a.append(int(adv[last]))
	else:
		out_a.append(0)
	road["pts"] = out
	road["kind"] = out_k
	road["advisory"] = out_a


func _fixed_profile(road: Dictionary, pts: PackedVector3Array) -> PackedByteArray:
	var fixed := PackedByteArray()
	fixed.resize(pts.size())
	var id := str(road["id"])
	for i in pts.size():
		if _vertex_locked(road, i):
			fixed[i] = 1
			continue
		var item := _junction_at(id, pts[i])
		if item.is_empty():
			continue
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var d := Vector2(pts[i].x - float(pos[0]), pts[i].z - float(pos[2])).length()
		if d <= float(item.get("radius", 8.0)) + 0.2:
			fixed[i] = 1
	return fixed


func _ease(pts: PackedVector3Array, orig: PackedFloat32Array, locked: PackedByteArray, start: int, stop: int, dir: int) -> void:
	var prev := start
	var g := 0.0
	var back := start - dir
	if back >= 0 and back < pts.size():
		var ds0 := Vector2(pts[start].x - pts[back].x, pts[start].z - pts[back].z).length()
		if ds0 > 0.05:
			g = (pts[start].y - pts[back].y) / ds0
	var j := start + dir
	while true:
		if dir > 0 and j > stop:
			break
		if dir < 0 and j < stop:
			break
		if locked[j] == 1:
			break
		var ds := Vector2(pts[j].x - pts[prev].x, pts[j].z - pts[prev].z).length()
		if ds < 0.02:
			var p0 := pts[j]
			p0.y = pts[prev].y
			pts[j] = p0
			prev = j
			j += dir
			continue
		var g_lo := maxf(g - BLEND_LIP, -BLEND_GRADE)
		var g_hi := minf(g + BLEND_LIP, BLEND_GRADE)
		var g_orig := (orig[j] - orig[prev]) / ds
		var g_snap := (orig[j] - pts[prev].y) / ds
		var y := pts[prev].y
		var g_use := g
		var matched := false
		if g_snap >= g_lo - 0.00001 and g_snap <= g_hi + 0.00001 and absf(g_snap - g_orig) <= BLEND_LIP + 0.00001:
			y = orig[j]
			g_use = g_snap
			matched = true
		else:
			g_use = clampf(g_snap, g_lo, g_hi)
			y = pts[prev].y + g_use * ds
		var p := pts[j]
		p.y = y
		pts[j] = p
		g = g_use
		prev = j
		var at := j
		j += dir
		if not matched:
			continue
		locked[at] = 1
		while true:
			if dir > 0 and j > stop:
				break
			if dir < 0 and j < stop:
				break
			if locked[j] == 1:
				break
			var q := pts[j]
			q.y = orig[j]
			pts[j] = q
			locked[j] = 1
			j += dir
		break


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


## Keep every authored vertex and insert samples so a grade change can ease off.
func _densify(pts: PackedVector3Array, kinds: PackedStringArray, step: float) -> Array:
	var out := PackedVector3Array()
	var out_k := PackedStringArray()
	out.append(pts[0])
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var kind := kinds[i] if i < kinds.size() else "grade"
		var dist := Vector2(b.x - a.x, b.z - a.z).length()
		var cuts := 0
		if dist > step:
			cuts = int(floor((dist - 0.01) / step))
		for k in cuts:
			var t := float(k + 1) * step / dist
			if t >= 0.999:
				break
			out.append(a.lerp(b, t))
			out_k.append(kind)
		out.append(b)
		out_k.append(kind)
	return [out, out_k]


func _class_cap(cls: String) -> float:
	if cls == "us_highway":
		return 0.05
	if cls == "rim_local":
		return 0.08
	if cls == "grade" or cls == "collector":
		return 0.10
	return 0.06


func _class_shoulder(cls: String) -> float:
	if cls == "us_highway":
		return 2.4
	if cls == "downtown":
		return 1.65
	if cls == "service":
		return 0.0
	return 1.2


func _class_ditch(cls: String) -> float:
	if cls == "us_highway":
		return 1.5
	return 1.0


## Approaches and the deck stay on the grade the seam was built for.
func _hold_profile(road: Dictionary) -> bool:
	if bool(road["rail"]):
		return true
	var id := str(road["id"])
	return _approach_road(id) or id == "us93_perrine_bridge"


## Pull any segment steeper than the class cap back onto the cone. Pinned vertices stay.
## Ordinary roads then spread kinks so a 1 m sample does not see a slope break.
func _cap_grade(road: Dictionary) -> void:
	var pts: PackedVector3Array = road["pts"]
	if pts.size() < 2:
		return
	var cap := GRADE_CAP if _hold_profile(road) else float(road.get("cap", GRADE_CAP))
	var pin: Dictionary = road.get("pins", {})
	for i in pts.size():
		if _vertex_locked(road, i):
			pin[i] = true
	_enforce_passes(road, pts, pin, cap)
	# Approach profiles still need the same kink cleanup as ordinary roads.
	# Locked bridge-joint vertices remain pinned, so smoothing cannot move the
	# asset interface itself.
	if not _hold_profile(road) or _approach_road(str(road["id"])):
		for _round in 8:
			_smooth_kinks(road, pts, pin, cap)
			_enforce_passes(road, pts, pin, cap)
	road["pts"] = pts
	road["pins"] = pin
	road["cap"] = cap


func _enforce_passes(road: Dictionary, pts: PackedVector3Array, pin: Dictionary, cap: float) -> void:
	for _pass in 8:
		for i in range(1, pts.size()):
			_enforce_grade(road, pts, i - 1, i, pin, cap)
		for i in range(pts.size() - 2, -1, -1):
			_enforce_grade(road, pts, i + 1, i, pin, cap)


## A kink larger than 2% shows up as an along step when the vertex falls on a sample.
func _smooth_kinks(road: Dictionary, pts: PackedVector3Array, pin: Dictionary, cap: float) -> void:
	var next := pts.duplicate()
	for i in range(1, pts.size() - 1):
		if pin.has(i) or _vertex_locked(road, i):
			continue
		var ds0 := Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		var ds1 := Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length()
		if ds0 < 0.05 or ds1 < 0.05:
			continue
		var g0 := (pts[i].y - pts[i - 1].y) / ds0
		var g1 := (pts[i + 1].y - pts[i].y) / ds1
		if absf(g1 - g0) <= 0.02:
			continue
		var y := (pts[i - 1].y / ds0 + pts[i + 1].y / ds1) / (1.0 / ds0 + 1.0 / ds1)
		y = lerpf(pts[i].y, y, 0.65)
		var lim0 := cap * ds0
		var lim1 := cap * ds1
		y = clampf(y, pts[i - 1].y - lim0, pts[i - 1].y + lim0)
		y = clampf(y, pts[i + 1].y - lim1, pts[i + 1].y + lim1)
		var p := next[i]
		p.y = y
		next[i] = p
	for i in pts.size():
		pts[i] = next[i]


## cap * ds / ds must not print over the cap. A 1 mm slack printed 10.02% on a short deck.
func _grade_drop(ds: float, cap: float) -> float:
	var limit := cap * ds
	var n := 0
	while n < 4 and limit > 0.0 and limit / ds > cap:
		limit *= 0.999999
		n += 1
	return limit


func _enforce_grade(road: Dictionary, pts: PackedVector3Array, ia: int, ib: int, pin: Dictionary, cap: float) -> void:
	var ds := Vector2(pts[ib].x - pts[ia].x, pts[ib].z - pts[ia].z).length()
	if ds < 0.05:
		return
	var dy := pts[ib].y - pts[ia].y
	if absf(dy) / ds <= cap:
		return
	if pin.has(ia) and pin.has(ib):
		_release_grade_pin(road, ia, ib, pin)
	var limit := _grade_drop(ds, cap)
	var clamped := clampf(dy, -limit, limit)
	if not pin.has(ib):
		var pb := pts[ib]
		pb.y = pts[ia].y + clamped
		var n := 0
		while n < 4 and absf(pb.y - pts[ia].y) / ds > cap:
			pb.y -= signf(clamped) * maxf(ds * 0.000001, 0.00001)
			n += 1
		pts[ib] = pb
	elif not pin.has(ia):
		var pa := pts[ia]
		pa.y = pts[ib].y - clamped
		var n2 := 0
		while n2 < 4 and absf(pts[ib].y - pa.y) / ds > cap:
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
	for i in pts.size():
		var b := 0.0 if rail else _bank_vertex(road, i)
		bank[i] = b
		var half_i := _half_at(road, i)
		if rail or absf(b) > deg_to_rad(1.0) or _vertex_locked(road, i) or _flat_span(road, i) or _inside_junction(str(road["id"]), pts[i]):
			crown[i] = 0.0
		else:
			crown[i] = CROWN_RATE * half_i
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
		var shoulder := float(road.get("shoulder", 1.2))
		var ditch := float(road.get("ditch", 1.0))
		var cls := str(road.get("class", ""))
		var rock_cls := cls == "grade" or cls == "rim_local"
		var approach := _approach_road(str(road["id"]))
		for i in pts.size() - 1:
			var kind := kinds[i]
			var ha := _half_at(road, i)
			var hb := _half_at(road, i + 1)
			var edge := {
				"road": str(road["id"]),
				"ax": pts[i].x, "ay": pts[i].y, "az": pts[i].z,
				"bx": pts[i + 1].x, "by": pts[i + 1].y, "bz": pts[i + 1].z,
				"half": maxf(ha, hb),
				"ha": ha,
				"hb": hb,
				"kind": kind,
				"ba": bank[i], "bb": bank[i + 1],
				"ca": crown[i], "cb": crown[i + 1],
				"rail": rail,
				"sh": shoulder,
				"ditch": ditch,
				# Approach slabs are fill, not a bridge span. The span itself stays open.
				"skip": rail or kind == "bridge" or (kind == "deck" and not approach),
				"rock": rock_cls,
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
	if not bool(edge.get("skip", false)):
		flat_r = float(edge["half"]) + float(edge.get("sh", 0.0)) + float(edge.get("ditch", 0.0)) + EARTH_REACH_M
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


func _mark_bed_lift(lift: PackedByteArray, i: int, dist: float, half_w: float) -> void:
	if i < 0 or i >= lift.size():
		return
	lift[i] = _inset_lift(dist, half_w)


func _cut_edge(grid: PackedFloat32Array, orig: PackedFloat32Array, lock: PackedByteArray, best: PackedFloat32Array, lift: PackedByteArray, origin: Vector2, n: int, spacing: float, edge: Dictionary) -> void:
	if bool(edge.get("skip", false)):
		return
	var ax := float(edge["ax"])
	var az := float(edge["az"])
	var bx := float(edge["bx"])
	var bz := float(edge["bz"])
	var reach := float(edge["half"]) + 36.0
	if not bool(edge.get("skip", false)):
		reach = float(edge["half"]) + float(edge.get("sh", 0.0)) + float(edge.get("ditch", 0.0)) + EARTH_REACH_M
	var min_x := minf(ax, bx) - reach
	var max_x := maxf(ax, bx) + reach
	var min_z := minf(az, bz) - reach
	var max_z := maxf(az, bz) + reach
	var c0 := clampi(int(floor((min_x - origin.x) / spacing)), 0, n - 1)
	var c1 := clampi(int(ceil((max_x - origin.x) / spacing)), 0, n - 1)
	var r0 := clampi(int(floor((min_z - origin.y) / spacing)), 0, n - 1)
	var r1 := clampi(int(ceil((max_z - origin.y) / spacing)), 0, n - 1)
	var legacy := bool(edge.get("skip", false))
	for r in range(r0, r1 + 1):
		var z := origin.y + float(r) * spacing
		var row := r * n
		for c in range(c0, c1 + 1):
			var x := origin.x + float(c) * spacing
			var hit := _seg_side(x, z, ax, az, bx, bz)
			if hit.x > reach:
				continue
			var i := row + c
			if _past_bridge_end(x, z, ax, az, bx, bz):
				continue
			if legacy:
				# Deck, bridge, and rail stay off the heightfield. The old cutter
				# only lowered, and its reach dug out the fill on the next segment.
				continue
			var rock := bool(edge.get("rock", false)) or _steep_cell(orig, n, c, r, spacing)
			var stamp := _stamp_at(edge, hit.x, hit.y, hit.z, orig[i], rock, spacing, x, z)
			if stamp.z < 0.5:
				continue
			var half_w := lerpf(float(edge.get("ha", edge["half"])), float(edge.get("hb", edge["half"])), hit.y)
			if hit.x <= half_w:
				stamp.x -= ROAD_BED_DEPTH_M
			if stamp.y > 0.5:
				# One cell past the paint still bilinear-blends into the lane.
				# That sample belongs to the carriageway, not to a nearer shoulder.
				var on_paint := hit.x <= half_w + maxf(spacing, 1.0)
				if on_paint:
					if lock[i] != 2 or hit.x < best[i] - 0.001:
						best[i] = hit.x
						grid[i] = stamp.x
						lock[i] = 2
						_mark_bed_lift(lift, i, hit.x, half_w)
					continue
				if lock[i] == 2:
					continue
				if hit.x < best[i] - 0.001:
					if lock[i] == 1 and stamp.x < grid[i] - 0.05:
						continue
					best[i] = hit.x
					grid[i] = stamp.x
					lock[i] = 1
					_mark_bed_lift(lift, i, hit.x, half_w)
				continue
			if lock[i] != 0:
				continue
			var o := orig[i]
			var target := stamp.x
			if target < o - 0.001:
				if grid[i] > target:
					grid[i] = target
					_mark_bed_lift(lift, i, hit.x, half_w)
			elif target > o + 0.001 and grid[i] >= o - 0.001 and grid[i] < target:
				grid[i] = target
				_mark_bed_lift(lift, i, hit.x, half_w)


func _steep_cell(orig: PackedFloat32Array, n: int, c: int, r: int, spacing: float) -> bool:
	var hl := orig[r * n + maxi(c - 1, 0)]
	var hr := orig[r * n + mini(c + 1, n - 1)]
	var hu := orig[maxi(r - 1, 0) * n + c]
	var hd := orig[mini(r + 1, n - 1) * n + c]
	var dx := (hr - hl) / (2.0 * spacing)
	var dz := (hd - hu) / (2.0 * spacing)
	var ny := 1.0 / sqrt(dx * dx + dz * dz + 1.0)
	return rad_to_deg(acos(clampf(ny, 0.0, 1.0))) >= ROCK_DEG


## y, lock (1 = pavement/shoulder/ditch), active (1 = write this cell).
## Terrain matches the crowned surface. The ribbon adds SURFACE_LIFT on top.
func _stamp_at(edge: Dictionary, dist: float, t: float, side: float, orig: float, rock: bool, _spacing: float, x: float, z: float) -> Vector3:
	var half := lerpf(float(edge.get("ha", edge["half"])), float(edge.get("hb", edge["half"])), t)
	var shoulder := float(edge.get("sh", 0.0))
	var cy := lerpf(float(edge["ay"]), float(edge["by"]), t)
	var px := lerpf(float(edge["ax"]), float(edge["bx"]), t)
	var pz := lerpf(float(edge["az"]), float(edge["bz"]), t)
	var bank := lerpf(float(edge.get("ba", 0.0)), float(edge.get("bb", 0.0)), t)
	var drop := lerpf(float(edge.get("ca", 0.0)), float(edge.get("cb", 0.0)), t)
	var sec := _section(cy, bank, drop, half)
	var edge_y := sec.x if side > 0.0 else sec.z
	var pave := edge_y
	if dist <= half and half > 0.01:
		pave = lerpf(sec.y, edge_y, dist / half)
	var junction := _junction_at(str(edge.get("road", "")), Vector3(x, cy, z))
	if not junction.is_empty():
		var pos: Array = junction.get("pos", [])
		if pos.size() >= 3:
			var centre_dist := Vector2(px - float(pos[0]), pz - float(pos[2])).length()
			if centre_dist <= float(junction.get("radius", 8.0)) + half:
				var dx := float(edge["bx"]) - float(edge["ax"])
				var dz := float(edge["bz"]) - float(edge["az"])
				var length := Vector2(dx, dz).length()
				var edge_x := px - dz / maxf(length, 0.001) * side * half
				var edge_z := pz + dx / maxf(length, 0.001) * side * half
				edge_y = _plane_at(junction, edge_x, edge_z)
				if dist <= half:
					pave = _plane_at(junction, x, z)
				elif dist <= half + maxf(shoulder, BENCH_M):
					pave = edge_y
	# 2 m bench at the road edge, then 4 m linear blend. Deeper earthwork
	# continues on the engineered face so a canyon cut does not become a wall.
	var bench := maxf(shoulder, BENCH_M)
	var flat := half + bench
	if dist <= flat:
		return Vector3(pave, 1.0, 1.0)
	var outer := dist - flat
	var delta := edge_y - orig
	var seam := SEAM_GRADE * BLEND_M
	if absf(delta) <= seam + 0.05:
		if outer >= BLEND_M:
			return Vector3(orig, 0.0, 0.0)
		return Vector3(lerpf(edge_y, orig, clampf(outer / BLEND_M, 0.0, 1.0)), 0.0, 1.0)
	var lip: float = edge_y - seam if delta > 0.0 else edge_y + seam
	if outer <= BLEND_M:
		return Vector3(lerpf(edge_y, lip, clampf(outer / BLEND_M, 0.0, 1.0)), 0.0, 1.0)
	if delta > 0.0:
		return _fill_stamp(lip, outer - BLEND_M, orig)
	return _cut_stamp(lip, outer - BLEND_M, orig, rock)


func _fill_stamp(edge_y: float, outer: float, orig: float) -> Vector3:
	var toe := maxf((edge_y - orig) * STAMP_FILL_H, 0.0)
	if outer >= toe + BLEND_M:
		return Vector3(orig, 0.0, 0.0)
	var slope := edge_y - outer / STAMP_FILL_H
	if outer >= toe:
		return Vector3(orig, 0.0, 1.0)
	var start := maxf(toe - BLEND_M, 0.0)
	if outer <= start:
		return Vector3(slope, 0.0, 1.0)
	var u := (outer - start) / maxf(toe - start, 0.001)
	var w := 0.5 - 0.5 * cos(PI * u)
	return Vector3(lerpf(slope, orig, w), 0.0, 1.0)


func _cut_stamp(bottom: float, past: float, orig: float, rock: bool) -> Vector3:
	var rise := orig - bottom
	if rise <= 0.0:
		return Vector3(orig, 0.0, 0.0)
	var toe := _cut_run(rise, rock)
	if past >= toe + BLEND_M:
		return Vector3(orig, 0.0, 0.0)
	if past >= toe:
		return Vector3(orig, 0.0, 1.0)
	var y := bottom + _cut_rise(past, rock, rise)
	var start := maxf(toe - BLEND_M, 0.0)
	if past <= start:
		return Vector3(y, 0.0, 1.0)
	var u := (past - start) / maxf(toe - start, 0.001)
	var w := 0.5 - 0.5 * cos(PI * u)
	return Vector3(lerpf(y, orig, w), 0.0, 1.0)


## Horizontal run of a cut face. Rock over 8 m gets a 3 m bench every 6 m.
func _cut_run(v: float, rock: bool) -> float:
	if v <= 0.0:
		return 0.0
	if not rock:
		return v * SOIL_CUT_H
	if v <= 8.0:
		return v * ROCK_CUT_H
	var run := 8.0 * ROCK_CUT_H
	var rest := v - 8.0
	var cycles := int(rest / 6.0)
	var rem := rest - float(cycles) * 6.0
	return run + float(cycles) * (6.0 * ROCK_CUT_H + 3.0) + rem * ROCK_CUT_H


func _cut_rise(past: float, rock: bool, max_v: float) -> float:
	if not rock or max_v <= 8.0:
		return past / SOIL_CUT_H if not rock else past / ROCK_CUT_H
	var lo := 0.0
	var hi := max_v
	for _i in 10:
		var mid := (lo + hi) * 0.5
		if _cut_run(mid, true) < past:
			lo = mid
		else:
			hi = mid
	return lo


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


## True when the cell is past an abutment and would fill the bridge span.
## A few metres of cap close the joint. The span itself stays open.
func _past_bridge_end(x: float, z: float, ax: float, az: float, bx: float, bz: float) -> bool:
	var abx := bx - ax
	var abz := bz - az
	var len2 := abx * abx + abz * abz
	if len2 < 0.0001:
		return false
	var raw := ((x - ax) * abx + (z - az) * abz) / len2
	if raw >= 0.0 and raw <= 1.0:
		return false
	var endx := ax if raw < 0.0 else bx
	var endz := az if raw < 0.0 else bz
	if not _bridge_end_xz(endx, endz):
		return false
	var overrun := -raw * sqrt(len2) if raw < 0.0 else (raw - 1.0) * sqrt(len2)
	return overrun > 3.0


func _bridge_end_xz(x: float, z: float) -> bool:
	if not _by_id.has("us93_perrine_bridge"):
		return false
	var road: Dictionary = _roads[int(_by_id["us93_perrine_bridge"])]
	var pts: PackedVector3Array = road["pts"]
	for q in pts:
		if Vector2(x - q.x, z - q.z).length() <= 3.0:
			return true
	return false


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
	var lanes := int(road["lanes"])
	var lane_w := float(road.get("lane_w", 3.35))
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
		var full_len := Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length()
		var seg_len := full_len * (t1 - t0)
		var pieces := maxi(int(ceil(seg_len / 4.0)), 1)
		for p in pieces:
			var a0 := t0 + (t1 - t0) * float(p) / float(pieces)
			var b0 := t0 + (t1 - t0) * float(p + 1) / float(pieces)
			if b0 - a0 <= 0.0000001:
				continue
			var lift0 := _ribbon_lift(road_id, kind, pts[i].lerp(pts[i + 1], a0))
			var lift1 := _ribbon_lift(road_id, kind, pts[i].lerp(pts[i + 1], b0))
			var ha := _half_at(road, i)
			var hb := _half_at(road, i + 1)
			_emit_span(road_id, kind, rail, lanes, lane_w, lerpf(ha, hb, a0), lerpf(ha, hb, b0), lift0, lift1, left[i], left[i + 1], right[i], right[i + 1], bank[i], bank[i + 1], crown[i], crown[i + 1], chain[i], chain[i + 1], a0, b0, grid, origin, n, spacing, surfs, faces)


func _emit_span(road_id: String, kind: String, rail: bool, lanes: int, lane_w: float, half: float, half_b: float, lift0: float, lift1: float, left_a: Vector3, left_b: Vector3, right_a: Vector3, right_b: Vector3, bank_a: float, bank_b: float, crown_a: float, crown_b: float, chain_a: float, chain_b: float, t0: float, t1: float, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, surfs: Dictionary, faces: PackedVector3Array) -> void:
	var l0 := left_a.lerp(left_b, t0)
	var l1 := left_a.lerp(left_b, t1)
	var r0 := right_a.lerp(right_b, t0)
	var r1 := right_a.lerp(right_b, t1)
	var flat := rail or kind == "deck" or kind == "bridge"
	var s0 := _section(l0.y + lift0, lerpf(bank_a, bank_b, t0), lerpf(crown_a, crown_b, t0), half) if not flat else Vector3(l0.y + lift0, l0.y + lift0, l0.y + lift0)
	var s1 := _section(l1.y + lift1, lerpf(bank_a, bank_b, t1), lerpf(crown_a, crown_b, t1), half_b) if not flat else Vector3(l1.y + lift1, l1.y + lift1, l1.y + lift1)
	l0.y = s0.x
	l1.y = s1.x
	r0.y = s0.z
	r1.y = s1.z
	var m0 := l0.lerp(r0, 0.5)
	var m1 := l1.lerp(r1, 0.5)
	m0.y = s0.y
	m1.y = s1.y
	# A cross street's centreline height is one sample. On a tilted junction
	# plane the edges are not at that height. Sample the plane at each corner
	# or the wider ribbon shelves over the graded road.
	l0.y = _on_plane(road_id, l0, l0.y)
	l1.y = _on_plane(road_id, l1, l1.y)
	r0.y = _on_plane(road_id, r0, r0.y)
	r1.y = _on_plane(road_id, r1, r1.y)
	m0.y = _on_plane(road_id, m0, m0.y)
	m1.y = _on_plane(road_id, m1, m1.y)
	var half_m := (half + half_b) * 0.5
	var c0 := chain_a + (chain_b - chain_a) * t0
	var c1 := chain_a + (chain_b - chain_a) * t1
	# Visual stays on the paint. Collision is the same plane, flared so a ray
	# on the paint edge or the centre seam is inside a triangle.
	_solid_carriage(faces, l0, m0, m1, l1)
	_solid_carriage(faces, r0, m0, m1, r1)
	# The v4 model is the deck. A shoulder and a parapet keep a walk beside
	# the span off the soffit. The asphalt sheet would hide the lanes.
	if kind == "bridge" and not rail:
		_bridge_shoulder(faces, l0, l1, r0)
		_bridge_shoulder(faces, r0, r1, l0)
		return
	if rail:
		var on_panel := _rail_on_panel(m0) and _rail_on_panel(m1)
		if not on_panel:
			var ball: _Surf = surfs["ballast"]
			_quad(ball, l0, m0, m1, l1, c0, c1, 0.0, half_m, false, faces)
			_quad(ball, m0, r0, r1, m1, c0, c1, half_m, half_m * 2.0, false, faces)
		_rails(surfs["rail"], l0, r0, r1, l1, c0, c1)
		if kind == "trestle":
			_trestle(surfs["basalt"], l0, r0, r1, l1, grid, origin, n, spacing, faces)
		return
	var top: _Surf = surfs["asphalt"]
	_quad(top, l0, m0, m1, l1, c0, c1, 0.0, half_m, false, faces)
	_quad(top, m0, r0, r1, m1, c0, c1, half_m, half_m * 2.0, false, faces)
	var use_lanes := lanes
	if lane_w > 0.5:
		use_lanes = clampi(int(round(half_m * 2.0 / lane_w)), 1, maxi(lanes, 1))
	var cr0 := lerpf(crown_a, crown_b, t0)
	var cr1 := lerpf(crown_a, crown_b, t1)
	_paint_lines(road_id, surfs, l0, r0, l1, r1, half_m, use_lanes, lane_w, c0, c1, cr0, cr1)
	# Grade raised approach edges into the surrounding terrain with a continuous
	# earth slope. Threshold-triggered parapet segments looked like stray blocks
	# and left gaps between spans. Keep structural parapets only at the bridge.
	if _approach_road(road_id) and kind != "bridge":
		var left_out := Vector3(l0.x - m0.x, 0.0, l0.z - m0.z).normalized()
		var right_out := Vector3(r0.x - m0.x, 0.0, r0.z - m0.z).normalized()
		_approach_fill(surfs["panel"], l0, l1, left_out, grid, origin, n, spacing, faces)
		_approach_fill(surfs["panel"], r0, r1, right_out, grid, origin, n, spacing, faces)
	if kind != "bridge":
		var rim := road_id == "rim_road_south"
		_guard_edge(surfs["guard"], l0, l1, r0, grid, origin, n, spacing, faces, rim)
		_guard_edge(surfs["guard"], r0, r1, l0, grid, origin, n, spacing, faces, rim)


## Height on the junction plane, or the section height when the point is outside the disc.
func _on_plane(road_id: String, p: Vector3, fallback: float) -> float:
	var item := _junction_at(road_id, p)
	if item.is_empty():
		return fallback
	var pos: Array = item.get("pos", [])
	if pos.size() < 3:
		return fallback
	var half := 0.0
	if _by_id.has(road_id):
		half = float(_roads[int(_by_id[road_id])].get("half", 0.0))
	var rad := float(item.get("radius", 8.0)) + half + 0.4
	if Vector2(p.x - float(pos[0]), p.z - float(pos[2])).length() > rad:
		return fallback
	return _plane_at(item, p.x, p.z) + SURFACE_LIFT


## Shoulder past the paint, then a parapet. The walk beside the span starts
## outside the wall, clear of the deck soffit.
func _bridge_shoulder(faces: PackedVector3Array, a: Vector3, b: Vector3, other: Vector3) -> void:
	var outward := Vector3(a.x - other.x, 0.0, a.z - other.z)
	if outward.length_squared() < 0.01:
		return
	outward = outward.normalized()
	var reach := 2.6
	var a2 := a + outward * reach
	var b2 := b + outward * reach
	a2.y = a.y
	b2.y = b.y
	_solid_quad(faces, a, a2, b2, b)
	var along := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if along.length_squared() < 0.04:
		return
	var dir := along.normalized()
	var ia := a2 - dir * 0.2
	var ib := b2 + dir * 0.2
	var thick := outward * PARA_T
	var up := Vector3(0.0, PARA_H, 0.0)
	var oa := ia + thick
	var ob := ib + thick
	_solid_both(faces, ia, ib, ib + up, ia + up)
	_solid_both(faces, ob, oa, oa + up, ob + up)
	_solid_both(faces, ia + up, ib + up, ob + up, oa + up)
	_solid_both(faces, ia, oa, ob, ib)


func _ribbon_lift(_road_id: String, _kind: String, _p: Vector3) -> float:
	# Deck, bridge, and approaches use the same lift as every other ribbon.
	# The joint stays flush because both sides move together, and the ribbon
	# stays above the heightfield where the stamp meets the deck.
	return SURFACE_LIFT


func _bridge_distance(p: Vector3) -> float:
	if not _by_id.has("us93_perrine_bridge"):
		return 1000.0
	var road: Dictionary = _roads[int(_by_id["us93_perrine_bridge"])]
	var pts: PackedVector3Array = road["pts"]
	var best := 1000.0
	for q in pts:
		best = minf(best, Vector2(p.x - q.x, p.z - q.z).length())
	return best


## Flared collision quad. Outer edge past the paint, inner edge past the centre.
func _solid_carriage(faces: PackedVector3Array, outer0: Vector3, inner0: Vector3, inner1: Vector3, outer1: Vector3) -> void:
	var span0 := Vector2(outer0.x - inner0.x, outer0.z - inner0.z).length()
	var span1 := Vector2(outer1.x - inner1.x, outer1.z - inner1.z).length()
	if span0 < 0.05 or span1 < 0.05:
		_solid_quad(faces, outer0, inner0, inner1, outer1)
		return
	var o0 := _extend_cross(inner0, outer0, span0, span0 + FLARE_M)
	var o1 := _extend_cross(inner1, outer1, span1, span1 + FLARE_M)
	var s0 := _extend_cross(inner0, outer0, span0, -SEAM_M)
	var s1 := _extend_cross(inner1, outer1, span1, -SEAM_M)
	var o0e := _extend_along(o0, o1, ALONG_M)
	var o1e := _extend_along(o1, o0, ALONG_M)
	var s0e := _extend_along(s0, s1, ALONG_M)
	var s1e := _extend_along(s1, s0, ALONG_M)
	_solid_quad(faces, o0e, s0e, s1e, o1e)


func _extend_cross(origin: Vector3, toward: Vector3, span: float, dist: float) -> Vector3:
	if span < 0.05:
		return origin
	return origin + (toward - origin) * (dist / span)


func _extend_along(p: Vector3, other: Vector3, dist: float) -> Vector3:
	var d := other - p
	var xz := Vector2(d.x, d.z).length()
	if xz < 0.05:
		return p
	return p - d * (dist / xz)


func _paint_lines(road_id: String, surfs: Dictionary, l0: Vector3, r0: Vector3, l1: Vector3, r1: Vector3, half: float, lanes: int, lane_w: float, c0: float, c1: float, crown0: float, crown1: float) -> void:
	var a := l0.lerp(r0, 0.5)
	var b := l1.lerp(r1, 0.5)
	var keep := _open_spans(road_id, a, b)
	var stripe := lane_w if lane_w > 0.5 else half * 2.0 / float(maxi(lanes, 1))
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
		var k0 := lerpf(crown0, crown1, u0)
		var k1 := lerpf(crown0, crown1, u1)
		if lanes >= 2:
			_line(surfs["yellow"], ll0, rr0, ll1, rr1, half, 0.0, LINE_W, 0.01, ca, cb, k0, k1, false)
		_line(surfs["white"], ll0, rr0, ll1, rr1, half, -(half - 0.22), LINE_W, 0.01, ca, cb, k0, k1, false)
		_line(surfs["white"], ll0, rr0, ll1, rr1, half, half - 0.22, LINE_W, 0.01, ca, cb, k0, k1, false)
		if lanes > 2:
			var k := 1
			while float(k) * stripe < half - 0.45:
				_line(surfs["white"], ll0, rr0, ll1, rr1, half, float(k) * stripe, LINE_W, 0.01, ca, cb, k0, k1, true)
				_line(surfs["white"], ll0, rr0, ll1, rr1, half, -float(k) * stripe, LINE_W, 0.01, ca, cb, k0, k1, true)
				k += 1


func _perrine_road(road_id: String) -> bool:
	return road_id == "us93_south_approach" or road_id == "us93_north" or road_id == "us93_perrine_bridge"


func _approach_road(road_id: String) -> bool:
	return road_id == "us93_south_approach" or road_id == "us93_north"


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


func _approach_structure(panel: _Surf, l0: Vector3, r0: Vector3, l1: Vector3, r1: Vector3, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, faces: PackedVector3Array, force: bool) -> void:
	if force or _approach_keep(l0, l1, grid, origin, n, spacing):
		_approach_edge(panel, l0, l1, r0, grid, origin, n, spacing, faces)
	if force or _approach_keep(r0, r1, grid, origin, n, spacing):
		_approach_edge(panel, r0, r1, l0, grid, origin, n, spacing, faces)


## Bridge joint, or an edge still high enough that a cone would fall off it.
func _approach_keep(a: Vector3, b: Vector3, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> bool:
	if _at_bridge_joint(a) or _at_bridge_joint(b):
		return true
	return _edge_fall(a, grid, origin, n, spacing) >= PARA_DROP_M or _edge_fall(b, grid, origin, n, spacing) >= PARA_DROP_M


func _edge_fall(p: Vector3, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> float:
	var g := _ground(grid, origin, n, spacing, p.x, p.z)
	if g < -70.0:
		return 0.0
	return p.y - g


func _approach_edge(panel: _Surf, a: Vector3, b: Vector3, other: Vector3, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, faces: PackedVector3Array) -> void:
	var outward := Vector3(a.x - other.x, 0.0, a.z - other.z)
	if outward.length_squared() < 0.01:
		return
	var width := outward.length()
	outward = outward.normalized()
	var along := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if along.length_squared() < 0.04:
		return
	var dir := along.normalized()
	var a0 := a
	var b0 := b
	# Overlap the next piece so a cone cannot slip through a joint.
	a = a0 - dir * 0.35
	b = b0 + dir * 0.35
	if _at_bridge_joint(a0):
		a = a0 - dir * 6.0
		_approach_wing(panel, a0, outward, width, grid, origin, n, spacing, faces)
	if _at_bridge_joint(b0):
		b = b0 + dir * 6.0
		_approach_wing(panel, b0, outward, width, grid, origin, n, spacing, faces)
	var inset := outward * 0.06
	var thick := outward * PARA_T
	var up := Vector3(0.0, PARA_H, 0.0)
	var ia := a + inset
	var ib := b + inset
	var oa := ia + thick
	var ob := ib + thick
	_wall(panel, ia, ib, ib + up, ia + up, false, faces)
	_wall(panel, ob, oa, oa + up, ob + up, false, faces)
	_wall(panel, ia + up, ib + up, ob + up, oa + up, false, faces)
	_solid_both(faces, ia, ib, ib + up, ia + up)
	_solid_both(faces, ob, oa, oa + up, ob + up)
	_solid_both(faces, ia + up, ib + up, ob + up, oa + up)
	_solid_both(faces, ia, oa, ob, ib)


## Solid block from the road edge out to the rail, overlapping the span so the
## parapet and the bridge rail share volume instead of leaving a corner gap.
func _approach_wing(panel: _Surf, edge: Vector3, outward: Vector3, width: float, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, faces: PackedVector3Array) -> void:
	var extra := ABUT_HALF - width * 0.5
	if extra < 0.3:
		extra = 2.6
	var along := _bridge_inward(edge)
	if along.length_squared() < 0.5:
		along = Vector3(-outward.z, 0.0, outward.x)
	var near := edge + outward * 0.06
	# Past the rail outer face so the block and the rail box overlap.
	var far := edge + outward * (extra + 0.5)
	# 1.8 m onto the span covers the rail end. 0.6 m landward covers the parapet.
	var nb := near - along * 0.6
	var nf := near + along * 1.8
	var ff := far + along * 1.8
	var fb := far - along * 0.6
	var floor_y := _lowest(grid, origin, n, spacing, [nb, nf, ff, fb, edge]) - 1.0
	_solid_prism(panel, faces, nb, nf, ff, fb, floor_y, edge.y + PARA_H)


## 2:1 fill as a closed solid: slope on the outside, walls through to a floor
## under the terrain so a cone cannot walk in an open end and under the slope.
func _approach_fill(surf: _Surf, a: Vector3, b: Vector3, outward: Vector3, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, faces: PackedVector3Array) -> void:
	var span := Vector2(b.x - a.x, b.z - a.z).length()
	var steps := maxi(int(ceil(span / 2.0)), 1)
	var tops: Array[Vector3] = []
	var runs: Array[float] = []
	for s in steps + 1:
		var t := float(s) / float(steps)
		var p := a.lerp(b, t)
		p += outward * 0.06
		tops.append(p)
		runs.append(_approach_toe(p, outward, grid, origin, n, spacing))
	var raised := false
	for s in steps + 1:
		var g := _ground(grid, origin, n, spacing, tops[s].x, tops[s].z)
		if runs[s] >= 0.4 or (g > -70.0 and tops[s].y - g >= PARA_DROP_M):
			raised = true
			break
	if not raised:
		return
	for s in steps:
		var top_a: Vector3 = tops[s]
		var top_b: Vector3 = tops[s + 1]
		var run_a := runs[s]
		var run_b := runs[s + 1]
		var toe_a := _slope_at(top_a, outward, run_a)
		var toe_b := _slope_at(top_b, outward, run_b)
		if run_a >= 0.4 or run_b >= 0.4:
			_earth_quad(surf, top_a, top_b, toe_b, toe_a)
			_solid_both(faces, top_a, top_b, toe_b, toe_a)
			# Outer face drops through the ground so the sheet cannot be walked under.
			_fill_wall(surf, faces, toe_a, toe_b, _bury_point(toe_b, grid, origin, n, spacing), _bury_point(toe_a, grid, origin, n, spacing))
		_fill_wall(surf, faces, top_a, top_b, _bury_point(top_b, grid, origin, n, spacing), _bury_point(top_a, grid, origin, n, spacing))
		_fill_diaphragm(surf, faces, top_a, outward, run_a, grid, origin, n, spacing)
		if s == steps - 1:
			_fill_diaphragm(surf, faces, top_b, outward, run_b, grid, origin, n, spacing)


func _slope_at(edge: Vector3, outward: Vector3, run: float) -> Vector3:
	var p := edge + outward * run
	p.y = edge.y - run / FILL_H_PER_V
	return p


## How far the 2:1 runs before it meets the ground. Where the canyon falls away
## steeper than 2:1 the run stops at the closest approach and the outer wall
## closes the rest.
func _approach_toe(edge: Vector3, outward: Vector3, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> float:
	var g0 := _ground(grid, origin, n, spacing, edge.x, edge.z)
	if g0 < -70.0 or g0 >= edge.y - PARA_DROP_M:
		return 0.0
	var dist := 2.0
	var prev_d := 0.0
	var prev_g := g0
	var best_d := 2.0
	var best_gap := edge.y - g0
	while dist <= 72.0:
		var g := _ground(grid, origin, n, spacing, edge.x + outward.x * dist, edge.z + outward.z * dist)
		var slope_y := edge.y - dist / FILL_H_PER_V
		if g < -70.0:
			return prev_d
		if g >= slope_y:
			var slope_prev := edge.y - prev_d / FILL_H_PER_V
			var gy := g - prev_g
			var sy := slope_y - slope_prev
			var den := gy - sy
			var u := 1.0 if absf(den) < 0.0001 else clampf((slope_prev - prev_g) / den, 0.0, 1.0)
			return lerpf(prev_d, dist, u)
		var gap := slope_y - g
		if gap < best_gap - 0.1:
			best_gap = gap
			best_d = dist
		elif dist >= 16.0 and gap > best_gap + 0.8:
			return best_d
		prev_d = dist
		prev_g = g
		dist += 2.0
	return best_d


func _bury_point(p: Vector3, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> Vector3:
	var g := _ground(grid, origin, n, spacing, p.x, p.z)
	var y := p.y - 1.0
	if g > -70.0:
		y = minf(g, p.y) - 1.0
	return Vector3(p.x, y, p.z)


func _fill_diaphragm(surf: _Surf, faces: PackedVector3Array, edge: Vector3, outward: Vector3, run: float, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> void:
	var foot := _bury_point(edge, grid, origin, n, spacing)
	if run < 0.4:
		if edge.y - foot.y < 0.4:
			return
		var nib := edge + outward * 0.25
		_fill_wall(surf, faces, edge, nib, _bury_point(nib, grid, origin, n, spacing), foot)
		return
	var nstep := maxi(int(ceil(run / 2.0)), 1)
	var prev_top := edge
	var prev_bot := foot
	for i in nstep:
		var d := run * float(i + 1) / float(nstep)
		var top := _slope_at(edge, outward, d)
		var bot := _bury_point(top, grid, origin, n, spacing)
		_fill_wall(surf, faces, prev_top, top, bot, prev_bot)
		prev_top = top
		prev_bot = bot


func _fill_wall(surf: _Surf, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	if a.distance_squared_to(d) < 0.02 and b.distance_squared_to(c) < 0.02:
		return
	_earth_quad(surf, a, b, c, d)
	_solid_both(faces, a, b, c, d)


func _lowest(grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, pts: Array) -> float:
	var lo := 1.0e9
	for p in pts:
		var at: Vector3 = p
		var g := _ground(grid, origin, n, spacing, at.x, at.z)
		if g > -70.0:
			lo = minf(lo, g)
	if lo > 1.0e8:
		var at0: Vector3 = pts[0]
		return at0.y - 2.0
	return lo


## Four plan corners, extruded from floor_y up to top_y. Collision on every face.
func _solid_prism(panel: _Surf, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, floor_y: float, top_y: float) -> void:
	if top_y < floor_y + 0.05:
		return
	var a0 := Vector3(a.x, floor_y, a.z)
	var b0 := Vector3(b.x, floor_y, b.z)
	var c0 := Vector3(c.x, floor_y, c.z)
	var d0 := Vector3(d.x, floor_y, d.z)
	var a1 := Vector3(a.x, top_y, a.z)
	var b1 := Vector3(b.x, top_y, b.z)
	var c1 := Vector3(c.x, top_y, c.z)
	var d1 := Vector3(d.x, top_y, d.z)
	_wall(panel, a1, b1, c1, d1, false, faces)
	_solid_both(faces, a1, b1, c1, d1)
	_solid_both(faces, a0, d0, c0, b0)
	_wall(panel, a0, b0, b1, a1, false, faces)
	_solid_both(faces, a0, b0, b1, a1)
	_wall(panel, b0, c0, c1, b1, false, faces)
	_solid_both(faces, b0, c0, c1, b1)
	_wall(panel, c0, d0, d1, c1, false, faces)
	_solid_both(faces, c0, d0, d1, c1)
	_wall(panel, d0, a0, a1, d1, false, faces)
	_solid_both(faces, d0, a0, a1, d1)


func _fill_toe_reach(edge: Vector3, outward: Vector3, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, reach: float) -> Vector2:
	var g0 := _ground(grid, origin, n, spacing, edge.x, edge.z)
	if g0 < -70.0 or g0 >= edge.y - 0.2:
		return Vector2(0.0, g0)
	var dist := 1.0
	var prev_d := 0.0
	var prev_g := g0
	while dist <= reach:
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
	return Vector2(reach, edge.y - reach / FILL_H_PER_V)


## The approach edge is a half-width off the bridge centreline (~7.32 m), so a
## 2.5 m test never sees the joint and the wing stays unbuilt. Match the end
## in road-axis coordinates: a couple of metres along, a half-width across.
func _at_bridge_joint(p: Vector3) -> bool:
	if not _by_id.has("us93_perrine_bridge"):
		return false
	var road: Dictionary = _roads[int(_by_id["us93_perrine_bridge"])]
	var pts: PackedVector3Array = road["pts"]
	if pts.size() < 2:
		return false
	var half := float(road["half"]) + 1.5
	var ends: Array[Vector3] = [pts[0], pts[pts.size() - 1]]
	for q in ends:
		var axis := _bridge_inward(q)
		var rel := Vector3(p.x - q.x, 0.0, p.z - q.z)
		if axis.length_squared() < 0.5:
			if rel.length() <= half:
				return true
			continue
		var long := rel.dot(axis)
		var lat := (rel - axis * long).length()
		if absf(long) <= 2.5 and lat <= half:
			return true
	return false


## Unit XZ from the nearest bridge end, pointing along the span.
func _bridge_inward(p: Vector3) -> Vector3:
	if not _by_id.has("us93_perrine_bridge"):
		return Vector3.ZERO
	var road: Dictionary = _roads[int(_by_id["us93_perrine_bridge"])]
	var pts: PackedVector3Array = road["pts"]
	if pts.size() < 2:
		return Vector3.ZERO
	var south: Vector3 = pts[0]
	var north: Vector3 = pts[pts.size() - 1]
	var use_south := Vector2(p.x - south.x, p.z - south.z).length_squared() <= Vector2(p.x - north.x, p.z - north.z).length_squared()
	var into := (north - south) if use_south else (south - north)
	into.y = 0.0
	if into.length_squared() < 0.01:
		return Vector3.ZERO
	return into.normalized()


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


func _paint_y(left_y: float, right_y: float, u: float, crown: float) -> float:
	# Edge lerp is already at the crowned edge. The tent puts the centre back
	# on the carriageway: 0 at each edge, full crown drop at the centre.
	return lerpf(left_y, right_y, u) + crown * (1.0 - absf(u * 2.0 - 1.0))


func _line(surf: _Surf, l0: Vector3, r0: Vector3, l1: Vector3, r1: Vector3, half: float, offset: float, width: float, lift: float, c0: float, c1: float, crown0: float, crown1: float, dashed: bool) -> void:
	var u := clampf(0.5 + offset / (half * 2.0), 0.02, 0.98)
	var hw := width / (half * 4.0)
	var ua := clampf(u - hw, 0.0, 1.0)
	var ub := clampf(u + hw, 0.0, 1.0)
	var a0 := l0.lerp(r0, ua)
	var b0 := l0.lerp(r0, ub)
	var a1 := l1.lerp(r1, ua)
	var b1 := l1.lerp(r1, ub)
	a0.y = _paint_y(l0.y, r0.y, ua, crown0)
	b0.y = _paint_y(l0.y, r0.y, ub, crown0)
	a1.y = _paint_y(l1.y, r1.y, ua, crown1)
	b1.y = _paint_y(l1.y, r1.y, ub, crown1)
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


func _is_map_edge(p: Vector3) -> bool:
	return p.x <= 5.0 or p.x >= 4995.0 or p.z >= -5.0 or p.z <= -7995.0


## The playable map ends on a tile boundary. Continue the carriageway and close
## it with a berm so a vehicle is still on solid ground past the last vertex.
func _emit_exits(coord: Vector2i, faces: PackedVector3Array) -> void:
	var rect := WorldConfig.chunk_rect(coord)
	for road in _roads:
		if bool(road["rail"]):
			continue
		var pts: PackedVector3Array = road["pts"]
		if pts.size() < 2:
			continue
		_emit_exit(road, 0, rect, faces)
		_emit_exit(road, pts.size() - 1, rect, faces)


func _emit_exit(road: Dictionary, index: int, rect: Rect2, faces: PackedVector3Array) -> void:
	var pts: PackedVector3Array = road["pts"]
	var p := pts[index]
	if not _is_map_edge(p):
		return
	var other := pts[1] if index == 0 else pts[pts.size() - 2]
	if _clip_span(other, p, rect).is_empty() and _clip_span(p, other, rect).is_empty():
		if not rect.has_point(Vector2(p.x, p.z)) and not rect.has_point(Vector2(other.x, other.z)):
			return
	var tangent := p - other
	tangent.y = 0.0
	if tangent.length_squared() < 0.04:
		return
	tangent = tangent.normalized()
	var side := Vector3(-tangent.z, 0.0, tangent.x)
	var y := p.y + SURFACE_LIFT
	var w := maxf(_half_at(road, index) + 12.0, 16.0)
	# Start on the end vertex. A pad that reaches back up the grade is a shelf.
	var back := p - tangent * 0.15
	var far := p + tangent * EXIT_PAD_M
	var l0 := back + side * w
	var r0 := back - side * w
	var l1 := far + side * w
	var r1 := far - side * w
	l0.y = y
	r0.y = y
	l1.y = y
	r1.y = y
	_solid_quad(faces, l0, r0, r1, l1)
	var b0 := p + tangent * EXIT_BERM_M
	var ba := b0 + side * w
	var bb := b0 - side * w
	ba.y = y
	bb.y = y
	var thick := tangent * 0.8
	var up := Vector3(0.0, 0.9, 0.0)
	_solid_both(faces, ba, bb, bb + thick, ba + thick)
	_solid_both(faces, ba + up, bb + up, bb + thick + up, ba + thick + up)
	_solid_both(faces, ba, ba + thick, ba + thick + up, ba + up)
	_solid_both(faces, bb + thick, bb, bb + up, bb + thick + up)


func _emit_junctions(coord: Vector2i, surf: _Surf, faces: PackedVector3Array, _grid: PackedFloat32Array, _n: int, _spacing: float) -> void:
	for item in _junctions:
		# Ordinary junctions are formed by the union of their approach ribbons.
		# A circular overlay rounds off the road footprint and creates a paved
		# blob at T and cross intersections. Keep a patch only at a bridge asset.
		if not _bridge_joint(item):
			continue
		var pos: Array = item.get("pos", [])
		if pos.size() < 3:
			continue
		var at := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		if WorldConfig.chunk_of(at.x, at.z) != coord:
			continue
		var radius := float(item.get("radius", 8.0))
		var lift := _joint_lift(item)
		# One plane for every junction, including the bridge ends. The roads
		# were blended onto this plane, so the disc and the carriageway meet.
		var rings := maxi(int(ceil(radius / 2.0)), 1)
		var sides := maxi(int(ceil(TAU * radius / 2.0)), 12)
		var prev := PackedVector3Array()
		prev.append(WorldConfig.to_local(Vector3(at.x, _plane_at(item, at.x, at.z) + lift, at.z)))
		for ring in rings:
			var rad := radius * float(ring + 1) / float(rings)
			var ring_pts := PackedVector3Array()
			for s in sides:
				var ang := float(s) / float(sides) * TAU
				var x := at.x + cos(ang) * rad
				var z := at.z + sin(ang) * rad
				ring_pts.append(WorldConfig.to_local(Vector3(x, _plane_at(item, x, z) + lift, z)))
			for s in sides:
				var nxt := (s + 1) % sides
				if prev.size() == 1:
					_tri(surf, prev[0], ring_pts[s], ring_pts[nxt], faces)
				else:
					_tri(surf, prev[s], ring_pts[s], ring_pts[nxt], faces)
					_tri(surf, prev[s], ring_pts[nxt], prev[nxt], faces)
			prev = ring_pts


func _emit_crossings(coord: Vector2i, surf: _Surf, _faces: PackedVector3Array) -> void:
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
		# Visual only. A flat panel on a graded road is a shelf, and the
		# carriageway ribbon already carries collision through the crossing.
		var empty := PackedVector3Array()
		_quad(surf, a, b, d, e, 0.0, along * 2.0, 0.0, half * 2.0, false, empty)


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
		var roads: Array = []
		var dir := Vector3(0.0, 0.0, -1.0)
		for id in item.get("roads", []):
			if not _by_id.has(str(id)):
				continue
			var road: Dictionary = _roads[int(_by_id[str(id)])]
			if bool(road["rail"]):
				continue
			roads.append(road)
			dir = _road_dir(road, at)
		if roads.is_empty():
			continue
		var stand := _sign_stand(at, roads)
		stand.y = at.y
		# Blade A runs along local +X, so it is parallel to the street it names.
		signs.append({
			"at": stand,
			"yaw": atan2(-dir.z, dir.x),
			"a": names[0],
			"b": names[1] if names.size() > 1 else "",
		})
	return signs


## Closest point that sits outside every carriageway at the junction.
func _sign_stand(at: Vector3, roads: Array) -> Vector3:
	var best := at
	var best_d := 1.0e9
	var fallback := at
	var fallback_m := -1.0e9
	for k in 36:
		var ang := TAU * float(k) / 36.0
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var dist := 2.0
		while dist <= 42.0:
			var p := at + dir * dist
			var margin := _stand_margin(p, roads)
			if margin > fallback_m:
				fallback_m = margin
				fallback = p
			if margin >= 1.6 and dist < best_d:
				best_d = dist
				best = p
				break
			dist += 0.5
	if best_d < 1.0e8:
		return best
	return fallback


func _stand_margin(p: Vector3, roads: Array) -> float:
	var margin := 1.0e9
	for road in roads:
		var hit := _closest_half(road, p)
		margin = minf(margin, hit.x - hit.y)
	return margin


## x is the distance to the centreline, y is the local half-width.
func _closest_half(road: Dictionary, p: Vector3) -> Vector2:
	var pts: PackedVector3Array = road["pts"]
	var best := 1.0e9
	var half := float(road["half"])
	for i in pts.size() - 1:
		var hit := _seg_side(p.x, p.z, pts[i].x, pts[i].z, pts[i + 1].x, pts[i + 1].z)
		if hit.x < best:
			best = hit.x
			half = lerpf(_half_at(road, i), _half_at(road, i + 1), hit.y)
	return Vector2(best, half)


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


func _miters(pts: PackedVector3Array, half: float, halves: PackedFloat32Array = PackedFloat32Array()) -> Array:
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	left.resize(pts.size())
	right.resize(pts.size())
	for i in pts.size():
		var h := half
		if i < halves.size():
			h = float(halves[i])
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
		var m := h / clampf(mid.dot(lp), 0.4, 1.0)
		if m > h * 1.8:
			m = h
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


func _cut_join_legacy(grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, jx: float, jz: float, rad: float, flat_y: float) -> void:
	var road_y := flat_y - CUT_CLEAR_M
	var flat_r := rad + SHOULDER_M
	var reach := flat_r + 36.0
	if jx < origin.x - reach or jx > origin.x + 500.0 + reach:
		return
	if jz < origin.y - reach or jz > origin.y + 500.0 + reach:
		return
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


func _joint_lift(_item: Dictionary) -> float:
	return SURFACE_LIFT


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


## Deepest drop within 3 m. A point outside this chunk uses the DEM so a canyon
## that starts just past the seam still gets a rail.
func _guard_drop(mid: Vector3, outward: Vector3, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float) -> float:
	var worst := 0.0
	var any := false
	for dist in [0.5, 1.0, 1.5, 2.0, 2.5, 3.0]:
		var g := _sample_ground(grid, origin, n, spacing, mid.x + outward.x * dist, mid.z + outward.z * dist)
		if g < -70.0:
			continue
		any = true
		worst = maxf(worst, mid.y - g)
	if not any:
		return BARRIER_DROP_M
	return worst


func _sample_ground(grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, x: float, z: float) -> float:
	var max_x := origin.x + float(n - 1) * spacing
	var max_z := origin.y + float(n - 1) * spacing
	if x < origin.x or z < origin.y or x > max_x or z > max_z:
		if _dem.is_valid():
			return float(_dem.call(x, z))
		return -80.0
	return _ground(grid, origin, n, spacing, x, z)


func _guard_edge(surf: _Surf, a: Vector3, b: Vector3, other: Vector3, grid: PackedFloat32Array, origin: Vector2, n: int, spacing: float, faces: PackedVector3Array, rim: bool) -> void:
	var outward := Vector3(a.x - other.x, 0.0, a.z - other.z)
	if outward.length_squared() < 0.01:
		return
	outward = outward.normalized()
	var mid := (a + b) * 0.5
	if _guard_drop(mid, outward, grid, origin, n, spacing) < BARRIER_DROP_M:
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
