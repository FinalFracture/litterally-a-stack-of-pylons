# Road bake-off, step 0

Scaffolding so strategies 0 to 10 can be scored on the same sites. Strategies 1 to 10 are stubs. Strategy 0 is the measured builder (the `1ed88ba` road pipeline, restored by a forward commit). These runs record that pipeline. They do not show a fixed road.

Seed for every run: `20261008`.

## 1. Selecting a strategy

Both the windowed game and the headless tools read the same two sources. A user argument wins over the environment variable. The default is 0.

| Source | Form |
|---|---|
| User argument, after `--` | `--road_strategy=N` |
| Environment | `PYLONS_ROAD_STRATEGY=N` |
| Default, neither set | `0` |

Parsed in `scripts/launch_config.gd` beside `--map`, and again inside `RoadStrategyRegistry` so a headless `-s` script sees it when the autoload has not run. With no flag, the launch line stays the same and the terrain generator builds a `TfRoadBuilder`.

Ids, names, and the gap limit each strategy declares:

| Id | Name | Gap max |
|---:|---|---:|
| 0 | `current_builder` | 0.050 m |
| 1 | `control_terrain_as_road` | 0.050 m |
| 2 | `ribbon_masked_terrain` | 0.300 m |
| 3 | `joint_junction_mesh` | 0.300 m |
| 4 | `corridor_heightfield_0_5` | 0.050 m |
| 5 | `corridor_heightfield_1_0` | 0.050 m |
| 6 | `constrained_tin` | 0.050 m |
| 7 | `road_height_raster` | 0.050 m |
| 8 | `extruded_solid` | 0.050 m |
| 9 | `sdf_carve` | 0.050 m |
| 10 | `global_constrained_solve` | 0.050 m |

An id outside 0..10, or a non-integer, pushes `strategy N not implemented` and builds nothing. Ids 1 to 10 do the same today.

## 2. Dev area and sites

Catalogue: `tools/road_bakeoff/sites.json`. Each entry has `id`, `kind` (`synthetic` or `map`), `centre` `[x, z]`, `size` `[width, depth]` metres, and `notes`.

RoadLab is a synthetic area of about 600 by 600 m on the same builder path. Roads: `world/twin_falls/data/road_lab/roads.json` (40 roads, 1 rail, stable `segment_ids` such as `lab_nw_st_0.s0`). Terrain ops: `world/twin_falls/data/road_lab/terrain.json`. Regenerate both with `python3 tools/road_bakeoff/build_lab_roads.py`. The box sits at x 100..700, z -2200..-1600 so it is inside the map index and off the real road corridors. Exits run 50 m past that box (to x 750 and z -2250). The cul-de-sac bulb reaches z -1608. The harness site `dev` is the rect centre `[435, -1929]`, size `[700, 700]`, which covers those exits.

Quadrants in the same file: `dev_nw`, `dev_ne`, `dev_centre`, `dev_sw`, `dev_se`, `dev_s`. Real cells: `A` `3370,-6480`, `B` `2850,-6480`, `C` `2350,-1750`, `D` `3500,-2500`, `E_east` `4800,-2500`, `E_north` `3330,-7850`, `F` `3900,-6150`, each 400 by 400 m. Regression pins are 80 by 80 m sites `pin_3153`, `pin_3218`, `pin_3320`, `pin_3365` at `(3153,-6143)`, `(3218,-6368)`, `(3320,-6511)`, `(3365,-6510)`.

Open the dev area in a window (this builds all four lab chunks; `--site` only aims the camera):

```
godot --path . res://scenes/road_lab.tscn
godot --path . res://scenes/road_lab.tscn -- --site=dev_nw --road_strategy=0
```

F6 on `scenes/road_lab.tscn` does the same. `scenes/road_strategy_lab.tscn` loads that script too. WASD flies, the mouse looks, Esc frees the mouse, Shift is faster. The main game scene is still `scenes/twin_falls.tscn`.

What a site builds:

- A synthetic site builds the four RoadLab chunks `(0,-5)`, `(1,-5)`, `(0,-4)`, `(1,-4)` through `RoadLabGenerator`. No lidar tile is read. The run is forced low so a canyon flag cannot swap in a 513 grid.
- A map site builds only the 500 m chunks its rectangle touches, plus a neighbour when a sample is within 40 m of a chunk edge. The rest of the Twin Falls map stays unloaded.
- Cell A, measured: chunks `(6,-13)`, `(6,-14)`, `(7,-13)`, `(7,-14)`, plus the Perrine bridge model.
- Cell C, measured: chunks `(4,-4)` and `(5,-4)` only. The 400 m square sits in one row of the 500 m grid. Chunk `(4,-4)` carries the 1 m paint corridor and took about 65 s.
- A pin site builds the chunk that contains the pin (and a neighbour if the pin is within 40 m of an edge).

`unsupported_by_strategy_0` in the catalogue is the feature list the current builder does not construct. The road centreline is still placed. The list: downtown curbs, sidewalks, crosswalks, and ADA ramps; the bus shelter pad; signal heads, stop bars, and 6 m / 12–15 m corner returns; the dev-area exit pad (strategy 0 only pads the Twin Falls boundary `x<=5`, `x>=4995`, `z>=-5`, `z<=-7995`); 3 m benches on a tall rock cut; a concrete barrier asset (a guard wall is emitted when the stamped drop exceeds 2.5 m); approach-slab abutment fill and the Perrine deck joint; lane-closure furniture; a solid freight-rail crossing; a 4.9 m underpass structure; the cul-de-sac apron and end sign; the service-road gate. Lab bridge spans do emit the 0.8 m parapet.

## 3. Metrics output

```
godot --headless --path <project> -s res://tools/road_bakeoff/run.gd -- --road_strategy=N --site=ID
```

`ID` is a catalogue id, or `all`. Omitting `--site` runs `dev`. The tool extends `tools/road_report.gd`. Rays start at design y + 2 m and hit the live `RoadBody` and `TerrainBody` for the road being measured. Gap and verge read `drawn_height_at` on the stamped grid, which is the surface the terrain mesh is built from. The strategy's own arrays are not the score. The gate sample grids are in Gate definitions below. The 1 m centreline walk remains a pre-screen field (`stats.prescreen_step_along_m`, `stats.prescreen_step_across_m`).

One run writes `bakeoff_out/<strategy>/<site>.json` and a short `.md` beside it. `bakeoff_out/` is gitignored. A gate failure still exits 0: a measured fail is a finished run. An unknown site, or a strategy other than 0, pushes `strategy N not implemented` when that applies, writes a stub JSON whose `gates.implemented` fails, and exits 1. No world is built.

Merge runs:

```
python3 tools/road_bakeoff/aggregate.py
python3 tools/road_bakeoff/aggregate.py --out tools/road_bakeoff/evolve_report.md
```

The default report path is `bakeoff_out/evolve_report.md`. One column per strategy. Each cell is `SITE PASS/FAIL (value)`. Failures follow, listed by x, z. There is no ranking and no realism score.

`fps`, `frame_time_ms`, and `draw_calls` are always the string list `not_measured_headless`. They are not guessed.

The committed example is `tools/road_bakeoff/baseline/strategy0_dev.json` (the dev-area run, 1079 stored failure rows). Abbreviated, the same document looks like this:

```json
{
  "strategy": {"id": 0, "name": "current_builder", "gap_max_m": 0.05},
  "site": "dev",
  "seed": 20261008,
  "git_commit": "8ea9a10ee09fc406fc45bc068e64a256c801cbb4",
  "gates": {
    "hit_rate": {"value": 0.696597520578583, "limit": 1.0, "pass": false},
    "step_along_m": {"value": 0.02752685546875, "limit": 0.02, "pass": false},
    "gap_max_m": {"value": 7.00721341080218, "limit": 0.05, "pass": false},
    "determinism": {"value": 1, "limit": 1, "pass": true}
  },
  "failures": [
    {"gate": "hit", "x": 114.049996948242, "z": -2172.0, "value": 0.0}
  ],
  "failure_counts": {"lab_nw_st_0|hit": 1377},
  "determinism_hash": "4bd4e746e32c3aa227787994cc108110fd1a7769227c9431de4cc1328c58f5e8",
  "determinism_hash_b": "4bd4e746e32c3aa227787994cc108110fd1a7769227c9431de4cc1328c58f5e8",
  "build_seconds": 64.156,
  "stats": {
    "determinism_build_seconds": 65.021,
    "samples": 130111,
    "roads": 40,
    "node_count": 93,
    "terrain_triangles": 35148,
    "road_triangles": 27383,
    "memory_mb": 179.079412460327,
    "barrier_samples": 0,
    "junctions": 37,
    "junctions_missing_features": 37
  },
  "not_measured_headless": ["fps", "frame_time_ms", "draw_calls"]
}
```

The `failures` array keeps the first 14 rows per road per gate (`FAIL_CAP` in `tools/road_report.gd`), so it is a sample. `failure_counts` holds the totals. `junction_dev_m` and `junction_tilt` share one pass flag: a junction fails when its deviation exceeds 0.03 m or its tilt exceeds 2% (3% when an approach grade is at least 6%). The value fields are the separate maxima, which is why dev tilt 0.030 can still pass. Grade and cross-slope pass from a count of over-limit samples; the value is the worst sample. The grade limit string is `class_cap+0.005`.

## Gate definitions

Civil's Rev 2 rulings. These apply when `bakeoff_mode` is on. `tools/road_report.gd` with the flag off still scores the 1 m centreline second-difference and still defaults an untagged end to `dead_end`.

1. **Step.** Along-step is every lane line and every 0.5 m stripe across the footprint, shoulder, and verge, at 0.05 m along the road, net of the design grade and crown (measured Δy minus design Δy), limit 0.02 m. The crown crease (`|offset| <= 0.05 m`) and, on a road with 4 or more lanes, the median band (`|offset| <= 0.30 m`, half of the 0.6 m median) are left out of the along-step. Across-step is 0.05 m spacing on lines every 1 m along the road, net of design cross-slope, limit 0.03 m. `step_across_at_0_02_fails` counts across samples over 0.02 m, including those that also exceed 0.03 m. It is advisory and is not a gate. Step and gap are not dropped inside junction patches. A deck or bridge stripe stays on the carriageway. The 1 m centreline second-difference and the 0.5 m across residual stay in `stats` as `prescreen_step_along_m` and `prescreen_step_across_m`. QA's own every-lane-line figure, if they publish one separately, is advisory on their side. The harness gate is the 0.05 m sweep above. Spacing is not coarsened when a site runs long.

2. **Cone gate.** One cone is pushed from the lane centre across each edge, both edges, every 50 m, plus the four regression pins `(3153,-6143)`, `(3218,-6368)`, `(3320,-6511)`, `(3365,-6510)` when the pin lies in the site. The push is re-applied at 5 m/s for up to 160 physics frames. A start or an end outside a chunk this run built is not a fail. The count is `cone_skipped_outside_built_chunks`. Where the segment has no barrier, the cone must come to rest on ground, the drop from the road height must be at most 3 m, and the cone must not be buried, stuck, or below the road surface. On a barrier segment (deck, bridge parapet, `rim_local` / `rim_road_south`, or a guard the horizontal ray finds on that edge) the cone must stay on the carriageway. The Perrine deck escape at `(3353.0, -6626.4)` is a fail when a scored cone ends there and breaks that rule. `stats.perrine_nearest_cone_m` is the nearest scored cone end, and `stats.perrine_escape_fail` is true when a fail landed within 8 m of that point. The single-launch set (lane centre, each lane centre, 0.4 m inside each edge, at 60°, 90°, and 120° from the forward tangent, positive toward the right edge) is recorded as `kind: "diagnostic"` and is not simulated. `stats.cone_diagnostic` is `not_simulated`. Those rows never enter `cone_fails`.

3. **Junction zone and cross-slope.** `junction_patches` is `{id, polygon: [[x,z], ...]}`, the convex hull of each junction's carriageway inside its radius, expanded 1 m. Inside that polygon the junction flatness gate applies (0.03 m deviation, 2% tilt, 3% when an approach grade is at least 6%) and cross-slope is not scored. `cross_slope_junction_excluded` is the number of centreline stations inside a patch. For 10 m outside the polygon the cross-slope limit is 4%. Farther out it is 2.5%, or the superelevation target ± 0.5% when the design slope exceeds 2.5%. There is no 15 m circle and no exclusion for a crossing road. Each road is measured on its own surface.

4. **Hit rate.** The 1 m by 0.5 m grid covers lanes, shoulder, and verge (carriageway only on a deck or bridge). A ribbon strategy needs a road-body hit. Strategies 1, 4, 5, 6, and 10 are road-is-terrain: the topmost hit within 0.05 m of design y counts. The ray origin is design y + 2 m.

5. **Grade and ends.** Grade is the centreline, about every 10 m, against the class cap + 0.5%. `stats.lane_grade_max` is the steepest 10 m grade on a lane line and is not a gate. An end counts as unclassified when the road record has no `start_kind` or `end_kind`. The harness does not fill that in as `dead_end`. The builder does not store an end class, and `roads.json` has none, so every in-site end fails this gate until a classification is written on the road record.

`cone_starts` rows are `{x, z, edge, kind, lane_offset, angle, barrier, built}`. `kind` is `every50`, `pin`, or `diagnostic`. `angle` is degrees from the forward tangent. `barrier` is the edge's barrier flag. `built` is whether the start sits in a chunk this run built.

## 4. Adding a strategy

Contract: `scripts/world/road_strategies/road_strategy.gd`. Inputs are the same for every id: a roads JSON, the terrain or lidar tiles (or the RoadLab height field), `RoadRules` (cross-sections, grade caps, junction, barrier, and road-end constants, seed `20261008`), and the gap limit on the strategy. Output is a drivable road plus the ground under it and beside it, with collision the harness can ray and cone.

`scripts/world/road_strategies/road_rules.gd` holds those shared numbers. Strategy 0 does not read that file.

To add one:

1. New script under `scripts/world/road_strategies/`, `extends RoadStrategy`. Set `id`, `strategy_name`, `gap_min`, `gap_max`, and `summary`.
2. Implement `make_builder()` so it returns an object with the `TfRoadBuilder` surface the generator already calls: `prepare`, `apply_cuts`, `clamp_footprint`, `build_chunk`, `jobs`, `cuts_block`, `apply_paint`, and a `_dem` callable the generator assigns. Return `null` only when the strategy cannot run.
3. In `RoadStrategyRegistry.create()`, construct that script for its id instead of `strategy_stub.gd`. The name and the gap are already in `SPECS`.
4. `TwinFallsTerrainGenerator.prepare()` already does `_roads = strategy.make_builder()`, then `prepare()` and `_dem` when the result is not null. A null builder skips road cuts and leaves the terrain generator's existing null checks in place.

Until that script exists, `strategy_stub.gd` pushes `strategy N not implemented` and returns null.

## 5. Known gaps

- Strategy 1 is a stub. The terrain-as-road bench from `41cbe8a` was written by editing the shared builder and the terrain generator. Putting that code behind the switch would have put the unvalidated stamp back on the default path. The reference is `git show 41cbe8a:scripts/debug/road_strategy_lab.gd`.
- The features in `unsupported_by_strategy_0` are marked there. The centreline is placed. The feature is not faked.
- Dev-area roads that run 50 m past the lab box do not get the strategy-0 exit pad. That pad is keyed to the Twin Falls boundary. Cell `E_east` and cell `E_north` are the sites that contain a real map-edge end.
- `barrier_seat_m` passed on dev, A, and C with `barrier_samples` 0. The probe steps down a non-ground collider only after a horizontal physics ray finds a steep face beside the edge. These runs found none, so the value is 0.0. Strategy 0 guard walls are a visual surface. The harness builds `TerrainBody`, `RoadBody`, and, on map sites, the Perrine bridge mark.
- `vertical_faces` counts triangles in the road collision ribbon whose `|normal.y| < 0.5`. Parapets and skirts in that ribbon count. Cell C has 0. Dev has 1720. Cell A has 2192.
- Junction completeness looks for a node whose name contains `stop`, `signal`, `crosswalk`, `curb`, `ramp`, or `arc` within 25 m. Strategy 0 does not create those nodes, so every in-site junction fails.
- `fps`, `frame_time_ms`, and `draw_calls` are `not_measured_headless`. Triangle count is terrain-mesh triangles plus road-collision faces for the chunks that were built, compared with 1.5 million as a site cap. Memory is `OS.get_static_memory_usage()`, cap 3072 MB. Node count is recorded and has no gate.
- The full-map `tools/road_report.gd` was not rerun for this step. The last full-network numbers remain the `1ed88ba` report. A pass on cell C (gap, grade, verge, edge drop, vertical faces, one component) is that 400 m square only.
- The dev area measured 7 connected components. The link roads were authored to join the quadrants. The gate result is 7.
- On cell C, `dt_av_-2` matched the site rectangle and then contributed 0 samples, because its stations lie outside the rect. It does not move the hit rate.
- The windowed RoadLab scene was not flown in a GUI. The same generator was measured headless as site `dev`.
- Quality Assurance's scorecard, realism score, heat maps, and blind A-to-J labels are out of this tree. The JSON above is the input that scorecard reads.

## Strategy 0 baseline

The table in this section is the measurement from before the Gate definitions above. Dev and cell C were not re-run under the revised rules. The revised site A run is recorded under "Site A, revised gates" once that process has finished.

Godot `4.7.2.stable.official.ed1daf0bf`. Commit measured: `8ea9a10ee09fc406fc45bc068e64a256c801cbb4`. Each run builds the world, hashes collision, frees it, builds it again, hashes again, then measures the second world. `build_seconds` is the first build. The second build is `stats.determinism_build_seconds`. All three hashes matched.

After those runs, `prepare()` was pointed at `make_builder()`. Strategy 0's `make_builder()` returns a new `TfRoadBuilder` and does not wrap its methods. A headless prepare of strategy 0 after that change still loaded 23 roads and 38 junctions, which is the real `roads.json`. The site table below is the `8ea9a10` measurement.

Wall clock is the process time, including both builds and the ray and cone passes.

| Site | Wall | First build | Second build | Chunks in the log |
|---|---:|---:|---:|---|
| `dev` | 4 min 27 s | 64.2 s | 65.0 s | `(0,-5)` 26.4 s / 27.8 s, `(0,-4)` 22.8 / 22.6, `(1,-5)` 6.2 / 6.3, `(1,-4)` 7.7 / 7.7 |
| `A` | 2 min 45 s | 58.1 s | 56.2 s | `(6,-13)` 26.4 / 25.5, `(6,-14)` 15.9 / 15.7, `(7,-13)` 10.5 / 10.3, `(7,-14)` 2.3 / 2.2, plus the bridge model |
| `C` | 4 min 35 s | 74.5 s | 72.8 s | `(4,-4)` 64.8 / 63.7, `(5,-4)` 6.5 / 6.6 |

Determinism hashes (build A equals build B):

| Site | Hash |
|---|---|
| `dev` | `4bd4e746e32c3aa227787994cc108110fd1a7769227c9431de4cc1328c58f5e8` |
| `A` | `7dcfbfb64477db5ebf8e825cfbd4d3e329fd3f0623077c9804aaa7be3d1be8d1` |
| `C` | `b5a1559beaf8bd0ff5904bf0651b088de02bc23999137941adaeb9604edb4560` |

| Gate | Limit | dev | A | C |
|---|---|---|---|---|
| hit_rate | 1 | FAIL 0.697 | FAIL 0.709 | FAIL 0.621 |
| step_along_m | 0.02 | FAIL 0.028 | FAIL 0.026 | FAIL 0.027 |
| step_across_m | 0.03 | FAIL 7.161 | FAIL 1.990 | FAIL 0.083 |
| gap_min_m | 0 | FAIL -7.110 | FAIL -0.724 | PASS -0.0005 |
| gap_max_m | 0.050 | FAIL 7.007 | FAIL 0.149 | PASS 0.046 |
| verge_gap_m | 0.10 | FAIL 0.900 | FAIL 0.257 | PASS 0.041 |
| grade | class cap + 0.5% | FAIL 0.160 | FAIL 0.126 | PASS 0.028 |
| cross_slope | 0.025, or superelevation + 0.005 | FAIL 0.058 | PASS 0.020 | PASS 0.012 |
| edge_drop_m | 3 | FAIL 4.894 | PASS 2.371 | PASS 0.253 |
| vertical_faces | 0 | FAIL 1720 | FAIL 2192 | PASS 0 |
| cone_fails | 0 | FAIL 26 | FAIL 33 | FAIL 81 |
| junction_dev_m | 0.03 | PASS 0.010 | PASS 0.019 | PASS 0.024 |
| junction_tilt | 0.02, or 0.03 on a grade ≥ 6% | PASS 0.030 | PASS 0.020 | PASS 0.012 |
| unclassified_ends | 0 | PASS 0 | PASS 0 | PASS 0 |
| junction_features_missing | 0 | FAIL 37 | FAIL 5 | FAIL 9 |
| barrier_seat_m | 0.05 | PASS 0 (0 samples) | PASS 0 (0 samples) | PASS 0 (0 samples) |
| components | 1 | FAIL 7 | PASS 1 | PASS 1 |
| determinism | hash match | PASS | PASS | PASS |
| memory_mb | 3072 | PASS 179 | PASS 250 | PASS 227 |
| triangles | 1500000 | PASS 62531 | PASS 127912 | PASS 44050 |

Samples / roads / nodes: dev 130111 / 40 / 93, A 32331 / 7 / 144, C 62586 / 9 / 136.

The merged table and the stored failure rows are in `tools/road_bakeoff/evolve_report.md`.

## Commands

One site:

```
godot --headless --path . -s res://tools/road_bakeoff/run.gd -- --road_strategy=0 --site=A
```

Every site in `tools/road_bakeoff/sites.json` (18 runs, each with two builds; dev alone was 4.5 minutes and cell C was 4.6 minutes, so the full set is a long run):

```
godot --headless --path . -s res://tools/road_bakeoff/run.gd -- --road_strategy=0 --site=all
```

The binary used for the baseline was Godot 4.7.2:

```
/tmp/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path /workspace -s res://tools/road_bakeoff/run.gd -- --road_strategy=0 --site=dev
```
