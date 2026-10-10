class_name ChunkStreamer
extends Node3D

## Streams a 3x3 window of chunks around the player (M2).
##
## Generation (ChunkGenerator.generate) runs on WorkerThreadPool threads. The results come
## back as ChunkData; the main thread then runs the generator's build jobs plus the city
## registration jobs under a per-frame time budget, so no single frame pays for a whole
## chunk. Unloading saves the chunk's persistence delta, unregisters it and frees its nodes,
## also in budgeted steps.
##
## Signals tell the rest of the game what is loaded: City keeps its road lookups per chunk,
## Traffic rebuilds its lane graph from the loaded chunks only (window_changed), and the
## pedestrian manager respawns walkers on loaded sidewalks.

signal chunk_loaded(coord: Vector2i, data: ChunkData)
signal chunk_unloading(coord: Vector2i)
signal chunk_unloaded(coord: Vector2i)
signal window_changed(loaded: Array)
## Spawn chunk: ground and the road/sidewalk under the player are in the tree.
signal spawn_floor_ready(spawn: Vector3)

const _Persistence := preload("res://scripts/world/chunk_persistence.gd")

## Main-thread time the streamer may spend per frame on build/unload steps, in microseconds.
@export var frame_budget_usec := 3000
## How far (m) the player must be inside a new chunk before the window recentres.
@export var hysteresis_m := 24.0
## Generation tasks allowed in flight at once.
@export var max_tasks := 2
## Recently unloaded chunk data kept in memory to skip regeneration on return.
@export var data_cache_size := 4

var world_seed := 0
var world_generator: ChunkGenerator
## Supplies the 3x3 core around chunk (0,0). Defaults to world_generator.
var core_generator: ChunkGenerator
var persistence: RefCounted
var target: Node3D
var center := Vector2i.ZERO

var _entries: Dictionary = {}   # Vector2i -> Dictionary
var _cache: Dictionary = {}     # Vector2i -> ChunkData
var _cache_order: Array[Vector2i] = []
var _window_dirty := false
var _city: Node

# Stats
var loads := 0
var unloads := 0
var gen_usec_total := 0
var gen_usec_max := 0
var frame_usec_max := 0
var frame_usec_hist: PackedInt32Array = PackedInt32Array()
var last_frame_usec := 0
var job_usec_max := 0
var job_usec_max_name := ""
## Boot generate runs on a plain Thread so its shadow tasks can wait on the pool.
var _boot_thread: Thread
## Keeps the worker object alive. The thread callable does not.
var _boot_job: RefCounted
var _boot_box: Dictionary = {}
var _boot_coord := Vector2i.ZERO
var _boot_floor_done := false
## Milliseconds since process start, for the boot probe.
var boot_started_ms := 0
var boot_floor_at_ms := -1
var boot_gen_at_ms := -1
var boot_floor_build_usec := 0


## One-shot worker for the spawn chunk. Not a pool task: it waits on shadow tasks.
class _BootRun:
	extends RefCounted
	var gen: ChunkGenerator
	var coord: Vector2i
	var seed: int
	var box: Dictionary

	func run() -> void:
		var data: ChunkData = gen.generate(coord, seed, box)
		var lock: Mutex = box["mutex"]
		lock.lock()
		box["data"] = data
		box["done"] = true
		lock.unlock()


func setup(city: Node, seed: int, generator: ChunkGenerator, core: ChunkGenerator = null) -> void:
	_city = city
	world_seed = seed
	world_generator = generator
	core_generator = core if core != null else generator
	world_generator.prepare()
	if world_generator.region != null:
		world_generator.region.prepare()
	if core_generator != world_generator:
		core_generator.prepare()
		if core_generator.region != null:
			core_generator.region.prepare()
	persistence = _Persistence.new()
	persistence.setup(self, seed)


func generator_for(coord: Vector2i) -> ChunkGenerator:
	return core_generator if WorldConfig.is_core(coord) else world_generator


func is_loaded(coord: Vector2i) -> bool:
	return _entries.has(coord) and str(_entries[coord]["state"]) == "loaded"


func loaded_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in _entries.keys():
		if str(_entries[c]["state"]) == "loaded":
			out.append(c)
	out.sort()
	return out


func data_for(coord: Vector2i) -> ChunkData:
	if _entries.has(coord):
		return _entries[coord].get("data")
	return null


func host_for(coord: Vector2i) -> Node3D:
	if _entries.has(coord):
		return _entries[coord].get("host")
	return null


func busy() -> bool:
	for c in _entries.keys():
		if str(_entries[c]["state"]) != "loaded":
			return true
	for c2 in WorldConfig.window(center):
		if not _entries.has(c2):
			return true
	return false


## Synchronous load (tools, teleport). Boot uses start_boot so the first frame is not this.
func load_now(coord: Vector2i) -> ChunkData:
	center = coord
	var data: ChunkData = _cached(coord)
	if data == null:
		data = generator_for(coord).generate(coord, world_seed)
		_note_gen(data)
	var e := _start_build(coord, data)
	while int(e["job_i"]) < (e["jobs"] as Array).size():
		# A step returns true when it stopped early and must run again.
		var step: Variant = (e["jobs"][e["job_i"]] as Callable).call()
		if step == true:
			continue
		e["job_i"] = int(e["job_i"]) + 1
	_finish_build(coord, e)
	return data


## Spawn chunk: ground goes in now, generation runs off the main thread.
## `focus` is the stand point when the launch overrides the sidewalk spawn.
func start_boot(coord: Vector2i, focus: Variant = null) -> void:
	center = coord
	_boot_coord = coord
	_boot_floor_done = false
	boot_started_ms = Time.get_ticks_msec()
	var host := Node3D.new()
	host.name = "Chunk_%d_%d" % [coord.x, coord.y]
	host.set_meta("chunk", coord)
	add_child(host)
	var gen := generator_for(coord)
	if gen.has_method("_ground_job"):
		gen.call("_ground_job", coord, host)
	var box := {
		"boot": true,
		"ready": false,
		"done": false,
		"data": null,
		"spawn": Vector3.ZERO,
		"cols": [],
		"mutex": Mutex.new(),
		"has_focus": focus is Vector3,
		"focus": focus if focus is Vector3 else Vector3.ZERO,
	}
	_boot_box = box
	_entries[coord] = {"state": "boot", "host": host, "drop": false}
	var job := _BootRun.new()
	job.gen = gen
	job.coord = coord
	job.seed = world_seed
	job.box = box
	_boot_job = job
	_boot_thread = Thread.new()
	var err := _boot_thread.start(job.run)
	if err != OK:
		_boot_thread = null
		_boot_job = null
		push_error("Spawn chunk thread failed to start (%s)." % error_string(err))


func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_flush_graveyard()
	var ta := Time.get_ticks_usec()
	_track_target()
	var tb := Time.get_ticks_usec()
	_schedule()
	var t1 := Time.get_ticks_usec()
	_phase("graveyard", ta - t0)
	_phase("track", tb - ta)
	_poll_tasks()
	_poll_boot()
	var t2 := Time.get_ticks_usec()
	_run_jobs(t2)
	_service_near(t2)
	var t3 := Time.get_ticks_usec()
	if _window_dirty and not _building():
		_window_dirty = false
		window_changed.emit(loaded_coords())
	var t4 := Time.get_ticks_usec()
	_phase("schedule", t1 - tb)
	_phase("poll", t2 - t1)
	_phase("jobs", t3 - t2)
	_phase("window_signal", t4 - t3)
	var spent := Time.get_ticks_usec() - t0
	last_frame_usec = spent
	frame_usec_max = maxi(frame_usec_max, spent)
	frame_usec_hist.append(spent)
	if frame_usec_hist.size() > 36000:
		frame_usec_hist = frame_usec_hist.slice(18000)


var phase_usec_max: Dictionary = {}
var job_usec_by_name: Dictionary = {}


func _phase(name: String, usec: int) -> void:
	if usec > int(phase_usec_max.get(name, 0)):
		phase_usec_max[name] = usec


func _callable_name(job: Callable) -> String:
	var method := str(job.get_method())
	var args := job.get_bound_arguments()
	if method == "_budget_job" and not args.is_empty():
		return str(args[0])
	if method == "_job_part_buf" and args.size() >= 4:
		return "_job_part_buf %s n=%d" % [str(args[1]), int(args[3])]
	if method == "_job_multimesh_buf" and args.size() >= 4:
		return "_job_multimesh_buf %s n=%d" % [str(args[1]), int(args[3])]
	if method == "_job_trimesh" and args.size() >= 2:
		var packed: Array = args[1]
		var faces: PackedVector3Array = packed[2]
		return "_job_trimesh %s f=%d" % [str(packed[0]), faces.size()]
	if method == "":
		return "lambda"
	return method


func _note_job(coord: Vector2i, job_name: String, usec: int) -> void:
	if usec > job_usec_max:
		job_usec_max = usec
		job_usec_max_name = job_name
	if usec > int(job_usec_by_name.get(job_name, 0)):
		job_usec_by_name[job_name] = usec
	if LaunchConfig.logs:
		LaunchConfig.log_line("PYLONS_JOB %s %s %d us" % [coord, job_name, usec])


func _track_target() -> void:
	if target == null or not is_instance_valid(target):
		return
	var p := target.global_position
	var here := WorldConfig.chunk_of(p.x, p.z)
	if not WorldConfig.in_world(here):
		return
	if here == center:
		return
	var rect := WorldConfig.chunk_rect(here).grow(-hysteresis_m)
	var far: bool = maxi(absi(here.x - center.x), absi(here.y - center.y)) > 1
	if far or rect.has_point(Vector2(p.x, p.z)):
		center = here
		if _city != null and _city.has_method("set_current_chunk"):
			_city.set_current_chunk(center)


func _schedule() -> void:
	# Neighbour generates share the generator object. Wait until the boot thread
	# has finished with it. The pool stays free for that thread's shadow tasks.
	if _boot_thread != null:
		return
	var want: Array[Vector2i] = WorldConfig.window(center)
	var wanted: Dictionary = {}
	for c in want:
		wanted[c] = true
	# Unload what left the window.
	for c in _entries.keys():
		if wanted.has(c):
			continue
		var e: Dictionary = _entries[c]
		var st := str(e["state"])
		if st == "loaded" or st == "build":
			_begin_unload(c, e)
		elif st == "gen":
			e["drop"] = true
	# Start what entered it, nearest first.
	var in_flight := 0
	for c2 in _entries.keys():
		if str(_entries[c2]["state"]) == "gen":
			in_flight += 1
	for c3 in want:
		if _entries.has(c3):
			var e3: Dictionary = _entries[c3]
			if str(e3["state"]) == "gen":
				e3["drop"] = false
			continue
		var cached: ChunkData = _cached(c3)
		if cached != null:
			_start_build(c3, cached)
			continue
		if in_flight >= max_tasks:
			continue
		var gen := generator_for(c3)
		var box := {"data": null}
		var seed := world_seed
		var coord := c3
		var id := WorkerThreadPool.add_task(func() -> void: box["data"] = gen.generate(coord, seed), false, "chunk %s" % str(coord))
		_entries[c3] = {"state": "gen", "task": id, "box": box, "drop": false}
		in_flight += 1


func _poll_tasks() -> void:
	for c in _entries.keys():
		var e: Dictionary = _entries[c]
		if str(e["state"]) != "gen":
			continue
		var id: int = e["task"]
		if not WorkerThreadPool.is_task_completed(id):
			continue
		WorkerThreadPool.wait_for_task_completion(id)
		var data: ChunkData = e["box"]["data"]
		if data == null:
			push_error("Chunk %s failed to generate." % str(c))
			_entries.erase(c)
			continue
		_note_gen(data)
		if bool(e["drop"]):
			_entries.erase(c)
			_remember(data)
			continue
		_start_build(c, data)


func _note_gen(data: ChunkData) -> void:
	gen_usec_total += data.gen_usec
	gen_usec_max = maxi(gen_usec_max, data.gen_usec)


func _start_build(coord: Vector2i, data: ChunkData) -> Dictionary:
	_cache.erase(coord)
	_cache_order.erase(coord)
	var prior: Dictionary = _entries.get(coord, {})
	var host: Node3D = prior.get("host")
	if host == null or not is_instance_valid(host):
		host = Node3D.new()
		host.name = "Chunk_%d_%d" % [coord.x, coord.y]
		host.set_meta("chunk", coord)
		add_child(host)
	# The job list itself is made by the first job, so starting a build costs ~nothing.
	var jobs: Array[Callable] = []
	var e := {"state": "build", "data": data, "host": host, "jobs": jobs, "job_i": 0}
	jobs.append(_plan_build.bind(coord))
	_entries[coord] = e
	return e


func _plan_build(coord: Vector2i) -> void:
	var e: Dictionary = _entries[coord]
	var jobs: Array[Callable] = e["jobs"]
	var data: ChunkData = e["data"]
	var host: Node3D = e["host"]
	jobs.append_array(generator_for(coord).build_jobs(data, host))
	if _city != null and _city.has_method("register_jobs"):
		jobs.append_array(_city.register_jobs(coord, data))
	# Cone stacks are real rigid bodies. Only the chunk the player is in (and the
	# chunks they are about to enter) spawn them; the rest wait until the player is close.
	if _want_cones(coord):
		jobs.append_array(persistence.restore_jobs(coord, data))
	else:
		e["cones_later"] = true


func _building() -> bool:
	for c in _entries.keys():
		var st := str(_entries[c]["state"])
		if st == "build" or st == "unload":
			return true
	return false


func _run_jobs(t0: int) -> void:
	var order: Array = _entries.keys()
	order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		# Unloads first (they free memory and are cheap), then the nearest builds.
		var ua: bool = str(_entries[a]["state"]) == "unload"
		var ub: bool = str(_entries[b]["state"]) == "unload"
		if ua != ub:
			return ua
		return (a - center).length_squared() < (b - center).length_squared())
	for c in order:
		var e: Dictionary = _entries[c]
		var st := str(e["state"])
		if st != "build" and st != "unload":
			continue
		var jobs: Array = e["jobs"]
		while int(e["job_i"]) < jobs.size():
			if Time.get_ticks_usec() - t0 >= frame_budget_usec:
				return
			var job: Callable = jobs[e["job_i"]]
			var jn := _callable_name(job)
			var js := Time.get_ticks_usec()
			var step: Variant = job.call()
			var took := Time.get_ticks_usec() - js
			_note_job(c, jn, took)
			# true: this step still has work. Leave job_i so the next frame resumes it.
			if step == true:
				if Time.get_ticks_usec() - t0 >= frame_budget_usec:
					return
				continue
			e["job_i"] = int(e["job_i"]) + 1
		var tf := Time.get_ticks_usec()
		if st == "build":
			_finish_build(c, e)
			_phase("finish_build", Time.get_ticks_usec() - tf)
		else:
			_finish_unload(c, e)
			_phase("finish_unload", Time.get_ticks_usec() - tf)


func _want_cones(coord: Vector2i) -> bool:
	# Boot builds the spawn chunk before City assigns a target. Only that chunk gets cones.
	if target == null or not is_instance_valid(target):
		return coord == center
	var at := Vector2(target.global_position.x, target.global_position.z)
	return WorldConfig.chunk_rect(coord).grow(90.0).has_point(at)


## Lamp nodes and small prop collision stay near the player. One short slice per frame.
func _service_near(t0: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	if Time.get_ticks_usec() - t0 >= frame_budget_usec:
		return
	var focus := Vector2(target.global_position.x, target.global_position.z)
	for c in _entries.keys():
		if Time.get_ticks_usec() - t0 >= frame_budget_usec:
			return
		var e: Dictionary = _entries[c]
		var st := str(e["state"])
		if st != "loaded" and st != "build":
			continue
		var data: ChunkData = e["data"]
		var rn = data.payload
		if rn == null or not rn.has_method("service_near"):
			continue
		var left := frame_budget_usec - (Time.get_ticks_usec() - t0)
		if left < 200:
			return
		var host: Node3D = e["host"]
		var js := Time.get_ticks_usec()
		rn.call("service_near", host, focus, mini(left, 800))
		var took := Time.get_ticks_usec() - js
		if took > 50:
			_note_job(c, "service_near", took)
		if bool(e.get("cones_later", false)) and _want_cones(c):
			if Time.get_ticks_usec() - t0 >= frame_budget_usec:
				return
			var job: Callable = e.get("cone_job", Callable())
			if not job.is_valid():
				var made: Array = persistence.restore_jobs(c, e["data"])
				if made.is_empty():
					e["cones_later"] = false
					continue
				job = made[0]
				e["cone_job"] = job
			var js2 := Time.get_ticks_usec()
			var step: Variant = job.call()
			_note_job(c, "restore_later", Time.get_ticks_usec() - js2)
			if step != true:
				e["cones_later"] = false
				e.erase("cone_job")


func _finish_build(coord: Vector2i, e: Dictionary) -> void:
	e["state"] = "loaded"
	e["jobs"] = []
	e["job_i"] = 0
	loads += 1
	_window_dirty = true
	chunk_loaded.emit(coord, e["data"])


func _begin_unload(coord: Vector2i, e: Dictionary) -> void:
	chunk_unloading.emit(coord)
	# All the work, including the list of steps, happens in budgeted jobs.
	var jobs: Array[Callable] = [_plan_unload.bind(coord)]
	e["state"] = "unload"
	e["jobs"] = jobs
	e["job_i"] = 0
	_window_dirty = true


func _plan_unload(coord: Vector2i) -> void:
	var e: Dictionary = _entries[coord]
	var jobs: Array = e["jobs"]
	# Cones and wrecks first, while the ground is still there.
	jobs.append_array(persistence.capture(coord))
	if _city != null and _city.has_method("unregister_jobs"):
		jobs.append_array(_city.unregister_jobs(coord))
	var host: Node3D = e["host"]
	var kids: Array = host.get_children()
	var at := 0
	while at < kids.size():
		jobs.append(_free_nodes.bind(kids.slice(at, at + 6)))
		at += 6


func _free_nodes(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			(n as Node).free()


func _finish_unload(coord: Vector2i, e: Dictionary) -> void:
	var host: Node3D = e["host"]
	if is_instance_valid(host):
		host.free()
	_remember(e["data"])
	_entries.erase(coord)
	unloads += 1
	_window_dirty = true
	chunk_unloaded.emit(coord)


func _remember(data: ChunkData) -> void:
	if data == null or data_cache_size <= 0:
		return
	_cache[data.coord] = data
	_cache_order.erase(data.coord)
	_cache_order.append(data.coord)
	while _cache_order.size() > data_cache_size:
		var old: Vector2i = _cache_order.pop_front()
		var gone: ChunkData = _cache[old]
		_cache.erase(old)
		_release(gone)


## Drop the last reference to a chunk's data on a worker thread: its generator payload
## (the whole road builder state) took tens of ms to free on the main thread.
func _release(data: ChunkData) -> void:
	if data == null:
		return
	_graveyard.append(data)


var _graveyard: Array = []
var _release_task := -1


func _flush_graveyard() -> void:
	if _graveyard.is_empty():
		return
	if _release_task >= 0:
		if not WorkerThreadPool.is_task_completed(_release_task):
			return
		WorkerThreadPool.wait_for_task_completion(_release_task)
		_release_task = -1
	# Only the box references the batch, so its last reference drops on the worker.
	var box := {"items": _graveyard}
	_graveyard = []
	_release_task = WorkerThreadPool.add_task(func() -> void: (box["items"] as Array).clear(), false, "chunk release")


func _cached(coord: Vector2i) -> ChunkData:
	return _cache.get(coord)


## Frame-cost stats for the soak test (microseconds).
func stats() -> Dictionary:
	var sorted := frame_usec_hist.duplicate()
	sorted.sort()
	var p99 := 0
	var p50 := 0
	if not sorted.is_empty():
		p99 = sorted[mini(sorted.size() - 1, int(sorted.size() * 0.99))]
		p50 = sorted[sorted.size() / 2]
	return {
		"loads": loads, "unloads": unloads, "loaded": loaded_coords().size(),
		"gen_ms_max": gen_usec_max / 1000.0, "gen_ms_total": gen_usec_total / 1000.0,
		"stream_frame_ms_max": frame_usec_max / 1000.0, "stream_frame_ms_p99": p99 / 1000.0,
		"stream_frame_ms_p50": p50 / 1000.0, "job_ms_max": job_usec_max / 1000.0, "job_max": job_usec_max_name,
		"phase_ms_max": _phase_ms(), "job_ms_max_by_name": _jobs_ms(),
	}


func _jobs_ms() -> Dictionary:
	var out := {}
	for k in job_usec_by_name.keys():
		out[k] = job_usec_by_name[k] / 1000.0
	return out


func _phase_ms() -> Dictionary:
	var out := {}
	for k in phase_usec_max.keys():
		out[k] = phase_usec_max[k] / 1000.0
	return out


func _poll_boot() -> void:
	if _boot_thread == null:
		return
	var box: Dictionary = _boot_box
	var lock: Mutex = box["mutex"]
	lock.lock()
	var floor_ready: bool = bool(box["ready"]) and not _boot_floor_done
	var done: bool = bool(box["done"])
	var spawn: Vector3 = box["spawn"]
	var cols: Array = box["cols"]
	lock.unlock()
	if floor_ready:
		_boot_floor_done = true
		var host: Node3D = _entries[_boot_coord]["host"]
		var t0 := Time.get_ticks_usec()
		for packed in cols:
			_add_floor_body(host, packed)
		boot_floor_build_usec = Time.get_ticks_usec() - t0
		boot_floor_at_ms = Time.get_ticks_msec()
		if LaunchConfig.logs:
			LaunchConfig.log_line("PYLONS_BOOT floor_at=%d since_boot=%d build_us=%d bodies=%d" % [boot_floor_at_ms, boot_floor_at_ms - boot_started_ms, boot_floor_build_usec, cols.size()])
		spawn_floor_ready.emit(spawn)
	if not done:
		return
	var thread := _boot_thread
	_boot_thread = null
	thread.wait_to_finish()
	_boot_job = null
	lock.lock()
	var data: ChunkData = box["data"]
	lock.unlock()
	boot_gen_at_ms = Time.get_ticks_msec()
	if data == null:
		push_error("Spawn chunk %s failed to generate." % str(_boot_coord))
		var host_gone: Node3D = _entries[_boot_coord]["host"] if _entries.has(_boot_coord) else null
		if host_gone != null and is_instance_valid(host_gone):
			host_gone.free()
		_entries.erase(_boot_coord)
		return
	_note_gen(data)
	if LaunchConfig.logs:
		var stage: Variant = data.stats.get("stage_ms", {})
		LaunchConfig.log_line("PYLONS_BOOT gen_at=%d since_boot=%d gen_us=%d stage=%s" % [boot_gen_at_ms, boot_gen_at_ms - boot_started_ms, data.gen_usec, stage])
	_start_build(_boot_coord, data)


func _add_floor_body(host: Node3D, packed: Array) -> void:
	var faces: PackedVector3Array = packed[2]
	if faces.size() < 3:
		return
	var body := StaticBody3D.new()
	body.name = str(packed[0])
	body.collision_layer = 1
	body.collision_mask = 1
	var group := str(packed[1])
	if group != "":
		body.add_to_group(group)
	var shape := CollisionShape3D.new()
	var solid := ConcavePolygonShape3D.new()
	solid.backface_collision = true
	solid.set_faces(faces)
	shape.shape = solid
	body.add_child(shape)
	var records: Array = packed[3]
	if not records.is_empty():
		body.set_meta("respawn_boxes", records)
	host.add_child(body)


func _exit_tree() -> void:
	if _boot_thread != null:
		_boot_thread.wait_to_finish()
		_boot_thread = null
		_boot_job = null
	if _release_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_release_task)
		_release_task = -1
	for c in _entries.keys():
		var e: Dictionary = _entries[c]
		if str(e["state"]) == "gen":
			WorkerThreadPool.wait_for_task_completion(int(e["task"]))
