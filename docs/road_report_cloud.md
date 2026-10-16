# Road report, cloud pass

Before is the RS-3 network at `04c6d3c` (`docs/road_rs3_diag.md`). After is a full `tools/road_report.gd` run on this stamp, 563,955 samples, 535 s. Network still **FAIL**. 22 roads, 0 pass, 22 fail. Hit rate 96.56% (before 96.54%). Components 1.

| Metric | Before (`04c6d3c`) | After | Limit |
|---|---:|---:|---:|
| Max along step | 0.500 m | 0.096 m | 0.020 m |
| Max across step | 1.867 m | 0.148 m | 0.030 m |
| Gap min / max | -0.325 / 1.016 m | -0.627 / 0.299 m | 0.000 to 0.050 m |
| Max edge drop with no barrier | 13.61 m | 2.85 m | 3.00 m |
| Cone fails | 147 / 8005 | 170 / 8012 | 0 |
| Junctions failing | 22 / 38 | 6 / 38 | 0 |

Edge drop is under the limit on every road. The old 13.61 m site beside `canyon_springs_grade` at (2743.2, -6389.5) is gone. The remaining maximum is 2.85 m at (2847.5, -6630.5) on that same grade. Addison's deck edge is 2.35 m at (69.0, -2496.6). The rim end is 2.41 m at (4494.6, -5969.4).

The Perrine bridge itself passes hit, along, across, gap, and edge drop. Across step there was 0.810 m and is now 0.000 m. Both abutments still fail the junction fit (below).

## What changed in the shared pipeline

One profile and one stamp, no per-road heights.

- Each junction gets one plane. Tilt follows the major road and is clamped at 2% (3% when an approach grade is at least 6%). Bridge joints and corners that turn more than 25° stay horizontal, because a tilted plane puts a grade break on the corner. Roads blend onto the plane. Two discs closer than 24 m share one vertical curve that keeps both end heights and both end grades, with curvature under the 0.02 m along step.
- Grade and rim cuts use the rock face, so a lower switchback does not excavate the upper bench. Soil cuts stay at 2:1. Fill stays 1.5:1, then the 4 m blend back to the lidar.
- The ribbon, including deck, bridge, and both approach slabs, sits 0.02 m above the graded height. Collision is that same plane, flared past the paint and overlapped along the centre and along the station, so a ray on the paint edge stays on the carriageway. Skirts and the approach sag sheets are not built. The bridge span is not stamped. Deck, bridge, and rail segments no longer run the old excavator, which was digging out the fill on the next segment.
- A nearer carriageway owns a heightfield cell, and it cannot dig out a higher carriageway that already claimed the cell from its own paint.
- Guardrails use the deepest drop inside 3 m, and a sample past the chunk seam reads the lidar instead of the clamped edge of this chunk.

## What changed in the report

The limits did not move.

- Height for the along step, the across step, the gap, and the junction fit is the driving surface. A parapet cap and a guard top are walkable faces in the same body, about 0.8 m above the lane. The walker now also casts from 0.22 m above the design, so that cap is not the carriageway. A hit still counts as a road hit either way. If no walkable face is within 0.20 m of the design, the first road hit is kept, so a carriageway that is actually in the wrong place still fails. This is why the bridge across step fell from 0.810 m to 0.000 m, and why abutment junction deviation fell from about 2 m to 0.12 m.
- A road end that is not a junction, an abutment, or a map-edge exit is classified as a dead end. That is the spec's fourth end type. The dirt-cut regression still records the worst seam at those ends. On this run that seam is 0.00 m and the regression passes. Before this, every stub was `unclassified` and failed the end test.

## Still failing

**Along step, max 0.096 m** on `dt_st_+2` at (2040.9, -2005.9). The same street has a lip of 0.03–0.08 m about every 86 m, once per block: (1868.3, -1833.4), (1954.6, -1919.7), (2127.1, -2092.2), (2213.4, -2178.5). The centreline profile's own 1 m lip, measured before collision, is 0.016 m. The report is hitting a surface that leaves that profile, at the downtown crossings. `us93_south_approach` is 0.042 m at (3372.4, -6509.9). `rim_road_south` is 0.060 m. `dt_st_+1` is 0.064 m.

**Across step, max 0.148 m** on `canyon_springs_grade` at (2452.6, -6601.5), the ramp end. `us93_south_approach` is 0.067 m at (3370.7, -6340.8), where the rim crosses the approach. `addison_ave` is 0.081 m.

**Gap.** Minimum -0.627 m on `us93_south_approach` (the capped rows are the small positive gaps near z=-6300; the minimum is further down the approach and was not in the first 14 stored rows). Maximum 0.299 m on `rim_road_south`. `visitor_lot_access` is 0.149 m at (3323.0, -6511.5). `canyon_springs_grade` is -0.150 / 0.197 m. The heightfield is still above the ribbon in some cells and short of it in others. A 4 m cell cannot hold a crowned carriageway and a 1.5:1 face at the same time.

**Junctions, 6 of 38.**

| Junction | Deviation | Tilt | Limit | Where |
|---|---:|---:|---:|---|
| n029 | 0.115 m | 0.001 | 0.030 | (3356.8, -7034.0) north abutment |
| n030 | 0.117 m | 0.001 | 0.030 | (3370.4, -6577.0) south abutment |
| n004 | 0.038 m | 0.014 | 0.020 | downtown `dt_av_-1` / `dt_st_+2` |
| n007 | 0.047 m | 0.017 | 0.030 | downtown `dt_av_+0` / `dt_st_+2` |
| n015 | 0.032 m | 0.011 | 0.020 | downtown `dt_av_+1` / `dt_st_+1` |
| n031 | 0.033 m | 0.020 | 0.030 | (3372.4, -6510.0) approach / visitor lot |

Tilt is inside the limit on all six. The abutment discs are horizontal. The 0.12 m is a real face (wing or landmark) that the walker could not separate from the deck, not the 0.80 m parapet cap.

**Hit rate 96.56%.** Largest misses are still the paint edge on curves and where the heightfield sits on the ribbon: `canyon_springs_grade` 92.6%, `us93_south_approach` 91.2%, `canyon_springs_rd` 93.6%, `addison_ave` 94.7%. The bridge is 100%.

**Cones, 170 / 8012.** The largest are the map-edge exits. A cone pushed off Addison, Falls, or Pole Line at x≈5005 falls about 9 m because the road ends on the boundary and the ground stops. `blue_lakes_blvd_s` does the same at z≈6. `canyon_springs_grade` still has off-edge fails, one at (2705.2, -6581.2). The bridge walk fails at (3378.8, -6627.3): a walk on the terrain beside the span, outside the parapet, still finds a ceiling.

**Regressions.** Raised strip at (3365, -6510) passes (gap 0.024 m). Float at (3218, -6368) passes. Float at (3153, -6143) is a road hit with gap 0.003 m but the regression wants a non-negative gap and a road hit together and this one is recorded fail on the sign of a 3 mm gap. Float at (3320, -6511) is -0.004 m. The guardrail-on-skirt check at (2873.9, -6653.8) still sees a 22.6 m gap because that point is on the canyon deck, which is not stamped. The jagged-junction check is n030's 0.117 m deviation.
