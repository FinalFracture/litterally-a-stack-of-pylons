extends Node

const STANDARD_H := 0.4572
const STANDARD_EXTRA := 0.1524
const MINI_H := 0.3048
const MINI_EXTRA := 0.1016
const BARREL_H := 1.0
const BARREL_EXTRA := 0.38
# No stack height cap (M1 decision): the old 12 ft CAP_M was never enforced and is removed.
const BASE_R := 0.14
# World cone physics (M1, REAL-001/005; M1.1 mass decision).
# Real-life masses for the shipped models: an 18" cone with a black base is 3 lb (1.36 kg),
# a 12" cone about 2 lb (0.9 kg). Barrel stays a gameplay estimate.
const STANDARD_MASS_KG := 1.4
const MINI_MASS_KG := 0.9
const BARREL_MASS_KG := 8.0
# Centre of mass above each piece's own bottom. About half of an 18" cone's 3 lb is the
# rubber base (0.028 m thick), the rest is the PVC shell; that puts the CoM near 0.10 m.
const STANDARD_COM_M := 0.10
const MINI_COM_M := 0.07
const BARREL_COM_M := 0.30
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
