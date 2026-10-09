extends CanvasLayer

const TITLE_SEC := 2.0
const DEFAULT_SPEED_NOTE := 4.5

var _title: Label
var _title_left := TITLE_SEC
var _pause: Control
var _controls: Control
var _hud: Control
var _esc_paused := false
var _console: PanelContainer
var _console_line: LineEdit
var _console_note: Label
var _console_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_title = Label.new()
	_title.name = "BootTitle"
	_title.text = "literally just a stack of pylons"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 36.0
	_title.offset_bottom = 100.0
	_title.add_theme_font_size_override("font_size", 36)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	_pause = (load("res://scenes/ui/pause_menu.tscn") as PackedScene).instantiate()
	_controls = (load("res://scenes/ui/controls.tscn") as PackedScene).instantiate()
	add_child(_pause)
	add_child(_controls)
	add_child((load("res://scenes/ui/silent_box.tscn") as PackedScene).instantiate())
	_pause.hide()
	_controls.hide()
	_hud = Control.new()
	_hud.name = "Hud"
	_hud.set_script(load("res://scripts/hud.gd"))
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	_pause.get_node("Center/Card/Column/ResumeButton").pressed.connect(_resume)
	_pause.get_node("Center/Card/Column/ControlsButton").pressed.connect(_show_controls)
	_controls.get_node("Center/Card/Column/CloseButton").pressed.connect(_hide_controls)
	_build_console()


func _process(delta: float) -> void:
	if _title_left <= 0.0:
		return
	_title_left -= delta
	if _title_left <= 0.0:
		_title.hide()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if _is_tilde(key):
		if _console_open:
			_close_console()
		else:
			_open_console()
		get_viewport().set_input_as_handled()
		return
	if _console_open and (key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE):
		_close_console()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_on_escape()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("controls"):
		if _controls.visible:
			_hide_controls()
		else:
			_show_controls()
		get_viewport().set_input_as_handled()


func _on_escape() -> void:
	if _controls.visible:
		_hide_controls()
		return
	if _esc_paused:
		_esc_paused = false
		_pause.hide()
		_sync_pause()
		return
	_esc_paused = true
	_pause.show()
	_sync_pause()


func _resume() -> void:
	_esc_paused = false
	_pause.hide()
	_controls.hide()
	_sync_pause()


func _show_controls() -> void:
	_controls.show()
	_sync_pause()


func _hide_controls() -> void:
	_controls.hide()
	_sync_pause()


func _sync_pause() -> void:
	var menu_open := _esc_paused or _controls.visible
	var held := menu_open or _console_open
	get_tree().paused = held
	if _hud != null:
		_hud.visible = not menu_open
	if held:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_console() -> void:
	_console = PanelContainer.new()
	_console.name = "DevConsole"
	_console.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_console.offset_left = 16.0
	_console.offset_right = -16.0
	_console.offset_top = -96.0
	_console.offset_bottom = -16.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.09, 0.98)
	style.content_margin_left = 14.0
	style.content_margin_top = 10.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 10.0
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	_console.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_console_note = Label.new()
	_console_note.add_theme_color_override("font_color", Color(0.94, 0.94, 0.92))
	column.add_child(_console_note)
	_console_line = LineEdit.new()
	_console_line.placeholder_text = "speed: 25"
	_console_line.custom_minimum_size = Vector2(0.0, 36.0)
	_console_line.text_submitted.connect(_on_console_submit)
	column.add_child(_console_line)
	_console.add_child(column)
	add_child(_console)
	_console.hide()


func _is_tilde(key: InputEventKey) -> bool:
	return key.physical_keycode == KEY_QUOTELEFT or key.keycode == KEY_QUOTELEFT or key.keycode == KEY_ASCIITILDE


func _open_console() -> void:
	_console_open = true
	_console.show()
	_console_line.text = ""
	_refresh_console_note("Enter a command. Esc or ~ closes this.")
	_sync_pause()
	_console_line.grab_focus()


func _close_console() -> void:
	_console_open = false
	_console.hide()
	_console_line.release_focus()
	_sync_pause()


func _on_console_submit(text: String) -> void:
	var message := _apply_console(text)
	_refresh_console_note(message)
	_console_line.text = ""
	_console_line.grab_focus()
	print(message)


func _refresh_console_note(message: String) -> void:
	var speed: float = DEFAULT_SPEED_NOTE
	var height: float = 0.49
	var soul: Node = get_tree().get_first_node_in_group("soul")
	if soul != null:
		speed = float(soul.get("max_speed"))
		height = float(soul.get("jump_height"))
	var usage := "speed: %.2f m/s    jump: %.2f m" % [speed, height]
	if message == "":
		_console_note.text = usage
	else:
		_console_note.text = "%s\n%s" % [message, usage]


func _apply_console(text: String) -> String:
	var line := text.strip_edges()
	var parts: PackedStringArray = line.split(":", false, 1)
	if parts.size() != 2:
		return "Use speed: 25 or jump: 2"
	var key := parts[0].strip_edges().to_lower()
	var raw := parts[1].strip_edges()
	if not raw.is_valid_float():
		return "Need a number after the colon."
	var value := raw.to_float()
	if value < 0.0:
		return "Use a number that is zero or higher."
	var soul: Node = get_tree().get_first_node_in_group("soul")
	if soul == null:
		return "Player is not in the scene."
	if key == "speed":
		soul.set("max_speed", value)
		return "Speed set to %.2f m/s." % value
	if key == "jump":
		soul.set("jump_height", value)
		return "Jump height set to %.2f m." % value
	return "Unknown command. Use speed or jump."
