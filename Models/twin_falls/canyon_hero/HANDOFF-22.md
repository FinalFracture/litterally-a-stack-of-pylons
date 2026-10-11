# HANDOFF-22 — Perrine-lookalike bridge v3

Target: `res://Models/twin_falls/canyon_hero/tf_perrine_lookalike_bridge_v3.glb`
Source: `canyon_hero/glb/tf_perrine_lookalike_bridge_v3.glb` (build: `make_canyon_hero.py -- glb bridge3`, Blender 5.2.2)
v2 is kept unchanged.

## Origin
Origin = **water level**, bridge axis centre (bottom-centre style, same as v2 — v2 was already relative to water: deck at local y 148).
Lanes local y 148.00, walkway 148.15, deck soffit 146.20, approach slabs 148 -> 149 over 40 m.
Deck/abutments end at local z ±247.5 (landmarks.json: perrine N/S abutments at z -7053 / -6558 = 495 m apart, centre -6805.5); approaches end at ±287.5.

## Placement transform (Godot)
- position: **(3363.62, -5.24, -6805.5)**
- rotation: yaw **-1.7°** about +Y (as landmarks.json), scale 1
- Result: lanes y 142.76, walkway y 142.91, ends at the abutments.

Do NOT place at y 142.76 (landmarks.json `perrine_bridge` position / note "origin at deck centre" is wrong for this glb: that would put lanes at 290.76).
landmarks.json still references v2 and needs updating (model path + y -5.24) — not changed here.

## Stats
6680 tris, 6 surfaces/materials, 9 -colonly shapes (8 boxes + approach trimesh). Ray checks: all exact (see `../bridge_v3_check_blender.log`).
