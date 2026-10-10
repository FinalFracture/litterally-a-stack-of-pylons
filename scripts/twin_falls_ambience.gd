extends Node

## Rim wind and sparse birds, river bed rising as the player drops into the canyon.
## Blend is by height: the south rim is near y 140 and the Snake River near y -6.

const WIND_DB := -10.0
const RIVER_DB := -8.0
const QUIET_DB := -46.0
const RIM_Y := 118.0
const FLOOR_Y := 6.0

var _wind: AudioStreamPlayer
var _river: AudioStreamPlayer
var _bird: AudioStreamPlayer3D
var _birds: Array[AudioStream] = []
var _wait := 3.5
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 20261010
	_wind = AudioStreamPlayer.new()
	_wind.name = "Wind"
	_wind.stream = load("res://Sounds_Music/ambience/amb_wind_light_loop.ogg")
	_wind.volume_db = WIND_DB
	add_child(_wind)
	_wind.play(_rng.randf() * 20.0)
	_river = AudioStreamPlayer.new()
	_river.name = "River"
	_river.stream = load("res://Sounds_Music/ambience/amb_river_flow_loop.ogg")
	_river.volume_db = QUIET_DB
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
	var canyon := 1.0 - smoothstep(FLOOR_Y, RIM_Y, y)
	_wind.volume_db = lerpf(WIND_DB, QUIET_DB, canyon)
	_river.volume_db = lerpf(QUIET_DB, RIVER_DB, canyon)
	if canyon > 0.42 or _birds.is_empty():
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
