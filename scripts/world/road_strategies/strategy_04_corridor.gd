extends RoadStrategy

## Strategy 4. Corridor heightfield at 0.5 m. The road is the terrain surface.
## make_builder() returns the corridor builder. Strategy 0 does not load this.

const _Builder := preload("res://scripts/world/road_strategies/corridor_heightfield.gd")


func _init() -> void:
	id = 4
	strategy_name = "corridor_heightfield_0_5"
	gap_min = 0.0
	gap_max = 0.050
	summary = "Corridor heightfield at 0.5 m. The road is the terrain surface."


func make_builder():
	return _Builder.new()
