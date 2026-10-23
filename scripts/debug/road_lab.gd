extends Node3D

## Windowed RoadLab. Builds the synthetic dev area through RoadLabGenerator,
## which is the measured builder on terrain.json.
##
##   godot --path . res://scenes/road_lab.tscn
##   godot --path . res://scenes/road_lab.tscn -- --site=dev_nw
##
## --road_strategy=N is the same switch as the game. Default 0.
## WASD flies. The mouse looks. Esc frees the mouse.

const SITES := "res://tools/road_bakeoff/sites.json"

var _fly := Vector3.ZERO
var _look := Vector2.ZERO
var _captured := true


func _ready() -> void:
	var site := _site()
	var centre := Vector2(435.0, -1929.0)
	if site.has("centre"):
		var c: Array = site["centre"]
		centre = Vector2(float(c[0]), float(c[1]))
	var gen := RoadLabGenerator.new()
	var t0 := Time.get_ticks_msec()
	gen.prepare()
	var host := Node3D.new()
	host.name = "RoadLabWorld"
	add_child(host)
	var built := 0
	for coord in _chunks():
		var dc := Vector2i(coord.x, -coord.y - 1)
		var pay = gen._build(coord, dc, false)
		var chunk := Node3D.new()
		chunk.name = "C_%d_%d" % [coord.x, coord.y]
		host.add_child(chunk)
		gen._job_body(chunk, pay)
		gen.place_parts(chunk, pay.parts)
		var pack: Dictionary = pay.roads
		if not pack.is_empty() and gen._roads != null:
			for job in gen._roads.jobs(chunk, pack):
				job.call()
		built += 1
		print("ROADLAB chunk %s" % coord)
	var cam := Camera3D.new()
	cam.position = Vector3(centre.x, 180.0, centre.y + 40.0)
	cam.rotation = Vector3(deg_to_rad(-55.0), 0.0, 0.0)
	cam.current = true
	add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(sun)
	print("ROADLAB site=%s chunks=%d ms=%d strategy=%d" % [
		str(site.get("id", "dev")), built, Time.get_ticks_msec() - t0, RoadStrategyRegistry.current_id(),
	])
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _chunks() -> Array[Vector2i]:
	return [
		Vector2i(0, -5), Vector2i(1, -5),
		Vector2i(0, -4), Vector2i(1, -4),
	]


func _site() -> Dictionary:
	var want := "dev"
	for raw in OS.get_cmdline_user_args():
		var arg := String(raw)
		if arg.begins_with("--site="):
			want = arg.substr(7)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SITES))
	if parsed is Dictionary:
		for item in parsed.get("sites", []):
			if item is Dictionary and str(item.get("id", "")) == want:
				return item
	return {"id": want, "centre": [435, -1929]}


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_captured = not _captured
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _captured else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and _captured:
		_look.x -= event.relative.x * 0.002
		_look.y = clampf(_look.y - event.relative.y * 0.002, deg_to_rad(-80.0), deg_to_rad(80.0))
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			cam.rotation = Vector3(_look.y, _look.x, 0.0)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var wish := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		wish.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		wish.z += 1.0
	if Input.is_key_pressed(KEY_A):
		wish.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		wish.x += 1.0
	if Input.is_key_pressed(KEY_E):
		wish.y += 1.0
	if Input.is_key_pressed(KEY_Q):
		wish.y -= 1.0
	if wish.length_squared() < 0.01:
		return
	var speed := 80.0 if Input.is_key_pressed(KEY_SHIFT) else 30.0
	var basis := cam.global_transform.basis
	cam.global_position += (basis * wish.normalized()) * speed * delta
