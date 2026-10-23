class_name RoadRules
extends RefCounted

## Shared inputs for every road strategy. Seed, cross-sections, grade caps,
## junction planes, barriers and road ends. From ROAD_SYSTEM_SPEC (2026-10-16)
## and the Rev 2 notes in ROAD_EVOLVE_SPEC. Strategy 0 does not read this file.
## It is the measured builder, wrapped and left alone. Strategies 1 to 10 must
## use these values when they are implemented.

const SEED := 20261008

## Half-widths are lane * lanes / 2. Shoulder and verge are added outside that.
const CROSS_SECTIONS := {
	"local": {"lane_m": 3.3, "lanes": 2, "shoulder_m": 0.0, "curb_m": 0.15, "walk_m": 1.5, "verge_m": 1.0, "crown": 0.02},
	"arterial": {"lane_m": 3.6, "lanes": 2, "shoulder_m": 1.2, "verge_m": 1.0, "crown": 0.02, "return_m": 12.0},
	"highway": {"lane_m": 3.6, "lanes": 4, "median_m": 0.6, "shoulder_m": 2.4, "verge_m": 1.5, "crown": 0.02, "super_max": 0.06},
	"rim": {"lane_m": 3.3, "lanes": 2, "shoulder_m": 1.2, "verge_m": 1.0, "crown": 0.02, "super_max": 0.06},
	"grade": {"lane_m": 3.3, "lanes": 2, "shoulder_m": 1.2, "verge_m": 1.0, "crown": 0.02, "super_max": 0.06},
}

## Fraction rise/run. The bakeoff adds 0.5% before it fails a 10 m sample.
const GRADE_CAP := {
	"us_highway": 0.05,
	"arterial": 0.06,
	"downtown": 0.06,
	"rim_local": 0.08,
	"grade": 0.10,
	"collector": 0.10,
	"service": 0.06,
}

const JUNCTION_DEV_M := 0.03
const JUNCTION_TILT := 0.02
const JUNCTION_TILT_STEEP := 0.03
const JUNCTION_STEEP_GRADE := 0.06
const RETURN_STREET_M := 6.0
const RETURN_ARTERIAL_M := 12.0
const RETURN_TRUCK_M := 15.0
const STOP_BAR_BEFORE_CROSSWALK_M := 1.2

const BARRIER_DROP_M := 3.0
const BARRIER_PROBE_M := 3.0
const GUARDRAIL_H_M := 0.7
const CONCRETE_H_M := 0.8
const BARRIER_SEAT_M := 0.05
const PARAPET_H_M := 0.8

const EDGE_DROP_M := 3.0
const STEP_ALONG_M := 0.02
const STEP_ACROSS_M := 0.03
const GAP_MIN_M := 0.0
const GAP_MAX_M := 0.050
const GAP_MAX_MASKED_M := 0.30
const VERGE_GAP_M := 0.10
const CROSS_SLOPE_MAX := 0.025
const SUPER_TOL := 0.005
const TAPER_MIN_M := 30.0
const MAP_EDGE_RUN_M := 50.0
const CUL_DE_SAC_M := 12.0
const APPROACH_SLAB_M := 19.0
const UNDERPASS_CLEAR_M := 4.9

const ROAD_END_KINDS := ["junction", "bridge", "map_edge", "dead_end"]
