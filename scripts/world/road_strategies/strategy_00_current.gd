extends RoadStrategy

## Strategy 0. The measured builder. make_builder() returns a new TfRoadBuilder
## and does not wrap its methods, so prepare / apply_cuts / build_chunk stay
## the 1ed88ba path. Gap limit is the default 0.050 m.

const _Builder := preload("res://scripts/world/tf_road_builder.gd")


func _init() -> void:
	id = 0
	strategy_name = "current_builder"
	gap_min = 0.0
	gap_max = 0.050
	summary = "Measured builder. Behaviour is the 1ed88ba road pipeline."


func make_builder():
	return _Builder.new()
