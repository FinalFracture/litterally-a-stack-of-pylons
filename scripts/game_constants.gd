extends Node

const STANDARD_H := 0.4572
const STANDARD_EXTRA := 0.1524
const MINI_H := 0.3048
const MINI_EXTRA := 0.1016
const BARREL_H := 1.0
const BARREL_EXTRA := 0.38
const CAP_M := 3.6576
const BASE_R := 0.14
# cos(radians(28))
const UPRIGHT_DOT := 0.882947592858927
const SWAP_RANGE := 2.4
# Practice-road asphalt: one 3.5 m lane in each direction.
# LANE_OFF is each direction's lane center from the road centerline.
const ROAD_HALF := 3.5
const LANE_OFF := 1.75
const LANE_PASS := 0.0
# Closed loop for the traffic playtest. Road centerlines, meters.
# PackedFloat32Array is not a constant expression, so these stay static vars.
static var LOOP_X: PackedFloat32Array = PackedFloat32Array([40.0, 150.0, 260.0, 370.0])
static var LOOP_Z: PackedFloat32Array = PackedFloat32Array([40.0, 150.0, 260.0])
