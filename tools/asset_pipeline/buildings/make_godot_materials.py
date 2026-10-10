"""Writes Godot StandardMaterial3D .tres for each building material slot. Intended res root: res://materials/buildings/
(textures under res://materials/buildings/tex/). Glb UVs are metres, so uv1_scale = 1 / real tile size."""
import os
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "materials"); R = "res://materials/buildings/tex/"
# slot: (polyhaven set, tile m, albedo tint)
PBR = {"brick_red": ("red_bricks_04", 2.5, "1,1,1"), "brick_buff": ("yellow_brick", 2.0, "1,1,1"),
       "stucco_tan": ("white_stucco", 2.0, "0.93,0.86,0.72"), "stone_limestone": ("white_sandstone_blocks_02", 2.0, "1,0.98,0.94"),
       "cmu_grey": ("concrete_block_wall", 2.0, "1,1,1"), "metal_panel": ("corrugated_iron_03", 2.0, "0.85,0.88,0.9"),
       "roof_membrane": ("concrete_floor_02", 2.0, "0.85,0.85,0.83"), "coping_concrete_alt": ("brushed_concrete_03", 2.0, "1,1,1")}
# trim-sheet slots: band index (0..7) -> sample the band centre along v; u runs along the metre UVs (1 m = 0.25 of the sheet)
TRIM = {"coping": 0, "canopy_fascia": 4, "trim_dark": 2, "door_dark": 3, "mullion_alu": 6, "sign_band": 5, "louvre_slat": 1}
def tres(name, body, exts):
    hdr = f'[gd_resource type="StandardMaterial3D" load_steps={len(exts)+1} format=3]\n\n'
    for i, p in enumerate(exts): hdr += f'[ext_resource type="Texture2D" path="{p}" id="{i+1}"]\n'
    open(os.path.join(OUT, name + ".tres"), "w").write(hdr + f'\n[resource]\nresource_name = "{name}"\n' + body)
for n, (s, t, tint) in PBR.items():
    k = 1 / t
    tres(n, f'albedo_color = Color({tint}, 1)\nalbedo_texture = ExtResource("1")\northogonal_note = 0\n'.replace('orthogonal_note = 0\n', '') +
         'orm_texture = ExtResource("2")\nnormal_enabled = true\nnormal_texture = ExtResource("3")\n'
         f'uv1_scale = Vector3({k:.4f}, {k:.4f}, 1)\ntexture_filter = 5\n',
         [f"{R}{s}_diff_1k.jpg", f"{R}{s}_arm_1k.jpg", f"{R}{s}_nor_gl_1k.jpg"])
for n, b in TRIM.items():
    v = 1 - (b + 0.5) / 8
    tres(n, 'albedo_texture = ExtResource("1")\norm_texture = ExtResource("2")\n'
         'texture_filter = 5\n',   # glbs now carry real trim UVs (make_buildings.py TRIM_BANDS, 2026-10-09)
         [f"{R}trim_sheet_albedo_1k.png", f"{R}trim_sheet_orm_1k.png"])
open(os.path.join(OUT, "door_red.tres"), "w").write('[gd_resource type="StandardMaterial3D" format=3]\n\n[resource]\nresource_name = "door_red"\nalbedo_color = Color(0.3, 0.015, 0.012, 1)\nroughness = 0.5\nmetallic = 0.1\n')
open(os.path.join(OUT, "glass_dark.tres"), "w").write('[gd_resource type="StandardMaterial3D" format=3]\n\n[resource]\nresource_name = "glass_dark"\n'
    'albedo_color = Color(0.03, 0.05, 0.07, 1)\nmetallic = 0.6\nmetallic_specular = 0.8\nroughness = 0.06\n')
# ORMMaterial3D would be the strict type; StandardMaterial3D with orm_texture is not valid -> rewrite header type
for f in os.listdir(OUT):
    p = os.path.join(OUT, f)
    if not f.endswith(".tres"): continue
    s = open(p).read()
    if "orm_texture" in s: open(p, "w").write(s.replace('type="StandardMaterial3D"', 'type="ORMMaterial3D"'))
print(sorted(os.listdir(OUT)))
