extends SceneTree

func _init() -> void:
	var root := Node3D.new()
	root.name = "CheckRoot"
	get_root().add_child(root)
	var soul := Node3D.new()
	soul.name = "SoulBody"
	soul.position = Vector3(22.0, 0.05, 22.0)
	soul.add_to_group("soul")
	root.add_child(soul)
	var city := Node3D.new()
	city.name = "City"
	city.set_script(load("res://scripts/city.gd"))
	city.set("road_test_seed", 4242)
	root.add_child(city)
	var traffic := Node3D.new()
	traffic.name = "Traffic"
	traffic.set_script(load("res://scripts/traffic.gd"))
	root.add_child(traffic)
	var code: int = _report(city, traffic)
	quit(code)


func _report(city: Node, traffic: Node) -> int:
	var edge_n := 0
	var edges: Variant = city.get_meta("road_drive_edges", [])
	if edges is Array:
		edge_n = (edges as Array).size()
	var control_n := 0
	var lights := 0
	var stops := 0
	var controls: Variant = city.get_meta("road_controls", [])
	if controls is Array:
		var rows: Array = controls
		control_n = rows.size()
		for item in rows:
			if item is Dictionary and str((item as Dictionary)["mode"]) == "light":
				lights += 1
			else:
				stops += 1
	var cars := 0
	var emergency := 0
	var short := 0
	var off := 0
	var samples := 0
	var worst := ""
	for child in traffic.get_children():
		if child.get("trip") != true:
			continue
		cars += 1
		var kind: String = str(child.get("vehicle_kind"))
		if kind == "police" or kind == "fire" or kind == "ambulance":
			emergency += 1
		if not child.has_method("route_points"):
			short += 1
			continue
		var raw: Variant = child.call("route_points")
		if not (raw is PackedVector3Array):
			short += 1
			continue
		var pts: PackedVector3Array = raw
		var length := 0.0
		var i := 1
		while i < pts.size():
			length += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
			i += 1
		if length < 80.0:
			short += 1
		var step := 0
		while step < pts.size():
			var point: Vector3 = pts[step]
			samples += 1
			if not bool(city.call("on_asphalt", point.x, point.z)):
				off += 1
				if worst == "":
					worst = "(%.1f, %.1f)" % [point.x, point.z]
			step += 3
	var ready: bool = bool(traffic.get("_drive_ready"))
	var share := 1.0
	if samples > 0:
		share = float(off) / float(samples)
	var ok := edge_n > 20 and control_n > 0 and lights > 0 and cars >= 36 and emergency == 0 and short == 0 and samples > 0 and share < 0.04
	print("FLEET edges=%d controls=%d lights=%d stops=%d cars=%d emergency=%d short=%d off=%d/%d share=%.3f worst=%s ready=%s" % [edge_n, control_n, lights, stops, cars, emergency, short, off, samples, share, worst, ready])
	if ok:
		print("FLEET_CHECK_PASS")
		return 0
	print("FLEET_CHECK_FAIL")
	return 1
