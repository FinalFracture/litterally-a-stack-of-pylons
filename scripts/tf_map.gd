class_name TfMap
extends Control

## Playtest map for the Twin Falls 5 x 8 km slice.
## M opens and closes it (Tab only if M is already bound). Esc closes it.
## The tree stays unpaused. --map=0 / PYLONS_MAP=0 leaves the key dead.
## Base image: python tools/tf_map_bake.py

const WORLD_W := 5000.0
const WORLD_H := 8000.0
const ORIGIN_E := 705536.0
const ORIGIN_N := 4712771.0
const CHUNK_M := 500.0
const ZOOM_MIN := 1.0
const ZOOM_MAX := 32.0
const LABEL_M := 800.0
const NEAR_ROAD_M := 30.0
const VIEW_CONE_M := 50.0
const DATA := "res://world/twin_falls/data"
const MAP_DIR := DATA + "/map"

var _open := false
var _allowed := true
var _toggle: Key = KEY_M
var _zoom := 4.0
var _cx := 2500.0
var _czn := 4000.0
var _follow := true
var _grid := false
var _legend := true
var _status := false
var _font: Font
var _base: Texture2D
var _height: Image
var _roads: Array = []
var _contours: Array = []
var _marks: Array = []
var _canyon := Vector2(2100.0, 7300.0)
var _report := {}
var _report_found := false
var _cursor := Vector2(640.0, 360.0)
var _dragging := false
var _dragged := false
var _toast := ""
var _toast_t := 0.0
var _prev_mouse := Input.MOUSE_MODE_CAPTURED
var _ready_ok := false


func _ready() -> void:
	add_to_group("tf_map")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	visible = true
	_font = load("res://fonts/Overpass-Bold.ttf")
	# Godot's unused ui_focus_mode default is M. This game has no focus navigation,
	# so the playtest map keeps M. Tab is only used if a project action already has M.
	_release_unused_focus_key()
	_toggle = _pick_toggle()
	_allowed = _flag_on()
	_load_all()
	_ready_ok = true
	var player := _player_xz()
	_cx = player.x
	_czn = -player.y
	_clamp_center()


func is_open() -> bool:
	return _open


func blocks_movement() -> bool:
	return _open


func open_map() -> void:
	_set_open(true)


func close_map() -> void:
	_set_open(false)


func arrow_xz() -> Vector2:
	return _player_xz()


func road_count() -> int:
	var n := 0
	for road in _roads:
		if str(road["kind"]) != "rail":
			n += 1
	return n


func rail_count() -> int:
	var n := 0
	for road in _roads:
		if str(road["kind"]) == "rail":
			n += 1
	return n


func terrain_y(x: float, godot_z: float) -> float:
	if _height == null:
		return 0.0
	var zn := -godot_z
	var w := float(_height.get_width())
	var h := float(_height.get_height())
	var col := x / WORLD_W * w - 0.5
	var row := (WORLD_H - zn) / WORLD_H * h - 0.5
	return _sample_height(col, row)


func nearest_road(x: float, godot_z: float) -> String:
	var p := Vector2(x, -godot_z)
	var best_d := NEAR_ROAD_M + 0.001
	var best := ""
	for road in _roads:
		var pts: PackedVector2Array = road["pts"]
		if pts.size() < 2:
			continue
		for i in pts.size() - 1:
			var d := _dist_point_seg(p, pts[i], pts[i + 1])
			if d < best_d:
				best_d = d
				best = _road_label(road)
	return best


func readout_for(x: float, godot_z: float) -> String:
	var lines := _readout_lines(x, godot_z)
	return "\n".join(lines)


func sample_road_point(road_id: String) -> Vector2:
	for road in _roads:
		if str(road["id"]) != road_id:
			continue
		var pts: PackedVector2Array = road["pts"]
		if pts.is_empty():
			return Vector2.ZERO
		var mid: Vector2 = pts[pts.size() / 2]
		return Vector2(mid.x, -mid.y)
	return Vector2.ZERO


## Road ids whose name never survives layout at 16x, centred on the name.
func roads_missing_labels() -> PackedStringArray:
	var missing := PackedStringArray()
	var saved_zoom := _zoom
	var saved_x := _cx
	var saved_zn := _czn
	_zoom = 16.0
	for road in _roads:
		if str(road["name"]) == "":
			continue
		var anchor := _label_anchor(road)
		_cx = anchor.x
		_czn = anchor.y
		var labels := _layout_labels(false)
		var hit := false
		for item in labels:
			if str(item["id"]) == str(road["id"]):
				hit = true
				break
		if not hit:
			missing.append(str(road["id"]))
	_zoom = saved_zoom
	_cx = saved_x
	_czn = saved_zn
	return missing


func screen_segment_count() -> int:
	var n := 0
	var view := _view()
	for road in _roads:
		var pts: PackedVector2Array = road["pts"]
		var parts: Array = road["parts"]
		for part in parts:
			var a := int(part["a"])
			var b := int(part["b"])
			for i in range(a, b):
				if i < 0 or i + 1 >= pts.size():
					continue
				var s0 := _to_screen(pts[i].x, pts[i].y)
				var s1 := _to_screen(pts[i + 1].x, pts[i + 1].y)
				if _segment_hits(s0, s1, view):
					n += 1
	return n


func _process(delta: float) -> void:
	if not _open:
		return
	if _follow:
		var player := _player_xz()
		_cx = player.x
		_czn = -player.y
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pan.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pan.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pan.y += 1.0
	if pan.length_squared() > 0.01:
		_follow = false
		var step := 560.0 * delta / maxf(_scale(), 0.0001)
		_cx += pan.x * step
		_czn -= pan.y * step
	_clamp_center()
	if _toast_t > 0.0:
		_toast_t = maxf(_toast_t - delta, 0.0)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _open or not _allowed:
		return
	if _is_press(event, _toggle, false):
		_set_open(true)
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if _is_press(event, _toggle, false) or _is_press(event, KEY_ESCAPE, false):
		_set_open(false)
		get_viewport().set_input_as_handled()
		return
	if _is_press(event, KEY_G, false):
		_grid = not _grid
		get_viewport().set_input_as_handled()
	elif _is_press(event, KEY_R, false):
		_status = not _status
		_load_report()
		get_viewport().set_input_as_handled()
	elif _is_press(event, KEY_F, false):
		_follow = not _follow
		get_viewport().set_input_as_handled()
	elif _is_press(event, KEY_L, false):
		_legend = not _legend
		get_viewport().set_input_as_handled()
	elif _is_press(event, KEY_HOME, false):
		_follow = true
		get_viewport().set_input_as_handled()
	elif _is_press(event, KEY_EQUAL, true) or _is_press(event, KEY_KP_ADD, true):
		_zoom_at(_cursor, _zoom * 1.25)
		get_viewport().set_input_as_handled()
	elif _is_press(event, KEY_MINUS, true) or _is_press(event, KEY_KP_SUBTRACT, true):
		_zoom_at(_cursor, _zoom / 1.25)
		get_viewport().set_input_as_handled()
	var motion := event as InputEventMouseMotion
	if motion != null:
		_cursor = motion.position


func _gui_input(event: InputEvent) -> void:
	if not _open:
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		_cursor = motion.position
		if _dragging:
			if motion.relative.length_squared() > 0.25:
				_dragged = true
				_follow = false
			var s := _scale()
			_cx -= motion.relative.x / s
			_czn += motion.relative.y / s
			_clamp_center()
			queue_redraw()
		accept_event()
		return
	var button := event as InputEventMouseButton
	if button == null:
		return
	_cursor = button.position
	if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
		_zoom_at(button.position, _zoom * 1.25)
		accept_event()
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
		_zoom_at(button.position, _zoom / 1.25)
		accept_event()
		return
	if button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_dragging = true
			_dragged = false
		else:
			_dragging = false
			if not _dragged:
				_copy_here(button.position)
		accept_event()


func _draw() -> void:
	if not _open:
		return
	var view := _view()
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.09, 0.08, 0.07, 1.0))
	_draw_base()
	if _zoom >= 2.0:
		_draw_contours(view)
	_draw_roads(view)
	if _grid:
		_draw_grid(view)
	_draw_marks(view)
	_draw_player()
	var labels := _layout_labels(true)
	_draw_labels(labels)
	if _zoom >= 2.0:
		_draw_contour_labels(view, labels)
	_draw_chrome(view)


func _set_open(on: bool) -> void:
	if on and not _allowed:
		return
	if on == _open:
		return
	_open = on
	mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	if on:
		_prev_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_follow = true
		_zoom = 4.0
		var player := _player_xz()
		_cx = player.x
		_czn = -player.y
		_clamp_center()
		_cursor = _view() * 0.5
		queue_redraw()
	else:
		Input.mouse_mode = _prev_mouse
		_dragging = false
		queue_redraw()


func _flag_on() -> bool:
	var node := get_node_or_null("/root/LaunchConfig")
	if node == null:
		return true
	var flag: Variant = node.get("map_enabled")
	if flag == null:
		return true
	return bool(flag)


func _pick_toggle() -> Key:
	if _action_uses(KEY_M):
		return KEY_TAB
	return KEY_M


func _release_unused_focus_key() -> void:
	if not InputMap.has_action("ui_focus_mode"):
		return
	var kept: Array[InputEvent] = []
	for ev in InputMap.action_get_events("ui_focus_mode"):
		var pressed := ev as InputEventKey
		if pressed != null and (pressed.keycode == KEY_M or pressed.physical_keycode == KEY_M):
			continue
		kept.append(ev)
	InputMap.action_erase_events("ui_focus_mode")
	for ev in kept:
		InputMap.action_add_event("ui_focus_mode", ev)


func _action_uses(key: Key) -> bool:
	for action in InputMap.get_actions():
		for ev in InputMap.action_get_events(action):
			var pressed := ev as InputEventKey
			if pressed != null and (pressed.keycode == key or pressed.physical_keycode == key):
				return true
	return false


func _is_press(event: InputEvent, key: Key, allow_echo: bool) -> bool:
	var pressed := event as InputEventKey
	if pressed == null or not pressed.pressed:
		return false
	if pressed.echo and not allow_echo:
		return false
	if pressed.ctrl_pressed or pressed.alt_pressed or pressed.meta_pressed:
		return false
	return pressed.keycode == key or pressed.physical_keycode == key


func _load_all() -> void:
	var base := _load_image(MAP_DIR + "/map_base.png")
	if base != null:
		_base = ImageTexture.create_from_image(base)
	_height = _load_image(MAP_DIR + "/map_height.png")
	_load_roads()
	_load_contours()
	_load_marks()
	_load_report()


func _load_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		push_error("Map image missing: %s" % path)
		return null
	var img := Image.new()
	var err := img.load(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("Map image failed: %s (%s)" % [path, error_string(err)])
		return null
	return img


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		push_error("Map JSON failed: %s" % path)
	return parsed


func _load_roads() -> void:
	_roads.clear()
	var data: Variant = _read_json(DATA + "/roads.json")
	if data == null or not (data is Dictionary):
		push_error("roads.json missing")
		return
	var body: Dictionary = data
	for raw in body.get("roads", []):
		_roads.append(_make_road(raw, false))
	for raw in body.get("railways", []):
		_roads.append(_make_road(raw, true))


func _make_road(raw: Variant, rail: bool) -> Dictionary:
	var body: Dictionary = raw
	var pts := PackedVector2Array()
	for p in body.get("polyline", []):
		pts.append(Vector2(float(p[0]), -float(p[2])))
	var kind := "rail" if rail else str(body.get("class", "street"))
	var lanes := float(body.get("lanes", 1.0))
	var default_lane := 1.435 if rail else 3.35
	var lane_w := float(body.get("lane_width_m", default_lane))
	var width := 2.0 if rail else maxf(lanes * lane_w, 3.0)
	var parts: Array = []
	var segs: Array = body.get("segments", [])
	if segs.is_empty() and pts.size() >= 2:
		parts.append({"tag": "grade", "a": 0, "b": pts.size() - 1})
	for seg in segs:
		parts.append({"tag": str(seg[2]), "a": int(seg[0]), "b": int(seg[1])})
	var nm: Variant = body.get("name")
	return {
		"id": str(body.get("id", "")),
		"name": "" if nm == null else str(nm),
		"kind": kind,
		"width": width,
		"rank": _rank(kind),
		"pts": pts,
		"parts": parts,
		"bridge": bool(body.get("bridge", false)),
	}


func _rank(kind: String) -> int:
	match kind:
		"us_highway":
			return 0
		"urban_arterial", "arterial_35":
			return 1
		"collector", "rim_local", "grade", "rail":
			return 2
		"downtown":
			return 3
		_:
			return 4


func _load_contours() -> void:
	_contours.clear()
	var data: Variant = _read_json(MAP_DIR + "/contours.json")
	if data == null or not (data is Dictionary):
		return
	var body: Dictionary = data
	for raw in body.get("lines", []):
		var line: Dictionary = raw
		var flat: Array = line.get("pts", [])
		var pts := PackedVector2Array()
		var i := 0
		while i + 1 < flat.size():
			pts.append(Vector2(float(flat[i]), float(flat[i + 1])))
			i += 2
		if pts.size() >= 2:
			_contours.append({
				"y": int(line.get("y", 0)),
				"major": bool(line.get("major", false)),
				"pts": pts,
			})


func _load_marks() -> void:
	_marks.clear()
	var data: Variant = _read_json(DATA + "/landmarks.json")
	if data is Dictionary:
		var body: Dictionary = data
		for raw in body.get("landmarks", []):
			var mark: Dictionary = raw
			var id := str(mark.get("id", ""))
			var icon := _mark_icon(id)
			if icon == "":
				continue
			var pos: Array = mark.get("position", [])
			if pos.size() < 3:
				continue
			var label := str(mark.get("name", id))
			if id == "shoshone_falls_card":
				label = "Shoshone Falls"
			_marks.append({
				"id": id,
				"name": label,
				"icon": icon,
				"x": float(pos[0]),
				"zn": -float(pos[2]),
			})
	var spawn: Variant = _read_json(DATA + "/spawn.json")
	if spawn is Dictionary:
		var at: Dictionary = (spawn as Dictionary).get("spawn", {})
		_marks.append({
			"id": "spawn",
			"name": "Spawn",
			"icon": "spawn",
			"x": float(at.get("x", 3320.0)),
			"zn": float(at.get("z_north", 6531.5)),
		})
	var water: Variant = _read_json(DATA + "/water.json")
	if water is Dictionary:
		var verts: Array = (water as Dictionary).get("vertices", [])
		if verts.size() > 40:
			var v: Dictionary = verts[verts.size() / 2]
			_canyon = Vector2(float(v.get("x", 2100.0)), float(v.get("z_north", 7000.0)) + 90.0)


func _mark_icon(id: String) -> String:
	if id == "perrine_bridge":
		return "bridge"
	if id == "visitor_centre":
		return "building"
	if id == "shoshone_falls_card":
		return "falls"
	if id.find("tower") >= 0:
		return "tower"
	return ""


func _load_report() -> void:
	_report = {}
	_report_found = false
	for path in [DATA + "/road_report.json", "res://_diag/road_report.json"]:
		var data: Variant = _read_json(path)
		if data == null or not (data is Dictionary):
			continue
		var body: Dictionary = data
		var roads: Variant = body.get("roads", body)
		if roads is Dictionary:
			for key in (roads as Dictionary).keys():
				_report[str(key)] = str((roads as Dictionary)[key]).to_lower()
			_report_found = true
			return
		if roads is Array:
			for item in roads:
				if item is Dictionary:
					_report[str(item.get("id", ""))] = str(item.get("status", "")).to_lower()
			_report_found = true
			return


func _player_xz() -> Vector2:
	var soul := get_tree().get_first_node_in_group("soul") as Node3D
	if soul == null:
		return Vector2(3320.0, -6531.5)
	return Vector2(soul.global_position.x, soul.global_position.z)


func _heading() -> Vector2:
	var fwd := Vector3(0.0, 0.0, -1.0)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		fwd = -cam.global_basis.z
	else:
		var soul := get_tree().get_first_node_in_group("soul") as Node3D
		if soul != null:
			fwd = -soul.global_basis.z
	var flat := Vector2(fwd.x, fwd.z)
	if flat.length_squared() < 0.0001:
		return Vector2(0.0, -1.0)
	return flat.normalized()


func _view() -> Vector2:
	if size.x >= 40.0 and size.y >= 40.0:
		return size
	return Vector2(1280.0, 720.0)


func _scale() -> float:
	var view := _view()
	return minf(view.x / WORLD_W, view.y / WORLD_H) * _zoom


func _font_px() -> int:
	return maxi(int(round(14.0 * _view().y / 1080.0)), 11)


func _to_screen(x: float, zn: float) -> Vector2:
	var view := _view()
	var s := _scale()
	return Vector2(view.x * 0.5 + (x - _cx) * s, view.y * 0.5 - (zn - _czn) * s)


func _to_world(screen: Vector2) -> Vector2:
	var view := _view()
	var s := maxf(_scale(), 0.0001)
	var x := _cx + (screen.x - view.x * 0.5) / s
	var zn := _czn - (screen.y - view.y * 0.5) / s
	return Vector2(x, zn)


func _clamp_center() -> void:
	var view := _view()
	var s := maxf(_scale(), 0.0001)
	var half_w := view.x * 0.5 / s
	var half_h := view.y * 0.5 / s
	if half_w * 2.0 >= WORLD_W:
		_cx = WORLD_W * 0.5
	else:
		_cx = clampf(_cx, half_w, WORLD_W - half_w)
	if half_h * 2.0 >= WORLD_H:
		_czn = WORLD_H * 0.5
	else:
		_czn = clampf(_czn, half_h, WORLD_H - half_h)


func _zoom_at(screen: Vector2, new_zoom: float) -> void:
	var world := _to_world(screen)
	_zoom = clampf(new_zoom, ZOOM_MIN, ZOOM_MAX)
	var s := maxf(_scale(), 0.0001)
	var view := _view()
	_cx = world.x - (screen.x - view.x * 0.5) / s
	_czn = world.y + (screen.y - view.y * 0.5) / s
	_clamp_center()
	_follow = false
	queue_redraw()


func _sample_height(col: float, row: float) -> float:
	var max_c := float(_height.get_width() - 1)
	var max_r := float(_height.get_height() - 1)
	col = clampf(col, 0.0, max_c)
	row = clampf(row, 0.0, max_r)
	var c0 := int(floor(col))
	var r0 := int(floor(row))
	var c1 := mini(c0 + 1, int(max_c))
	var r1 := mini(r0 + 1, int(max_r))
	var tx := col - float(c0)
	var ty := row - float(r0)
	var h00 := _decode_px(_height.get_pixel(c0, r0))
	var h10 := _decode_px(_height.get_pixel(c1, r0))
	var h01 := _decode_px(_height.get_pixel(c0, r1))
	var h11 := _decode_px(_height.get_pixel(c1, r1))
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), ty)


func _decode_px(color: Color) -> float:
	var hi := int(round(color.r * 255.0))
	var lo := int(round(color.g * 255.0))
	return float(hi * 256 + lo) * 0.01 - 50.0


func _draw_base() -> void:
	if _base == null:
		return
	var nw := _to_screen(0.0, WORLD_H)
	var se := _to_screen(WORLD_W, 0.0)
	draw_texture_rect(_base, Rect2(nw, se - nw), false)


func _draw_contours(view: Vector2) -> void:
	for line in _contours:
		var pts: PackedVector2Array = line["pts"]
		var major := bool(line["major"])
		var col := Color(0.16, 0.12, 0.08, 0.85) if major else Color(0.22, 0.17, 0.12, 0.55)
		var width := 2.0 if major else 1.0
		for i in pts.size() - 1:
			var s0 := _to_screen(pts[i].x, pts[i].y)
			var s1 := _to_screen(pts[i + 1].x, pts[i + 1].y)
			if _segment_hits(s0, s1, view):
				draw_line(s0, s1, col, width)


func _draw_roads(view: Vector2) -> void:
	for road in _roads:
		_stroke_road(road, view, true)
	for road in _roads:
		_stroke_road(road, view, false)


func _stroke_road(road: Dictionary, view: Vector2, casing: bool) -> void:
	var kind := str(road["kind"])
	if kind == "rail":
		if casing:
			return
		_stroke_rail(road, view)
		return
	var pts: PackedVector2Array = road["pts"]
	var width_m := float(road["width"])
	var fill_px := _fill_px(width_m, kind)
	var parts: Array = road["parts"]
	for part in parts:
		var tag := str(part["tag"])
		var deck := tag == "bridge" or tag == "deck" or bool(road["bridge"])
		var a := int(part["a"])
		var b := int(part["b"])
		var col: Color
		var width: float
		if casing:
			if deck:
				col = Color(0.02, 0.02, 0.02, 0.95)
				width = maxf(fill_px + 8.0, 7.0)
			elif kind == "us_highway":
				col = Color(0.45, 0.20, 0.04, 0.95)
				width = maxf(fill_px + 6.0, 3.0)
			elif kind == "urban_arterial" or kind == "arterial_35":
				col = Color(0.55, 0.42, 0.08, 0.9)
				width = fill_px + 2.0
			else:
				col = Color(0.32, 0.32, 0.34, 0.95)
				width = fill_px + 3.0
		else:
			col = _fill_color(road)
			width = fill_px
			if deck:
				width = maxf(fill_px - 1.0, 1.5)
		for i in range(a, b):
			if i < 0 or i + 1 >= pts.size():
				continue
			var s0 := _to_screen(pts[i].x, pts[i].y)
			var s1 := _to_screen(pts[i + 1].x, pts[i + 1].y)
			if not _segment_hits(s0, s1, view):
				continue
			draw_line(s0, s1, col, width)
			if not casing and deck:
				draw_line(s0, s1, Color(0.02, 0.02, 0.02, 0.9), maxf(1.0, fill_px * 0.18))


func _stroke_rail(road: Dictionary, view: Vector2) -> void:
	var pts: PackedVector2Array = road["pts"]
	var col := _fill_color(road)
	var width := maxf(2.0 * _scale(), 1.5)
	for i in pts.size() - 1:
		var s0 := _to_screen(pts[i].x, pts[i].y)
		var s1 := _to_screen(pts[i + 1].x, pts[i + 1].y)
		if not _segment_hits(s0, s1, view):
			continue
		draw_dashed_line(s0, s1, col, width, 8.0)


func _fill_px(width_m: float, kind: String) -> float:
	var px := width_m * _scale()
	if kind == "us_highway":
		return maxf(px, 2.2)
	if kind == "urban_arterial" or kind == "arterial_35":
		return maxf(px, 1.8)
	return maxf(px, 1.4)


func _fill_color(road: Dictionary) -> Color:
	if _status:
		var state := str(_report.get(str(road["id"]), ""))
		if state == "pass":
			return Color(0.18, 0.72, 0.28)
		if state == "fail":
			return Color(0.86, 0.16, 0.14)
		return Color(0.55, 0.55, 0.55)
	match str(road["kind"]):
		"us_highway":
			return Color(0.93, 0.48, 0.10)
		"urban_arterial", "arterial_35":
			return Color(0.96, 0.82, 0.16)
		"rail":
			return Color(0.04, 0.04, 0.04)
		_:
			return Color(0.96, 0.96, 0.94)


func _draw_grid(view: Vector2) -> void:
	var col := Color(1.0, 1.0, 1.0, 0.35)
	for cx in 11:
		var a := _to_screen(float(cx) * CHUNK_M, 0.0)
		var b := _to_screen(float(cx) * CHUNK_M, WORLD_H)
		if _segment_hits(a, b, view):
			draw_line(a, b, col, 1.0)
	for cz in 17:
		var a := _to_screen(0.0, float(cz) * CHUNK_M)
		var b := _to_screen(WORLD_W, float(cz) * CHUNK_M)
		if _segment_hits(a, b, view):
			draw_line(a, b, col, 1.0)
	var cell := CHUNK_M * _scale()
	if cell < 36.0:
		return
	var font := _font_or()
	var px := maxi(_font_px() - 2, 10)
	for cx in 10:
		for cz in 16:
			var at := _to_screen(float(cx) * CHUNK_M + 12.0 / maxf(_scale(), 0.01), float(cz) * CHUNK_M + CHUNK_M - 18.0 / maxf(_scale(), 0.01))
			if at.x < 0.0 or at.y < 0.0 or at.x > view.x or at.y > view.y:
				continue
			draw_string(font, at, "%d,%d" % [cx, cz], HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(1, 1, 1, 0.8))


func _draw_marks(view: Vector2) -> void:
	var font := _font_or()
	var px := _font_px()
	for mark in _marks:
		var at := _to_screen(float(mark["x"]), float(mark["zn"]))
		if at.x < -20.0 or at.y < -20.0 or at.x > view.x + 20.0 or at.y > view.y + 20.0:
			continue
		_draw_icon(at, str(mark["icon"]))
		_halo_text(font, at + Vector2(10.0, 4.0), str(mark["name"]), px, Color(0.98, 0.96, 0.88))
	var canyon_at := _to_screen(_canyon.x, _canyon.y)
	if canyon_at.x > 0.0 and canyon_at.y > 0.0 and canyon_at.x < view.x and canyon_at.y < view.y:
		_halo_text(font, canyon_at, "Snake River Canyon", px + 2, Color(0.85, 0.93, 0.95))


func _draw_icon(at: Vector2, icon: String) -> void:
	var ink := Color(0.98, 0.96, 0.90)
	var dark := Color(0.08, 0.07, 0.06)
	if icon == "bridge":
		draw_rect(Rect2(at - Vector2(7, 3), Vector2(14, 6)), dark)
		draw_rect(Rect2(at - Vector2(6, 2), Vector2(12, 4)), Color(0.75, 0.72, 0.66))
	elif icon == "building":
		draw_colored_polygon(PackedVector2Array([at + Vector2(-6, 2), at + Vector2(0, -7), at + Vector2(6, 2)]), Color(0.85, 0.35, 0.22))
		draw_rect(Rect2(at + Vector2(-5, 2), Vector2(10, 7)), ink)
	elif icon == "falls":
		draw_colored_polygon(PackedVector2Array([at + Vector2(-7, -4), at + Vector2(7, -4), at + Vector2(0, 7)]), Color(0.29, 0.56, 0.78))
	elif icon == "tower":
		draw_rect(Rect2(at + Vector2(-2, -2), Vector2(4, 10)), ink)
		draw_colored_polygon(PackedVector2Array([at + Vector2(-5, -2), at + Vector2(0, -9), at + Vector2(5, -2)]), Color(0.85, 0.3, 0.18))
	elif icon == "spawn":
		draw_circle(at, 5.0, Color(0.95, 0.82, 0.2))
		draw_arc(at, 8.0, 0.0, TAU, 16, dark, 1.5, true)
	else:
		draw_circle(at, 4.0, ink)


func _draw_player() -> void:
	var player := _player_xz()
	var at := _to_screen(player.x, -player.y)
	var head := _heading()
	var reach := VIEW_CONE_M * _scale()
	var ang := head.angle()
	var left := Vector2.from_angle(ang - deg_to_rad(18.0)) * reach
	var right := Vector2.from_angle(ang + deg_to_rad(18.0)) * reach
	draw_colored_polygon(PackedVector2Array([at, at + left, at + right]), Color(1.0, 0.72, 0.25, 0.32))
	var tip := at + head * 14.0
	var back := at - head * 6.0
	var side := Vector2(-head.y, head.x) * 6.5
	draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), Color(0.08, 0.06, 0.04, 0.95))
	var tip2 := at + head * 12.0
	var back2 := at - head * 4.5
	var side2 := Vector2(-head.y, head.x) * 4.5
	draw_colored_polygon(PackedVector2Array([tip2, back2 + side2, back2 - side2]), Color(0.98, 0.46, 0.08, 1.0))


func _layout_labels(cull: bool) -> Array:
	var view := _view()
	var font := _font_or()
	var px := _font_px()
	var ranked: Array = _roads.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["rank"]) == int(b["rank"]):
			return str(a["id"]) < str(b["id"])
		return int(a["rank"]) < int(b["rank"])
	)
	var kept: Array[Rect2] = []
	var labels: Array = []
	for road in ranked:
		if str(road["name"]) == "":
			continue
		if not _rank_visible(int(road["rank"])):
			continue
		var pts: PackedVector2Array = road["pts"]
		var stations := _label_stations(pts)
		for station in stations:
			var along := _along_at(pts, station)
			var screen := _to_screen(station.x, station.y)
			if cull and (screen.x < -40.0 or screen.y < -20.0 or screen.x > view.x + 40.0 or screen.y > view.y + 20.0):
				continue
			var dir := Vector2(along.x, -along.y)
			if dir.length_squared() < 0.0001:
				dir = Vector2.RIGHT
			dir = dir.normalized()
			if dir.x < 0.0 or (absf(dir.x) < 0.02 and dir.y > 0.0):
				dir = -dir
			var text := str(road["name"])
			var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
			var placed := false
			var perp := Vector2(-dir.y, dir.x)
			var shifts: Array[float] = [0.0, 1.0, -1.0, 2.0, -2.0]
			for step in shifts:
				var at: Vector2 = screen + perp * step * (float(px) + 3.0)
				var rect := Rect2(at - Vector2(text_size.x * 0.5, float(px) * 0.5), text_size + Vector2(4.0, 2.0))
				if _hits_any(rect, kept):
					continue
				kept.append(rect)
				labels.append({
					"id": str(road["id"]),
					"text": text,
					"at": at,
					"angle": dir.angle(),
					"rank": int(road["rank"]),
				})
				placed = true
				break
			if not placed:
				continue
	return labels


func _rank_visible(rank: int) -> bool:
	if rank <= 1:
		return true
	if rank == 2:
		return _zoom >= 1.5
	if rank == 3:
		return _zoom >= 3.0
	return _zoom >= 5.0


func _draw_labels(labels: Array) -> void:
	var font := _font_or()
	var px := _font_px()
	for item in labels:
		var at: Vector2 = item["at"]
		var angle := float(item["angle"])
		var text := str(item["text"])
		var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_set_transform(at, angle, Vector2.ONE)
		var origin := Vector2(-text_w * 0.5, float(px) * 0.32)
		for off in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			draw_string(font, origin + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0.05, 0.04, 0.03, 0.92))
		draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0.98, 0.96, 0.90))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_contour_labels(view: Vector2, road_labels: Array) -> void:
	var font := _font_or()
	var px := maxi(_font_px() - 1, 11)
	var kept: Array[Rect2] = []
	for item in road_labels:
		var at: Vector2 = item["at"]
		kept.append(Rect2(at - Vector2(40, 10), Vector2(80, 20)))
	for line in _contours:
		if not bool(line["major"]):
			continue
		var pts: PackedVector2Array = line["pts"]
		var total := _poly_len(pts)
		if total < 200.0:
			continue
		var text := str(int(line["y"]))
		var dist := 400.0
		while dist < total:
			var station := _point_at(pts, dist)
			dist += 1400.0
			var screen := _to_screen(station.x, station.y)
			if screen.x < 8.0 or screen.y < 8.0 or screen.x > view.x - 8.0 or screen.y > view.y - 8.0:
				continue
			var rect := Rect2(screen - Vector2(12, 8), Vector2(28, 16))
			if _hits_any(rect, kept):
				continue
			kept.append(rect)
			_halo_text(font, screen, text, px, Color(0.22, 0.16, 0.10))


func _draw_chrome(view: Vector2) -> void:
	var font := _font_or()
	var px := _font_px()
	var world := _to_world(_cursor)
	world.x = clampf(world.x, 0.0, WORLD_W)
	world.y = clampf(world.y, 0.0, WORLD_H)
	var lines := _readout_lines(world.x, -world.y)
	var panel_w := 360.0 * _view().y / 1080.0
	var panel_h := float(lines.size()) * (float(px) + 6.0) + 16.0
	var panel := Rect2(12.0, view.y - panel_h - 12.0, maxf(panel_w, 280.0), panel_h)
	draw_rect(panel, Color(0.04, 0.04, 0.05, 0.82))
	draw_rect(Rect2(panel.position, Vector2(panel.size.x, 2.0)), Color(0.95, 0.55, 0.16))
	for i in lines.size():
		draw_string(font, panel.position + Vector2(10.0, 8.0 + float(px) + float(i) * (float(px) + 6.0)), lines[i], HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 16.0, px, Color(0.97, 0.95, 0.88))
	_draw_scale(view, font, px)
	_draw_north(view, font, px)
	if _legend:
		_draw_legend(view, font, px)
	var hint := "M close    wheel/+/- zoom    drag/WASD pan    F follow    G chunks    R status    L legend    Home"
	draw_string(font, Vector2(12.0, 12.0 + float(px)), hint, HORIZONTAL_ALIGNMENT_LEFT, view.x - 80.0, px, Color(0.96, 0.94, 0.88))
	var zoom_text := "%.1fx" % _zoom
	draw_string(font, Vector2(view.x - 78.0, 12.0 + float(px)), zoom_text, HORIZONTAL_ALIGNMENT_LEFT, 70.0, px, Color(0.98, 0.9, 0.7))
	if _status:
		var note := "road status  green pass / red fail" if _report_found else "road_report not found"
		draw_string(font, Vector2(12.0, 18.0 + float(px) * 2.0), note, HORIZONTAL_ALIGNMENT_LEFT, view.x - 24.0, px, Color(0.98, 0.86, 0.45))
	if _toast_t > 0.0 and _toast != "":
		var tw := font.get_string_size(_toast, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + 16.0
		var toast_at := Vector2(clampf(_cursor.x + 14.0, 8.0, view.x - tw - 8.0), clampf(_cursor.y - 28.0, 8.0, view.y - 28.0))
		draw_rect(Rect2(toast_at, Vector2(tw, float(px) + 10.0)), Color(0.05, 0.05, 0.06, 0.9))
		draw_string(font, toast_at + Vector2(8.0, float(px) + 1.0), _toast, HORIZONTAL_ALIGNMENT_LEFT, tw, px, Color(0.98, 0.94, 0.8))


func _readout_lines(x: float, godot_z: float) -> PackedStringArray:
	var y := terrain_y(x, godot_z)
	var zn := -godot_z
	var cx := int(floor(x / CHUNK_M))
	var cz := int(floor(zn / CHUNK_M))
	var road := nearest_road(x, godot_z)
	var road_line := road if road != "" else "no road within 30 m"
	return PackedStringArray([
		"x %.1f    z %.1f    y %.1f" % [x, godot_z, y],
		"UTM %.0f E    %.0f N" % [ORIGIN_E + x, ORIGIN_N + zn],
		"chunk c_%d_%d" % [cx, cz],
		road_line,
	])


func _draw_scale(view: Vector2, font: Font, px: int) -> void:
	var target_px := clampf(view.x * 0.18, 80.0, 220.0)
	var metres := target_px / maxf(_scale(), 0.0001)
	var nice := 50.0
	for step in [50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0]:
		if step <= metres:
			nice = step
	var bar := nice * _scale()
	var origin := Vector2(view.x * 0.5 - bar * 0.5, view.y - 28.0)
	draw_line(origin, origin + Vector2(bar, 0.0), Color(0.97, 0.95, 0.88), 3.0)
	draw_line(origin, origin + Vector2(0.0, -8.0), Color(0.97, 0.95, 0.88), 2.0)
	draw_line(origin + Vector2(bar, 0.0), origin + Vector2(bar, -8.0), Color(0.97, 0.95, 0.88), 2.0)
	var word := "%.0f m" % nice if nice < 1000.0 else "%.0f km" % (nice / 1000.0)
	draw_string(font, origin + Vector2(0.0, -12.0), word, HORIZONTAL_ALIGNMENT_LEFT, bar, px, Color(0.97, 0.95, 0.88))


func _draw_north(view: Vector2, font: Font, px: int) -> void:
	var at := Vector2(view.x - 36.0, 78.0)
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -16), at + Vector2(-7, 8), at + Vector2(7, 8)]), Color(0.96, 0.94, 0.88))
	draw_string(font, at + Vector2(-6.0, -18.0), "N", HORIZONTAL_ALIGNMENT_LEFT, 20.0, px, Color(0.98, 0.95, 0.88))


func _draw_legend(view: Vector2, font: Font, px: int) -> void:
	var rows := [
		[Color(0.93, 0.48, 0.10), "Highway"],
		[Color(0.96, 0.82, 0.16), "Arterial"],
		[Color(0.96, 0.96, 0.94), "Street"],
		[Color(0.04, 0.04, 0.04), "Rail"],
		[Color(0.29, 0.56, 0.78), "Water"],
	]
	var w := 150.0
	var h := float(rows.size()) * (float(px) + 6.0) + 14.0
	var panel := Rect2(view.x - w - 12.0, view.y - h - 48.0, w, h)
	draw_rect(panel, Color(0.04, 0.04, 0.05, 0.82))
	for i in rows.size():
		var y := panel.position.y + 10.0 + float(i) * (float(px) + 6.0)
		draw_line(panel.position + Vector2(10.0, y - panel.position.y + 4.0), panel.position + Vector2(28.0, y - panel.position.y + 4.0), rows[i][0], 3.0)
		draw_string(font, Vector2(panel.position.x + 36.0, y + float(px)), str(rows[i][1]), HORIZONTAL_ALIGNMENT_LEFT, 100.0, px, Color(0.97, 0.95, 0.88))


func _halo_text(font: Font, at: Vector2, text: String, px: int, col: Color) -> void:
	for off in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		draw_string(font, at + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0.05, 0.04, 0.03, 0.9))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


func _copy_here(screen: Vector2) -> void:
	var world := _to_world(screen)
	var x := int(round(clampf(world.x, 0.0, WORLD_W)))
	var gz := int(round(-clampf(world.y, 0.0, WORLD_H)))
	var text := "%d,%d" % [x, gz]
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(text)
	_toast = "Copied %s" % text
	_toast_t = 1.6
	queue_redraw()


func _road_label(road: Dictionary) -> String:
	var nm := str(road["name"])
	if nm != "":
		return nm
	return str(road["id"])


func _label_anchor(road: Dictionary) -> Vector2:
	var pts: PackedVector2Array = road["pts"]
	var stations := _label_stations(pts)
	if stations.is_empty():
		if pts.is_empty():
			return Vector2.ZERO
		return pts[0]
	return stations[0]


func _label_stations(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var total := _poly_len(pts)
	if total < 1.0:
		return out
	if total < LABEL_M:
		out.append(_point_at(pts, total * 0.5))
		return out
	var dist := LABEL_M * 0.5
	while dist < total - 60.0:
		out.append(_point_at(pts, dist))
		dist += LABEL_M
	return out


func _poly_len(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	return total


func _point_at(pts: PackedVector2Array, dist: float) -> Vector2:
	var left := dist
	for i in pts.size() - 1:
		var step := pts[i].distance_to(pts[i + 1])
		if step < 0.001:
			continue
		if left <= step:
			return pts[i].lerp(pts[i + 1], left / step)
		left -= step
	return pts[pts.size() - 1]


func _along_at(pts: PackedVector2Array, at: Vector2) -> Vector2:
	var best_d := 1.0e12
	var best := Vector2.RIGHT
	for i in pts.size() - 1:
		var d := _dist_point_seg(at, pts[i], pts[i + 1])
		if d < best_d:
			best_d = d
			best = pts[i + 1] - pts[i]
	if best.length_squared() < 0.0001:
		return Vector2.RIGHT
	return best.normalized()


func _dist_point_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var den := ab.length_squared()
	var t := 0.0 if den < 0.000001 else clampf((p - a).dot(ab) / den, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _segment_hits(a: Vector2, b: Vector2, view: Vector2) -> bool:
	var margin := 24.0
	var min_x := minf(a.x, b.x)
	var max_x := maxf(a.x, b.x)
	var min_y := minf(a.y, b.y)
	var max_y := maxf(a.y, b.y)
	return max_x >= -margin and min_x <= view.x + margin and max_y >= -margin and min_y <= view.y + margin


func _hits_any(rect: Rect2, kept: Array[Rect2]) -> bool:
	for other in kept:
		if rect.intersects(other):
			return true
	return false


func _font_or() -> Font:
	if _font != null:
		return _font
	return ThemeDB.fallback_font
