# RS-3 diagnosis

Source: `_diag/road_report.json` from the RS-2 run recorded in `docs/road_report_rs2.md` (commit `86da082`, stamp `45cf8d7`). No pipeline code was changed before this note. The report's `failures` array keeps only the first 14 rows for each road and test (`FAIL_CAP` in `tools/road_report.gd`), so those 1159 rows are not a census. Counts below use the uncapped per-road totals, the derived miss counts, and `network.worst`.

RS-2 did grade ordinary carriageways. Rim gap max fell 12.223 m to 0.971 m, Canyon Springs Grade 12.665 m to 1.016 m, Addison 6.247 m to 0.594 m, and the downtown gap maxima fell from about 0.5 m to about 0.1–0.3 m. The network maxima barely moved because they are not those samples.

`drawn_height_at` is the runtime heightfield: `_build` stamps `apply_cuts` into the grid, emits the mesh, resamples triangles with a per-cell max (`_collision_from_mesh`), then `clamp_footprint` only lowers cells the simplifier raised. Ordinary before/after gaps show that this is the graded surface, not the pre-RS-2 DEM. `_skirts` has no caller. Approach roads still emit `_close_span` and `_approach_structure` collision.

OSM is not in the file. All 22 roads are `source: SCHEMATIC`, `osm_id` null, no `layer`. `bridge: true` is only `us93_perrine_bridge`. That road's gap is exempt and 0. Its across step is 0.810 m (the bridge shell against a flat design), not the network 13.700 m.

## Top 5 causes

### 1. Whole-road approach skip on fill and cut segments

`TfRoadBuilder._rebuild_edges` sets `skip` when the road id is `us93_north` or `us93_south_approach`, for every segment, not only `deck` and `bridge`. Skipped edges use the legacy cutter, which only lowers the heightfield. The gap test still scores fill and cut. Deck and bridge samples are the ones the report exempts.

This owns the unchanged network max gap, 30.885 m, on `us93_north` (30,008 samples, hit 96.8%, across 13.700 m, gap 0.008 / 30.885 m). All 10 `network.worst` rows are that road, segment kind `fill` (polyline segment 1, y about 138), about 7.2 m off the centreline, about 100 m north of junction `n029`. They are road hits, so the ribbon collider is there and the ground under it was not filled.

| value | x | z |
|---:|---:|---:|
| 30.885 m | 3346.4 | -7137.7 |
| 30.719 m | 3346.6 | -7137.7 |
| 30.702 m | 3346.7 | -7130.7 |

`us93_south_approach` (8,649 samples) is the same skip. Its max gap 7.964 m and max across 13.644 m match RS-1. The 13.644 m point is past the first 14 across-step rows, so the JSON does not store its coordinate. The road's min gap did move, 0.002 m to -1.950 m: something raised `drawn` ground above the ribbon. The skip path never fills, and `clamp_footprint` only pulls `drawn` down onto the cut.

### 2. Rays at the paint edge miss the ribbon

Hit rate 96.53% is 19,547 misses out of 563,970 samples (RS-1 was 96.96%). 20 of 22 roads fail hit. The bridge (0 misses) and `visitor_lot_access` (0) pass. Largest miss totals: `us93_blue_lakes_s` 3,770 / 57,045, `blue_lakes_blvd_s` 2,353 / 37,545, `canyon_springs_grade` 2,180 / 29,666, `rim_road_south` 1,659 / 25,785, downtown avenues about 500–1,500 each.

Of the 280 capped hit rows, 195 sit in the outer 0.6 m of the paint and 85 are interior. On 16 roads the median lateral distance of those rows is the half-width. Straight roads barely miss (`falls_ave` 99.9%, `pole_line_rd` 99.9%, `addison_ave` 99.7%). Curved roads sit near 93%. The ribbon is the `RoadBody` faces. A downward ray on the mathematical edge of a zero-margin concave polygon misses. Grading the heightfield does not add that triangle. Example interior miss: `blue_lakes_blvd_s` at (3493.4, -2490.1), 1.65 m off a 3.35 m half-width. Example edge miss: `us93_blue_lakes_s`, half-width 3.35 m, capped rows on the paint edge.

### 3. Edge probe still sees a cliff beside a graded fill

Network edge drop went from 11.31 m to 13.61 m. Two roads fail the 3 m limit.

- `canyon_springs_grade` 13.614 m at (2743.2, -6389.5). Nearest authored vertex is fill, index 86, (2740.0, 102.45, -6391.2), 457 m from a junction. `skip` is false. The same road's carriageway gap max fell 12.665 m to 1.016 m, so the stamp is in the heightfield under the paint. The 3 m outward probe is not, and the barrier ray did not count a guard. Guards are collision (`_guard_edge` writes `faces`), but they are emitted only when the ground 3 m out is already at least 2 m below the edge (`DROP_RAIL_M`).
- `addison_ave` 7.96 m at (113.0, -2496.6), kind `deck`, stamp skipped. Unchanged from RS-1. Deck is exempt from the gap test and not from the edge-drop test.

### 4. Junction patches were not rebuilt

22 of 38 junctions fail (RS-1 was 24 of 38). Every road fails the junction test because the road stores its worst junction. The two large ones are the bridge ends, unchanged by the ordinary stamp:

- `n029` dev 2.072 m, tilt 0.042, limit 0.02, at (3356.84, -7034.0). North end of `us93_perrine_bridge`. Same 2.072 m as RS-1.
- `n030` dev 1.961 m, tilt 0.036, at (3370.41, -6577.0). South end. RS-1 was 1.964 m.

Next is `n032` 0.432 m at (3377.74, -6330.0). These numbers do not set the network gap, across step, hit rate, or edge drop.

### 5. Abutment cross-section, separate from the heightfield

Network max across step 13.700 m is `us93_north` at the north abutment, kind `deck` (gap-exempt), unchanged from RS-1:

| value | x | z |
|---:|---:|---:|
| 13.700 m | 3363.6 | -7036.2 |
| 13.650 m | 3363.6 | -7037.2 |
| 13.600 m | 3349.4 | -7037.8 |

The samples step 0.05 m per metre of station, about 7 m off the centreline (half-width 7.32 m). Across step compares consecutive road-collision heights with the design cross-slope. It does not read `drawn_height_at`. The approach still builds a closed solid and wing walls, and the report loads the Perrine landmark. The sister value 13.644 m is the south approach maximum, also unchanged. The bridge's own across step, 0.810 m at (3371.2, -6578.0), is the shell against a flat design.

The report cap is not why the headlines stuck. The uncapped per-road maxima match RS-1 on `us93_north` to the millimetre for across step, gap max, and edge drop.

## Fix chosen

Cause 1. `skip` will follow segment kind (`deck`, `bridge`, rail) instead of the road id, so fill, cut, and grade on the Perrine approaches take the same stamp as every other road. Deck and bridge stay unstamped and gap-exempt. Approach profiles stay pinned so the deck joint does not move. No per-road height edits.
