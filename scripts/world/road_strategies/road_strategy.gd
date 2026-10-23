class_name RoadStrategy
extends RefCounted

## One contract for every bake-off strategy.
##
## Inputs, the same for all of them:
##   roads.json (centrelines, class, lanes, segment ids)
##   terrain / lidar tiles, or the RoadLab height field when the site is synthetic
##   RoadRules (Rev 2 cross-sections, grade caps, junction, barrier, road-end)
##   seed RoadRules.SEED (20261008)
##
## Outputs:
##   a drivable road plus the ground under it and beside it, with collision
##   the harness can ray and cone. The strategy's own arrays are not the score.

var id := 0
var strategy_name := "unnamed"
var gap_min := 0.0
var gap_max := 0.050
var summary := ""


func fail_unimplemented() -> void:
	push_error("strategy %d not implemented" % id)


## Strategy 0 returns the live TfRoadBuilder. Stubs return null after the error.
func make_builder():
	fail_unimplemented()
	return null
