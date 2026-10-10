extends SceneTree
## Road-alignment checker (M2). Generates a region of chunks (pure data, worker threads)
## and verifies that roads meet across every shared chunk edge:
##  1. asphalt: the road cross-sections just inside each side of an edge (0.3 m in) must
##     match interval for interval (ends within TOL_M), so no road stops at a border or
##     shifts sideways across it;
##  2. lanes: no drive-graph lane end dangles within 2 m of an edge once both chunks'
##     lanes are merged (lanes that cross must join);
##  3. anchors: the generator's border_anchors() for the edge, seen from both chunks, agree.
##
##   godot --headless --path . -s res://tools/road_alignment_check.gd -- [--region=-3,-3,3,3] [--seed=N] [--out=user://road_alignment.json]
## Exit code 0 = every edge matches.

const TOL_M := 0.10
const STEP_M := 0.05
const INSET_M := 0.3
const DEEP_M := 4.5

var x0 := -3
var z0 := -3
var x1 := 3
var z1 := 3
var seed := 20261008
var out_path := "user://road_alignment.json"
## --self-test: shift chunk (x0, z0)'s asphalt by 0.5 m; the check must then FAIL.
var self_test := false


func _initialize() -> void:
	for raw in OS.get_cmdline_user_args():
		var a := String(raw)
		if a.begins_with("--region="):
			var p := a.substr(9).split(",")
			x0 = int(p[0]); z0 = int(p[1]); x1 = int(p[2]); z1 = int(p[3])
		elif a.begins_with("--seed="):
			seed = int(a.substr(7))
		elif a.begins_with("--out="):
			out_path = a.substr(6)
		elif a == "--self-test":
			self_test = true
	var cfg: Script = load("res://scripts/world/world_config.gd")
	var gen: Resource = load("res://scripts/world/road_chunk_generator.gd").new()
	gen.prepare()
	var t0 := Time.get_ticks_msec()
	var boxes := {}
	var ids: Array[int] = []
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var c := Vector2i(x, z)
			var box := {"d": null}
			boxes[c] = box
			ids.append(WorkerThreadPool.add_task(func() -> void: box["d"] = gen.generate(c, seed), false, "align %s" % str(c)))
	for id in ids:
		WorkerThreadPool.wait_for_task_completion(id)
	var gen_s := (Time.get_ticks_msec() - t0) / 1000.0
	if self_test:
		var victim: RefCounted = boxes[Vector2i(x0, z0)]["d"]
		for item in victim.get("road_rects"):
			var r0: Rect2 = item["area"]
			item["area"] = Rect2(r0.position + Vector2(0.5, 0.5), r0.size)
		print("ALIGN self-test: shifted chunk %s by 0.5 m; expecting FAIL" % str(Vector2i(x0, z0)))
	print("ALIGN generated %d chunks in %.1f s (seed %d)" % [boxes.size(), gen_s, seed])
	var edges: Array = []
	var bad := 0
	var crossings := 0
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var c := Vector2i(x, z)
			if x < x1:
				var r := _check(cfg, gen, boxes, c, c + Vector2i(1, 0), true)
				edges.append(r)
			if z < z1:
				var r2 := _check(cfg, gen, boxes, c, c + Vector2i(0, 1), false)
				edges.append(r2)
	for r3 in edges:
		crossings += int(r3["roads"])
		if not bool(r3["ok"]):
			bad += 1
			print("ALIGN MISMATCH %s" % JSON.stringify(r3))
	var report := {"seed": seed, "region": [x0, z0, x1, z1], "chunks": boxes.size(), "edges": edges.size(),
		"edges_bad": bad, "road_crossings": crossings, "tolerance_m": TOL_M, "generate_s": gen_s, "detail": edges}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
	print("ALIGN %s: %d edges, %d road crossings, %d mismatched edges, tolerance %.2f m | json %s" % [
		"PASS" if bad == 0 else "FAIL", edges.size(), crossings, bad, TOL_M, ProjectSettings.globalize_path(out_path)])
	quit(0 if bad == 0 else 1)


## Edge between chunk a and its east (along_z) or north neighbour b.
func _check(cfg: Script, gen: Resource, boxes: Dictionary, a: Vector2i, b: Vector2i, east: bool) -> Dictionary:
	var da: RefCounted = boxes[a]["d"]
	var db: RefCounted = boxes[b]["d"]
	var ob: Vector2 = cfg.chunk_origin(b)
	var line: float = ob.x if east else ob.y        # the shared border coordinate
	var lo: float = ob.y if east else ob.x          # edge runs from lo to lo + size
	var size: float = cfg.CHUNK_SIZE_M
	var rects: Array = []
	for item in da.get("road_rects"):
		rects.append(item["area"])
	for item2 in db.get("road_rects"):
		rects.append(item2["area"])
	var near: Array = []
	for r in rects:
		var rr: Rect2 = r
		var lo_c: float = rr.position.x if east else rr.position.y
		var hi_c: float = rr.end.x if east else rr.end.y
		if hi_c >= line - DEEP_M - 0.01 and lo_c <= line + DEEP_M + 0.01:
			near.append(rr)
	# Cross-sections at four depths: deep in A, just inside A, just inside B, deep in B.
	# A tile may straddle the border (one chunk owns it), so the shallow pair alone could
	# pass trivially; the deep sections check each chunk's own road continues the same way.
	var depths: Array[float] = [-DEEP_M, -INSET_M, INSET_M, DEEP_M]
	var secs: Array = []
	for dpt in depths:
		secs.append(_intervals(near, east, line + dpt, lo, size))
	var side_a: Array[Vector2] = secs[1]
	var problems: Array = []
	var res_a := _match(secs[1], secs[2])
	var res_b := _match(secs[2], secs[1])
	for bad_a in res_a["bad"]:
		problems.append("road %.2f-%.2f on %s side has no match" % [bad_a.x, bad_a.y, str(a)])
	for bad_b in res_b["bad"]:
		problems.append("road %.2f-%.2f on %s side has no match" % [bad_b.x, bad_b.y, str(b)])
	for pair in [[0, 1, a], [3, 2, b]]:
		var deep: Array[Vector2] = secs[pair[0]]
		var shallow: Array[Vector2] = secs[pair[1]]
		for bad_d in _match(shallow, deep)["bad"]:
			problems.append("road %.2f-%.2f at the edge does not continue %.1f m into %s" % [bad_d.x, bad_d.y, DEEP_M, str(pair[2])])
	# Lanes: merge both chunks' drive edges; count degree-1 nodes within 2 m of the edge.
	var degree := {}
	var pos := {}
	for d in [da, db]:
		for e in d.get("drive_edges"):
			for end in [Vector2(float(e["ax"]), float(e["az"])), Vector2(float(e["bx"]), float(e["bz"]))]:
				var key := Vector2i(int(round(end.x * 4.0)), int(round(end.y * 4.0)))
				degree[key] = int(degree.get(key, 0)) + 1
				pos[key] = end
	var dangling := 0
	for key2 in degree.keys():
		if int(degree[key2]) != 1:
			continue
		var p: Vector2 = pos[key2]
		var off: float = (p.x if east else p.y) - line
		var along: float = p.y if east else p.x
		if absf(off) <= 2.0 and along > lo + 1.0 and along < lo + size - 1.0:
			dangling += 1
	if dangling > 0:
		problems.append("%d lane end(s) dangle within 2 m of the edge" % dangling)
	# Anchors from both sides.
	var side_e: int = gen.SIDE_EAST if east else gen.SIDE_NORTH
	var side_w: int = gen.SIDE_WEST if east else gen.SIDE_SOUTH
	var anc_a: Array = gen.border_anchors(a, side_e, seed)
	var anc_b: Array = gen.border_anchors(b, side_w, seed)
	var anchors_ok: bool = JSON.stringify(anc_a) == JSON.stringify(anc_b)
	if not anchors_ok:
		problems.append("border_anchors differ: %d vs %d" % [anc_a.size(), anc_b.size()])
	return {"a": [a.x, a.y], "b": [b.x, b.y], "edge": "east" if east else "north", "roads": int(res_a["matched"]) + int(res_a["tee"]) + int(res_b["tee"]),
		"matched": res_a["matched"], "tees": int(res_a["tee"]) + int(res_b["tee"]), "along_edge": int(res_a["along"]) + int(res_b["along"]),
		"anchors": anc_a.size(), "dangling_lanes": dangling, "ok": problems.is_empty(), "problems": problems}


## A crossing on one side is fine when the other side has the same interval (ends within
## TOL_M), or when it runs into a road lying along the edge on the other side (a T: the
## interval sits inside a longer one). Intervals longer than ALONG_M are roads running
## along the edge itself and need no counterpart.
const ALONG_M := 20.0


func _match(mine: Array[Vector2], other: Array[Vector2]) -> Dictionary:
	var bad: Array[Vector2] = []
	var matched := 0
	var tee := 0
	var along := 0
	for iv in mine:
		var ok := false
		for ov in other:
			if absf(ov.x - iv.x) <= TOL_M and absf(ov.y - iv.y) <= TOL_M:
				ok = true
				matched += 1
				break
		if ok:
			continue
		if iv.y - iv.x > ALONG_M:
			along += 1
			continue
		for ov2 in other:
			if ov2.y - ov2.x > ALONG_M and iv.x >= ov2.x - TOL_M and iv.y <= ov2.y + TOL_M:
				ok = true
				tee += 1
				break
		if not ok:
			bad.append(iv)
	return {"bad": bad, "matched": matched, "tee": tee, "along": along}


## Covered intervals (in metres along the edge, from its low corner) on the line
## (x = at if east, else z = at), sampled every STEP_M.
func _intervals(rects: Array, east: bool, at: float, lo: float, size: float) -> Array[Vector2]:
	var spans: Array[Vector2] = []
	for r in rects:
		var rr: Rect2 = r
		var c_lo: float = rr.position.x if east else rr.position.y
		var c_hi: float = rr.end.x if east else rr.end.y
		if at < c_lo or at > c_hi:
			continue
		var s0: float = (rr.position.y if east else rr.position.x) - lo
		var s1: float = (rr.end.y if east else rr.end.x) - lo
		spans.append(Vector2(clampf(s0, 0.0, size), clampf(s1, 0.0, size)))
	spans.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
	var merged: Array[Vector2] = []
	for s in spans:
		if s.y - s.x <= 0.0:
			continue
		if not merged.is_empty() and s.x <= merged[merged.size() - 1].y + STEP_M:
			merged[merged.size() - 1].y = maxf(merged[merged.size() - 1].y, s.y)
		else:
			merged.append(s)
	return merged
