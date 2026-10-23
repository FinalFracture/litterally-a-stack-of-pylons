extends RoadStrategy

## Strategy 2. Rev 2 ribbon: the road mesh is its own collision, terrain under the
## footprint is masked 0.10 m below that surface, and a verge strip runs out to
## the stamped ground. Edge policy, junction plane, taper and cross-section come
## from the shared profile (RoadRules / the measured builder's grade and plane
## pass). Crests where two ribbons overlap stay overlapped; that is this method.

const _Builder := preload("res://scripts/world/road_strategies/ribbon_builder.gd")


func _init() -> void:
	id = 2
	strategy_name = "ribbon_masked_terrain"
	gap_min = 0.0
	gap_max = 0.300
	summary = "Rev 2 ribbon. Own collision, terrain masked 0.10 m below, verge strip."


func make_builder():
	return _Builder.new()
