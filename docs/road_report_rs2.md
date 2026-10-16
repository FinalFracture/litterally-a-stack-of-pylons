# RS-2 road report

Terrain graded to ordinary roads. Junction patches, bridge decks, and the Perrine approaches are unchanged. Before is the RS-1 network on `d8f02c0`. After is the same `tools/road_report.gd` run on the RS-2 stamp.

## Before

Network **FAIL**. 22 roads, 0 pass, 22 fail. Samples 563970. Hit rate 96.96%. Components 1.

| Metric | Value | Limit |
|---|---:|---:|
| Max along step | 0.500 m | 0.020 m |
| Max across step | 13.700 m | 0.030 m |
| Gap min / max | 0.002 / 30.885 m | 0.000 to 0.050 m |
| Max edge drop with no barrier | 11.31 m | 3.00 m |
| Cone fails | 188 / 8048 | 0 |
| Junctions failing | 24 / 38 | 0 |

| Road | Status | Hit | Step along | Step across | Gap min | Gap max | Edge drop | Cone fails | Junction dev | Ends |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| us93_blue_lakes_s | FAIL | 93.4% | 0.067 | 0.341 | 0.110 | 1.360 | 1.33 | 0 | 0.216 | 0 |
| us93_south_approach | FAIL | 97.2% | 0.500 | 13.644 | 0.002 | 7.964 | 0.48 | 1 | 1.964 | 0 |
| us93_perrine_bridge | FAIL | 100.0% | 0.000 | 0.810 | 0.000 | 0.000 | 0.00 | 33 | 2.072 | 0 |
| us93_north | FAIL | 96.8% | 0.055 | 13.700 | 0.008 | 30.885 | 0.57 | 2 | 2.072 | 0 |
| blue_lakes_blvd_s | FAIL | 93.4% | 0.039 | 0.033 | 0.110 | 0.613 | 0.88 | 9 | 0.054 | 0 |
| addison_ave | FAIL | 100.0% | 0.068 | 0.050 | 0.110 | 6.247 | 7.96 | 23 | 0.054 | 0 |
| falls_ave | FAIL | 100.0% | 0.049 | 0.030 | 0.110 | 0.785 | 0.82 | 12 | 0.039 | 0 |
| pole_line_rd | FAIL | 100.0% | 0.056 | 0.041 | 0.110 | 1.107 | 1.17 | 12 | 0.037 | 0 |
| rim_road_south | FAIL | 94.1% | 0.127 | 1.011 | 0.064 | 12.223 | 3.37 | 24 | 0.179 | 1 |
| visitor_lot_access | FAIL | 100.0% | 0.050 | 0.025 | 0.110 | 1.330 | 1.26 | 0 | 0.482 | 1 |
| canyon_springs_rd | FAIL | 93.5% | 0.024 | 0.126 | 0.110 | 0.383 | 0.37 | 0 | 0.087 | 0 |
| canyon_springs_grade | FAIL | 93.3% | 0.075 | 0.042 | 0.102 | 12.665 | 11.31 | 72 | 0.087 | 1 |
| dt_av_+0 | FAIL | 94.5% | 0.026 | 0.042 | 0.110 | 0.622 | 0.63 | 0 | 0.053 | 1 |
| dt_av_+1 | FAIL | 95.7% | 0.028 | 0.054 | 0.107 | 0.366 | 0.34 | 0 | 0.063 | 2 |
| dt_av_+2 | FAIL | 95.8% | 0.041 | 0.043 | 0.110 | 0.448 | 0.45 | 0 | 0.043 | 1 |
| dt_av_-1 | FAIL | 95.4% | 0.055 | 0.047 | 0.106 | 0.444 | 0.48 | 0 | 0.050 | 2 |
| dt_av_-2 | FAIL | 94.6% | 0.027 | 0.030 | 0.109 | 0.506 | 0.68 | 0 | 0.026 | 2 |
| dt_st_+0 | FAIL | 97.5% | 0.095 | 0.083 | 0.110 | 0.601 | 0.58 | 0 | 0.045 | 1 |
| dt_st_+1 | FAIL | 96.0% | 0.104 | 0.091 | 0.110 | 0.520 | 0.49 | 0 | 0.050 | 2 |
| dt_st_+2 | FAIL | 95.8% | 0.316 | 0.281 | 0.107 | 0.557 | 0.58 | 0 | 0.047 | 2 |
| dt_st_-1 | FAIL | 94.9% | 0.089 | 0.078 | 0.107 | 0.656 | 0.64 | 0 | 0.043 | 2 |
| dt_st_-2 | FAIL | 94.3% | 0.082 | 0.071 | 0.108 | 0.316 | 0.32 | 0 | 0.063 | 2 |

Log line: `NETWORK FAIL roads=22 pass=0 fail=22 hit=96.96 components=1`

## After

Same tool on `45cf8d7`. Network **FAIL**. 22 roads, 0 pass, 22 fail. Samples 563970. Hit rate 96.53% (before 96.96%). Components 1.

| Metric | Before | After | Limit |
|---|---:|---:|---:|
| Max along step | 0.500 m | 0.480 m | 0.020 m |
| Max across step | 13.700 m | 13.700 m | 0.030 m |
| Gap min / max | 0.002 / 30.885 m | -1.950 / 30.885 m | 0.000 to 0.050 m |
| Max edge drop with no barrier | 11.31 m | 13.61 m | 3.00 m |
| Cone fails | 188 / 8048 | 154 / 8010 | 0 |
| Junctions failing | 24 / 38 | 22 / 38 | 0 |

| Road | Status | Hit | Step along | Step across | Gap min | Gap max | Edge drop | Cone fails | Junction dev | Ends |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| us93_blue_lakes_s | FAIL | 93.4% | 0.077 | 0.510 | -0.019 | 0.740 | 0.72 | 1 | 0.326 | 0 |
| us93_south_approach | FAIL | 93.5% | 0.480 | 13.644 | -1.950 | 7.964 | 0.48 | 3 | 1.961 | 0 |
| us93_perrine_bridge | FAIL | 100.0% | 0.000 | 0.810 | 0.000 | 0.000 | 0.00 | 32 | 2.072 | 0 |
| us93_north | FAIL | 96.8% | 0.055 | 13.700 | 0.008 | 30.885 | 0.57 | 3 | 2.072 | 0 |
| blue_lakes_blvd_s | FAIL | 93.7% | 0.032 | 0.028 | 0.000 | 0.134 | 0.31 | 8 | 0.120 | 0 |
| addison_ave | FAIL | 99.7% | 0.156 | 0.198 | -0.015 | 0.594 | 7.96 | 21 | 0.120 | 0 |
| falls_ave | FAIL | 99.9% | 0.017 | 0.021 | -0.001 | 0.086 | 0.35 | 12 | 0.033 | 0 |
| pole_line_rd | FAIL | 99.9% | 0.021 | 0.020 | -0.003 | 0.096 | 0.49 | 12 | 0.056 | 0 |
| rim_road_south | FAIL | 93.6% | 0.121 | 0.701 | -0.010 | 0.971 | 1.67 | 16 | 0.432 | 1 |
| visitor_lot_access | FAIL | 100.0% | 0.047 | 0.025 | 0.015 | 0.523 | 0.93 | 0 | 0.320 | 1 |
| canyon_springs_rd | FAIL | 92.5% | 0.029 | 0.235 | -0.011 | 0.297 | 0.31 | 0 | 0.170 | 0 |
| canyon_springs_grade | FAIL | 92.7% | 0.021 | 0.116 | -0.009 | 1.016 | 13.61 | 44 | 0.170 | 1 |
| dt_av_+0 | FAIL | 92.7% | 0.181 | 0.167 | -0.005 | 0.185 | 0.30 | 0 | 0.069 | 1 |
| dt_av_+1 | FAIL | 93.0% | 0.112 | 0.109 | -0.001 | 0.202 | 0.14 | 1 | 0.095 | 2 |
| dt_av_+2 | FAIL | 92.7% | 0.090 | 0.085 | 0.000 | 0.169 | 0.20 | 0 | 0.038 | 1 |
| dt_av_-1 | FAIL | 93.7% | 0.094 | 0.088 | -0.002 | 0.111 | 0.20 | 0 | 0.058 | 2 |
| dt_av_-2 | FAIL | 93.8% | 0.065 | 0.062 | 0.001 | 0.090 | 0.33 | 0 | 0.035 | 2 |
| dt_st_+0 | FAIL | 97.1% | 0.105 | 0.093 | -0.004 | 0.115 | 0.16 | 0 | 0.044 | 1 |
| dt_st_+1 | FAIL | 95.8% | 0.114 | 0.101 | -0.002 | 0.123 | 0.21 | 1 | 0.038 | 2 |
| dt_st_+2 | FAIL | 95.8% | 0.304 | 0.264 | -0.002 | 0.285 | 0.26 | 0 | 0.069 | 2 |
| dt_st_-1 | FAIL | 95.1% | 0.099 | 0.088 | -0.003 | 0.134 | 0.18 | 0 | 0.058 | 2 |
| dt_st_-2 | FAIL | 95.0% | 0.092 | 0.081 | -0.003 | 0.141 | 0.07 | 0 | 0.095 | 2 |

Log line: `NETWORK FAIL roads=22 pass=0 fail=22 hit=96.53 components=1`

### Regressions

Before values are the RS-1 baseline on `d8f02c0`.

| Location | Before | After |
|---|---|---|
| dirt_cut_end | FAIL, seam -0.152 m at (1899.4, -1968.0), dt_av_-1 | FAIL, seam 0.000 m at (2445.0, -6757.0), canyon_springs_grade |
| float_skirt_3153 (3153.0, -6143.0) canyon_springs_rd | FAIL, gap -0.013 m, TerrainBody | FAIL, gap 0.003 m, TerrainBody |
| float_skirt_3218 (3218.0, -6368.0) rim_road_south | FAIL, gap 0.371 m, RoadBody | PASS, gap 0.009 m, RoadBody |
| float_skirt_3320 (3320.0, -6511.0) visitor_lot_access | FAIL, gap -0.000 m, TerrainBody | FAIL, gap -0.008 m, TerrainBody |
| raised_strip_3365 (3365.0, -6510.0) visitor_lot_access | FAIL, gap 0.721 m, step 0.000 m, RoadBody | FAIL, gap 0.463 m, step 0.000 m, RoadBody |
| guardrail_on_skirt (2873.9, -6653.8) canyon_springs_grade | FAIL, gap 26.111 m | FAIL, gap 22.593 m |
| jagged_junction (3356.8, -7034.0) | FAIL, dev 2.072 m, tilt 0.042 | FAIL, dev 2.072 m, tilt 0.042 |

Every road is still FAIL. Along step improved 0.500 m to 0.480 m. Across step is unchanged at 13.700 m. Gap min went from 0.002 m to -1.950 m. Unprotected edge drop went from 11.31 m to 13.61 m. Cone fails fell from 188 to 154. Junctions failing fell from 24 to 22.
