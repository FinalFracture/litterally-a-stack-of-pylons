# HANDOFF-23 — Twin Falls street-name sign (MUTCD D3-1 style, no baked text)

Target: `res://Models/street_furniture/` →
- `tf_street_name_sign.glb` (LOD0, 224 tris, 4 materials = 4 draw calls)
- `tf_street_name_sign_lod1.glb` (56 tris, 2 draw calls; green blades without border, no anchors; suggest swap at ~60 m via visibility_range)
- `tf_street_name_blade.glb` (blade alone, 16 tris, 3 draw calls, pivot = blade bottom centre, no collision)

Source: `street_name_sign/make_street_name_sign.py` (`blender -b --factory-startup -P make_street_name_sign.py -- <out_dir>`, Blender 5.2.2). In-house, flat PBR factors as in `make_street_kit.py`: `galv_steel`, `sign_back_alu`, `sign_green_retro` (0,105,74), `sign_white_retro`. No textures.

## Geometry (Godot metres, pivot = bottom centre at the post axis, y up)
- Post: 2-3/8 in OD (60.4 mm) galvanized round, crossed bracket (collar, U-clamps on each blade edge, stem, cap). Top 2.85 m.
- Blade: 0.900 × 0.230 × 0.003 m, white 12.7 mm border; **green text face 0.8746 × 0.2046 m** per side (two-sided).
- Blade A: faces ±Z (front −Z), bottom **2.30 m**, centre 2.415. Blade B: faces ±X, crossed 90°, bottom 2.59, centre 2.705.
- Collision: `post-convcolonly` box 0.0604 × 2.27 × 0.0604 (post only; blades/bracket none). Note: the older kit signs are knockable (CE 2026-10-09, `*_breakaway.tscn`); if this one should be too, drop the box and wrap it like those.

## Text anchors (Node3D/empties in the glb, position in Godot m)
Each anchor's **+Z points out of its face, +Y up**, so a child Label3D with identity transform reads correctly.
| Name | Position | Faces |
|---|---|---|
| `TextAnchor_A_front` | (0, 2.415, −0.003) | −Z |
| `TextAnchor_A_back`  | (0, 2.415, +0.003) | +Z |
| `TextAnchor_B_front` | (−0.003, 2.705, 0) | −X |
| `TextAnchor_B_back`  | (+0.003, 2.705, 0) | +X |
Blade glb: `TextAnchor_front` (0, 0.115, −0.003), `TextAnchor_back` (0, 0.115, +0.003).

## Suggested Label3D
- Font: Overpass Bold (OFL 1.1, `street_furniture/_fonts/Overpass-Bold.ttf`; Highway-Gothic-inspired, not FHWA Series E(M)). Cap height = 0.70 em.
- **pixel_size 0.001, font_size 214** → 150 mm caps (MUTCD ~6 in on 8–9 in blades). Lowercase ≈ 113 mm.
- modulate white (245,245,240), outline_size 0, double_sided false (one Label3D per anchor), no_depth_test false, offset (0,0); billboard off; shaded off.
- Fit: face is 874 mm wide → about 8–9 mixed-case Overpass Bold characters at 150 mm (e.g. "Blue Lakes"). For longer names set `width = 860` with `autowrap_mode = off` and drop font_size (min ~171 = 120 mm caps), or use the abbreviation (St, Ave, Blvd).
- Note 150 mm caps on a 205 mm field leaves ~27 mm margin top/bottom; fine for caps + lowercase without descenders.

## Checks
Blender re-import: AABB 0.900 × 2.850 × 0.900, min y 0.000; anchor +Z normals verified (A ∓Z, B ∓X). Not measured in Godot (no Godot on the box).
Render: `../renders/tf_street_name_sign_person.png` (Blender EEVEE, next to a 1.8 m capsule).
