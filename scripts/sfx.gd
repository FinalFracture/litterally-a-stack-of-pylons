extends Node

## One-shot positional sound effects (M1, real CC0 audio since M1.1).
## Each slot lists one or more files; several files are played through an AudioStreamRandomizer.
## To swap a sound, drop a new file into Sounds_Music/sfx/ and change its path below (wav or ogg).
## Licences and sources: Sounds_Music/sfx/CREDITS.md.

const SFX_DIR := "res://Sounds_Music/sfx/"
# volume_db, unit_size and max_distance follow the Asset Manager's MANIFEST.md (m1-sounds).
const SOUNDS := {
	"click": { # a cone or stack added to the stack
		"files": ["sfx_cone_attach_click_01.ogg", "sfx_cone_attach_click_02.ogg", "sfx_cone_attach_click_03.ogg"],
		"volume_db": -6.0, "unit_size": 6.0, "max_distance": 25.0,
	},
	"dull_click": { # a verb with nothing to act on
		"files": ["sfx_dull_click_01.ogg", "sfx_dull_click_02.ogg"],
		"volume_db": -10.0, "unit_size": 6.0, "max_distance": 25.0,
	},
	"knock": { # refused pickup, car hits a cone / the player
		"files": ["sfx_knock_01.ogg", "sfx_knock_02.ogg", "sfx_knock_03.ogg"],
		"volume_db": -4.0, "unit_size": 6.0, "max_distance": 25.0,
	},
	"thunk": { # a cone dropped or landing hard. Still the M1 placeholder: the CC0 set has no "thunk" slot.
		"files": ["placeholder_thunk.wav"],
		"volume_db": 0.0, "unit_size": 6.0, "max_distance": 60.0,
	},
}
const MAX_VOICES := 16
# Variation for slots with several files (manifest: random_pitch ~1.08, random_volume_offset_db ~2).
const RANDOM_PITCH := 1.08
const RANDOM_VOLUME_DB := 2.0

var _streams: Dictionary = {}
var _voices: Array = []


func _ready() -> void:
	for key in SOUNDS.keys():
		var stream := _build(key, SOUNDS[key]["files"])
		if stream != null:
			_streams[key] = stream


func _build(key: String, files: Array) -> AudioStream:
	var loaded: Array[AudioStream] = []
	for file in files:
		var path: String = SFX_DIR + str(file)
		if ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			if stream != null:
				loaded.append(stream)
				continue
		push_warning("Sfx: missing sound '%s' at %s" % [key, path])
	if loaded.is_empty():
		return null
	if loaded.size() == 1:
		return loaded[0]
	var randomizer := AudioStreamRandomizer.new()
	randomizer.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	randomizer.random_pitch = RANDOM_PITCH
	randomizer.random_volume_offset_db = RANDOM_VOLUME_DB
	for stream in loaded:
		randomizer.add_stream(-1, stream)
	return randomizer


## Plays a named sound at a world position. Unknown or missing sounds are skipped silently.
## volume_db is added to the slot's own level.
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
	var slot: Dictionary = SOUNDS[sound]
	var player := AudioStreamPlayer3D.new()
	player.name = "Sfx_%s" % sound
	player.stream = stream
	player.unit_size = float(slot["unit_size"])
	player.max_distance = float(slot["max_distance"])
	player.volume_db = float(slot["volume_db"]) + volume_db
	if not (stream is AudioStreamRandomizer):
		player.pitch_scale = randf_range(0.95, 1.05)
	scene.add_child(player)
	player.global_position = at
	player.finished.connect(player.queue_free)
	player.play()
	_voices.append(player)
	return player


func has_sound(sound: String) -> bool:
	return _streams.has(sound)


## The resolved file paths for a slot (used by probes and the README).
func paths_for(sound: String) -> PackedStringArray:
	var out := PackedStringArray()
	if SOUNDS.has(sound):
		for file in SOUNDS[sound]["files"]:
			out.append(SFX_DIR + str(file))
	return out
