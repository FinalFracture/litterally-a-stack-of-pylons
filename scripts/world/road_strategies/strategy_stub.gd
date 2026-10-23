extends RoadStrategy

## Strategies 1 to 10. They fail loudly and build nothing.
## Strategy 1 (control, terrain-as-road) is one of these. The 41cbe8a lab
## implemented that seam by editing the shared builder, so keeping it behind
## the switch would have put the unvalidated stamp back on the default path.
## The reference remains at commit 41cbe8a (scripts/debug/road_strategy_lab.gd).


func fail_unimplemented() -> void:
	push_error("strategy %d not implemented" % id)


func make_builder():
	fail_unimplemented()
	return null
