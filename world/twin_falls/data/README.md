# Twin Falls (TF-02) terrain data
Made by `../tools/tf_terrain.py` on 2026-10-10. Rerun: `python3 -m venv venv && venv/bin/pip install rasterio pyproj numpy pillow scipy scikit-image && venv/bin/python ../tools/tf_terrain.py --cache <dir>` (downloads ~985 MB of source GeoTIFFs into the cache; default `/workspace/cache-tf`). Runtime is about 20 s once the files are cached.

## Source
- **USGS 3DEP 1 m DEM**, project `ID_SouthernID_2018_D19` (lidar collected 2018; TNM publication date 2024-05-27), tiles `USGS_1M_11_x70y472`, `x70y473`, `x71y472`, `x71y473`, from
  `https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/1m/Projects/ID_SouthernID_2018_D19/TIFF/USGS_1M_11_<tile>_ID_SouthernID_2018_D19.tif`.
  Found with the TNM API: `https://tnmaccess.nationalmap.gov/api/v1/products?datasets=Digital%20Elevation%20Model%20(DEM)%201%20meter&bbox=-114.497,42.54,-114.436,42.6121`. Public domain. Source CRS is EPSG:26911 (NAD83 / UTM 11N) with NAVD88 metres.
- **Why 1 m:** the 1 m data covers the whole area with no gaps (the script checks this), so the 1/3 arc-second data was not needed.

## Grid and conventions
- **Bounds reading.** TF-02 is given in lat/lon, but the chunk grid has to be square in metres. I read it as a **5,000 x 8,000 m box aligned to the UTM 11N axes**, with its SW corner at the TF-02 SW corner (42.5400 N, 114.4970 W) rounded to whole metres: **E 705536, N 4712771** (42.5400000 N, -114.4970050 W). Because UTM 11N is about 1.7° off true north here, the NE corner sits about 230 m east of 114.4360 W. The bridge site, chunk ids and set-piece chunks all still land where the bible puts them.
- **Chunks:** 10 x 16 chunks of 500 m. cx 0-9 runs west to east and cz 0-15 runs south to north. Chunk (cx,cz) has its SW corner at x = 500·cx, z_north = 500·cz.
- **Axes:** x = east (UTM E − 705536). z_north = north (UTM N − 4712771). y = up. Following the bible's "+Z north (game −Z per engine convention)", the JSON files give both `z_north` and `godot_z = −z_north`.
- **Heights:** game y = DEM (NAVD88 m) − 958.
- **PNG tiles:** 16-bit grayscale. Row 0 is the north edge and column 0 is the west edge. Edge rows and columns are shared with neighbouring tiles.
  - **Encoding (fixed scale, the same for every tile):** `y = value × 0.01 − 50.0`, i.e. 1 cm steps covering y −50 to +605 m.
  - `tiles/c_<cx>_<cz>.png`: 129 x 129 samples at 3.90625 m spacing, 160 files.
  - `tiles_hi/c_<cx>_<cz>.png`: 513 x 513 samples at 0.9765625 m spacing, only for canyon chunks.
  - Each low-res tile is exactly every 4th sample of the high-res grid.
- **Resampling:** heights are interpolated bilinearly from the 1 m source onto points placed exactly on the grid corners. No reprojection was needed because the source is already EPSG:26911.

## Files
| File | Content | Size |
|---|---|---|
| tiles/ | 160 PNGs, 129² | 2.37 MB |
| tiles_hi/ | 35 PNGs, 513² | 6.52 MB |
| index.json | origin, grid, encoding, y offset, per-chunk min/max y | 13 KB |
| canyon_chunks.json | 35 chunks with reasons, relief, slopes | 7 KB |
| spawn.json | south-rim spawn | <1 KB |
| water.json | Snake River centreline, 211 vertices | 19 KB |
Total about 8.9 MB.

## Canyon chunks
A chunk is flagged if its **99th-percentile slope is over 45°** (slope computed on the 0.98 m grid) **or its relief is over 40 m**. I used the 99th percentile instead of the maximum because single pixels at buildings and road cuts reach very high slopes everywhere.
- 30 of the flagged chunks are the Snake River canyon (cz 11-15).
- 5 are south of the canyon: (6,0), (3,2), (2,3), (0,4), (1,4). These are flagged on slope only, with relief under 40 m. I have **not checked what they are**; my guess is canal banks, a quarry or a gully. Review them before building cliff meshes there.

## Spawn
- Spawn is at **x 3359.38, y 140.243, z_north 6546.88 (godot_z −6546.88)** in chunk (6,13). That is 42.5980008 N, -114.4537377 W, DEM 1098.19 m.
- How it was found:
  - The south abutment / rim is estimated as the first point, walking north along the bridge longitude (-114.4537), where the mean slope goes over 40°. That gives x 3371, z_north 6558, y 138.85.
  - The spawn is the nearest point to that rim with slope under 5° across a ~9 m window and 15-30 m from any slope over 30°. It ended up 15.2 m from the nearest steep cell.
- **Caveat:** the spot may be on the US-93 roadway or its approach fill. I did not check it against road or bridge geometry; move it onto the visitor-centre lot if needed.

## Water
- The Snake River surface is **APPROXIMATED**.
  - The centreline is a least-cost path through the lowest cells of the 3.9 m grid. 3DEP lidar is hydro-flattened, so DEM low points are the water surface as of 2018.
  - Heights are median-filtered and forced to never rise downstream.
  - The river enters at the east edge (x 5000, z_north 6770) and leaves through the **north edge near the NW corner** (x ≈ 94, z_north 8000). The last few vertices follow the map edge.
- Surface y is **−6.36 to −5.13** (DEM 951.6-952.9 m). No river width was derived, and NHD/OSM flowlines were not used.

## Checks run (by the script)
- 160 low-res tiles, each 129 x 129.
- Every shared edge between neighbouring tiles is identical: 0 mismatches. The same holds for high-res seams between flagged neighbours, and each high-res tile subsampled every 4th sample equals its low-res tile.
- No nodata inside the bounds.
- Heights checked: global DEM range is 951.6-1162.9 m. The water surface is about 952 m. The spawn rim is 1098 m.

## Differences from the bible (not resolved)
- **River height:** the bible's EPQS spot value is 958 m at the bridge. This DEM gives about 952-953 m (y ≈ −5.2), so the river is about 5 m below y = 0. The difference could come from the river stage in 2018 or from EPQS using a different source; not verified.
- **Rim height:** the bible gives a south rim of 1107 m at 42.5953. The rim edge found here at the bridge is about 1097 m, about 300 m further north.
- The task brief's "floor ~1000 m" does not match: the real floor is about 952 m.
