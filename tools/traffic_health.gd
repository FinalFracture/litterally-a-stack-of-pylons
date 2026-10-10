extends SceneTree
## Traffic health report (M2). Runs the game headless for N minutes with the streamed
## window loaded and watches every driving car:
##  - stuck cars (no progress > STUCK_S while not held by a red light / stop / halt),
##  - wrecks (new wrecked cars),
##  - near misses (car-car closer than 2.6 m centre-to-centre while closing > 3 m/s,
##    car-pedestrian closer than 1.5 m at >= 4 m/s), without a crash,
##  - lane departures (a moving car's centre off asphalt),
##  - light and stop compliance (same rules as the M1 fleet log: crossing a red stop line
##    above 2 m/s; rolling a stop it was told to wait at above 1.6 m/s),
##  - streaming upkeep (graph rebuilds, despawns, reroutes).
## Optional --roam moves the player through neighbouring chunks so the window streams.
##
##   godot --headless --path . -s res://tools/traffic_health.gd -- --minutes=3 [--roam] [--out=user://traffic_health.json]
## Exit code 0 = no stuck car over STUCK_S, red-light and stop compliance >= 95 %.

const STUCK_S := 30.0
const SAMPLE_S := 0.1

var minutes := 3.0
var roam := false
var out_path := "user://traffic_health.json"
var main: Node
var city: Node
var traffic: Node
var soul: Node3D
var frames := 0
var t := 0.0
var acc := 0.0
var cars := {}           # instance id -> record
var seen_cars := {}
var wrecked := {}
var near_pairs := {}
var stats := {
	"car_samples": 0, "moving_samples": 0, "off_asphalt_samples": 0, "lane_departures": 0,
	"red_approaches": 0, "red_runs": 0, "stop_approaches": 0, "stop_rolls": 0,
	"near_miss_car": 0, "near_miss_ped": 0, "wrecks": 0, "stuck_events": 0, "max_stuck_s": 0.0,
	"speed_sum": 0.0,
}
var events: Array = []
var roam_pts := [Vector3(250, 2, 250), Vector3(700, 2, 250), Vector3(700, 2, 700), Vector3(250, 2, 700)]
var roam_i := 0


func _initialize() -> void:
	for raw in OS.get_cmdline_user_args():
		var a := String(raw)
		if a.begins_with("--minutes="):
			minutes = float(a.substr(10))
		elif a == "--roam":
			roam = true
		elif a.begins_with("--out="):
			out_path = a.substr(6)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main


func _physics_process(delta: float) -> bool:
	frames += 1
	if frames == 2:
		city = main.get_node("City")
		traffic = main.get_node_or_null("Traffic")
		soul = main.get_node("SoulBody")
	if frames < 3:
		return false
	if t == 0.0 and (city.get("streamer") as Node).busy():
		return false
	t += delta
	if roam:
		_roam(delta)
	acc += delta
	if acc >= SAMPLE_S:
		_sample(acc)
		acc = 0.0
	if t >= minutes * 60.0:
		_finish()
		return true
	return false


func _roam(delta: float) -> void:
	var goal: Vector3 = roam_pts[roam_i]
	var to := goal - soul.global_position
	to.y = 0.0
	if to.length() < 2.0:
		roam_i = (roam_i + 1) % roam_pts.size()
		return
	soul.global_position += to.normalized() * minf(6.0 * delta, to.length())


func _ev(kind: String, detail: Dictionary) -> void:
	if events.size() < 400:
		detail["t"] = snappedf(t, 0.1)
		detail["event"] = kind
		events.append(detail)


func _sample(dt: float) -> void:
	var drivers: Array = []
	for n in get_nodes_in_group("hitter"):
		if n is Node3D and bool(n.get("trip")):
			drivers.append(n)
		if bool(n.get("_wrecked")) and not wrecked.has(n.get_instance_id()):
			wrecked[n.get_instance_id()] = true
			stats["wrecks"] += 1
			_ev("wreck", {"car": str(n.name), "at": _xz(n)})
	for car in drivers:
		var id: int = car.get_instance_id()
		seen_cars[id] = true
		var rec: Dictionary = cars.get(id, {"still": 0.0, "last": (car as Node3D).global_position, "red": false, "ran": false, "stop": false, "rolled": false, "off": false, "stuck_flag": false})
		cars[id] = rec
		var pos: Vector3 = (car as Node3D).global_position
		var vel: Variant = car.get("travel_velocity")
		var spd: float = Vector2((vel as Vector3).x, (vel as Vector3).z).length() if vel is Vector3 else 0.0
		stats["car_samples"] += 1
		stats["speed_sum"] += spd
		var sight: Dictionary = car.get("drive_sight") if car.get("drive_sight") is Dictionary else {}
		var light := str(sight.get("light", "none"))
		var light_m: float = float(sight.get("light_m", 999.0))
		var stop := str(sight.get("stop", "none"))
		var stop_m: float = float(sight.get("stop_m", 999.0))
		var halt := str(sight.get("halt", ""))
		# Lights: an approach is a car within 10 m of a red line; a run is crossing it fast.
		if light == "red" and light_m > 0.0 and light_m < 10.0 and not bool(rec["red"]):
			rec["red"] = true
			stats["red_approaches"] += 1
		if light == "red" and light_m > 0.2 and light_m < 1.6 and spd > 2.0 and not bool(rec["ran"]):
			rec["ran"] = true
			stats["red_runs"] += 1
			_ev("red_run", {"car": str(car.name), "speed": snappedf(spd, 0.1), "at": _xz(car)})
		if light != "red" or light_m > 14.0 or light_m < -1.0:
			rec["red"] = false
			rec["ran"] = false
		if stop == "wait" and stop_m > 0.0 and stop_m < 10.0 and not bool(rec["stop"]):
			rec["stop"] = true
			stats["stop_approaches"] += 1
		if stop == "wait" and halt == "stop" and stop_m < -0.4 and spd > 1.6 and not bool(rec["rolled"]):
			rec["rolled"] = true
			stats["stop_rolls"] += 1
			_ev("stop_roll", {"car": str(car.name), "speed": snappedf(spd, 0.1), "at": _xz(car)})
		if stop != "wait":
			rec["stop"] = false
			rec["rolled"] = false
		# Lane departure.
		if spd > 2.0:
			stats["moving_samples"] += 1
			var on: bool = city.call("on_asphalt", pos.x, pos.z)
			if not on:
				stats["off_asphalt_samples"] += 1
				if not bool(rec["off"]):
					rec["off"] = true
					stats["lane_departures"] += 1
					_ev("lane_departure", {"car": str(car.name), "speed": snappedf(spd, 0.1), "at": _xz(car)})
			else:
				rec["off"] = false
		# Stuck: not moving and not legitimately held.
		var held: bool = (light == "red" and light_m < 20.0) or stop == "wait" or halt != ""
		if spd < 0.3 and not held:
			rec["still"] = float(rec["still"]) + dt
			stats["max_stuck_s"] = maxf(stats["max_stuck_s"], float(rec["still"]))
			if float(rec["still"]) > STUCK_S and not bool(rec["stuck_flag"]):
				rec["stuck_flag"] = true
				stats["stuck_events"] += 1
				_ev("stuck", {"car": str(car.name), "at": _xz(car), "sight": JSON.stringify({"light": light, "stop": stop, "halt": halt})})
		elif spd >= 0.3:
			rec["still"] = 0.0
			rec["stuck_flag"] = false
	_near_misses(drivers)


func _near_misses(drivers: Array) -> void:
	var grid := {}
	for car in drivers:
		var p: Vector3 = (car as Node3D).global_position
		var key := Vector2i(int(floor(p.x / 8.0)), int(floor(p.z / 8.0)))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(car)
	for car in drivers:
		var p: Vector3 = (car as Node3D).global_position
		var v: Vector3 = car.get("travel_velocity") if car.get("travel_velocity") is Vector3 else Vector3.ZERO
		var key := Vector2i(int(floor(p.x / 8.0)), int(floor(p.z / 8.0)))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for other in grid.get(key + Vector2i(dx, dz), []):
					if other.get_instance_id() <= car.get_instance_id():
						continue
					var q: Vector3 = (other as Node3D).global_position
					var d := Vector2(q.x - p.x, q.z - p.z)
					if d.length() > 2.6 or d.length() < 0.01:
						continue
					var w: Vector3 = other.get("travel_velocity") if other.get("travel_velocity") is Vector3 else Vector3.ZERO
					var closing: float = -Vector2(w.x - v.x, w.z - v.z).dot(d.normalized())
					var pair := "%d-%d" % [car.get_instance_id(), other.get_instance_id()]
					if closing > 3.0 and t - float(near_pairs.get(pair, -99.0)) > 3.0:
						near_pairs[pair] = t
						stats["near_miss_car"] += 1
						_ev("near_miss_car", {"cars": [str(car.name), str(other.name)], "closing": snappedf(closing, 0.1), "at": _xz(car)})
		var spd := Vector2(v.x, v.z).length()
		if spd >= 4.0:
			for ped in get_nodes_in_group("pedestrian"):
				var pp: Vector3 = (ped as Node3D).global_position
				if Vector2(pp.x - p.x, pp.z - p.z).length() < 1.5:
					var pair2 := "%d-p%d" % [car.get_instance_id(), ped.get_instance_id()]
					if t - float(near_pairs.get(pair2, -99.0)) > 3.0:
						near_pairs[pair2] = t
						stats["near_miss_ped"] += 1
						_ev("near_miss_ped", {"car": str(car.name), "ped": str(ped.name), "speed": snappedf(spd, 0.1)})


func _xz(n: Node) -> Array:
	var p: Vector3 = (n as Node3D).global_position
	return [snappedf(p.x, 0.1), snappedf(p.z, 0.1)]


func _finish() -> void:
	var red_ok: float = 1.0 if int(stats["red_approaches"]) == 0 else 1.0 - float(stats["red_runs"]) / float(stats["red_approaches"])
	var stop_ok: float = 1.0 if int(stats["stop_approaches"]) == 0 else 1.0 - float(stats["stop_rolls"]) / float(stats["stop_approaches"])
	var off_share: float = 0.0 if int(stats["moving_samples"]) == 0 else float(stats["off_asphalt_samples"]) / float(stats["moving_samples"])
	var mean_spd: float = 0.0 if int(stats["car_samples"]) == 0 else float(stats["speed_sum"]) / float(stats["car_samples"])
	var stream := {}
	if traffic != null:
		for k in ["graph_rebuilds", "stream_despawned", "stream_rerouted", "stream_dead_end_despawns"]:
			stream[k] = traffic.get(k)
	var healthy: bool = int(stats["stuck_events"]) == 0 and red_ok >= 0.95 and stop_ok >= 0.95
	var report := {
		"minutes": minutes, "roam": roam, "cars_seen": seen_cars.size(), "mean_speed_mps": mean_spd,
		"red_light_compliance": red_ok, "stop_compliance": stop_ok, "off_asphalt_share_moving": off_share,
		"stats": stats, "streaming": stream, "healthy": healthy, "events": events,
		"seed": get_root().get_node("LaunchConfig").get("world_seed"),
	}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
	print("TRAFFIC HEALTH %s (%.1f min%s, %d cars seen, mean %.1f m/s)" % ["OK" if healthy else "ATTENTION", minutes, ", roaming" if roam else "", seen_cars.size(), mean_spd])
	print("  stuck cars (> %.0f s unheld): %d   longest unheld standstill: %.1f s" % [STUCK_S, stats["stuck_events"], stats["max_stuck_s"]])
	print("  wrecks: %d" % stats["wrecks"])
	print("  near misses: car-car %d, car-pedestrian %d" % [stats["near_miss_car"], stats["near_miss_ped"]])
	print("  lane departures: %d (off asphalt %.2f %% of moving samples)" % [stats["lane_departures"], off_share * 100.0])
	print("  red lights: %d approaches, %d run -> %.1f %% compliance" % [stats["red_approaches"], stats["red_runs"], red_ok * 100.0])
	print("  stop signs: %d approaches, %d rolled -> %.1f %% compliance" % [stats["stop_approaches"], stats["stop_rolls"], stop_ok * 100.0])
	print("  streaming: %s" % JSON.stringify(stream))
	print("  json: %s" % ProjectSettings.globalize_path(out_path))
	quit(0 if healthy else 1)
