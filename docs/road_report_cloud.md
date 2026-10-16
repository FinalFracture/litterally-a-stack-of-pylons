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

## RS-5, after `33df80a`

Before is the RS-4 network at `33df80a` (the table above). After is a full `tools/road_report.gd` run, 564,445 samples, 734 s. Network still **FAIL**. 22 roads, 0 pass, 22 fail. Hit rate 99.80% (before 96.56%). Components 1.

| Metric | Before (`33df80a`) | After | Limit |
|---|---:|---:|---:|
| Max along step | 0.096 m | 0.040 m | 0.020 m |
| Max across step | 0.148 m | 0.067 m | 0.030 m |
| Gap min / max | -0.627 / 0.299 m | -0.867 / 0.221 m | 0.000 to 0.050 m |
| Max edge drop with no barrier | 2.85 m | 2.85 m | 3.00 m |
| Cone fails | 170 / 8012 | 79 / 8084 | 0 |
| Junctions failing | 6 / 38 | 2 / 38 | 0 |
| Hit rate | 96.56% | 99.80% | 100% |

### What changed in the shared pipeline

- A cross-street ribbon samples the junction plane at each corner, so the wider road is not a horizontal shelf over the graded street. `dt_st_+2` along step at (2040.9, -2005.9) fell from 0.096 m to 0.016 m.
- Where a wider road ends into a narrower collinear road, the half-width tapers over 30 m. US-93 is 3.35 m half at (3378.6, -6300) and 7.32 m at 30 m. A through road that only crosses a side street is not tapered.
- A sign pole is placed from every road at the junction. The stand has to clear every carriageway by 1.6 m. The old poles in the US-93 lanes now stand at (3486.6, -2494.3) and (3412.4, -4994.3), each 1.64 m clear.
- Lane paint adds the crown tent, so the centre stripe is at the crowned surface rather than the edge height.
- A map-edge exit continues 18 m past the last vertex on a `RoadBody` pad at the road height, with a berm at 15.5 m. The pad starts at the end vertex so it does not shelf the last metres of the grade. Addison, Falls, and Pole Line at x=5005 are on that pad.
- The bridge span gets a 2.6 m shoulder and a parapet, so a walk beside the deck is not standing under the soffit. The point (3378.8, -6627.3) is on the shoulder.
- The canyon grade holds its heading for 24 m past the authored end, then turns toward the ramp. The across step at the old ramp kink (2452.6, -6601.5) is gone. The ramp-end residual is 0.025 m.
- On a low (4 m) tile the mesh stays coarse. The stored heightfield under the paint is rewritten at 1 m to the crowned section, and a later fill cannot overwrite that paint. The 2 m hole at (3373, -6486) is a 0.023 m gap.
- A rail crossing panel is visual only. The flat collision panel was a shelf on the graded road. The carriageway ribbon already covers the crossing.

### What changed in the report

Limits did not move. New regression checks, skipped by the generic step/gap loop:

- RL-INT-01 poles at (3491.4, -2494.1) and (3417.2, -4994.1): the computed stand must clear every carriageway by 1.6 m.
- RL-INT-02: `_paint_y` puts the crown tent back on the edge lerp.
- RL-INT-05 driving surface versus the junction plane at the visitor T, the rim T, and Canyon Springs. Pass if at least three road samples and the worst is within 0.03 m.
- RL-INT-08: the south approach half at (3378.6, -6300) matches Blue Lakes, and the half 30 m along is the full 7.32 m.
- The hole at (3373, -6486), the ceiling at (3378.8, -6627.3), and the three map-edge exits at x=5005.
- The driving-surface walker keeps the walkable road face closest to the design within 0.20 m, instead of the first face in that window.

All of those new checks pass on this run. The visitor, rim, and canyon meeting steps that were 0.53 m, 0.72 m, and 0.255 m measure 0.022 m, 0.012 m, and 0.000 m against the junction plane.

### Still failing

**Along step, max 0.040 m** on `rim_road_south` at (4502.2, -5970.5), near the east end. Downtown avenues are 0.024–0.026 m at the block crossings (`dt_av_+0` at (2386.9, -1653.1)). Addison is 0.027 m at (1548.0, -2500.0), where `dt_av_+0` meets it just outside the junction disc. The centreline profile's own lip is at most 0.016 m. The extra is the neighbouring ribbon overlapping the crest.

**Across step, max 0.067 m** on `us93_south_approach` at (3370.7, -6340.8). The rim ribbon still covers the approach edge outside the junction disc and is higher than the approach section. The same pattern is about 0.057 m on Addison, Falls, Pole Line, and Blue Lakes, and 0.054 m on `canyon_springs_grade` at (3145.7, -6555.5).

**Gap.** Minimum -0.867 m on `us93_south_approach`. The first 14 stored gap rows for that road are the small gaps near the north end, so the minimum's coordinate is not in the failure list. Maximum 0.221 m on `rim_road_south`. `canyon_springs_grade` is 0.176 m at (3147.4, -6555.6). `visitor_lot_access` is 0.149 m at (3323.0, -6511.5), the west end of that road, outside the painted corridor. The 1 m paint stamp holds the crowned lane. It does not hold a side slope that starts inside the same sample, and a cell the stamp did not claim can still sit above the ribbon.

**Junctions, 2 of 38.** n004 dev 0.030 m (limit 0.020) at (1951.2, -1916.3), `dt_av_-1` / `dt_st_+2`. n007 dev 0.039 m (limit 0.030) at (2037.5, -2002.5), `dt_av_+0` / `dt_st_+2`. Tilt is inside the limit. The abutments n029 and n030 are on the plane (dev 0.000 and 0.001 on a ribbon probe; the report's junction dev on the bridge roads is 0.002 m).

**Hit rate 99.80%.** 143 stored misses. `canyon_springs_grade` is 98.4%, `us93_south_approach` 99.1%, `rim_road_south` 99.4%. The bridge is 100%.

**Cones, 79 / 8084.** The x=5005 map-edge falls are gone; those three exit regressions pass on `RoadBody`. What remains is a cone leaving the carriageway where the shoulder drops and the drop rule did not call for a barrier. The largest stored are Addison off-edge at (200.0, -2491.3) about 4.9 m, the rim east end at (4470.2, -5991.7) about 4.3 m, and the canyon grade cut at (2555.8, -6566.6) and (2705.2, -6581.2). One straight cone at the ramp head (2447.2, -6762.6) is 0.16 m.

**Regressions still open.** Float at (3153, -6143) hits `TerrainBody`. Float at (3320, -6511) is a -0.004 m gap on `TerrainBody`. The guardrail-on-skirt point (2873.9, -6653.8) is still the unstamped canyon deck, gap 22.6 m. The jagged-junction check is n007 at 0.039 m. Dirt-cut end, raised strip, both poles, crown paint, the three meeting steps, the taper, the hole, the bridge ceiling, and the three map-edge exits pass.
