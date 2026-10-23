extends RoadStrategy

## Strategy 6. Constrained TIN: one surface for the carriageway, the shoulder
## and the junction disk. Breaklines are the centreline, the lane edges, the
## verge and the apron. Junction interiors are a constrained fan on the
## best-fit plane. Slope, ditch and daylight breaklines are the earth TIN.

const _Builder := preload("res://scripts/world/road_strategies/tin_builder.gd")


func _init() -> void:
	id = 6
	strategy_name = "constrained_tin"
	gap_min = 0.0
	gap_max = 0.050
	summary = "One mesh for ground and road. Vertices on edges, ditch and daylight."


func make_builder():
	return _Builder.new()
