extends RefCounted

## Session persistence for streamed chunks (M2).
##
## When a chunk unloads, the cones and wrecks standing in it are saved as a sparse delta
## in memory, and reapplied when the chunk loads again:
## - Generated cone stacks have stable ids "seed:cx:cz:index". A stack still in its
##   generated pose is not stored at all (it regenerates identically). A moved stack, or
##   one with a different piece count, is stored with its transform and pieces.
##   A stack that no longer exists (taken into the player's stack) is remembered as gone.
## - Loose cones the player dropped or knocked off get a session id "p:N" the first time
##   an unloading chunk sees them, and are stored the same way.
## - A cone is stored in the chunk it stands in when that chunk unloads, wherever it
##   was generated; its home chunk skips it on reload.
## - Wrecks (crashed cars, still or rigid) are detached from the scene and kept as nodes,
##   then re-attached on reload.
## Nothing is written to disk. A new game (a new process) starts clean.

const _WorldCone := preload("res://scripts/world_cone.gd")
const _CONE := preload("res://scenes/player/standard_cone.tscn")
const MOVED_M := 0.05
const SITES_PER_JOB := 2
const MAX_STASHED_WRECKS := 24

var _streamer: Node
var _seed := 0
var _live: Dictionary = {}     # id -> body
var _origin: Dictionary = {}   # generated id -> {xf, count}
var _saved: Dictionary = {}    # Vector2i -> {id: record}
var _where: Dictionary = {}    # id -> Vector2i (chunk whose delta holds it)
var _gone: Dictionary = {}     # generated id -> true
var _wrecks: Dictionary = {}   # Vector2i -> Array of {node, parent}
var _player_seq := 0
var _wreck_order: Array[Vector2i] = []


func setup(streamer: Node, world_seed: int) -> void:
	_streamer = streamer
	_seed = world_seed


func site_id(chunk: Vector2i, index: int) -> String:
	return "%d:%d:%d:%d" % [_seed, chunk.x, chunk.y, index]


func saved_count() -> int:
	var n := 0
	for c in _saved.keys():
		n += (_saved[c] as Dictionary).size()
	return n


func summary() -> Dictionary:
	var wrecks := 0
	for c in _wrecks.keys():
		wrecks += (_wrecks[c] as Array).size()
	return {"saved_cones": saved_count(), "gone": _gone.size(), "live": _live.size(), "stashed_wrecks": wrecks}


func _tree() -> SceneTree:
	return _streamer.get_tree()


func _sweep() -> void:
	for id in _live.keys():
		var body: Variant = _live[id]
		if is_instance_valid(body) and (body as Node).is_inside_tree():
			continue
		_live.erase(id)
		if _origin.has(id) and not _where.has(id):
			_gone[id] = true


func _held_by_soul(node: Node) -> bool:
	var n := node
	while n != null:
		if n.is_in_group("soul"):
			return true
		n = n.get_parent()
	return false


## Unload: store the delta for everything standing in `chunk`, detach it from physics now,
## and return small jobs that free the nodes over the next frames.
func capture(chunk: Vector2i) -> Array[Callable]:
	var doomed: Array = []
	_sweep()
	var rect := WorldConfig.chunk_rect(chunk)
	var saved: Dictionary = _saved.get(chunk, {})
	for node in _tree().get_nodes_in_group("stack_target"):
		if not (node is RigidBody3D) or _held_by_soul(node):
			continue
		var body := node as RigidBody3D
		var p := body.global_position
		if not rect.has_point(Vector2(p.x, p.z)):
			continue
		var id := str(body.get_meta("cone_id", ""))
		if id == "":
			_player_seq += 1
			id = "p:%d" % _player_seq
		var rec := _snapshot(body)
		_live.erase(id)
		if (rec["pieces"] as Array).is_empty():
			if _origin.has(id):
				_gone[id] = true
		elif _origin.has(id) and _unchanged(id, rec):
			saved.erase(id)
			_where.erase(id)
		else:
			saved[id] = rec
			_where[id] = chunk
		body.remove_from_group("stack_target")
		body.process_mode = Node.PROCESS_MODE_DISABLED
		body.visible = false
		body.collision_layer = 0
		body.collision_mask = 0
		body.freeze = true
		doomed.append(body)
	_saved[chunk] = saved
	var stash: Array = []
	for node2 in _wreck_nodes():
		var n3 := node2 as Node3D
		var q := n3.global_position
		if not rect.has_point(Vector2(q.x, q.z)):
			continue
		var parent := n3.get_parent()
		var keep_xf := n3.global_transform
		parent.remove_child(n3)
		stash.append({"node": n3, "parent": parent, "xf": keep_xf})
	if not stash.is_empty():
		var have: Array = _wrecks.get(chunk, [])
		have.append_array(stash)
		_wrecks[chunk] = have
		_wreck_order.append(chunk)
	_cap_wrecks()
	var jobs: Array[Callable] = []
	var at := 0
	while at < doomed.size():
		jobs.append(_free_batch.bind(doomed.slice(at, at + SITES_PER_JOB)))
		at += SITES_PER_JOB
	return jobs


func _free_batch(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			(n as Node).free()


## Stashed wrecks are detached node trees; keep at most MAX_STASHED_WRECKS for the session
## (oldest freed first) so a long drive can't grow memory without bound.
func _cap_wrecks() -> void:
	var total := 0
	for c in _wrecks.keys():
		total += (_wrecks[c] as Array).size()
	while total > MAX_STASHED_WRECKS and not _wreck_order.is_empty():
		var c2: Vector2i = _wreck_order.pop_front()
		var list: Array = _wrecks.get(c2, [])
		if list.is_empty():
			continue
		var rec: Dictionary = list.pop_front()
		if is_instance_valid(rec["node"]):
			(rec["node"] as Node).free()
		total -= 1
		if list.is_empty():
			_wrecks.erase(c2)
		else:
			_wrecks[c2] = list


func stashed_nodes() -> int:
	var n := 0
	for c in _wrecks.keys():
		for rec in (_wrecks[c] as Array):
			if is_instance_valid(rec["node"]):
				n += _count_tree(rec["node"])
	return n


func _count_tree(node: Node) -> int:
	var n := 1
	for c in node.get_children():
		n += _count_tree(c)
	return n


func _wreck_nodes() -> Array:
	var out: Array = []
	for node in _tree().get_nodes_in_group("vehicle"):
		if node is RigidBody3D and node is Node3D:
			out.append(node)
	for node2 in _tree().get_nodes_in_group("hitter"):
		if node2 is Node3D and bool(node2.get("_wrecked")):
			out.append(node2)
	for node3 in _tree().get_nodes_in_group("wreck_hulk"):
		if node3 is Node3D and not out.has(node3):
			out.append(node3)
	return out


func _snapshot(body: RigidBody3D) -> Dictionary:
	var pieces: Array = []
	for child in body.get_children():
		if child is Node3D and child.has_method("piece_height"):
			var piece := child as Node3D
			pieces.append({"scene": piece.scene_file_path, "xf": piece.transform})
	return {"xf": body.global_transform, "pieces": pieces}


func _unchanged(id: String, rec: Dictionary) -> bool:
	var o: Dictionary = _origin[id]
	if (rec["pieces"] as Array).size() != int(o["count"]):
		return false
	var a: Transform3D = rec["xf"]
	var b: Transform3D = o["xf"]
	if a.origin.distance_to(b.origin) > MOVED_M:
		return false
	return a.basis.y.dot(b.basis.y) > 0.999 and a.basis.x.dot(b.basis.x) > 0.999


## Load: spawn this chunk's cone stacks (minus gone/moved-away ones), the stored delta, and wrecks.
func restore_jobs(chunk: Vector2i, data: ChunkData) -> Array[Callable]:
	var jobs: Array[Callable] = []
	var at := 0
	while at < data.cone_sites.size():
		jobs.append(_restore_sites.bind(chunk, data.cone_sites, at, mini(at + SITES_PER_JOB, data.cone_sites.size())))
		at += SITES_PER_JOB
	jobs.append(_restore_rest.bind(chunk))
	return jobs


func _cone_root() -> Node:
	var city: Node = _streamer.get("_city")
	if city != null and city.has_method("cone_root"):
		return city.cone_root()
	return _streamer


func _restore_sites(chunk: Vector2i, sites: Array, from: int, to: int) -> void:
	_sweep()
	var saved: Dictionary = _saved.get(chunk, {})
	var root := _cone_root()
	for i in range(from, to):
		var id := site_id(chunk, i)
		var spec: Dictionary = sites[i]
		if _gone.has(id):
			continue
		if _live.has(id):
			continue
		if _where.has(id) and _where[id] != chunk:
			continue
		var body: RigidBody3D
		if saved.has(id):
			body = _spawn_record(root, saved[id])
			saved.erase(id)
			_where.erase(id)
		else:
			body = _spawn_site(root, spec)
		body.name = "ConeStack_%d_%d_%d" % [chunk.x, chunk.y, i]
		body.set_meta("cone_id", id)
		_live[id] = body
		if not _origin.has(id):
			var count := 0
			for child in body.get_children():
				if child.has_method("piece_height"):
					count += 1
			_origin[id] = {"xf": body.global_transform, "count": count}


func _restore_rest(chunk: Vector2i) -> void:
	var saved: Dictionary = _saved.get(chunk, {})
	var root := _cone_root()
	for id in saved.keys():
		if _origin.has(id):
			# A generated stack from another chunk that came to rest here.
			pass
		var body := _spawn_record(root, saved[id])
		body.set_meta("cone_id", id)
		_live[id] = body
		_where.erase(id)
	_saved.erase(chunk)
	for item in _wrecks.get(chunk, []):
		var node: Node3D = item["node"]
		var parent: Node = item["parent"]
		if not is_instance_valid(node):
			continue
		if not is_instance_valid(parent):
			parent = _cone_root()
		parent.add_child(node)
		node.global_transform = item["xf"]
	_wrecks.erase(chunk)


func _spawn_site(root: Node, spec: Dictionary) -> RigidBody3D:
	var body := _WorldCone.new() as RigidBody3D
	body.position = spec["at"]
	body.rotation.y = float(spec["yaw"])
	var extra: float = GameConstants.STANDARD_EXTRA
	var height: float = GameConstants.STANDARD_H
	for i in int(spec["count"]):
		var piece := _CONE.instantiate() as Node3D
		body.add_child(piece)
		piece.position = Vector3(0.0, float(i) * extra + height * 0.5, 0.0)
	root.add_child(body)
	return body


func _spawn_record(root: Node, rec: Dictionary) -> RigidBody3D:
	var body := _WorldCone.new() as RigidBody3D
	for p in rec["pieces"]:
		var path := str(p["scene"])
		var scene: PackedScene = load(path) if path != "" else _CONE
		var piece := scene.instantiate() as Node3D
		body.add_child(piece)
		piece.transform = p["xf"]
	root.add_child(body)
	body.global_transform = rec["xf"]
	return body
