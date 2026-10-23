extends Node

## Test hooks and launch flags (Milestone 1).
## Every flag can come from an environment variable or from a user argument after `--`.
## User arguments win over environment variables.
##
##   PYLONS_SEED=N         --seed=N          world seed (default DEFAULT_WORLD_SEED)
##   PYLONS_SPAWN=x,y,z    --spawn=x,y,z     spawn point (default: a sidewalk in the centre chunk)
##   PYLONS_MAX_FPS=N      --max-fps=N       Engine.max_fps (0 = uncapped)
##   PYLONS_KEYMOUSE=1     --keymouse        keyboard stand-in for mouse look and click verbs
##                         --keymouse is also read when it sits before the `--` separator.
##   PYLONS_LOGS=1         --logs            telemetry prints and traffic log files
##   PYLONS_CHUNK=x,z      --chunk=x,z       start (teleport) in chunk x,z (500 m grid; default 0,0)
##   PYLONS_WORLD_HALF_M=N --world-half-m=N  world edge at +-N metres (default 2000; fall-off beyond)
##   PYLONS_PEDS=N         --peds=N          pedestrians kept near the player (default 16)
##   PYLONS_ROAD_STRATEGY=N --road_strategy=N  bake-off strategy 0..10 (default 0)
##
## At boot the game prints one PYLONS_LAUNCH line that replays the same run.
## With no road strategy flag the line and the roads match the measured builder.

## Fixed default world seed. Chosen once for Milestone 1 (2026-10-08) so every
## plain run builds the same city. Change it only on purpose, and say so in STATUS.md.
const DEFAULT_WORLD_SEED := 20261008

## The world is laid out in 500 m chunks (scripts/world/world_config.gd). The game starts
## in this chunk unless PYLONS_CHUNK / --chunk says otherwise, and streams a 3x3 window.
const CENTRE_CHUNK := Vector2i(0, 0)

## Keyboard stand-ins, registered only when keymouse is on.
const KEYMOUSE_ACTIONS := {
	"km_look_left": KEY_J,
	"km_look_right": KEY_L,
	"km_look_up": KEY_I,
	"km_look_down": KEY_K,
	"km_take": KEY_U,
	"km_drop": KEY_O,
}

var world_seed: int = DEFAULT_WORLD_SEED
var seed_source := "default"
var has_spawn_override := false
var spawn_override := Vector3.ZERO
var max_fps := 0
var keymouse := false
var logs := false
var effective_spawn := Vector3.ZERO
## M2 streaming: chunk to start in (teleport target) and world edge.
var start_chunk := Vector2i(0, 0)
var has_chunk_flag := false
var world_half_m := 2000.0
var peds := 16
## Playtest map (M). On unless --map=0 or PYLONS_MAP=0.
var map_enabled := true
## Bake-off road strategy. 0 is the measured builder. Parsed with --map.
var road_strategy := 0
var road_strategy_source := "default"
var _announced := false
## Chunk the player was actually placed in. The launch line prints this, not the raw flag.
var placed_chunk := Vector2i.ZERO
var has_placed_chunk := false


func _init() -> void:
	# Parsed in _init so scene scripts can read the flags in their own _ready.
	_parse()


func _ready() -> void:
	Engine.max_fps = max_fps
	# Global randf()/randi() (traffic colours, driver moods) also start from the world seed.
	# Physics timing can still reorder calls, so traffic is only roughly repeatable.
	seed(world_seed)
	if keymouse:
		_register_keymouse()


func _parse() -> void:
	var args := _user_args()
	var raw_seed := _pick(args, "seed", "PYLONS_SEED")
	if raw_seed != "":
		if raw_seed.is_valid_int() and int(raw_seed) != 0:
			world_seed = int(raw_seed)
			seed_source = "flag"
		else:
			push_warning("PYLONS_SEED '%s' is not a non-zero integer; using %d." % [raw_seed, DEFAULT_WORLD_SEED])
	var raw_spawn := _pick(args, "spawn", "PYLONS_SPAWN")
	if raw_spawn != "":
		var parts := raw_spawn.split(",")
		if parts.size() == 3 and parts[0].strip_edges().is_valid_float() and parts[1].strip_edges().is_valid_float() and parts[2].strip_edges().is_valid_float():
			spawn_override = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
			has_spawn_override = true
		else:
			push_warning("PYLONS_SPAWN '%s' is not x,y,z; using the sidewalk spawn." % raw_spawn)
	var raw_fps := _pick(args, "max-fps", "PYLONS_MAX_FPS")
	if raw_fps != "":
		if raw_fps.is_valid_int():
			max_fps = maxi(int(raw_fps), 0)
		else:
			push_warning("PYLONS_MAX_FPS '%s' is not an integer; leaving fps uncapped." % raw_fps)
	var raw_chunk := _pick(args, "chunk", "PYLONS_CHUNK")
	if raw_chunk != "":
		var cparts := raw_chunk.split(",")
		if cparts.size() == 2 and cparts[0].strip_edges().is_valid_int() and cparts[1].strip_edges().is_valid_int():
			start_chunk = Vector2i(int(cparts[0]), int(cparts[1]))
			has_chunk_flag = true
		else:
			push_warning("PYLONS_CHUNK '%s' is not x,z; starting in chunk 0,0." % raw_chunk)
	var raw_half := _pick(args, "world-half-m", "PYLONS_WORLD_HALF_M")
	if raw_half != "":
		if raw_half.is_valid_float() and float(raw_half) >= 500.0:
			world_half_m = float(raw_half)
		else:
			push_warning("PYLONS_WORLD_HALF_M '%s' must be a number >= 500; using %.0f." % [raw_half, world_half_m])
	var raw_peds := _pick(args, "peds", "PYLONS_PEDS")
	if raw_peds != "" and raw_peds.is_valid_int():
		peds = maxi(int(raw_peds), 0)
	var raw_map := _pick(args, "map", "PYLONS_MAP")
	if raw_map != "":
		var map_flag := raw_map.to_lower()
		map_enabled = map_flag == "1" or map_flag == "true" or map_flag == "yes" or map_flag == "on"
	road_strategy = RoadStrategyRegistry.current_id()
	road_strategy_source = RoadStrategyRegistry.source()
	keymouse = _flag(args, "keymouse", "PYLONS_KEYMOUSE") or _keymouse_before_separator()
	logs = _flag(args, "logs", "PYLONS_LOGS")


func _keymouse_before_separator() -> bool:
	for raw in OS.get_cmdline_args():
		var arg := String(raw).strip_edges().to_lower()
		if arg == "--keymouse":
			return true
		if arg.begins_with("--keymouse="):
			var value := arg.substr(11)
			return value == "1" or value == "true" or value == "yes" or value == "on"
	return false


func _user_args() -> Dictionary:
	var found := {}
	for raw in OS.get_cmdline_user_args():
		var arg := String(raw)
		if not arg.begins_with("--"):
			continue
		arg = arg.substr(2)
		var eq := arg.find("=")
		if eq < 0:
			found[arg.to_lower()] = "1"
		else:
			found[arg.substr(0, eq).to_lower()] = arg.substr(eq + 1)
	return found


func _pick(args: Dictionary, arg_name: String, env_name: String) -> String:
	if args.has(arg_name):
		return String(args[arg_name]).strip_edges()
	return OS.get_environment(env_name).strip_edges()


func _flag(args: Dictionary, arg_name: String, env_name: String) -> bool:
	var raw := _pick(args, arg_name, env_name).to_lower()
	return raw == "1" or raw == "true" or raw == "yes" or raw == "on"


func _register_keymouse() -> void:
	for action in KEYMOUSE_ACTIONS.keys():
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = KEYMOUSE_ACTIONS[action]
		InputMap.action_add_event(action, key)


## True when the keyboard stand-in for the mouse is active.
func keymouse_on() -> bool:
	return keymouse and InputMap.has_action("km_take")


## Logs a telemetry line only when PYLONS_LOGS=1.
func log_line(line: String) -> void:
	if logs:
		print(line)


## Called once by City after the centre chunk is built and the soul is placed.
func announce(spawn: Vector3) -> void:
	effective_spawn = spawn
	placed_chunk = WorldConfig.chunk_of(spawn.x, spawn.z)
	has_placed_chunk = true
	if _announced:
		return
	_announced = true
	print(launch_line())


func launch_line() -> String:
	var s := effective_spawn
	var spawn_text := "%.3f,%.3f,%.3f" % [s.x, s.y, s.z]
	var flags := PackedStringArray()
	if keymouse:
		flags.append("--keymouse")
	if logs:
		flags.append("--logs")
	var fleet := OS.get_environment("PYLONS_FLEET")
	var env_prefix := ""
	if fleet != "":
		env_prefix = "PYLONS_FLEET=%s " % fleet
	if world_half_m != 2000.0:
		flags.append("--world-half-m=%.0f" % world_half_m)
	if peds != 16:
		flags.append("--peds=%d" % peds)
	if road_strategy != 0:
		flags.append("--road_strategy=%d" % road_strategy)
	var tail := ""
	if not flags.is_empty():
		tail = " " + " ".join(flags)
	var chunk_v := placed_chunk if has_placed_chunk else start_chunk
	var chunk_text := "%d,%d" % [chunk_v.x, chunk_v.y]
	return "PYLONS_LAUNCH seed=%d (%s) chunk=%s (%s) spawn=%s (%s) max_fps=%d keymouse=%s logs=%s | replay: %sgodot --path . -- --seed=%d --chunk=%s --spawn=%s --max-fps=%d%s" % [
		world_seed, seed_source, chunk_text, "flag" if has_chunk_flag else "default", spawn_text,
		"flag" if has_spawn_override else "sidewalk", max_fps,
		"on" if keymouse else "off", "on" if logs else "off",
		env_prefix, world_seed, chunk_text, spawn_text, max_fps, tail,
	]
