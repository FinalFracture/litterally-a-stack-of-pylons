extends SceneTree
## Pedestrian reaction / ragdoll probe (M2, PHYSICS_SPEC_v1 §1 tier table).
## Real physics for projectiles (a cone body flies into the pedestrian's sensor), direct
## take_hit() for the soul and cars (the same entry point hit_cube uses).
##   godot --headless --path . -s res://tools/ragdoll_probe.gd [-- --out=user://ragdoll.json]
## Exit code 0 = every case got its expected tier and the caps held.

# Loaded at run time: scripts that use autoloads can't be preloaded by a -s script.
var _Peds: Script
var _Piece: Script

var world: Node3D
var peds: Node3D
var results: Array = []
var ok := true
var out_path := "user://ragdoll.json"


func _initialize() -> void:
	_Peds = load("res://scripts/pedestrians.gd")
	_Piece = load("res://scripts/cone_piece.gd")
	for raw in OS.get_cmdline_user_args():
		if String(raw).begins_with("--out="):
			out_path = String(raw).substr(6)
	world = Node3D.new()
	get_root().add_child(world)
	var ground := StaticBody3D.new()
	var gs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	gs.shape = box
	gs.position = Vector3(0, -0.5, 0)
	ground.add_child(gs)
	world.add_child(ground)
	peds = Node3D.new()
	peds.set_script(_Peds)
	world.add_child(peds)
	_run.call_deferred()


func _ped(at: Vector3) -> CharacterBody3D:
	var y: float = GameConstants.PED_HEIGHT_M * 0.5
	var p: CharacterBody3D = peds.call("_add", "P%d" % results.size(), PackedVector3Array([Vector3(at.x, y, at.z), Vector3(at.x + 40, y, at.z)]), 0, 0.0, Color.GRAY)
	return p


func _wait(sec: float) -> void:
	await create_timer(sec, true, true).timeout


func _expect(name: String, got: int, want: int, extra: Dictionary = {}) -> void:
	var pass_: bool = got == want
	ok = ok and pass_
	var row := {"case": name, "tier": got, "expected": want, "pass": pass_}
	row.merge(extra)
	results.append(row)
	print("RAGDOLL %-44s tier %d (want %d) %s %s" % [name, got, want, "OK" if pass_ else "FAIL", "" if extra.is_empty() else JSON.stringify(extra)])


func _projectile(name: String, kg: float, speed: float, want: int, h: float = 0.6) -> void:
	var x := results.size() * 12.0
	var ped := _ped(Vector3(x, 0, 0))
	await _wait(0.2)
	var rb := RigidBody3D.new()
	rb.add_to_group("stack_target")
	rb.mass = kg
	rb.gravity_scale = 0.0   # a straight shot at height h; gravity is not what's measured
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.15
	cs.shape = sph
	rb.add_child(cs)
	world.add_child(rb)
	rb.global_position = Vector3(x - 1.5, h, 0)
	rb.linear_velocity = Vector3(speed, 0, 0)
	await _wait(0.6)
	var extra := {"mass_kg": kg, "v": speed, "J": kg * speed}
	var body: RigidBody3D = ped.call("ragdoll_body")
	if body != null:
		extra["ragdoll_mass"] = body.mass
	_expect(name, int(ped.get("last_tier")), want, extra)
	rb.queue_free()


func _direct(name: String, src: Node3D, mass: float, v: Vector3, want: int) -> Dictionary:
	var x := results.size() * 12.0
	var ped := _ped(Vector3(x, 0, 0))
	await _wait(0.1)
	src.global_position = Vector3(x - 0.8, 0.9, 0)
	var tier: int = ped.call("take_hit", src, mass, v, ped.global_position)
	var extra := {"v": v.length()}
	var body: RigidBody3D = ped.call("ragdoll_body")
	if body != null:
		extra["ragdoll_mass"] = body.mass
		extra["launch_speed"] = snappedf(body.linear_velocity.length(), 0.01)
		extra["horiz"] = snappedf(Vector2(body.linear_velocity.x, body.linear_velocity.z).length(), 0.01)
		extra["up"] = snappedf(body.linear_velocity.y, 0.01)
		extra["spin"] = snappedf(body.angular_velocity.length(), 0.01)
		extra["spin_axis"] = str(body.angular_velocity.normalized().snappedf(0.01))
		var cap: float = minf(1.5 * v.length(), GameConstants.PED_SPEED_CAP_MPS)
		var capped: bool = body.linear_velocity.length() <= cap + 0.01 and body.angular_velocity.length() <= GameConstants.PED_SPIN_CAP_RADS + 0.01
		extra["caps_ok"] = capped
		ok = ok and capped
	_expect(name, tier, want, extra)
	return {"ped": ped, "extra": extra}


func _run() -> void:
	await _wait(0.3)
	# Projectiles (real contact through the sensor).
	await _projectile("cone slow slide 1.0 m/s", 1.4, 1.0, 0)
	await _projectile("cone 3 m/s (J 4.2)", 1.4, 3.0, 1)
	await _projectile("cone 5 m/s (J 7.0)", 1.4, 5.0, 2)
	await _projectile("cone flung 9 m/s (J 12.6)", 1.4, 9.0, 3)
	await _projectile("cone car-launched 12 m/s", 1.4, 12.0, 3)
	await _projectile("mini 9 m/s (J 8.1) stumble only", 0.9, 9.0, 2)
	await _projectile("barrel rolling 3 m/s (J 24, v<4)", 8.0, 3.0, 1)
	await _projectile("barrel 5 m/s (J 40, v<7)", 8.0, 5.0, 2)
	# Soul (never knocks down).
	var soul := CharacterBody3D.new()
	soul.add_to_group("soul")
	world.add_child(soul)
	await _direct("soul empty-handed 2.0 m/s", soul, 0.0, Vector3(2.0, 0, 0), 0)
	await _direct("soul empty-handed 4.5 m/s", soul, 0.0, Vector3(4.5, 0, 0), 1)
	for i in 6:
		var piece := Node3D.new()
		piece.set_script(_Piece)
		soul.add_child(piece)
	await _direct("soul with 6-cone stack 4.5 m/s", soul, 0.0, Vector3(4.5, 0, 0), 2)
	await _direct("soul with 6-cone stack 9 m/s (cap tier 2)", soul, 0.0, Vector3(9.0, 0, 0), 2)
	# Vehicles (kinematic: speed decides).
	var car := AnimatableBody3D.new()
	car.add_to_group("hitter")
	world.add_child(car)
	await _direct("car 0.5 m/s (creeping)", car, 1400.0, Vector3(0.5, 0, 0), 0)
	await _direct("car walking pace 1.4 m/s", car, 1400.0, Vector3(1.4, 0, 0), 2)
	await _direct("car 5 m/s (11 mph)", car, 1400.0, Vector3(5.0, 0, 0), 3)
	var a: Dictionary = await _direct("car 11 m/s (25 mph)", car, 1400.0, Vector3(11.0, 0, 0), 4)
	var b: Dictionary = await _direct("car 11 m/s again (spin axis differs)", car, 1400.0, Vector3(11.0, 0, 0), 4)
	var c: Dictionary = await _direct("car 18 m/s (40 mph, capped)", car, 1400.0, Vector3(18.0, 0, 0), 4)
	var axes_differ: bool = str(a["extra"].get("spin_axis")) != str(b["extra"].get("spin_axis"))
	ok = ok and axes_differ
	print("RAGDOLL random spin axis: %s vs %s -> %s" % [a["extra"].get("spin_axis"), b["extra"].get("spin_axis"), "OK" if axes_differ else "FAIL"])
	# No re-escalation within 1 s of a knockdown.
	var p2: Node = c["ped"]
	var again: int = p2.call("take_hit", car, 1400.0, Vector3(18, 0, 0), Vector3.ZERO)
	print("RAGDOLL re-hit while down -> tier %d %s" % [again, "OK" if again == 0 else "FAIL"])
	ok = ok and again == 0
	# Max 6 active ragdolls: knock 3 more (8 down in total), count unfrozen bodies.
	for i in 3:
		await _direct("extra knockdown %d" % i, car, 1400.0, Vector3(7.0, 0, 0), 4)
	var active := 0
	var frozen := 0
	for n in get_nodes_in_group("ped_ragdoll"):
		if (n as RigidBody3D).freeze:
			frozen += 1
		else:
			active += 1
	var cap_ok: bool = active <= GameConstants.PED_MAX_RAGDOLLS
	ok = ok and cap_ok
	print("RAGDOLL active ragdolls %d (max %d), frozen %d -> %s" % [active, GameConstants.PED_MAX_RAGDOLLS, frozen, "OK" if cap_ok else "FAIL"])
	# Get-up: a 5 m/s knockdown is down 2.5 s + 1.0 s get-up + 0.6 s facing the source.
	var g: Dictionary = await _direct("knockdown for get-up timing", car, 1400.0, Vector3(5.0, 0, 0), 3)
	var gp: Node = g["ped"]
	var t0 := Time.get_ticks_msec()
	while int(gp.get("state")) != 0 and Time.get_ticks_msec() - t0 < 10000:
		await _wait(0.1)
	var took: float = (Time.get_ticks_msec() - t0) / 1000.0
	var up_ok: bool = int(gp.get("state")) == 0 and took >= 3.5 and took <= 5.0 and (gp as CharacterBody3D).collision_layer == 1 and gp.call("ragdoll_body") == null
	ok = ok and up_ok
	print("RAGDOLL got up and walking after %.1f s (spec 2.5 + 1.0 + 0.6 = 4.1 s) -> %s" % [took, "OK" if up_ok else "FAIL"])
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"ok": ok, "cases": results, "getup_s": took, "active_ragdolls": active}, "  "))
	print("RAGDOLL %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
