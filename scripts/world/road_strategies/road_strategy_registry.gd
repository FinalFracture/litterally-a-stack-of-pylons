class_name RoadStrategyRegistry
extends RefCounted

## Ids 0 to 10. 0 is the measured builder. 1 to 10 are the Rev 2 list.
## Gap max is 0.050 m except strategies 2 and 3 (masked terrain), which are 0.30 m.
## Selection: --road_strategy=N or PYLONS_ROAD_STRATEGY=N. Default 0.
## User arguments win over the environment variable.

const _Current := preload("res://scripts/world/road_strategies/strategy_00_current.gd")
const _Corridor := preload("res://scripts/world/road_strategies/strategy_04_corridor.gd")
const _Stub := preload("res://scripts/world/road_strategies/strategy_stub.gd")

const SPECS: Array[Dictionary] = [
	{"id": 0, "name": "current_builder", "gap_max": 0.050, "summary": "Measured builder. Behaviour unchanged."},
	{"id": 1, "name": "control_terrain_as_road", "gap_max": 0.050, "summary": "Control. Terrain is the road: 2 m bench, 4 m blend, no junction disc."},
	{"id": 2, "name": "ribbon_masked_terrain", "gap_max": 0.300, "summary": "Rev 2 ribbon. Own collision, terrain masked 0.10 m below, verge strip."},
	{"id": 3, "name": "joint_junction_mesh", "gap_max": 0.300, "summary": "As strategy 2, with junctions and ends solved as one mesh per chunk."},
	{"id": 4, "name": "corridor_heightfield_0_5", "gap_max": 0.050, "summary": "Corridor heightfield at 0.5 m. The road is the terrain surface."},
	{"id": 5, "name": "corridor_heightfield_1_0", "gap_max": 0.050, "summary": "Corridor heightfield at 1.0 m."},
	{"id": 6, "name": "constrained_tin", "gap_max": 0.050, "summary": "One mesh for ground and road. Vertices on edges, ditch and daylight."},
	{"id": 7, "name": "road_height_raster", "gap_max": 0.050, "summary": "0.25 m road-height raster and mask. Terrain has a hole."},
	{"id": 8, "name": "extruded_solid", "gap_max": 0.050, "summary": "Extruded solid with cut and fill slopes. Terrain has a hole."},
	{"id": 9, "name": "sdf_carve", "gap_max": 0.050, "summary": "0.5 m SDF carve, remesh, bake collision."},
	{"id": 10, "name": "global_constrained_solve", "gap_max": 0.050, "summary": "Offline smooth solve, road cells pinned, output at 1.0 m."},
]

static var _cached := false
static var _id := 0
static var _source := "default"


static func current_id() -> int:
	if not _cached:
		_read()
	return _id


static func source() -> String:
	if not _cached:
		_read()
	return _source


static func spec_for(strategy_id: int) -> Dictionary:
	if strategy_id >= 0 and strategy_id < SPECS.size():
		return SPECS[strategy_id]
	return {"id": strategy_id, "name": "invalid", "gap_max": 0.050, "summary": "outside 0..10"}


static func create() -> RoadStrategy:
	var strategy_id := current_id()
	var spec := spec_for(strategy_id)
	var strategy: RoadStrategy
	if strategy_id == 0:
		strategy = _Current.new()
	elif strategy_id == 4:
		strategy = _Corridor.new()
	else:
		strategy = _Stub.new()
		strategy.id = strategy_id
		strategy.strategy_name = str(spec.get("name", "invalid"))
		strategy.gap_max = float(spec.get("gap_max", 0.050))
		strategy.summary = str(spec.get("summary", ""))
	return strategy


static func _read() -> void:
	_cached = true
	_id = 0
	_source = "default"
	var raw := _pick()
	if raw == "":
		return
	_source = "flag"
	if not raw.is_valid_int():
		push_error("strategy %s not implemented" % raw)
		_id = -1
		return
	var parsed := int(raw)
	if parsed < 0 or parsed > 10:
		push_error("strategy %d not implemented" % parsed)
		_id = parsed
		return
	_id = parsed


static func _pick() -> String:
	var args := _user_args()
	if args.has("road_strategy"):
		return String(args["road_strategy"]).strip_edges()
	return OS.get_environment("PYLONS_ROAD_STRATEGY").strip_edges()


static func _user_args() -> Dictionary:
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
