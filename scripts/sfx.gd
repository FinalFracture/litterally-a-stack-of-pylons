extends Node

## One-shot positional sound effects (M1). Replaces the old print("click") stubs.
## To swap a sound, drop a new file in and change its path below (wav or ogg both work).
## The placeholder_*.wav files are synthesized stand-ins until the Asset Manager delivers CC0 audio.

const SOUNDS := {
	"click": "res://Sounds_Music/sfx/placeholder_click.wav",          # a cone or stack added to the stack
	"dull_click": "res://Sounds_Music/sfx/placeholder_dull_click.wav", # a verb with nothing to act on
	"knock": "res://Sounds_Music/sfx/placeholder_knock.wav",          # refused pickup, car hits a cone / the player
	"thunk": "res://Sounds_Music/sfx/placeholder_thunk.wav",          # a cone dropped or landing hard
}
const MAX_VOICES := 16
const UNIT_SIZE := 6.0
const MAX_DISTANCE := 60.0

var _streams: Dictionary = {}
var _voices: Array = []


func _ready() -> void:
	for key in SOUNDS.keys():
		var path: String = SOUNDS[key]
		if ResourceLoader.exists(path):
			_streams[key] = load(path)
		else:
			push_warning("Sfx: missing sound '%s' at %s" % [key, path])


## Plays a named sound at a world position. Unknown or missing sounds are skipped silently.
func play_at(sound: String, at: Vector3, volume_db: float = 0.0) -> AudioStreamPlayer3D:
	var stream: AudioStream = _streams.get(sound)
	var scene: Node = get_tree().current_scene
	if scene == null:
		scene = get_tree().root
	if stream == null:
		return null
	var alive: Array = []
	for voice in _voices:
		if is_instance_valid(voice):
			alive.append(voice)
	_voices = alive
	if _voices.size() >= MAX_VOICES:
		var oldest: AudioStreamPlayer3D = _voices.pop_front()
		oldest.queue_free()
	var player := AudioStreamPlayer3D.new()
	player.name = "Sfx_%s" % sound
	player.stream = stream
	player.unit_size = UNIT_SIZE
	player.max_distance = MAX_DISTANCE
	player.volume_db = volume_db
	player.pitch_scale = randf_range(0.95, 1.05)
	scene.add_child(player)
	player.global_position = at
	player.finished.connect(player.queue_free)
	player.play()
	_voices.append(player)
	return player


func has_sound(sound: String) -> bool:
	return _streams.has(sound)
