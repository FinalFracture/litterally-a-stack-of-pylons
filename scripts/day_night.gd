extends DirectionalLight3D

const DAY_SEC := 16.0 * 60.0
const NIGHT_SEC := 8.0 * 60.0
const CYCLE := DAY_SEC + NIGHT_SEC
# Clock stays at solar noon. Set false to resume the day-night cycle.
const HOLD_AT_NOON := true

var _time := DAY_SEC * 0.5
var _env: Environment
var _lamps_ready := false
var _lamps_on := false
var _day_fog := Color(0.78, 0.87, 0.96)
var _night_fog := Color(0.05, 0.06, 0.09)
var _day_sky := Color(0.4, 0.66, 0.95)
var _night_sky := Color(0.02, 0.025, 0.04)


func _ready() -> void:
	shadow_enabled = true
	# Two hard-ish cascades. Four soft splits were most of the fill cost on the integrated GPU.
	directional_shadow_mode = SHADOW_PARALLEL_2_SPLITS
	directional_shadow_max_distance = 55.0
	directional_shadow_blend_splits = false
	shadow_blur = 0.4
	var world := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world != null:
		_env = world.environment
	_apply_time()


func _process(delta: float) -> void:
	if not HOLD_AT_NOON:
		_time = fmod(_time + delta, CYCLE)
	_apply_time()
	_cull_lamps()


func _apply_time() -> void:
	var day := _time < DAY_SEC
	var along: float = _time / DAY_SEC
	# +X east, -X west, +Z north, -Z south. Dawn sits in the east, noon in the south, dusk in the west.
	var yaw: float = PI * 0.5 + along * PI
	var elev: float = sin(along * PI) * 1.15 + 0.12
	if not day:
		along = (_time - DAY_SEC) / NIGHT_SEC
		yaw = PI * 1.5 + along * PI
		elev = sin(along * PI) * 0.28 + 0.05
	rotation = Vector3(-elev, yaw, 0.0)
	if day:
		light_color = Color(1.0, 0.985, 0.95)
		light_energy = 0.65 + sin(along * PI) * 0.75
		_tint(_day_fog, Color(0.66, 0.76, 0.9), 0.5, _day_sky, 0.00055)
	else:
		light_color = Color(0.75, 0.82, 0.95)
		light_energy = 0.04
		_tint(_night_fog, Color(0.12, 0.14, 0.18), 0.05, _night_sky, 0.0016)


func _cull_lamps() -> void:
	var night: bool = _time >= DAY_SEC
	if not _lamps_ready or night != _lamps_on:
		_lamps_ready = true
		_lamps_on = night
		_street_glow(night)
	var soul := get_tree().get_first_node_in_group("soul") as Node3D
	var soul_at := Vector2.ZERO
	var have_soul := soul != null
	if have_soul:
		soul_at = Vector2(soul.global_position.x, soul.global_position.z)
	var reach := 55.0
	for node in get_tree().get_nodes_in_group("night_lamp"):
		if not (node is Node3D):
			continue
		var host := node as Node3D
		var near := true
		if have_soul:
			var flat := Vector2(host.global_position.x, host.global_position.z)
			near = flat.distance_to(soul_at) <= reach
		var energy: float = 0.0
		if night and near:
			energy = 1.35
		for child in host.get_children():
			if child is OmniLight3D:
				(child as OmniLight3D).light_energy = energy
	for node2 in get_tree().get_nodes_in_group("signal_lamp"):
		if not (node2 is OmniLight3D):
			continue
		var lamp := node2 as OmniLight3D
		var near2 := true
		if have_soul:
			var flat2 := Vector2(lamp.global_position.x, lamp.global_position.z)
			near2 = flat2.distance_to(soul_at) <= reach
		lamp.light_energy = 1.15 if near2 else 0.0


func _street_glow(on: bool) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var city: Node = parent.get_node_or_null("City")
	if city == null or not city.has_meta("street_bulb_mat"):
		return
	var mat: Variant = city.get_meta("street_bulb_mat")
	if mat is StandardMaterial3D:
		(mat as StandardMaterial3D).emission_energy_multiplier = 2.4 if on else 0.0


func sun_up() -> bool:
	return _time < DAY_SEC


func body_along() -> float:
	if _time < DAY_SEC:
		return _time / DAY_SEC
	return (_time - DAY_SEC) / NIGHT_SEC


func sun_flat() -> Vector2:
	var toward: Vector3 = global_transform.basis.z
	var flat := Vector2(toward.x, toward.z)
	if flat.length_squared() < 0.0004:
		return Vector2.RIGHT
	return flat.normalized()


func _tint(fog: Color, ambient: Color, energy: float, sky: Color, density: float) -> void:
	if _env == null:
		return
	_env.fog_light_color = fog
	_env.fog_density = density
	_env.ambient_light_color = ambient
	_env.ambient_light_energy = energy
	_env.background_color = sky
