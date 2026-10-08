extends Node

var _file: FileAccess
var _time := 0.0
var _last: Dictionary = {}
var _blocked: Dictionary = {}


func _ready() -> void:
	var path := ProjectSettings.globalize_path("res://../logs/traffic_paths.log")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_error("path log failed: %s" % path)
		return
	_file.store_line("t\tcar\tevent\tkind\talt\tx\tz\tblock_x\tblock_z\tpoints")


func _physics_process(delta: float) -> void:
	_time += delta
	if _file == null:
		return
	var soul := get_tree().get_first_node_in_group("soul") as Node3D
	for node in get_tree().get_nodes_in_group("hitter"):
		if not (node is Node3D) or typeof(node.get("drive_sight")) != TYPE_DICTIONARY:
			continue
		var car := node as Node3D
		if soul != null:
			var dx: float = car.global_position.x - soul.global_position.x
			var dz: float = car.global_position.z - soul.global_position.z
			if dx * dx + dz * dz > 8100.0:
				continue
		var sight: Dictionary = car.get("drive_sight")
		if sight.is_empty():
			continue
		var id := car.get_instance_id()
		var kind := str(sight.get("path_kind", "route"))
		var alt := int(sight.get("path_alt", 0))
		var points: PackedVector3Array = sight.get("path", PackedVector3Array())
		var offer := str(sight.get("path_offer", ""))
		var shape := _shape(points)
		var previous: Dictionary = _last.get(id, {})
		var same_choice := str(previous.get("kind", "")) == kind and int(previous.get("alt", -1)) == alt and str(previous.get("offer", "")) == offer
		var same_path := same_choice and shape == str(previous.get("shape", ""))
		if not same_path:
			_write(car, "path", sight, points)
		_last[id] = {"kind": kind, "alt": alt, "offer": offer, "shape": shape}
		var blocked := bool(sight.get("holding", false)) or bool(sight.get("escaping", false))
		var was_blocked := bool(_blocked.get(id, false))
		if blocked and not was_blocked:
			_write(car, "block_found", sight, points)
		elif was_blocked and not blocked:
			_write(car, "block_cleared", sight, points)
		_blocked[id] = blocked
	if int(_time * 2.0) != int((_time - delta) * 2.0):
		_file.flush()


func _write(car: Node3D, event: String, sight: Dictionary, points: PackedVector3Array) -> void:
	var block: Vector3 = sight.get("block_at", Vector3.ZERO)
	_file.store_line("%0.3f\t%s\t%s\t%s\t%d\t%0.2f\t%0.2f\t%0.2f\t%0.2f\t%s" % [
		_time, car.name, event, str(sight.get("path_kind", "route")), int(sight.get("path_alt", 0)),
		car.global_position.x, car.global_position.z, block.x, block.z, _polyline(points),
	])


func _polyline(points: PackedVector3Array) -> String:
	var out := PackedStringArray()
	for point in points:
		out.append("%0.1f,%0.1f" % [point.x, point.z])
	return ";".join(out)


func _shape(points: PackedVector3Array) -> String:
	if points.is_empty():
		return "empty"
	if points.size() == 2:
		var short_delta := points[1] - points[0]
		var short_angle: float = atan2(short_delta.z, short_delta.x)
		return "short:%d" % int(roundf(short_angle / (PI / 12.0)))
	# Compare a few lookahead locations relative to the current path start. The route
	# array is sliced as the car advances, so hashing every vertex logged normal
	# progress through a curve as if it were a fresh steering decision.
	var profile := PackedStringArray()
	var distances: Array[float] = [0.0, 8.0, 20.0, 40.0, 80.0]
	var samples: Array[Vector3] = []
	var walked := 0.0
	var segment := 0
	for target in distances:
		while segment < points.size() - 1 and walked + points[segment].distance_to(points[segment + 1]) < target:
			walked += points[segment].distance_to(points[segment + 1])
			segment += 1
		if segment < points.size() - 1:
			var span: float = points[segment].distance_to(points[segment + 1])
			var t := 0.0 if span < 0.001 else (target - walked) / span
			samples.append(points[segment].lerp(points[segment + 1], clampf(t, 0.0, 1.0)))
		else:
			samples.append(points[points.size() - 1])
	var anchor := points[0]
	for sample in samples:
		profile.append("%d,%d" % [int(roundf((sample.x - anchor.x) / 2.0)), int(roundf((sample.z - anchor.z) / 2.0))])
	var end: Vector3 = points[points.size() - 1]
	# Quantize lane position too; the 0.1 m anchor used to turn every motion
	# sample into a new route row, especially during a pull-off.
	return "%d|%s|%d,%d" % [int(roundf(anchor.z / 2.0)), ";".join(profile), int(roundf(end.x / 20.0)), int(roundf(end.z / 20.0))]


func _exit_tree() -> void:
	if _file != null:
		_file.flush()
		_file.close()
