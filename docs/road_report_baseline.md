# Road report baseline

Measure only. Thresholds from the Road System Spec acceptance table. Deck and bridge samples are exempt from the terrain-gap test because the stamp is skipped under them. Along step is the 1 m slope break, so a steady grade is not counted as a lip. Across step subtracts the design crown and bank.

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

## Regressions

- **FAIL** dirt_cut_end. dirt-cut road end at (1899.4, -1968.0). road dt_av_-1, seam -0.152 m
- **FAIL** float_skirt_3153. float and skirts at (3153.0, -6143.0). road canyon_springs_rd, gap -0.013 m, hit TerrainBody
- **FAIL** float_skirt_3218. float and skirts at (3218.0, -6368.0). road rim_road_south, gap 0.371 m, hit RoadBody
- **FAIL** float_skirt_3320. float and skirts at (3320.0, -6511.0). road visitor_lot_access, gap -0.000 m, hit TerrainBody
- **FAIL** raised_strip_3365. raised strip at (3365.0, -6510.0). road visitor_lot_access, gap 0.721 m, step 0.000 m, hit RoadBody
- **FAIL** guardrail_on_skirt. guardrail on a skirt at (2873.9, -6653.8). road canyon_springs_grade, gap 26.111 m
- **FAIL** jagged_junction. jagged junction blob at (3356.8, -7034.0). dev 2.072 m tilt 0.042

## Worst locations

- us93_north gap at (3346.7, -7132.7) value 30.404 limit 0.050
- us93_north gap at (3346.8, -7126.7) value 30.546 limit 0.050
- us93_north gap at (3346.8, -7131.7) value 30.523 limit 0.050
- us93_north gap at (3346.6, -7132.7) value 30.616 limit 0.050
- us93_north gap at (3346.6, -7137.7) value 30.719 limit 0.050
- us93_north gap at (3346.4, -7137.7) value 30.885 limit 0.050
- us93_north gap at (3346.8, -7130.7) value 30.522 limit 0.050
- us93_north gap at (3346.8, -7124.7) value 30.382 limit 0.050
- us93_north gap at (3346.7, -7130.7) value 30.702 limit 0.050
- us93_north gap at (3346.7, -7127.7) value 30.398 limit 0.050
