extends Node3D

## Twin Falls streaming world. Terrain comes from TwinFallsTerrainGenerator.
## The player stays frozen until the chunk under them has a heightfield body.
## Below y -300, or when the whole stack is under the river, they respawn at
## --spawn when that flag is set, otherwise at spawn.json. --spawn y snaps to the ground.

const _Gen := preload("res://scripts/world/twin_falls_terrain_generator.gd")
const _Streamer := preload("res://scripts/world/chunk_streamer.gd")
const _River := preload("res://scripts/twin_falls_river.gd")

## Basalt talus rests near 35 degrees. Steeper than this, the cone is not on a floor and slides.
const TALUS_FLOOR_DEG := 34.0
const KILL_Y := -300.0

var streamer: ChunkStreamer
var generator: TwinFallsTerrainGenerator
var _river
var _soul: CharacterBody3D
var _stand := Vector3.ZERO
var _held_chunk := Vector2i(999999, 999999)
var _capture := false
var _released := false
var _phase := 0
var _hold := 0
var _started_ms := 0
var _fps_sum := 0.0
var _fps_min := 9999.0
var _fps_n := 0
var _draws := 0
var _nodes := 0
var _shooting := false
var _aim := Vector3.ZERO
var _warm: MeshInstance3D
var _warm_frames := 0
var _roads_logged := false
var _idle_logged := false
var _shot_notes := ""


func _ready() -> void:
	WorldConfig.world_half_m = 8000.0
	# Lower values run first. Freeze the body before SoulBody's own physics step.
	process_physics_priority = -100
	_capture = _wants_capture()
	_started_ms = Time.get_ticks_msec()
	generator = _Gen.new()
	streamer = _Streamer.new()
	streamer.name = "ChunkStreamer"
	add_child(streamer)
	streamer.setup(null, 1, generator)
	streamer.max_tasks = 4
	_river = _River.new()
	_river.name = "RiverFlow"
	_river.setup(generator)
	add_child(_river)
	_stand = _boot_stand()
	_warm_shader()
	_soul = get_node("SoulBody") as CharacterBody3D
	_soul.recover_falls = false
	_soul.floor_max_angle = deg_to_rad(TALUS_FLOOR_DEG)
	_soul.global_position = _stand
	_soul.velocity = Vector3.ZERO
	_soul.boot_held = true
	_soul.set_physics_process(false)
	_build_river()
	streamer.spawn_floor_ready.connect(_release_spawn)
	streamer.start_boot(_boot_chunk(_stand), _stand)
	streamer.target = _soul
	if _capture:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _warm_shader() -> void:
	var mat := generator.material()
	if mat == null:
		return
	var warm := MeshInstance3D.new()
	warm.name = "ShaderWarm"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4)
	warm.mesh = quad
	warm.material_override = mat
	warm.position = Vector3(_stand.x, _stand.y + 1.4, _stand.z - 2.5)
	warm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(warm)
	_warm = warm


func _wants_capture() -> bool:
	if OS.get_cmdline_user_args().has("--tf-capture"):
		return true
	for arg in OS.get_cmdline_args():
		if str(arg) == "--tf-capture":
			return true
	return false


func _release_spawn(_spawn: Vector3) -> void:
	# The boot signal is the raw heightfield. The stack stays put until
	# _try_release sees the mesh-sampled body and stands on that surface.
	pass


func _try_release() -> void:
	if _released or _soul == null:
		return
	if not _floor_ready(_stand):
		return
	var y := generator.drawn_height_at(_stand.x, _stand.z)
	if y > -70.0:
		_stand.y = y + 0.45
	_released = true
	_soul.global_position = _stand
	_soul.velocity = Vector3.ZERO
	_soul.flow_velocity = Vector3.ZERO
	streamer.target = _soul
	_soul.boot_held = false
	_soul.set_physics_process(true)
	print("TF_RELEASE ms=%d y=%.2f" % [Time.get_ticks_msec() - _started_ms, _stand.y])
	LaunchConfig.announce(_stand)
	var yaw := generator.spawn_yaw
	var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
	_aim = _soul.global_position + dir * 280.0 + Vector3(0.0, -6.0, 0.0)
	_look()


## --spawn / PYLONS_SPAWN wins. --chunk / PYLONS_CHUNK alone stands at that chunk's centre.
## A chunk id with a positive z is a data cell (cx, cz_north); a negative z is a Godot chunk.
func _boot_stand() -> Vector3:
	if LaunchConfig.has_spawn_override:
		var s := LaunchConfig.spawn_override
		var ground := generator.height_at(s.x, s.z)
		# On the DEM the flag's y is ignored and the stack stands on the ground.
		var y := ground + 0.2 if ground > -70.0 else s.y
		return Vector3(s.x, y, s.z)
	if LaunchConfig.has_chunk_flag:
		var center := WorldConfig.chunk_center(_flag_chunk(LaunchConfig.start_chunk))
		return Vector3(center.x, generator.height_at(center.x, center.z) + 0.2, center.z)
	var g := generator.spawn
	return Vector3(g.x, generator.height_at(g.x, g.z) + 0.2, g.z)


func _boot_chunk(stand: Vector3) -> Vector2i:
	var at := WorldConfig.chunk_of(stand.x, stand.z)
	if not LaunchConfig.has_chunk_flag:
		return at
	var flagged := _flag_chunk(LaunchConfig.start_chunk)
	if LaunchConfig.has_spawn_override and not WorldConfig.chunk_rect(flagged).has_point(Vector2(stand.x, stand.z)):
		return at
	return flagged


func _flag_chunk(flag: Vector2i) -> Vector2i:
	var as_data := Vector2i(flag.x, -flag.y - 1)
	if generator.covers(as_data) and not generator.covers(flag):
		return as_data
	return flag


func _physics_process(_delta: float) -> void:
	if _soul == null:
		return
	if _soul.global_position.y < KILL_Y:
		respawn_player()
		return
	# The river is mid-sink. Leave the body frozen so this step does not clear boot_held.
	if _river != null and bool(_river.call("holds_player")):
		_soul.boot_held = true
		_soul.velocity = Vector3.ZERO
		return
	if not _released:
		_try_release()
		return
	if _floor_ready(_soul.global_position):
		if _soul.boot_held:
			var stand_y := generator.drawn_height_at(_soul.global_position.x, _soul.global_position.z)
			if stand_y > -70.0:
				_soul.global_position.y = stand_y + 0.45
			_soul.velocity = Vector3.ZERO
			_soul.boot_held = false
			_held_chunk = Vector2i(999999, 999999)
		return
	var coord := WorldConfig.chunk_of(_soul.global_position.x, _soul.global_position.z)
	# Off the DEM there is never a floor. Leave the body free so the kill plane can catch it.
	if not generator.covers(coord):
		return
	_soul.velocity = Vector3.ZERO
	_soul.boot_held = true
	if coord != _held_chunk:
		_held_chunk = coord
		LaunchConfig.log_line("PYLONS_HOLD %s" % coord)


func _floor_ready(at: Vector3) -> bool:
	if streamer == null:
		return false
	var host := streamer.host_for(WorldConfig.chunk_of(at.x, at.z))
	if host == null:
		return false
	var body := host.get_node_or_null("TerrainBody")
	if body == null:
		return false
	return bool(body.get_meta("mesh_sampled", false))


## Kill plane and a fully submerged stack share this point.
func respawn_player() -> void:
	var s := generator.spawn
	if LaunchConfig.has_spawn_override:
		s = LaunchConfig.spawn_override
	var stand := generator.dry_ground(s.x, s.z, s.y)
	var drawn := generator.drawn_height_at(stand.x, stand.z)
	if drawn > -70.0:
		stand.y = drawn + 0.45
	_soul.global_position = stand
	_soul.velocity = Vector3.ZERO
	_soul.flow_velocity = Vector3.ZERO
	_soul.boot_held = not _floor_ready(stand)
	if streamer != null:
		streamer.target = _soul
	LaunchConfig.log_line("PYLONS_RESPAWN %.2f,%.2f,%.2f" % [stand.x, stand.y, stand.z])


func _process(_delta: float) -> void:
	if _warm != null:
		_warm_frames += 1
		if _warm_frames > 3:
			_warm.visible = false
			_warm = null
	if not _roads_logged and _released and streamer != null and _soul != null:
		var here := WorldConfig.chunk_of(_soul.global_position.x, _soul.global_position.z)
		var host := streamer.host_for(here)
		if host != null and streamer.is_loaded(here) and host.get_node_or_null("Roads") != null:
			_roads_logged = true
			var marks := 0
			for child in host.get_children():
				if str(child.name).begins_with("Lm_"):
					marks += 1
			var signs := host.get_node_or_null("StreetSigns") != null
			print("TF_ROADS chunk=%s marks=%d signs=%s" % [host.name, marks, str(signs)])
	if not _idle_logged and _released and streamer != null and not streamer.busy():
		_idle_logged = true
		print("TF_IDLE ms=%d" % (Time.get_ticks_msec() - _started_ms))
	if not _capture or _shooting:
		return
	if Time.get_ticks_msec() - _started_ms > 240000:
		_write_stats("timeout")
		get_tree().quit()
		return
	if not _released or _soul == null:
		return
	_look()
	if _phase == 0:
		if not _view_ready():
			_hold = 0
			return
		_hold += 1
		if _hold < 24:
			return
		_phase = 1
		_hold = 0
		_reset_fps()
	elif _phase == 1:
		_sample()
		_hold += 1
		if _hold >= 90:
			_note_shot("spawn")
			_shooting = true
			_shot("res://_diag/tf06_spawn.png", 2)
	elif _phase == 2:
		_teleport(Vector3(3363.62, 144.0, -6805.5), Vector3(0.0, -6.0, -90.0))
		_phase = 3
		_hold = 0
	elif _phase == 3:
		if not _view_ready():
			_hold = 0
			return
		_hold += 1
		if _hold < 30:
			return
		_phase = 4
		_hold = 0
		_reset_fps()
	elif _phase == 4:
		_sample()
		_hold += 1
		if _hold >= 90:
			_note_shot("bridge")
			_shooting = true
			_shot("res://_diag/tf06_bridge.png", 5)
	elif _phase == 5:
		_teleport(Vector3(2210.0, 184.0, -1830.0), Vector3(40.0, -2.0, 0.0))
		_phase = 6
		_hold = 0
	elif _phase == 6:
		if not _view_ready():
			_hold = 0
			return
		_hold += 1
		if _hold < 30:
			return
		_phase = 7
		_hold = 0
		_reset_fps()
	elif _phase == 7:
		_sample()
		_hold += 1
		if _hold >= 90:
			_note_shot("downtown")
			_shooting = true
			_shot("res://_diag/tf06_downtown.png", 8)
	elif _phase == 8:
		_write_stats("ok")
		_phase = 9
		get_tree().quit()


func _view_ready() -> bool:
	if streamer.busy() or not _soul.is_on_floor():
		return false
	return _has_mesh()


func _has_mesh() -> bool:
	var coord := WorldConfig.chunk_of(_soul.global_position.x, _soul.global_position.z)
	var host := streamer.host_for(coord)
	if host == null:
		return false
	for child in host.get_children():
		if str(child.name).begins_with("Terrain_"):
			return true
	return false


func _look() -> void:
	var cam := get_node_or_null("CameraRig")
	if cam != null and cam.has_method("look_toward"):
		cam.look_toward(_aim)


func _teleport(stand: Vector3, aim_off: Vector3) -> void:
	var y := generator.drawn_height_at(stand.x, stand.z)
	if y < -70.0:
		y = generator.height_at(stand.x, stand.z)
	if y > -70.0:
		stand.y = y + 0.6
	_soul.velocity = Vector3.ZERO
	_soul.global_position = stand
	_aim = stand + aim_off
	_look()


func _note_shot(tag: String) -> void:
	var fps := 0.0
	if _fps_n > 0:
		fps = _fps_sum / float(_fps_n)
	var p := _soul.global_position
	var line := "%s fps_avg=%.1f fps_min=%.1f draws=%d nodes=%d at=%.1f,%.1f,%.1f" % [tag, fps, _fps_min, _draws, _nodes, p.x, p.y, p.z]
	_shot_notes += line + "\n"
	print("TF_SHOT %s" % line)


func _reset_fps() -> void:
	_fps_sum = 0.0
	_fps_min = 9999.0
	_fps_n = 0


func _sample() -> void:
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	_fps_sum += fps
	_fps_min = minf(_fps_min, fps)
	_fps_n += 1
	_draws = maxi(_draws, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	_nodes = maxi(_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))


func _shot(path: String, next_phase: int) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("Screenshot %s failed (%s)." % [path, error_string(err)])
	_phase = next_phase
	_shooting = false


func _nearest_water(stand: Vector3) -> Vector3:
	var best := stand + Vector3(0.0, -2.0, -80.0)
	var best_d := 1.0e12
	for p in generator.water_pts:
		var d := Vector2(p.x - stand.x, p.z - stand.z).length_squared()
		if d < best_d:
			best_d = d
			best = p
	return best


## Visual ribbon only. Water stays non-solid; the floor stand is moved off the strip instead.
func _build_river() -> void:
	var pts := generator.water_pts
	var count := pts.size()
	if count < 2:
		return
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var indices := PackedInt32Array()
	var half := 20.0
	for i in count:
		var p: Vector3 = pts[i]
		var prev: Vector3 = pts[maxi(i - 1, 0)]
		var next: Vector3 = pts[mini(i + 1, count - 1)]
		var d0 := Vector2(p.x - prev.x, p.z - prev.z)
		var d1 := Vector2(next.x - p.x, next.z - p.z)
		if d0.length_squared() < 1.0:
			d0 = d1
		if d1.length_squared() < 1.0:
			d1 = d0
		if d0.length_squared() < 1.0:
			d0 = Vector2.RIGHT
			d1 = Vector2.RIGHT
		d0 = d0.normalized()
		d1 = d1.normalized()
		var side := Vector2(-(d0.y + d1.y), d0.x + d1.x)
		if side.length_squared() < 0.0001:
			side = Vector2(-d0.y, d0.x)
		side = side.normalized()
		var along := Vector2(-d0.y, d0.x)
		var denom := clampf(side.dot(along), 0.35, 1.0)
		var miter := half / denom
		# water.json height is the surface. The bed is carved below it.
		var y := p.y
		verts.append(WorldConfig.to_local(Vector3(p.x - side.x * miter, y, p.z - side.y * miter)))
		verts.append(WorldConfig.to_local(Vector3(p.x + side.x * miter, y, p.z + side.y * miter)))
		norms.append(Vector3.UP)
		norms.append(Vector3.UP)
	for i in count - 1:
		var a := i * 2
		indices.append(a)
		indices.append(a + 1)
		indices.append(a + 2)
		indices.append(a + 1)
		indices.append(a + 3)
		indices.append(a + 2)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.38, 0.42, 0.86)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.28
	mat.metallic = 0.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var inst := MeshInstance3D.new()
	inst.name = "River"
	inst.mesh = mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)


func _write_stats(reason: String) -> void:
	var fps := 0.0
	if _fps_n > 0:
		fps = _fps_sum / float(_fps_n)
	var y := _soul.global_position.y if _soul != null else 0.0
	var expect := generator.height_at(_soul.global_position.x, _soul.global_position.z) if _soul != null else 0.0
	var info := streamer.stats() if streamer != null else {}
	var gpu := RenderingServer.get_video_adapter_name()
	var chunks := ""
	if streamer != null:
		for coord in streamer.loaded_coords():
			var data := streamer.data_for(coord)
			if data != null:
				chunks += "%s=%s " % [coord, data.stats]
	var text := "reason=%s\ngpu=%s\nfps_avg=%.1f\nfps_min=%.1f\ndraws=%d\nnodes=%d\nplayer_y=%.2f\nheight_at=%.2f\nstreamer=%s\nchunks=%s\nshots:\n%s" % [reason, gpu, fps, _fps_min if _fps_n > 0 else 0.0, _draws, _nodes, y, expect, str(info), chunks, _shot_notes]
	var path := ProjectSettings.globalize_path("res://_diag/tf_stats.txt")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s" % path)
		return
	file.store_string(text)
	file.close()
	print("TF_STATS %s" % text.replace("\n", " | "))
