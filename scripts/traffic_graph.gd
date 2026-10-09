extends RefCounted

## Lane graph assembly for streamed chunks (M2). Pure data, runs on a WorkerThreadPool
## thread; Traffic swaps the result in on the main thread.
##
## Only edges whose two ends both sit in loaded chunks are used, so no trip can lead into
## an unloaded chunk. Nodes merge by position (0.25 m grid), which is how lanes join across
## a chunk border: both chunks emit the same lattice crossing points.

const CELL := 24.0


static func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / CELL)), int(floor(z / CELL)))


static func build(chunk_edges: Array, chunk_controls: Array, loaded: Dictionary, chunk_m: float, shuffle_seed: int) -> Dictionary:
	var node_at: Array[Vector2] = []
	var leave: Array = []
	var index: Dictionary = {}
	var seen: Dictionary = {}
	var dropped := 0
	for edges in chunk_edges:
		for raw in edges:
			var edge: Dictionary = raw
			var a := Vector2(float(edge["ax"]), float(edge["az"]))
			var b := Vector2(float(edge["bx"]), float(edge["bz"]))
			var ca := Vector2i(int(floor(a.x / chunk_m)), int(floor(a.y / chunk_m)))
			var cb := Vector2i(int(floor(b.x / chunk_m)), int(floor(b.y / chunk_m)))
			if not loaded.has(ca) or not loaded.has(cb):
				dropped += 1
				continue
			var ia := _node_id(index, node_at, leave, a)
			var ib := _node_id(index, node_at, leave, b)
			if ia == ib:
				continue
			var length: float = maxf(float(edge["length"]), 0.5)
			_add_hop(seen, leave, ia, ib, edge["forward"], length)
			_add_hop(seen, leave, ib, ia, edge["back"], length)
	var in_main := _main_component(node_at, leave)
	# Spatial index of every hop polyline segment (for picking a departure lane).
	var hop_grid: Dictionary = {}
	var spots: Array = []
	for ni in leave.size():
		var outs: Array = leave[ni]
		for hi in outs.size():
			var poly: PackedVector3Array = outs[hi]["poly"]
			for k in range(poly.size() - 1):
				var p: Vector3 = poly[k]
				var q: Vector3 = poly[k + 1]
				var c0 := cell_of(minf(p.x, q.x), minf(p.z, q.z))
				var c1 := cell_of(maxf(p.x, q.x), maxf(p.z, q.z))
				for cx in range(c0.x, c1.x + 1):
					for cz in range(c0.y, c1.y + 1):
						var key := Vector2i(cx, cz)
						if not hop_grid.has(key):
							hop_grid[key] = []
						(hop_grid[key] as Array).append(Vector3i(ni, hi, k))
			if in_main[ni] == 0:
				continue
			# Parking spots for new cars, every 18 m along the lane.
			for k2 in range(1, poly.size()):
				var a2: Vector3 = poly[k2 - 1]
				var b2: Vector3 = poly[k2]
				var delta := Vector2(b2.x - a2.x, b2.z - a2.z)
				var span: float = delta.length()
				if span < 6.0:
					continue
				var face := Vector3(delta.x / span, 0.0, delta.y / span)
				var t: float = 6.0
				while t < span - 2.0:
					spots.append({"at": Vector3(a2.x, 0.65, a2.z) + face * t, "face": face})
					t += 18.0
	var rng := RandomNumberGenerator.new()
	rng.seed = shuffle_seed
	for i in range(spots.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = spots[i]
		spots[i] = spots[j]
		spots[j] = tmp
	var lights: Array[Dictionary] = []
	var stops: Array[Dictionary] = []
	for rows in chunk_controls:
		for item in rows:
			var row: Dictionary = item
			var pos: Vector3 = row["pos"]
			if not loaded.has(Vector2i(int(floor(pos.x / chunk_m)), int(floor(pos.z / chunk_m)))):
				continue
			if str(row["mode"]) == "light":
				lights.append({"pos": pos, "dir": row["dir"], "kind": int(row["kind"])})
			else:
				stops.append({"pos": pos, "dir": row["dir"], "kind": 0, "cross": Vector2(float(row["cx"]), float(row["cz"]))})
	return {
		"node_at": node_at, "leave": leave, "in_main": in_main, "hop_grid": hop_grid,
		"spots": spots, "lights": lights, "stops": stops,
		"light_grid": line_grid(lights), "stop_grid": line_grid(stops), "dropped": dropped,
		"loaded": loaded.duplicate(),
	}


static func line_grid(lines: Array) -> Dictionary:
	var grid: Dictionary = {}
	for i in lines.size():
		var pos: Vector3 = lines[i]["pos"]
		var key := cell_of(pos.x, pos.z)
		if not grid.has(key):
			grid[key] = PackedInt32Array()
		var bucket: PackedInt32Array = grid[key]
		bucket.append(i)
		grid[key] = bucket
	return grid


static func _node_id(index: Dictionary, node_at: Array[Vector2], leave: Array, at: Vector2) -> int:
	var key := Vector2i(int(round(at.x * 4.0)), int(round(at.y * 4.0)))
	if index.has(key):
		return int(index[key])
	var id: int = node_at.size()
	index[key] = id
	node_at.append(at)
	leave.append([])
	return id


static func _add_hop(seen: Dictionary, leave: Array, frm: int, to: int, poly: PackedVector3Array, length: float) -> void:
	if poly.size() < 2:
		return
	var key := Vector2i(frm, to)
	if seen.has(key):
		return
	seen[key] = true
	(leave[frm] as Array).append({"to": to, "poly": poly, "length": length})


static func _main_component(node_at: Array[Vector2], leave: Array) -> PackedByteArray:
	var n := node_at.size()
	var comp := PackedInt32Array()
	comp.resize(n)
	comp.fill(-1)
	var sizes: Array[int] = []
	# Undirected reachability (lanes are paired both ways).
	for start in n:
		if comp[start] >= 0:
			continue
		var id := sizes.size()
		var count := 0
		var stack: Array[int] = [start]
		comp[start] = id
		while not stack.is_empty():
			var at: int = stack.pop_back()
			count += 1
			for hop in (leave[at] as Array):
				var nxt: int = int(hop["to"])
				if comp[nxt] < 0:
					comp[nxt] = id
					stack.append(nxt)
		sizes.append(count)
	var best := 0
	for i in sizes.size():
		if sizes[i] > sizes[best]:
			best = i
	var out := PackedByteArray()
	out.resize(n)
	for i2 in n:
		out[i2] = 1 if comp[i2] == best else 0
	return out


## A* (straight-line heuristic, admissible: a hop is never shorter than its chord) with a
## binary heap. Returns the node chain start..goal, or [] if unreachable.
static func path(node_at: Array[Vector2], leave: Array, start: int, goal: int) -> Array[int]:
	var none: Array[int] = []
	var count: int = node_at.size()
	if start < 0 or goal < 0 or start >= count or goal >= count or start == goal:
		return none
	var target: Vector2 = node_at[goal]
	var dist := PackedFloat32Array()
	dist.resize(count)
	dist.fill(1.0e12)
	var prev := PackedInt32Array()
	prev.resize(count)
	prev.fill(-1)
	var done := PackedByteArray()
	done.resize(count)
	var heap_d := PackedFloat32Array()
	var heap_n := PackedInt32Array()
	dist[start] = 0.0
	_push(heap_d, heap_n, node_at[start].distance_to(target), start)
	while heap_n.size() > 0:
		var at: int = heap_n[0]
		_pop(heap_d, heap_n)
		if done[at] == 1:
			continue
		done[at] = 1
		if at == goal:
			break
		var d: float = dist[at]
		for hop in (leave[at] as Array):
			var nxt: int = int(hop["to"])
			if done[nxt] == 1:
				continue
			var alt: float = d + float(hop["length"])
			if alt < dist[nxt]:
				dist[nxt] = alt
				prev[nxt] = at
				_push(heap_d, heap_n, alt + node_at[nxt].distance_to(target), nxt)
	if prev[goal] < 0:
		return none
	var chain: Array[int] = []
	var cursor := goal
	var guard := 0
	while cursor >= 0 and guard <= count:
		chain.append(cursor)
		if cursor == start:
			break
		cursor = prev[cursor]
		guard += 1
	if chain.is_empty() or chain[chain.size() - 1] != start:
		return none
	chain.reverse()
	return chain


static func _push(hd: PackedFloat32Array, hn: PackedInt32Array, d: float, n: int) -> void:
	hd.append(d)
	hn.append(n)
	var i := hd.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if hd[p] <= hd[i]:
			break
		var td := hd[p]; hd[p] = hd[i]; hd[i] = td
		var tn := hn[p]; hn[p] = hn[i]; hn[i] = tn
		i = p


static func _pop(hd: PackedFloat32Array, hn: PackedInt32Array) -> void:
	var last := hd.size() - 1
	hd[0] = hd[last]
	hn[0] = hn[last]
	hd.resize(last)
	hn.resize(last)
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < last and hd[l] < hd[m]:
			m = l
		if r < last and hd[r] < hd[m]:
			m = r
		if m == i:
			break
		var td := hd[m]; hd[m] = hd[i]; hd[i] = td
		var tn := hn[m]; hn[m] = hn[i]; hn[i] = tn
		i = m
