extends Node

## Rim wind, sparse birds, and the Snake River.
## River loudness is distance to the water.json centreline, not height.
## Wind only falls 8 dB from the rim to the floor, so a descent does not go quiet:
## on the spawn rim-to-floor line the combined level stays inside about 4 dB.

const WIND_RIM_DB := -10.0
const WIND_FLOOR_DB := -18.0
const RIVER_NEAR_DB := -8.0
const RIVER_FAR_DB := -26.0
const WIND_FLOOR_Y := 0.0
const WIND_RIM_Y := 140.0
const RIVER_NEAR_M := 40.0
const RIVER_FAR_M := 320.0
## Birds still follow height. They stop once the old canyon blend passes 0.42 (about y 68).
const BIRD_FLOOR_Y := 6.0
const BIRD_RIM_Y := 118.0

var _wind: AudioStreamPlayer
var _river: AudioStreamPlayer
var _bird: AudioStreamPlayer3D
var _birds: Array[AudioStream] = []
var _wait := 3.5
var _rng := RandomNumberGenerator.new()
var _gen: TwinFallsTerrainGenerator


func _ready() -> void:
	_rng.seed = 20261010
	_wind = AudioStreamPlayer.new()
	_wind.name = "Wind"
	_wind.stream = load("res://Sounds_Music/ambience/amb_wind_light_loop.ogg")
	_wind.volume_db = WIND_RIM_DB
	add_child(_wind)
	_wind.play(_rng.randf() * 20.0)
	_river = AudioStreamPlayer.new()
	_river.name = "River"
	_river.stream = load("res://Sounds_Music/ambience/amb_river_flow_loop.ogg")
	_river.volume_db = RIVER_FAR_DB
	add_child(_river)
	_river.play(_rng.randf() * 20.0)
	_bird = AudioStreamPlayer3D.new()
	_bird.name = "Bird"
	_bird.unit_size = 14.0
	_bird.max_distance = 90.0
	_bird.volume_db = -10.0
	add_child(_bird)
	for path in [
		"res://Sounds_Music/ambience/bird_robin_call_01.ogg",
		"res://Sounds_Music/ambience/bird_robin_call_02.ogg",
		"res://Sounds_Music/ambience/bird_cardinal_song_01.ogg",
		"res://Sounds_Music/ambience/bird_house_sparrow_chirps_01.ogg",
		"res://Sounds_Music/ambience/bird_mourning_dove_coo_01.ogg",
	]:
		var stream := load(path) as AudioStream
		if stream != null:
			_birds.append(stream)


func _process(delta: float) -> void:
	var soul := get_tree().get_first_node_in_group("soul") as Node3D
	if soul == null:
		return
	var y := soul.global_position.y
	var mix := mix_db(y, _river_distance(soul.global_position))
	_wind.volume_db = mix.x
	_river.volume_db = mix.y
	var height_canyon := 1.0 - smoothstep(BIRD_FLOOR_Y, BIRD_RIM_Y, y)
	if height_canyon > 0.42 or _birds.is_empty():
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = _rng.randf_range(7.0, 15.0)
	_bird.stream = _birds[_rng.randi() % _birds.size()]
	var ang := _rng.randf() * TAU
	var dist := _rng.randf_range(16.0, 38.0)
	_bird.global_position = soul.global_position + Vector3(cos(ang) * dist, 2.0, sin(ang) * dist)
	_bird.pitch_scale = _rng.randf_range(0.94, 1.06)
	_bird.play()


## Wind from height, river from metres to the centreline. x = wind dB, y = river dB.
func mix_db(y: float, river_m: float) -> Vector2:
	var wind_t := smoothstep(WIND_FLOOR_Y, WIND_RIM_Y, y)
	var river_t := smoothstep(RIVER_NEAR_M, RIVER_FAR_M, river_m)
	return Vector2(lerpf(WIND_FLOOR_DB, WIND_RIM_DB, wind_t), lerpf(RIVER_NEAR_DB, RIVER_FAR_DB, river_t))


func _river_distance(at: Vector3) -> float:
	if _gen == null:
		var world := get_parent()
		if world != null:
			var g: Variant = world.get("generator")
			if g is TwinFallsTerrainGenerator:
				_gen = g
	if _gen == null or _gen.water_pts.is_empty():
		return 9999.0
	return _gen.water_nearest(at.x, at.z).x
