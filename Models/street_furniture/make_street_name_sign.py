"""TF street-name sign (MUTCD D3-1 style) + blade alone. In-house, flat PBR factors like make_street_kit.py (no textures, NO baked text).
blender -b --factory-startup --python make_street_name_sign.py -- <out_dir>
Blender Z-up, front (blade A front) built facing Blender +Y = Godot -Z. Pivot bottom centre (post axis at ground).
Godot import suffix '-convcolonly' -> StaticBody3D + convex shape (post only)."""
import bpy, sys, os, json, math
from mathutils import Vector, Matrix
OUT = sys.argv[sys.argv.index("--") + 1]; os.makedirs(OUT, exist_ok=True)
def srgb(c): return tuple((x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in [v / 255 for v in c])
def mat(name, rgb, rough, metal=0.0):
    m = bpy.data.materials.get(name)
    if m: return m
    m = bpy.data.materials.new(name); m.use_nodes = True; b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*srgb(rgb), 1); b.inputs["Roughness"].default_value = rough; b.inputs["Metallic"].default_value = metal; return m
def box(name, size, loc, m):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc); o = bpy.context.active_object; o.name = name; o.scale = size
    bpy.ops.object.transform_apply(scale=True); o.data.materials.append(m); return o
def cyl(name, r, h, loc, m, verts=12, caps=True):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=loc, end_fill_type="NGON" if caps else "NOTHING")
    o = bpy.context.active_object; o.name = name; o.data.materials.append(m); bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35)); return o
def empty(name, loc, n):
    """Marker: Godot local +Z (Blender local -Y) = outward face normal n, Godot +Y (Blender +Z) = up; Label3D placed as child reads correctly."""
    n = Vector(n).normalized(); up = Vector((0, 0, 1)); y = -n; x = y.cross(up)
    M = Matrix((x, y, up)).transposed().to_4x4(); M.translation = loc
    e = bpy.data.objects.new(name, None); e.empty_display_type = "ARROWS"; e.empty_display_size = 0.1; bpy.context.scene.collection.objects.link(e); e.matrix_world = M; return e
def mats():
    return dict(galv=mat("galv_steel", (150, 152, 154), 0.45, 0.35), edge=mat("sign_back_alu", (170, 172, 174), 0.5, 0.35),
                green=mat("sign_green_retro", (0, 105, 74), 0.35), white=mat("sign_white_retro", (245, 245, 240), 0.35))
BW, BH, BT, BORDER = 0.900, 0.230, 0.003, 0.0127   # 1/2 in border [MUTCD D3-1 practice]
FW, FH = BW - 2 * BORDER, BH - 2 * BORDER
def blade(tag, cz, rotz, M, lod=0):
    """White retroreflective sheet over alu edge, green field 0.5 mm proud on both faces (two-sided blade)."""
    parts = [box(f"blade_{tag}_plate", (BW, BT, BH), (0, 0, cz), M["white"] if lod == 0 else M["green"])]
    if lod == 0:
        parts[0].data.materials.append(M["edge"])
        for p in parts[0].data.polygons:   # end/top/bottom faces -> alu edge
            if abs(p.normal.y) < 0.5: p.material_index = 1
        for s in (1, -1):
            bpy.ops.mesh.primitive_plane_add(size=1, location=(0, s * (BT / 2 + 0.0005), cz), rotation=(math.radians(90) * -s, 0, 0))
            f = bpy.context.active_object; f.name = f"blade_{tag}_field{'F' if s > 0 else 'B'}"; f.scale = (FW, FH, 1)
            bpy.ops.object.transform_apply(scale=True, rotation=True); f.data.materials.append(M["green"]); parts.append(f)
    for o in parts:
        o.matrix_world = Matrix.Rotation(rotz, 4, "Z") @ o.matrix_world
    return parts
def anchors(tag, cz, rotz):
    d = 0.0005 + BT / 2 + 0.001
    R = Matrix.Rotation(rotz, 3, "Z"); nf = R @ Vector((0, 1, 0))
    return [empty(f"TextAnchor_{tag}_front", Vector((0, 0, cz)) + nf * d, nf), empty(f"TextAnchor_{tag}_back", Vector((0, 0, cz)) - nf * d, -nf)]
def export(name, extra):
    vis = [o for o in bpy.data.objects if o.type == "MESH" and "colonly" not in o.name]
    tris = sum(len(p.vertices) - 2 for o in vis for p in o.data.polygons)
    mset = sorted({m.name for o in vis for m in o.data.materials})
    vs = [o.matrix_world @ v.co for o in vis for v in o.data.vertices]
    mn = [min(v[i] for v in vs) for i in range(3)]; mx = [max(v[i] for v in vs) for i in range(3)]
    an = {o.name: [round(o.matrix_world.translation.x, 4), round(o.matrix_world.translation.z, 4), round(-o.matrix_world.translation.y, 4)] for o in bpy.data.objects if o.type == "EMPTY"}
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB", use_selection=True, export_yup=True, export_apply=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, name + ".blend"), compress=True)
    log = dict(name=name, tris=tris, materials=mset, draw_calls=len(mset), aabb_godot_m=[round(mx[0] - mn[0], 4), round(mx[2] - mn[2], 4), round(mx[1] - mn[1], 4)],
               aabb_min_y=round(mn[2], 4), anchors_godot_m=an, **extra)
    json.dump(log, open(os.path.join(OUT, name + ".log.json"), "w"), indent=1); print("SNS", json.dumps(log))
POST_R, A_BOT, GAP = 0.0302, 2.30, 0.06     # 2-3/8 in OD galv round post; blade A bottom 2.30 m; 60 mm between blades
A_CZ = A_BOT + BH / 2; B_BOT = A_BOT + BH + GAP; B_CZ = B_BOT + BH / 2; TOP = B_BOT + BH + 0.03
def sign(lod):
    bpy.ops.wm.read_factory_settings(use_empty=True); M = mats()
    v = 12 if lod == 0 else 6
    cyl("post", POST_R, A_BOT - 0.03, (0, 0, (A_BOT - 0.03) / 2), M["galv"], v)
    if lod == 0:
        # crossed bracket: lower saddle under A, U-clamp channels on each blade edge, stem between blades, upper cap over B
        cyl("bracket_collar", 0.040, 0.10, (0, 0, A_BOT - 0.06), M["galv"], 12)
        for tag, bot, rz in (("A", A_BOT, 0.0), ("B", B_BOT, math.pi / 2)):
            for z in (bot - 0.012, bot + BH + 0.012):
                c = box(f"bracket_{tag}_clamp", (0.16, 0.024, 0.024), (0, 0, z), M["galv"]); c.matrix_world = Matrix.Rotation(rz, 4, "Z") @ c.matrix_world
        cyl("bracket_stem", 0.022, GAP, (0, 0, A_BOT + BH + GAP / 2), M["galv"], 8)
        cyl("bracket_cap", 0.03, 0.02, (0, 0, TOP - 0.01), M["galv"], 8)
    else:
        box("bracket_lod", (0.04, 0.04, TOP - A_BOT + 0.03), (0, 0, (TOP + A_BOT - 0.03) / 2), M["galv"])
    blade("A", A_CZ, 0.0, M, lod); blade("B", B_CZ, math.pi / 2, M, lod)
    if lod == 0: anchors("A", A_CZ, 0.0); anchors("B", B_CZ, math.pi / 2)
    s = 2 * POST_R; bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, (A_BOT - 0.03) / 2)); c = bpy.context.active_object
    c.name = "post-convcolonly"; c.scale = (s, s, A_BOT - 0.03); bpy.ops.object.transform_apply(scale=True)
    name = "tf_street_name_sign" + ("" if lod == 0 else "_lod1")
    export(name, dict(lod=lod, blade_face_m=[FW, FH], blade_m=[BW, BH, BT], blade_A_bottom_m=A_BOT, blade_A_centre_m=round(A_CZ, 4),
                      blade_B_bottom_m=round(B_BOT, 4), blade_B_centre_m=round(B_CZ, 4), top_m=round(TOP, 4), post="2-3/8 in OD round galv",
                      collision="post-convcolonly box %.4f x %.4f x %.4f (post only; blades none)" % (s, A_BOT - 0.03, s)))
def blade_only():
    bpy.ops.wm.read_factory_settings(use_empty=True); M = mats()
    blade("A", BH / 2, 0.0, M); anchors("A", BH / 2, 0.0)
    for o in bpy.data.objects:
        if o.type == "EMPTY": o.name = o.name.replace("_A_", "_")
    export("tf_street_name_blade", dict(blade_face_m=[FW, FH], blade_m=[BW, BH, BT], pivot="bottom centre of blade", collision="none"))
sign(0); sign(1); blade_only()
