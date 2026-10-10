# Twin Falls terrain ground textures (CC0, 2K, tileable)
Path: /workspace/assets/handoffs/twin-falls-terrain/  ·  Built 2026-10-10 CT by the Asset Manager.
All sources from Poly Haven (api.polyhaven.com); licence page https://polyhaven.com/license states CC0 for all assets (checked 2026-10-10). The tf_* files are in-house colour/roughness grades of the CC0 sources (still CC0, no attribution needed; credit given anyway).

| Set | Use | Files (textures/) | Source | Author | Real tile | Suggested triplanar uv1_scale (world) |
|---|---|---|---|---|---|---|
| 1 Rim dirt | flat rim ground | dry_ground_01_{albedo,normal_gl,roughness,ao}_2k.jpg (albedo as-is, mean RGB 132/121/105 tan-grey) | https://polyhaven.com/a/dry_ground_01 | Rob Tuytel | 4.0 m | 0.25 |
| 2 Basalt | canyon walls, steep slopes | **tf_basalt_albedo_2k.jpg** (graded to near-black, mean 48/47/46) + rock_face_{normal_gl,roughness,ao}_2k.jpg; original rock_face_albedo kept for reference | https://polyhaven.com/a/rock_face | Greg Zaal (photo), Dario Barresi (processing) | 2.38 m | 0.42 true scale; 0.1667 (6 m) matches existing builds/twin_falls/materials/basalt_cliff.tres |
| 3 Talus/scree | cliff bases | **tf_talus_albedo_2k.jpg** (grey, mean 86/84/80) + rock_06_{normal_gl,roughness,ao}_2k.jpg | https://polyhaven.com/a/rock_06 | Rob Tuytel | 1.5 m | 0.667 (matches basalt_talus.tres; now 2K instead of 1K) |
| 4 Wet riverbank | river edge | **tf_wetbank_albedo_2k.jpg** (darkened, mean 68/64/57) + **tf_wetbank_roughness_2k.jpg** (×0.45, mean 0.38) + river_small_rocks_{normal_gl,ao}_2k.jpg | https://polyhaven.com/a/river_small_rocks | Rob Tuytel, Rico Cilliers | 2.9 m | 0.345 |

Consistency: sets 2 and 3 reuse the previous worker's sources (rock_face, rock_06). Their stock albedos are warm brown (means 97/70/50 and 126/97/70), not Snake River basalt, so I graded them to grey/near-black; the normals, roughness and AO are unchanged.

Tiling: Poly Haven textures are made to tile. Measured edge-wrap difference ÷ interior adjacent-pixel difference for each albedo is 0.98–1.10 (1.0 = seam not distinguishable from interior). rock_06 roughness reads 1.84, so it may show a faint seam at grazing angles. I didn't check tiling by eye in-engine.

Godot import (all): Compress Mode = VRAM Compressed, Mipmaps Generate = on, 3D detect off. Normals (*_normal_gl_*): Normal Map = Enable, invert Y off (they are OpenGL/+Y, which is what Godot expects). Roughness/AO: VRAM Compressed; pack into ORM if the shader wants it.
Import check: Godot 4.7.2 --headless --import on a temp copy (/tmp/assets-check/terrain): 20/20 .ctex produced, 0 errors in the log. Headless import doesn't test how they look on screen.

Preview: slope_blend_preview.jpg is a 2D numpy cross-fade (wet → dirt → talus → basalt, left to right, 4 tiles each). It is NOT a Godot triplanar render.
