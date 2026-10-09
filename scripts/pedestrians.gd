extends Node3D

## Pedestrian population (M2, streaming-aware). Each loaded chunk gets a few walkers on its
## own sidewalk boxes, chosen deterministically from the chunk seed. When a chunk unloads,
## its walkers (and their ragdolls) go; when it loads, new ones appear (a few per frame).
## Car occupants who get out (spawn_exit) join the nearest sidewalk.
## Total population is LaunchConfig.peds (PYLONS_PEDS / --peds, default 16), capped at
## GameConstants.PED_PER_CHUNK_MAX per chunk.

const _Ped := preload("res://scripts/pedestrian.gd")
# Sidewalk top: ROAD_Y 0.025 + 6 kerb units (road_network.gd).
const SIDEWALK_TOP := 0.025 + 6.0 * 3.66 / 72.0
const COATS: Array[Color] = [
	Color(0.25, 0.32, 0.38), Color(0.42, 0.24, 0.22), Color(0.22, 0.28, 0.24),
	Color(0.36, 0.34, 0.3), Color(0.28, 0.26, 0.4), Color(0.62, 0.24, 0.2),
]

var _city: Node
var _queue: Array = []        # [{chunk, index}]
var _riders := 0
var _mats: Dictionary = {}
var _skin: StandardMaterial3D
var _legs: StandardMaterial3D
var spawned := 0
var despawned := 0


func _ready() -> void:
	add_to_group("walker_home")
	_skin = _mat(Color(0.72, 0.62, 0.52))
	_legs = _mat(Color(0.16, 0.16, 0.18))
	_hook.call_deferred()


func _hook() -> void:
	_city = get_tree().get_first_node_in_group("city")
	if _city == null:
		_city = get_parent().get_node_or_null("City")
	if _city == null or not _city.has_method("loaded_chunks"):
		return
	var streamer: Node = _city.get("streamer")
	if streamer != null:
		streamer.window_changed.connect(func(_l: Array) -> void: _sync())
	_sync()


func _quota(loaded: Dictionary) -> Dictionary:
	var out := {}
	var keys: Array = loaded.keys()
	if keys.is_empty():
		return out
	var center: Vector2i = _city.get("streamer").center if _city.get("streamer") != null else Vector2i.ZERO
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da: int = (a - center).length_squared()
		var db: int = (b - center).length_squared()
		return da < db if da != db else (a.x < b.x if a.x != b.x else a.y < b.y))
	var total: int = LaunchConfig.peds
	var base: int = total / keys.size()
	var extra: int = total % keys.size()
	for i in keys.size():
		out[keys[i]] = mini(base + (1 if i < extra else 0), GameConstants.PED_PER_CHUNK_MAX)
	return out


func _sync() -> void:
	var loaded: Dictionary = _city.call("loaded_chunks")
	var quota := _quota(loaded)
	var have := {}
	for child in get_children():
		if not (child is CharacterBody3D) or child.get("home_chunk") == null:
			continue
		var c: Vector2i = child.get("home_chunk")
		if not loaded.has(c):
			despawned += 1
			child.queue_free()
			continue
		have[c] = int(have.get(c, 0)) + 1
	_queue = _queue.filter(func(job: Dictionary) -> bool: return loaded.has(job["chunk"]))
	var queued := {}
	for job in _queue:
		queued[job["chunk"]] = int(queued.get(job["chunk"], 0)) + 1
	for c2 in quota.keys():
		var need: int = int(quota[c2]) - int(have.get(c2, 0)) - int(queued.get(c2, 0))
		var start: int = int(have.get(c2, 0)) + int(queued.get(c2, 0))
		for k in need:
			_queue.append({"chunk": c2, "index": start + k})


func _physics_process(_delta: float) -> void:
	# One new walker per physics frame: a body, a sensor and three boxes, well under 1 ms.
	if _queue.is_empty() or _city == null:
		return
	var job: Dictionary = _queue.pop_front()
	var loaded: Dictionary = _city.call("loaded_chunks")
	var data: RefCounted = loaded.get(job["chunk"])
	if data == null:
		return
	var path := _walk_path(data, int(job["index"]))
	if path.size() < 2:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldConfig.feature_seed(int(data.get("chunk_seed")), "ped%d" % int(job["index"]))
	var ped := _add("Walker_%d_%d_%d" % [job["chunk"].x, job["chunk"].y, int(job["index"])], path, rng.randi_range(0, 1),
		rng.randf_range(1.1, 1.45), COATS[rng.randi_range(0, COATS.size() - 1)])
	ped.set("home_chunk", job["chunk"])


func _walk_path(data: RefCounted, index: int) -> PackedVector3Array:
	var boxes: Array = data.get("walk_boxes")
	var long: Array = []
	for b in boxes:
		if float(b["length"]) >= 10.0:
			long.append(b)
	if long.is_empty():
		return PackedVector3Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldConfig.feature_seed(int(data.get("chunk_seed")), "pedpath%d" % index)
	var box: Dictionary = long[rng.randi_range(0, long.size() - 1)]
	return _box_path(box)


func _box_path(box: Dictionary) -> PackedVector3Array:
	var angle: float = float(box["angle"])
	var dir := Vector3(cos(angle), 0.0, sin(angle))
	var mid: Vector3 = box["mid"]
	var half: float = maxf(float(box["length"]) * 0.5 - 1.0, 0.5)
	var y: float = SIDEWALK_TOP + GameConstants.PED_HEIGHT_M * 0.5
	var a := Vector3(mid.x, y, mid.z) - dir * half
	var b := Vector3(mid.x, y, mid.z) + dir * half
	return PackedVector3Array([a, b])


## A car occupant gets out at `at` and joins the nearest sidewalk.
func spawn_exit(at: Vector3, _dest: Vector3) -> void:
	_riders += 1
	var path := PackedVector3Array()
	var home := WorldConfig.chunk_of(at.x, at.z)
	if _city != null:
		var data: RefCounted = (_city.call("loaded_chunks") as Dictionary).get(home)
		if data != null:
			var best: Dictionary = {}
			var best_d := 1.0e9
			for b in data.get("walk_boxes"):
				var m: Vector3 = b["mid"]
				var d: float = Vector2(m.x - at.x, m.z - at.z).length()
				if d < best_d:
					best_d = d
					best = b
			if not best.is_empty() and best_d < 60.0:
				path = _box_path(best)
	if path.size() < 2:
		var y: float = SIDEWALK_TOP + GameConstants.PED_HEIGHT_M * 0.5
		path = PackedVector3Array([Vector3(at.x, y, at.z), Vector3(at.x + 4.0, y, at.z)])
	var body := _add("Rider%d" % _riders, path, 0, 1.35, COATS[5])
	body.global_position = Vector3(at.x, SIDEWALK_TOP + GameConstants.PED_HEIGHT_M * 0.5, at.z)
	body.set("home_chunk", home)
	body._joined = false
	body.add_to_group("injured")


func _add(node_name: String, path: PackedVector3Array, start: int, walk_speed: float, coat: Color) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 1
	body.set_script(_Ped)
	var index: int = start % path.size()
	body.points = path
	body.point_index = (index + 1) % path.size()
	body.speed = walk_speed
	body.position = path[index]
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = GameConstants.PED_HEIGHT_M
	capsule.radius = GameConstants.PED_RADIUS_M
	shape.shape = capsule
	body.add_child(shape)
	# Visual: 1.70 m tall at 1.0x scale (spec), boxes only, no face.
	var visual := Node3D.new()
	visual.name = "Visual"
	body.add_child(visual)
	_mesh(visual, "Legs", Vector3(0.0, -0.43, 0.0), Vector3(0.34, 0.84, 0.24), _legs)
	_mesh(visual, "Coat", Vector3(0.0, 0.25, 0.0), Vector3(0.46, 0.56, 0.3), _coat(coat))
	_mesh(visual, "Head", Vector3(0.0, 0.70, 0.0), Vector3(0.26, 0.28, 0.26), _skin)
	add_child(body)
	spawned += 1
	return body


func _coat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mats.has(key):
		_mats[key] = _mat(c)
	return _mats[key]


func _mat(c: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 0.8
	return mat


func _mesh(parent: Node3D, node_name: String, at: Vector3, size: Vector3, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	mesh.material_override = mat
	parent.add_child(mesh)
