extends RoadStrategy

## Strategy 3. Joint junction mesh. make_builder() returns the shared-edge builder.
## Strategy 0 is a different script and is not wrapped.

const _Builder := preload("res://scripts/world/road_strategies/strategy_03_builder.gd")


func _init() -> void:
	id = 3
	strategy_name = "joint_junction_mesh"
	gap_min = 0.0
	gap_max = 0.300
	summary = "As strategy 2, with junctions and ends solved as one mesh per chunk."


func make_builder():
	var builder = _Builder.new()
	builder.strategy_id = id
	return builder
