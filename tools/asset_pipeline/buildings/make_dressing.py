"""Core dressing (in-house): roof HVAC units, City Hall flagpole + entry steps, storefront sign panels. Asset Manager 2026-10-09.
blender -b --factory-startup --python make_dressing.py -- <out_dir>
Godot coords in comments (y up, front -Z). Pivot bottom-centre. Static pieces carry '<name>-col' on the collidable part only."""
import bpy, sys, os, json, math
OUT = sys.argv[sys.argv.index("--") + 1]; os.makedirs(OUT, exist_ok=True)
HERE = os.path.dirname(os.path.abspath(__file__))
def srgb(c): c = c / 255; return c / 12.92 if c <= 0.04045 else ((c + .055) / 1.055) ** 2.4
def mat(n, c, r=.7, m=0, tex=None):
    if n in bpy.data.materials: return bpy.data.materials[n]
    M = bpy.data.materials.new(n); M.use_nodes = True; b = M.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*[srgb(v) for v in c], 1); b.inputs["Roughness"].default_value = r; b.inputs["Metallic"].default_value = m
    if tex:
        t = M.node_tree.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(tex); M.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"])
    return M
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
def box(name, cx, y0, cz, sx, sy, sz, M):  # Godot coords -> Blender (x, -z, y)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(cx, -cz, y0 + sy / 2)); o = bpy.context.object
    o.scale = (sx, sz, sy); o.name = name; bpy.ops.object.transform_apply(scale=True); o.data.materials.append(M); return o
def cyl(name, cx, y0, cz, r, h, M, v=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=v, radius=r, depth=h, location=(cx, -cz, y0 + h / 2)); o = bpy.context.object
    o.name = name; o.data.materials.append(M); return o
def export(name, info):
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.data.objects if o.type == "MESH")
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB", export_yup=True)
    info.update(name=name, tris=tris); json.dump(info, open(os.path.join(OUT, name + ".log.json"), "w"), indent=1); print("DRESS", json.dumps(info))
# --- HVAC rooftop units (static, sit on roof decks; box collider)
for nm, (sx, sy, sz) in {"roof_hvac_small": (1.6, 1.0, 1.2), "roof_hvac_large": (2.5, 1.2, 1.5)}.items():
    reset(); metal = mat("hvac_metal", (186, 186, 180), .5, .3); dark = mat("hvac_grille", (40, 42, 44), .7, .2)
    b = box(nm + "-col", 0, 0.1, 0, sx, sy, sz, metal); box(nm + "_curb", 0, 0, 0, sx + .1, .1, sz + .1, dark)
    cyl(nm + "_fan", -sx * .2, .1 + sy, 0, min(sx, sz) * .3, .04, dark, 16)
    export(nm, {"collision": "'-col' box body (trimesh of 12 tris)", "pivot": "bottom-centre", "size_m": [sx + .1, sy + .14, sz + .1],
                "place": "on roof decks >= 1.5 m from the climb-face parapet so it does not block landings"})
# --- Roof hatch 0.9 x 1.2 (world bible 05) with a separate 'hatch' lid node (pivot on its back hinge edge) for the Developer to animate
reset(); metal = mat("hvac_metal", (186, 186, 180), .5, .3); dark = mat("hvac_grille", (40, 42, 44), .7, .2)
box("roof_hatch_curb-col", 0, 0, 0, 1.1, .3, 1.4, metal)
lid = box("hatch", 0, .3, 0, 1.0, .05, 1.3, dark); bpy.context.scene.cursor.location = (0, -0.65, .3); bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
export("roof_hatch_0p9x1p2", {"collision": "'-col' on the curb only; lid 'hatch' node has none (add a scene shape if it must block)", "pivot": "bottom-centre; lid origin on the +Z hinge edge",
       "opening_m": [0.9, 1.2], "place": "T2+ roofs, away from the landing edge (town-core roof caches)"})
# --- Flagpole (static; only the pole collides)
reset(); alu = mat("pole_alu", (200, 202, 204), .35, .9); gold = mat("finial_gold", (212, 175, 55), .3, 1)
conc = mat("base_concrete", (170, 166, 158), .9); flag = mat("flag_city", (255, 255, 255), .8, 0, os.path.join(HERE, "textures/signage/flag_city.png"))
cyl("flagpole-col", 0, 0, 0, .06, 10.0, alu, 10); cyl("flagpole_base", 0, 0, 0, .35, .3, conc, 12)
bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=6, radius=.1, location=(0, 0, 10.08)); bpy.context.object.data.materials.append(gold)
bpy.ops.mesh.primitive_plane_add(size=1, location=(0.8, 0, 9.35), rotation=(math.pi / 2, 0, 0)); f = bpy.context.object
f.scale = (1.5, 1.0, 1); f.name = "flag_cloth"; bpy.ops.object.transform_apply(scale=True); f.data.materials.append(flag)
export("cityhall_flagpole_10m", {"collision": "'-col' on the pole only (base and flag have no collider)", "pivot": "bottom-centre of pole",
       "place": "City Hall forecourt, e.g. (-8, 0.175, -17) in City Hall local coords", "flag": "in-house fictional city flag, no real emblem"})
# --- City Hall entry steps (static -col): 3 risers 0.15 from walk to an entry landing, 14 m wide
reset(); stone = mat("stone_limestone", (204, 196, 178), .85)
for i in range(3): box(f"cityhall_steps_{i}-col", 0, 0, 0.525 - .35 * (3 - i) / 2, 14.0, .15 * (i + 1), .35 * (3 - i), stone)
export("cityhall_entry_steps", {"collision": "'-col' boxes", "pivot": "bottom-centre", "size_m": [14.0, .45, 1.05],
       "caveat": "rises 3 x 0.15 to a 0.45 landing; needs the City Hall floor/plinth level confirmed (see README)"})
# --- Storefront sign panels (static dressing on sign bands; no collider: 0.02 thick, inside the 0.03 projection rule)
for s in sorted(os.listdir(os.path.join(HERE, "textures/signage"))):
    if not s.startswith("sign_"): continue
    reset(); n = s[:-4]; M = mat(n, (255, 255, 255), .6, 0, os.path.join(HERE, "textures/signage", s))
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0.0105, 0.3), rotation=(-math.pi / 2, math.pi, 0)); p = bpy.context.object
    p.scale = (4.8, 0.6, 1); bpy.ops.object.transform_apply(scale=True); p.data.materials.append(M); p.name = n
    box(n + "_back", 0, 0, 0.0, 4.8, .6, 0.02, mat("sign_back", (40, 40, 40), .7))
    export("storefront_" + n, {"collision": "none (0.02 m, sits on the sign band)", "pivot": "bottom-centre of the back face",
           "size_m": [4.8, 0.6, 0.02], "front": "-Z", "brand": "fictional, in-house, no real brands"})
