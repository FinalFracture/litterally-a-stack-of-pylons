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


static func piece_mass(kind: int) -> float:
	match kind:
		1:
			return MINI_MASS_KG
		2:
			return BARREL_MASS_KG
		_:
			return STANDARD_MASS_KG


# --- Pedestrians and their reactions (M2; PHYSICS_SPEC_v1 §1, tier table F5) -------------
# Every hit goes through pedestrian.take_hit(source, mass, v_rel_vec, point). v_rel is the
# relative speed along the contact normal (m/s); J = mass * v_rel (kg·m/s).
# Body: spec [T] 75 kg (approved 70-80), visual height 1.70 m, CoM about 0.95 m.
const PED_MASS_KG := 75.0
const PED_HEIGHT_M := 1.70
const PED_RADIUS_M := 0.24
const PED_WALK_MPS := 1.3
const PED_PER_CHUNK_MAX := 4
# Ragdoll body: velocity is set directly so the fling doesn't depend on mass; with 75 kg,
# cones bounce off a downed body instead of shoving it.
const PED_RAGDOLL_LINEAR_DAMP := 0.1
const PED_RAGDOLL_ANGULAR_DAMP := 0.8
const PED_RAGDOLL_FRICTION := 0.7
const PED_MAX_RAGDOLLS := 6             # oldest is frozen first
const PED_HIT_EXCEPTION_S := 0.5        # collision exception with the hitter
const PED_NO_REESCALATE_S := 1.0        # after tier >= 3 (no car-sandwich launches)
const PED_SPEED_CAP_MPS := 12.0         # and <= 1.5 x v_in
const PED_SPIN_CAP_RADS := 6.0
# Projectiles (loose cones, barrels). Tier 1 flinch J >= 2.5 and v >= 2; tier 2 stumble
# J >= 6 and v >= 4; tier 3 knockdown J >= 11 and v >= 7. Knockdown by a flung cone is a
# deliberate ~5x Goat-Sim amplification of real momentum transfer (spec §1, M-05).
const PED_PROJ_FLINCH_J := 2.5
const PED_PROJ_FLINCH_V := 2.0
const PED_PROJ_STUMBLE_J := 6.0
const PED_PROJ_STUMBLE_V := 4.0
const PED_PROJ_KNOCK_J := 11.0
const PED_PROJ_KNOCK_V := 7.0
# Optional "trip/head" multiplier on J when the contact is above 1.1 m or below 0.35 m.
const PED_PROJ_TRIP_MULT := 1.25
const PED_PROJ_TRIP_LOW_M := 0.35
const PED_PROJ_TRIP_HIGH_M := 1.1
# The soul (player) never knocks anyone down: flinch from 2.5 m/s, stumble only with a
# stack of >= 5 cones at >= 4 m/s.
const PED_SOUL_FLINCH_V := 2.5
const PED_SOUL_STUMBLE_V := 4.0
const PED_SOUL_STUMBLE_STACK := 5
# Vehicles: < 0.7 none, 0.7-2.5 stumble (walking pace = 1.4), 2.5-6 knockdown, >= 6 fling.
const PED_CAR_STUMBLE_V := 0.7
const PED_CAR_KNOCK_V := 2.5
const PED_CAR_FLING_V := 6.0
# Reactions and recovery.
const PED_FLINCH_S := 0.4
const PED_STUMBLE_S_MIN := 0.6
const PED_STUMBLE_S_MAX := 1.2
const PED_STUMBLE_RECOVER_S := 1.2
const PED_KNOCK_SPEED_MAX := 6.0        # tier 3: v = 0.8 * dir * min(v, 6), up 1.0-1.5
const PED_KNOCK_UP_MIN := 1.0
const PED_KNOCK_UP_MAX := 1.5
const PED_KNOCK_DOWN_S := 2.5
const PED_KNOCK_GETUP_S := 1.0
const PED_FLING_H_MIN := 6.0            # tier 4: horiz clamp(0.9 v, 6, 12)
const PED_FLING_UP_MIN := 1.5           # up clamp(0.25 v, 1.5, 4)
const PED_FLING_UP_MAX := 4.0
const PED_FLING_SPIN_MIN := 2.0         # random axis, 2-6 rad/s
const PED_FLING_DOWN_S_MIN := 3.5
const PED_FLING_DOWN_S_MAX := 4.5
const PED_FLING_GETUP_S := 1.2
const PED_FACE_SOURCE_S := 0.6
