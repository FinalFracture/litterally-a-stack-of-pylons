extends Node

var _file: FileAccess
var _time := 0.0
var _frame := 0
var _last_event: Dictionary = {}


func _ready() -> void:
	var path := ProjectSettings.globalize_path("res://../logs/traffic_passes.log")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_error("pass log failed: %s" % path)
		return
	_file.store_line("t\tframe\tevent\taccepted\treason\tcar\tcar_x\tcar_y\tcar_z\ttarget\ttarget_x\ttarget_y\ttarget_z\tgap_m\ttarget_speed\tturn_m\toncoming_clear\tfollow_s\tintel\taggression\tpath_kind\tpath")


func _physics_process(delta: float) -> void:
	_time += delta
	_frame += 1
	if _file == null:
		return
	for node in get_tree().get_nodes_in_group("hitter"):
		if not (node is Node3D) or typeof(node.get("drive_sight")) != TYPE_DICTIONARY:
			continue
		var car := node as Node3D
		var sight: Dictionary = car.get("drive_sight")
		var raw: Variant = sight.get("pass_event", {})
		if not (raw is Dictionary):
			continue
		var event: Dictionary = raw
		var id := int(event.get("id", 0))
		if id <= 0 or int(_last_event.get(car.get_instance_id(), 0)) == id:
			continue
		_last_event[car.get_instance_id()] = id
		_write(car, sight, event)
		_file.flush()


func _write(car: Node3D, sight: Dictionary, event: Dictionary) -> void:
	var car_at: Vector3 = event.get("car_position", car.global_position)
	var target_at: Vector3 = event.get("target_position", Vector3.ZERO)
	var path: PackedVector3Array = sight.get("path", PackedVector3Array())
	_file.store_line("%0.3f\t%d\t%s\t%s\t%s\t%s\t%0.2f\t%0.2f\t%0.2f\t%s\t%0.2f\t%0.2f\t%0.2f\t%0.2f\t%0.2f\t%0.2f\t%s\t%0.2f\t%0.3f\t%0.3f\t%s\t%s" % [
		_time,
		_frame,
		str(event.get("event", "")),
		"1" if bool(event.get("accepted", false)) else "0",
		str(event.get("reason", "")),
		str(event.get("car", car.name)),
		car_at.x, car_at.y, car_at.z,
		str(event.get("target", "none")),
		target_at.x, target_at.y, target_at.z,
		float(event.get("gap", -1.0)),
		float(event.get("target_speed", -1.0)),
		float(event.get("turn_distance", -1.0)),
		"1" if bool(event.get("oncoming_clear", false)) else "0",
		float(event.get("follow_time", 0.0)),
		float(event.get("intel", 0.0)),
		float(event.get("aggression", 0.0)),
		str(sight.get("path_kind", "")),
		_polyline(path),
	])


func _polyline(points: PackedVector3Array) -> String:
	var out := PackedStringArray()
	for point in points:
		out.append("%0.1f,%0.1f" % [point.x, point.z])
	return ";".join(out)


func _exit_tree() -> void:
	if _file == null:
		return
	_file.flush()
	_file.close()
	_file = null
