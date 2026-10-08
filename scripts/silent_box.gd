extends Control

const SHOW_SEC := 4.0

var _flags := {
	"bent": false,
	"tire_stamp": false,
	"dirt": false,
	"tape": false,
	"glasses_mesh": false,
}
var _left := 0.0


func _ready() -> void:
	add_to_group("silent_box")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()
	_apply()


func show_trigger(trigger: String) -> void:
	var marks: Array = []
	match trigger:
		"hit":
			marks = ["bent", "tire_stamp"]
		"stack":
			marks = ["tape"]
		"swap":
			marks = ["glasses_mesh"]
		"respawn":
			marks = ["dirt"]
		_:
			return
	for mark in marks:
		_flags[mark] = true
	_apply()
	_left = SHOW_SEC
	show()


func _process(delta: float) -> void:
	if not visible:
		return
	_left -= delta
	if _left <= 0.0:
		hide()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("dialogue_advance"):
		hide()
		get_viewport().set_input_as_handled()


func _apply() -> void:
	var cone := $Panel/Portrait/Cone as Polygon2D
	cone.rotation_degrees = -10.0 if _flags["bent"] else 0.0
	($Panel/Portrait/TireStamp as CanvasItem).visible = _flags["tire_stamp"]
	($Panel/Portrait/Dirt as CanvasItem).visible = _flags["dirt"]
	($Panel/Portrait/Tape as CanvasItem).visible = _flags["tape"]
	($Panel/Portrait/GlassesMesh as CanvasItem).visible = _flags["glasses_mesh"]
