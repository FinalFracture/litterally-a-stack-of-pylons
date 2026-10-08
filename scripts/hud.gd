extends Control

const _MAP_METERS := 260.0

var _stack: Node
var _city: Node
var _sky: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	var soul: Node = get_tree().get_first_node_in_group("soul")
	if soul != null:
		_stack = soul.get_node_or_null("StackController")
	_city = get_tree().root.get_node_or_null("Main/City")
	if _city == null:
		var main: Node = get_parent()
		if main != null:
			_city = main.get_parent().get_node_or_null("City")
	_sky = get_tree().root.get_node_or_null("Main/DirectionalLight3D")
	if _sky == null and get_parent() != null:
		_sky = get_parent().get_parent().get_node_or_null("DirectionalLight3D")


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var view: Vector2 = size
	if view.x < 40.0:
		return
	_draw_notice(view)
	_draw_readout()
	_draw_sky(view)
	_draw_map(view)


func _duties() -> Node:
	if _city == null:
		return null
	return _city.get_node_or_null("Duties")


func _draw_notice(view: Vector2) -> void:
	var desk := _duties()
	if desk == null or not desk.has_method("dept_name"):
		return
	var dept := str(desk.call("dept_name"))
	var body := str(desk.call("task_text"))
	if dept == "" or body == "":
		return
	var progress := str(desk.call("task_progress"))
	var panel := Rect2(view.x * 0.5 - 250.0, 16.0, 500.0, 78.0)
	_frame(panel, Color(1.0, 0.55, 0.18, 0.7))
	var font: Font = ThemeDB.fallback_font
	draw_string(font, panel.position + Vector2(16.0, 22.0), dept, HORIZONTAL_ALIGNMENT_LEFT, 460.0, 13, Color(1.0, 0.62, 0.28))
	draw_string(font, panel.position + Vector2(16.0, 46.0), body, HORIZONTAL_ALIGNMENT_LEFT, 468.0, 15, Color(0.94, 0.92, 0.86))
	if progress != "":
		draw_string(font, panel.position + Vector2(16.0, 68.0), progress, HORIZONTAL_ALIGNMENT_LEFT, 200.0, 13, Color(1.0, 0.78, 0.4))


func _frame(rect: Rect2, accent: Color) -> void:
	draw_rect(rect, Color(0.03, 0.04, 0.05, 0.78))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1.0)), accent)
	var arm := 14.0
	var c := Color(1.0, 0.58, 0.22, 0.95)
	var p := rect.position
	var s := rect.size
	draw_line(p, p + Vector2(arm, 0), c, 2.0)
	draw_line(p, p + Vector2(0, arm), c, 2.0)
	draw_line(p + Vector2(s.x, 0), p + Vector2(s.x - arm, 0), c, 2.0)
	draw_line(p + Vector2(s.x, 0), p + Vector2(s.x, arm), c, 2.0)
	draw_line(p + Vector2(0, s.y), p + Vector2(arm, s.y), c, 2.0)
	draw_line(p + Vector2(0, s.y), p + Vector2(0, s.y - arm), c, 2.0)
	draw_line(p + s, p + s - Vector2(arm, 0), c, 2.0)
	draw_line(p + s, p + s - Vector2(0, arm), c, 2.0)


func _draw_readout() -> void:
	var panel := Rect2(16.0, 108.0, 220.0, 72.0)
	_frame(panel, Color(1.0, 0.55, 0.2, 0.55))
	var font: Font = ThemeDB.fallback_font
	var height: float = 0.0
	if _stack != null:
		height = float(_stack.get_stack_height())
	var roads := "Hall Avenue  /  Bridge Road"
	if _city != null and _city.has_method("nearest_names"):
		var soul: Node3D = get_tree().get_first_node_in_group("soul") as Node3D
		if soul != null:
			var names: PackedStringArray = _city.nearest_names(soul.global_position.x, soul.global_position.z)
			if names.size() >= 2:
				roads = "%s  /  %s" % [names[0], names[1]]
	draw_string(font, Vector2(32.0, 142.0), "%.1f m" % height, HORIZONTAL_ALIGNMENT_LEFT, 180.0, 28, Color(0.96, 0.94, 0.88))
	draw_string(font, Vector2(32.0, 166.0), roads, HORIZONTAL_ALIGNMENT_LEFT, 190.0, 13, Color(0.78, 0.8, 0.74))


func _draw_sky(view: Vector2) -> void:
	var panel := Rect2(view.x - 168.0, 108.0, 148.0, 108.0)
	_frame(panel, Color(1.0, 0.62, 0.28, 0.4))
	var center := Vector2(panel.position.x + 74.0, panel.position.y + 66.0)
	var radius := 28.0
	draw_arc(center, radius, 0.0, TAU, 40, Color(1.0, 0.62, 0.28, 0.85), 1.5, true)
	var day := true
	var flat := Vector2.RIGHT
	if _sky != null and _sky.has_method("sun_up"):
		day = bool(_sky.sun_up())
	if _sky != null and _sky.has_method("sun_flat"):
		flat = _sky.sun_flat()
	var dot: Vector2 = center + _compass_screen(flat) * (radius - 2.0)
	var tint: Color = Color(1.0, 0.78, 0.28) if day else Color(0.82, 0.88, 0.95)
	draw_circle(dot, 5.5, tint)
	draw_arc(dot, 9.0, 0.0, TAU, 16, tint, 1.0, true)
	var font: Font = ThemeDB.fallback_font
	var word: String = "SUN" if day else "MOON"
	draw_string(font, panel.position + Vector2(14.0, 18.0), word, HORIZONTAL_ALIGNMENT_LEFT, 80.0, 12, tint)
	_draw_compass_letters(center, radius + 2.0, font, 11)


func _draw_map(view: Vector2) -> void:
	var map_size := 210.0
	var origin := Vector2(view.x - map_size - 16.0, view.y - map_size - 16.0)
	var map_rect := Rect2(origin, Vector2(map_size, map_size))
	_frame(map_rect, Color(1.0, 0.55, 0.2, 0.45))
	var clip := map_rect.grow(-4.0)
	var soul: Node3D = get_tree().get_first_node_in_group("soul") as Node3D
	var focus := Vector2.ZERO
	var facing := Vector2.UP
	if soul != null:
		focus = Vector2(soul.global_position.x, soul.global_position.z)
		facing = _look_flat()
	if _city != null and _city.has_method("map_blocks"):
		var blocks: Array = _city.map_blocks()
		for block in blocks:
			var rect: Rect2 = block
			_draw_world_rect(rect, origin, map_size, focus, clip, Color(0.45, 0.46, 0.48, 0.9))
	var seen: Dictionary = {}
	if _city != null and _city.has_method("map_segments"):
		var segments: Array = _city.map_segments()
		for seg in segments:
			var line: Dictionary = seg
			var kind: String = str(line.get("kind", ""))
			var p0: Vector2 = _map_point(float(line["x0"]), float(line["z0"]), origin, map_size, focus)
			var p1: Vector2 = _map_point(float(line["x1"]), float(line["z1"]), origin, map_size, focus)
			var clipped: PackedVector2Array = _clip_seg(p0, p1, clip)
			if clipped.size() < 2:
				continue
			if kind != "":
				seen[kind] = true
			var main_road: bool = bool(line.get("main", false))
			draw_line(clipped[0], clipped[1], _road_color(kind, main_road), _road_width(kind, main_road))
	var font: Font = ThemeDB.fallback_font
	_draw_stall(origin, map_size, focus, clip, font)
	var desk := _duties()
	if desk != null and desk.has_method("job_point"):
		var spot: Vector3 = desk.call("job_point")
		if spot.x < 2000.0:
			var mark: Vector2 = _map_point(spot.x, spot.z, origin, map_size, focus)
			if clip.has_point(mark):
				draw_rect(Rect2(mark - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), Color(1.0, 0.78, 0.2, 0.95))
				draw_arc(mark, 7.0, 0.0, TAU, 12, Color(1.0, 0.55, 0.12), 1.5, true)
	_draw_legend(origin, map_size, font, seen)
	if soul != null and _city != null and _city.has_method("nearest_names"):
		var names: PackedStringArray = _city.nearest_names(soul.global_position.x, soul.global_position.z)
		if names.size() >= 2:
			draw_string(font, origin + Vector2(8.0, 16.0), names[0], HORIZONTAL_ALIGNMENT_LEFT, map_size - 28.0, 12, Color(0.95, 0.93, 0.84))
			draw_string(font, origin + Vector2(8.0, 32.0), names[1], HORIZONTAL_ALIGNMENT_LEFT, map_size - 28.0, 12, Color(0.95, 0.93, 0.84))
	var player_at := origin + Vector2(map_size * 0.5, map_size * 0.5)
	_draw_compass_letters(player_at, map_size * 0.46, font, 11)
	if _sky != null and _sky.has_method("sun_flat"):
		var sun_at: Vector2 = player_at + _compass_screen(_sky.sun_flat()) * (map_size * 0.40)
		var day_mark := true
		if _sky.has_method("sun_up"):
			day_mark = bool(_sky.sun_up())
		var sun_tint: Color = Color(1.0, 0.78, 0.28) if day_mark else Color(0.82, 0.88, 0.95)
		draw_circle(sun_at, 3.5, sun_tint)
	draw_circle(player_at, 4.0, Color(0.95, 0.48, 0.12))
	if facing.length_squared() > 0.01:
		var tip: Vector2 = player_at + facing.normalized() * 9.0
		draw_line(player_at, tip, Color(1.0, 0.86, 0.55), 2.0)


func _draw_stall(origin: Vector2, map_size: float, focus: Vector2, clip: Rect2, font: Font) -> void:
	if _city == null or not _city.has_method("stall_rect"):
		return
	var raw: Variant = _city.call("stall_rect")
	if not (raw is Rect2):
		return
	var stall: Rect2 = raw
	var shown: Rect2 = _world_rect_on_map(stall, origin, map_size, focus).intersection(clip)
	if shown.size.x < 2.0 or shown.size.y < 2.0:
		return
	draw_rect(shown, Color(0.96, 0.74, 0.12, 0.95))
	draw_rect(shown.grow(1.0).intersection(clip), Color(0.1, 0.07, 0.02, 1.0), false, 2.0)
	if shown.size.x > 36.0 and shown.size.y > 12.0:
		draw_string(font, shown.get_center() + Vector2(-22.0, -4.0), "STALL", HORIZONTAL_ALIGNMENT_LEFT, 56.0, 12, Color(0.12, 0.08, 0.02))


func _draw_world_rect(rect: Rect2, origin: Vector2, map_size: float, focus: Vector2, clip: Rect2, color: Color) -> void:
	var shown: Rect2 = _world_rect_on_map(rect, origin, map_size, focus).intersection(clip)
	if shown.size.x < 1.0 or shown.size.y < 1.0:
		return
	draw_rect(shown, color)


func _world_rect_on_map(rect: Rect2, origin: Vector2, map_size: float, focus: Vector2) -> Rect2:
	var s0: Vector2 = _map_point(rect.position.x, rect.position.y, origin, map_size, focus)
	var s1: Vector2 = _map_point(rect.end.x, rect.end.y, origin, map_size, focus)
	var left: float = minf(s0.x, s1.x)
	var top: float = minf(s0.y, s1.y)
	return Rect2(left, top, absf(s1.x - s0.x), absf(s1.y - s0.y))


func _draw_legend(origin: Vector2, map_size: float, font: Font, seen: Dictionary) -> void:
	var kinds: PackedStringArray = PackedStringArray(["arterial", "street", "strips", "alley", "radial", "court"])
	var labels: PackedStringArray = PackedStringArray(["Artery", "Street", "Strip", "Alley", "Radial", "Court"])
	var shown: PackedStringArray = PackedStringArray()
	var words: PackedStringArray = PackedStringArray()
	for i in kinds.size():
		if not seen.has(kinds[i]):
			continue
		shown.append(kinds[i])
		words.append(labels[i])
	if shown.is_empty():
		return
	var rows: int = (shown.size() + 1) / 2
	var plate_h: float = float(rows) * 13.0 + 6.0
	var plate := Rect2(origin.x + 6.0, origin.y + map_size - plate_h - 6.0, map_size - 12.0, plate_h)
	draw_rect(plate, Color(0.03, 0.04, 0.05, 0.82))
	for n in shown.size():
		var col: int = n % 2
		var row: int = n / 2
		var at := plate.position + Vector2(8.0 + float(col) * 96.0, 12.0 + float(row) * 13.0)
		draw_line(at + Vector2(0.0, -3.0), at + Vector2(16.0, -3.0), _road_color(shown[n], false), _road_width(shown[n], false))
		draw_string(font, at + Vector2(20.0, 1.0), words[n], HORIZONTAL_ALIGNMENT_LEFT, 70.0, 11, Color(0.95, 0.93, 0.84))


func _road_color(kind: String, main_road: bool) -> Color:
	if kind == "arterial" or (kind == "" and main_road):
		return Color(0.86, 0.84, 0.76)
	if kind == "street":
		return Color(0.58, 0.60, 0.62)
	if kind == "strips":
		return Color(0.55, 0.66, 0.78)
	if kind == "alley":
		return Color(0.74, 0.52, 0.32)
	if kind == "radial":
		return Color(0.86, 0.66, 0.28)
	if kind == "court":
		return Color(0.62, 0.68, 0.38)
	return Color(0.42, 0.44, 0.46)


func _road_width(kind: String, main_road: bool) -> float:
	if kind == "arterial" or (kind == "" and main_road):
		return 3.0
	if kind == "street":
		return 2.0
	if kind == "strips":
		return 2.2
	return 1.6


func _look_flat() -> Vector2:
	var cam := get_viewport().get_camera_3d()
	var ahead := Vector3(0.0, 0.0, -1.0)
	if cam != null:
		ahead = -cam.global_basis.z
	else:
		var soul: Node3D = get_tree().get_first_node_in_group("soul") as Node3D
		if soul != null:
			ahead = -soul.global_transform.basis.z
	return _compass_screen(Vector2(ahead.x, ahead.z))


func _compass_screen(flat: Vector2) -> Vector2:
	return Vector2(flat.x, -flat.y)


func _draw_compass_letters(center: Vector2, radius: float, font: Font, font_size: int) -> void:
	var ink := Color(0.95, 0.93, 0.84)
	var marks: PackedStringArray = PackedStringArray(["N", "E", "S", "W"])
	var at: Array[Vector2] = [
		center + Vector2(-4.0, -radius),
		center + Vector2(radius - 4.0, 4.0),
		center + Vector2(-4.0, radius + 8.0),
		center + Vector2(-radius - 2.0, 4.0),
	]
	for i in marks.size():
		draw_string(font, at[i], marks[i], HORIZONTAL_ALIGNMENT_LEFT, 16.0, font_size, ink)


func _map_point(x: float, z: float, origin: Vector2, map_size: float, focus: Vector2) -> Vector2:
	var scale: float = map_size / _MAP_METERS
	var center := origin + Vector2(map_size * 0.5, map_size * 0.5)
	return center + Vector2((x - focus.x) * scale, (focus.y - z) * scale)


func _clip_seg(a: Vector2, b: Vector2, rect: Rect2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var left: float = rect.position.x
	var top: float = rect.position.y
	var right: float = rect.end.x
	var bottom: float = rect.end.y
	var x0: float = a.x
	var y0: float = a.y
	var x1: float = b.x
	var y1: float = b.y
	var c0: int = _out_code(x0, y0, left, top, right, bottom)
	var c1: int = _out_code(x1, y1, left, top, right, bottom)
	for _guard in 8:
		if c0 == 0 and c1 == 0:
			out.append(Vector2(x0, y0))
			out.append(Vector2(x1, y1))
			return out
		if (c0 & c1) != 0:
			return out
		var code: int = c0 if c0 != 0 else c1
		var x: float = x0
		var y: float = y0
		if (code & 8) != 0:
			var dy_top: float = y1 - y0
			if absf(dy_top) < 0.00001:
				return out
			x = x0 + (x1 - x0) * (top - y0) / dy_top
			y = top
		elif (code & 4) != 0:
			var dy_bot: float = y1 - y0
			if absf(dy_bot) < 0.00001:
				return out
			x = x0 + (x1 - x0) * (bottom - y0) / dy_bot
			y = bottom
		elif (code & 1) != 0:
			var dx_left: float = x1 - x0
			if absf(dx_left) < 0.00001:
				return out
			y = y0 + (y1 - y0) * (left - x0) / dx_left
			x = left
		else:
			var dx_right: float = x1 - x0
			if absf(dx_right) < 0.00001:
				return out
			y = y0 + (y1 - y0) * (right - x0) / dx_right
			x = right
		if code == c0:
			x0 = x
			y0 = y
			c0 = _out_code(x0, y0, left, top, right, bottom)
		else:
			x1 = x
			y1 = y
			c1 = _out_code(x1, y1, left, top, right, bottom)
	return out


func _out_code(x: float, y: float, left: float, top: float, right: float, bottom: float) -> int:
	var code := 0
	if x < left:
		code |= 1
	elif x > right:
		code |= 2
	if y < top:
		code |= 8
	elif y > bottom:
		code |= 4
	return code
