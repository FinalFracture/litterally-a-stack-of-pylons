To: Developer. Subject: Twin Falls canyon DRESSING modules (sit on the lidar heightfield) + Perrine-lookalike bridge v2 (DRAFT)
DRESSING: /workspace/assets/builds/twin_falls/canyon_dressing/glb/ → res://Models/twin_falls/dressing/ (script make_canyon_dressing.py; shaders/ → res://shaders/)
- Every module: bottom-centre pivot at the face foot, front = -Z (toward the river), embeds 1.5 m below the pivot and 2.5 m back into the slope with side/back skirts (built to hide a 0-10° terrain mismatch; checked only in the test-heightfield renders). Collision is inside the glb (-colonly boxes; boulders use a -convcolonly hull); talus chunks, seep stain and seep growth have no collision. One mesh per variant; explicit _lod1/_lod2 glbs for each, and Godot auto-LOD is also left on.
- Placement guide (slope ° / height band / LOD0 tris / collision):
  tf_basalt_columns_l_15m  75-90 / lower colonnade, 10-20 m above toe or a ledge / 322 / 1 box
  tf_basalt_columns_m_8m   70-90 / lower colonnade bands / 102 / 1
  tf_basalt_columns_s_3m   60-90 / any face band, talus top / 120 / 1
  tf_basalt_flowband_20m   65-90 / mid-upper face, chain along X every 20 m (0.5 m overlap) / 832 / 1
  tf_basalt_ledge_8m       break of slope on 60-90 faces (walkable top) / 64 / 1
  tf_basalt_overhang_6m    60-90, under the rim lip / 94 / 1
  tf_talus_chunk_0..7      25-45 / cliff toe to river; MultiMesh at scale 0.3-2.5, random yaw / 16-22 / none
  tf_talus_patch_6m/12m    20-40 / talus aprons and benches / 252, 472 / 1
  tf_seep_stain_4x14       60-90 / lower half of the face, 0.15 m proud / 14 / none (dark glossy material)
  tf_seep_growth           0-35 / seep foot, benches, river springs / 200 / none
  tf_river_boulder_3m/5m   0-25 / waterline -1 to +3 m / 20 / convex hull
- Materials: tf_basalt_dressing (shaders/basalt_dressing.gdshader): near-black basalt in world triplanar (Poly Haven cliff_side CC0 luminance + a second-scale detail layer), vertex colour R = desert varnish, G = mineral/lichen streak, B = wet. Rendered column pixels read sRGB about 29/33/40 at noon. tf_seep_green, tf_seep_wet_stain. A cheap river shader (depth tint, 2 scrolling noise normals, fresnel) is in shaders/river_water.gdshader; it is optional.
- Budget (headless Vulkan, main pass with shadows off, full 1.2 km test scene: 857 dressing modules, 5,200 talus chunks, 1,800 sagebrush, bridge, lane MultiMesh): 73-83k tris and 36-47 draw calls for everything except the terrain. With 4-cascade shadows the counts are roughly 4x (all passes) — godot_budget_noshadow.log.
BRIDGE v2: /workspace/assets/builds/twin_falls/canyon_hero/glb/tf_perrine_lookalike_bridge_v2.glb (script canyon_hero/make_canyon_hero.py bridge2; materials canyon_hero/materials/*.tres + CC0 Poly Haven asphalt_02, concrete_wall_008, rust_coarse_01)
- Deck at 148.000 now runs to z ±252 (the rim edge in our test field; it was 21 m short). Abutment seats are on the cliff tops, and the approach slabs ramp from 148 to 149 over 40 m with trimesh collision. The arch is a truss: top and bottom chords, Warren web, lateral X-bracing, and spandrel columns. 5 expansion joints. 12 lamps per side.
- Colour: weathering (Cor-Ten-type) brown. The real bridge is unpainted Cor-Ten (ITD; SAH Archipedia). The member layout is ours, not a likeness.
- 6,728 tris, 6 draw calls, 10 collision shapes. Rays: lanes 148.000, walk 148.150, approach 148.500 / 148.975, deck underside 146.200 (godot_bridge_v2_check.log). Lane markings: road-kit rm_lane_broken_white_3p05 + rm_edge_line_white_3p66 as 2 MultiMeshes in the scene, not in the glb.
- The bridge ends assume the rim edge is at |z| 252 from the bridge centre. Move or trim the approaches to match the lidar rim.
Renders: /workspace/assets/builds/twin_falls/renders/v3/ (test heightfield, NOT the game terrain; slope-blended terrain set).
Not done: the cliff/talus rebuild was paused (canyon_hero/glb has the experimental full cliff modules; don't use them). The test terrain reads too pale (talus, dirt) — this is the terrain material, which gets tuned later. The dressing is sparse/patchy on the face.
