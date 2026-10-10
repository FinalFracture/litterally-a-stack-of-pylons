"""In-house street-furniture kit (Asset Manager), scripted Blender hard-surface, flat PBR factors (style-guide §5/§9).
blender -b --factory-startup --python make_street_kit.py -- <out_root> <faces_dir> [items...]
items: speed_signs bus_shelter cobra_light bollard bench mutcd_signs traffic_signal   (default: the first five)
Conventions: metres, Blender Z-up -> glTF/Godot +Y up, forward = -Y in Blender (= +Z in Godot faces the camera side
"front"), pivot = base centre at ground unless the README says otherwise. Colliders are "<name>-convcolonly" boxes
(Godot import suffix -> StaticBody3D + 8-point ConvexPolygonShape3D). No textures except sign faces.
"""
import bpy, bmesh, sys, os, json, math
from mathutils import Vector, Matrix
a = sys.argv[sys.argv.index("--") + 1:]
OUT, FACES = a[0], a[1]
ITEMS = a[2:] or ["speed_signs", "bus_shelter", "cobra_light", "bollard", "bench"]
IN = 0.0254

def srgb(c):
    c = [x / 255.0 for x in c]  # inputs are 0-255 sRGB
    return tuple((x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c)
def mat(name, rgb, rough=0.6, metal=0.0, alpha=1.0, emit=None, tex=None):
    m = bpy.data.materials.get(name)
    if m: return m
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*srgb(rgb), 1.0)
    b.inputs["Roughness"].default_value = rough; b.inputs["Metallic"].default_value = metal
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
        m.surface_render_method = "BLENDED"
    if emit:
        b.inputs["Emission Color"].default_value = (*srgb(emit[0]), 1.0); b.inputs["Emission Strength"].default_value = emit[1]
    if tex:
        t = m.node_tree.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(tex)
        m.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"])
    return m

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def box(name, size, loc, m, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object; o.name = name; o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel > 0:
        bv = o.modifiers.new("b", "BEVEL"); bv.width = bevel; bv.segments = 2
        bpy.ops.object.modifier_apply(modifier="b")
    o.data.materials.append(m); return o

def cyl(name, r, h, loc, m, verts=16, r2=None, rot=None):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r if r2 is None else r2, depth=h, location=loc)
    o = bpy.context.active_object; o.name = name
    if rot: o.rotation_euler = rot; bpy.ops.object.transform_apply(rotation=True)
    o.data.materials.append(m)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35)); return o

def col(name, size, loc):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object; o.name = name + "-convcolonly"; o.scale = size
    bpy.ops.object.transform_apply(scale=True); return o

def _to_godot(v):  # Blender Z-up -> glTF/Godot Y-up
    return (v[0], v[2], -v[1])

def finish(name, _unused, folder, extra=None, mobile=False, mass=None, anchors=None, tscn=True):
    """Studio import standard (2026-10-09):
    * built facing Blender -Y, then turned 180 deg about Z so the front faces Blender +Y = glTF/Godot -Z (forward -Z)
    * pivot = bottom centre of the visible mesh bounds (XY centre, min Z)
    * static kit: the visible mesh is named '<name>-col' (Godot suffix -> mesh + StaticBody3D/trimesh from that mesh);
      the helper boxes are dropped
    * mobile props: no collision in the glb; the helper boxes become a scene-side PROPOSED .tscn with BoxShape3Ds + mass"""
    d = os.path.join(OUT, folder); os.makedirs(d, exist_ok=True)
    objs = [o for o in bpy.data.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    Rz = Matrix.Rotation(math.pi, 4, "Z")
    for o in objs: o.matrix_world = Rz @ o.matrix_world
    anchors = {k: Rz @ Vector(v) for k, v in (anchors or {}).items()}
    vis = [o for o in objs if not o.name.endswith("colonly")]
    boxes = [o for o in objs if o.name.endswith("colonly")]
    vs = [o.matrix_world @ v.co for o in vis for v in o.data.vertices]
    mn = Vector([min(v[i] for v in vs) for i in range(3)]); mx = Vector([max(v[i] for v in vs) for i in range(3)])
    off = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    for o in objs: o.matrix_world = Matrix.Translation(-off) @ o.matrix_world
    anchors = {k: v - off for k, v in anchors.items()}
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    shapes = []
    for b in boxes:
        bv = [v.co for v in b.data.vertices]
        bmn = Vector([min(v[i] for v in bv) for i in range(3)]); bmx = Vector([max(v[i] for v in bv) for i in range(3)])
        c = (bmn + bmx) / 2; sz = bmx - bmn
        shapes.append({"name": b.name.replace("-convcolonly", ""), "centre_godot": [round(x, 4) for x in _to_godot(c)],
                       "size_godot": [round(sz.x, 4), round(sz.z, 4), round(sz.y, 4)]})
        bpy.data.objects.remove(b)
    bpy.ops.object.select_all(action="DESELECT")
    for o in vis: o.select_set(True)
    bpy.context.view_layer.objects.active = vis[0]
    if len(vis) > 1: bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = name if mobile else name + "-col"
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    log = {"name": name, "tris": tris, "size_m_xyz_blender": [round(mx[i] - mn[i], 4) for i in range(3)],
           "pivot": "bottom centre of mesh bounds; front faces -Z (Godot)",
           "materials": [m.name for m in body.data.materials if m],
           "collision": (("none in glb (mobile); scene shapes in %s_collider_PROPOSED.tscn" % name) if tscn else "none in glb (knockable); scene shapes in %s_breakaway.tscn (make_sign_scenes.py)" % name) if mobile
                        else "'-col' on the visible mesh -> Godot StaticBody3D + trimesh of the render mesh",
           "anchors_godot_m": {k: [round(x, 4) for x in _to_godot(v)] for k, v in anchors.items()}}
    if mass: log["mass_kg"] = mass
    if mobile: log["proposed_scene_shapes"] = shapes
    if extra: log.update(extra)
    if mobile and tscn and shapes:
        L = ["[gd_scene load_steps=%d format=3]" % (len(shapes) + 1), "",
             "; PROPOSAL (Asset Manager), generated by make_street_kit.py; not wired into the game. The Developer owns the repo change.",
             "; Studio standard: mobile props keep collision in the scene. Instance %s.glb as a child 'Model' at the origin" % name,
             "; (glb pivot = bottom centre = this body's origin). Mass %s kg [see README for source]." % mass, ""]
        for i, sh in enumerate(shapes):
            L += ['[sub_resource type="BoxShape3D" id="Box_%d"]' % i, "size = Vector3(%.4f, %.4f, %.4f)" % tuple(sh["size_godot"]), ""]
        L += ['[node name="%s" type="RigidBody3D"]' % name, "mass = %s" % mass, ""]
        for i, sh in enumerate(shapes):
            L += ['[node name="Col_%s" type="CollisionShape3D" parent="."]' % sh["name"],
                  "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.4f, %.4f, %.4f)" % tuple(sh["centre_godot"]),
                  'shape = SubResource("Box_%d")' % i, ""]
        open(os.path.join(d, name + "_collider_PROPOSED.tscn"), "w").write("\n".join(L))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=os.path.join(d, name + ".glb"), export_format="GLB", use_selection=True,
                              export_yup=True, export_apply=True, export_image_format="AUTO")
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(d, name + ".blend"), compress=True)
    json.dump(log, open(os.path.join(d, name + ".log.json"), "w"), indent=2)
    print("KIT", json.dumps(log))

# ---------------------------------------------------------------- speed-limit signs (MUTCD R2-1, 24 x 30 in)
def speed_sign(speed):
    reset()
    W, H, T = 24 * IN, 30 * IN, 0.003                  # aluminium blank, 0.080 in ~ 2 mm (3 mm used)
    BOTTOM = 7 * 12 * IN                               # 7 ft to sign bottom (urban, pedestrians) [REF MUTCD 2A.18]
    post_m = mat("galv_steel", (150, 152, 154), 0.45, 0.35)
    back_m = mat("sign_back_alu", (170, 172, 174), 0.5, 0.35)
    face = os.path.join(FACES, f"r2-1_speed_{speed}_512x640.png")
    face_m = mat(f"r2-1_face_{speed}", (255, 255, 255), 0.35, 0.0, tex=face)
    # plate: back box + a UV-mapped face quad 0.5 mm in front (-Y is the front)
    box("plate", (W, T, H), (0, 0.004, BOTTOM + H / 2), back_m, bevel=0.0)
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0.004 - T / 2 - 0.0005, BOTTOM + H / 2), rotation=(math.radians(90), 0, 0))
    f = bpy.context.active_object; f.scale = (W, H, 1); bpy.ops.object.transform_apply(scale=True, rotation=True)
    f.data.materials.append(face_m)
    # plane UVs: default 0..1; make sure the image is upright when seen from -Y
    uv = f.data.uv_layers.active.data
    for poly in f.data.polygons:
        for li in poly.loop_indices:
            co = f.data.vertices[f.data.loops[li].vertex_index].co
            uv[li].uv = ((co.x / W) + 0.5, ((co.z - (BOTTOM + H / 2)) / H) + 0.5)
    # 2 in square perforated-tube post (no holes modelled), 25 mm behind the plate
    POST = 2 * IN; top = BOTTOM + H + 0.03
    box("post", (POST, POST, top), (0, 0.004 + T / 2 + POST / 2, top / 2), post_m)
    col("post", (POST, POST, top), (0, 0.004 + T / 2 + POST / 2, top / 2))
    col("plate", (W, 0.02, H), (0, 0.004, BOTTOM + H / 2))
    finish(f"sign_r2-1_speed_{speed}", None, "speed_limit_signs",
           {"panel_in": "24x30", "bottom_m": round(BOTTOM, 3), "post_top_m": round(top, 3), "knockable": "CE 2026-10-09; see *_breakaway.tscn",
            "mass_note": "post %.1f kg + plate %.2f kg" % (POST_KG, W * H * PLATE_KG_M2)},
           anchors={"post_axis_at_ground": (0, 0.004 + T / 2 + POST / 2, 0)}, mobile=True, mass=round(POST_KG + W * H * PLATE_KG_M2, 1), tscn=False)

# ---------------------------------------------------------------- bus shelter (CE spec: roof ~2.9 m; canopy edge 0.6 m behind curb face)
def bus_shelter():
    reset()
    L, D = 4.0, 2.0                                    # length 4.0, depth 2.0 [REF CE 05-asset-requests §1/§2]
    ROOF_TOP = 2.90; ROOF_T = 0.12; SETBACK = 0.60      # [REF CE spec 2026-10-09]
    # convention: Blender -Y = toward the street; origin on the curb-face line at walk level,
    # so the shelter occupies y in [SETBACK, SETBACK + D] (the canopy front edge is SETBACK behind the curb face)
    metal = mat("powder_coat_dark", (58, 62, 66), 0.55, 0.0)
    glass = mat("glass_tint", (200, 215, 220), 0.05, 0.0, alpha=0.25)
    seat_m = mat("bench_slat_alu", (120, 124, 128), 0.5, 0.3)
    ad = mat("ad_panel_lit", (225, 225, 215), 0.3, 0.0, emit=((240, 238, 225), 1.5))
    light = mat("canopy_led", (240, 240, 235), 0.3, 0.0, emit=((255, 250, 235), 3.0))
    y0, y1 = SETBACK, SETBACK + D
    # roof slab (overhangs posts by 0.1 m)
    box("roof", (L, D, ROOF_T), (0, (y0 + y1) / 2, ROOF_TOP - ROOF_T / 2), metal, bevel=0.01)
    # 4 posts 0.1 m square, inset 0.1 m
    for x in (-L / 2 + 0.15, L / 2 - 0.15):
        for y in (y0 + 0.15, y1 - 0.12):
            box("post", (0.1, 0.1, ROOF_TOP - ROOF_T), (x, y, (ROOF_TOP - ROOF_T) / 2), metal)
    # back glass wall (full length), 0.1 m gap at the ground, up to 2.3 m
    box("back_glass", (L - 0.3, 0.012, 2.2), (0, y1 - 0.12, 0.1 + 1.1), glass)
    box("back_rail", (L - 0.3, 0.06, 0.06), (0, y1 - 0.12, 2.33), metal)
    # one end: glass side panel; other end: lit ad panel (1.2 x 1.8 m, 0.15 deep, blank, no branding)
    box("side_glass", (0.012, D - 0.45, 2.2), (-L / 2 + 0.15, (y0 + y1) / 2 + 0.05, 1.2), glass)
    box("ad_frame", (0.16, 1.3, 1.95), (L / 2 - 0.15, (y0 + y1) / 2 + 0.05, 1.12), metal)
    box("ad_face_street", (0.005, 1.2, 1.8), (L / 2 - 0.15 - 0.081, (y0 + y1) / 2 + 0.05, 1.12), ad)
    box("ad_face_back", (0.005, 1.2, 1.8), (L / 2 - 0.15 + 0.081, (y0 + y1) / 2 + 0.05, 1.12), ad)
    # bench along the back wall: seat at 0.45 m, 2.4 m long
    box("bench_seat", (2.4, 0.38, 0.05), (-0.3, y1 - 0.38, 0.45), seat_m, bevel=0.01)
    for x in (-1.3, 0.7):
        box("bench_leg", (0.06, 0.3, 0.42), (x, y1 - 0.38, 0.21), metal)
    # LED strip under the roof front edge
    box("led", (L - 0.6, 0.06, 0.02), (0, y0 + 0.15, ROOF_TOP - ROOF_T - 0.01), light)
    # colliders: roof (walkable perch), posts, back wall, end panels, bench
    col("roof", (L, D, ROOF_T), (0, (y0 + y1) / 2, ROOF_TOP - ROOF_T / 2))
    for x in (-L / 2 + 0.15, L / 2 - 0.15):
        for y in (y0 + 0.15, y1 - 0.12):
            col("post", (0.1, 0.1, ROOF_TOP - ROOF_T), (x, y, (ROOF_TOP - ROOF_T) / 2))
    col("back_wall", (L - 0.3, 0.06, 2.3), (0, y1 - 0.12, 1.15))
    col("side_wall", (0.06, D - 0.45, 2.3), (-L / 2 + 0.15, (y0 + y1) / 2 + 0.05, 1.15))
    col("ad_panel", (0.16, 1.3, 2.05), (L / 2 - 0.15, (y0 + y1) / 2 + 0.05, 1.03))
    col("bench", (2.4, 0.38, 0.47), (-0.3, y1 - 0.38, 0.235))
    finish("bus_shelter", None, "bus_shelter",
           {"street_side": "front = -Z Godot; see anchors for the curb-face line",
            "roof_top_m": ROOF_TOP, "canopy_front_edge_from_curb_face_m": SETBACK, "length_m": L, "depth_m": D,
            "clear_height_under_roof_m": round(ROOF_TOP - ROOF_T, 3)},
           anchors={"curb_face_line_centre": (0, 0, 0), "canopy_front_edge_centre": (0, SETBACK, ROOF_TOP)})

# ---------------------------------------------------------------- cobra-head street light (9.1 m mounting)
def cobra_light():
    reset()
    galv = mat("galv_steel", (150, 152, 154), 0.45, 0.35)
    head_m = mat("luminaire_grey", (110, 114, 118), 0.5, 0.2)
    lens = mat("luminaire_lens", (235, 235, 225), 0.2, 0.0, emit=((255, 214, 150), 0.0))   # emission off by day; game drives it at night
    H = 9.1                                             # 30 ft mounting height [E typical US arterial]
    cyl("pole", 0.11, H, (0, 0, H / 2), galv, verts=12, r2=0.07)
    box("base_plate", (0.4, 0.4, 0.03), (0, 0, 0.015), galv)
    # mast arm: 2.4 m, rising slightly, toward -Y (street)
    arm_len = 2.4; tilt = math.radians(5)
    cyl("arm", 0.04, arm_len, (0, -arm_len / 2, H - 0.25 + math.sin(tilt) * arm_len / 2), galv, verts=8, rot=(math.radians(90) - tilt, 0, 0))  # (0,0,1)->(0,-cos t,+sin t): rises toward the street
    hx, hy, hz = 0, -arm_len - 0.26, H - 0.25 + math.sin(tilt) * arm_len
    box("head", (0.32, 0.72, 0.16), (hx, hy, hz), head_m, bevel=0.04)
    box("lens", (0.26, 0.5, 0.02), (hx, hy - 0.04, hz - 0.09), lens)
    col("pole", (0.22, 0.22, H), (0, 0, H / 2))
    finish("street_light_cobra_9m", None, "street_light_cobra",
           {"mounting_height_m": H, "arm_m": arm_len, "arm_direction": "toward the street = forward (-Z Godot)"},
           anchors={"pole_base_centre": (0, 0, 0)})

# ---------------------------------------------------------------- bollard (6 in steel pipe, 42 in)
def bollard():
    reset()
    y = mat("safety_yellow_paint", (222, 180, 30), 0.5, 0.0)   # saturated safety colour is allowed (style-guide §7)
    H, R = 42 * IN, 3.3 * IN                                  # 6.625 in OD pipe [REF ASTM pipe size 6]
    cyl("pipe", R, H, (0, 0, H / 2), y, verts=16)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=6, radius=R, location=(0, 0, H))
    s = bpy.context.active_object; s.scale = (1, 1, 0.45); bpy.ops.object.transform_apply(scale=True)
    s.data.materials.append(y); bpy.ops.object.shade_smooth()
    col("bollard", (2 * R, 2 * R, H + R * 0.45), (0, 0, (H + R * 0.45) / 2))
    finish("bollard_steel_42in", None, "bollard", {"height_m": round(H, 3), "diameter_m": round(2 * R, 3)})

# ---------------------------------------------------------------- bench with back (1.8 m, slats + steel ends)
def bench():
    reset()
    wood = mat("bench_wood_slat", (122, 92, 62), 0.7, 0.0)
    metal = mat("powder_coat_dark", (58, 62, 66), 0.55, 0.0)
    L = 1.8
    for i in range(4):                                   # seat slats, seat height 0.45 m
        box("seat", (L, 0.09, 0.035), (0, -0.2 + i * 0.105, 0.45), wood, bevel=0.006)
    for i in range(3):                                   # back slats, reclined 15 deg
        z = 0.575 + i * 0.105; yb = 0.17 + (z - 0.5) * math.tan(math.radians(15))
        o = box("back", (L, 0.035, 0.09), (0, yb, z), wood, bevel=0.006)
        o.rotation_euler = (math.radians(-15), 0, 0)
    for x in (-L / 2 + 0.12, L / 2 - 0.12):
        box("end_leg_f", (0.05, 0.05, 0.45), (x, -0.2, 0.225), metal)
        box("end_leg_b", (0.05, 0.05, 0.85), (x, 0.2, 0.425), metal)
        box("end_rail", (0.05, 0.46, 0.04), (x, 0.0, 0.42), metal)
    col("seat", (L, 0.45, 0.47), (0, 0.0, 0.235))
    col("back", (L, 0.1, 0.5), (0, 0.22, 0.7))
    finish("bench_slat_1800", None, "bench", {"seat_height_m": 0.45, "length_m": L}, mobile=True, mass=45)

# ---------------------------------------------------------------- MUTCD sign set (shaped plates, faces from mutcd_signs/make_faces_mutcd.py)
MUTCD_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mutcd_signs")
def shaped_plate(name, face_png, outline_uv, W, H, cz, face_m, back_m, y0=0.0, T=0.003, two_sided=False):
    """Plate in the XZ plane, front at -Y (y0 - T/2), centre (0, y0, cz). Front UV = outline UV (face texture);
    back gets the same texture mirrored if two_sided (street-name blades), else plain aluminium."""
    bm = bmesh.new(); uvl = bm.loops.layers.uv.new("UVMap")
    pts = [((u - 0.5) * W, (v - 0.5) * H + cz) for u, v in outline_uv]
    f = [bm.verts.new((x, y0 - T / 2, z)) for x, z in pts]; b = [bm.verts.new((x, y0 + T / 2, z)) for x, z in pts]
    ff = bm.faces.new(f[::-1]); ff.material_index = 0      # wound to face -Y
    fb = bm.faces.new(b); fb.material_index = 1 if not two_sided else 0
    n = len(pts)
    for i in range(n):
        s = bm.faces.new([f[i], f[(i + 1) % n], b[(i + 1) % n], b[i]]); s.material_index = 1
    bm.normal_update()
    for fc in (ff, fb):
        for l in fc.loops:
            x, z = l.vert.co.x, l.vert.co.z; u = x / W + 0.5; v = (z - cz) / H + 0.5
            l[uvl].uv = (u if fc is ff else 1 - u, v)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    me.materials.append(face_m); me.materials.append(back_m)
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o); return o

POST_KG = 9.0          # CE 2026-10-09: "post of about 9 kg" (2 in square perforated tube incl. hardware)
PLATE_KG_M2 = 5.48     # 0.080 in (2.03 mm) aluminium x 2.70 t/m3 [E: MUTCD 2A sheet-aluminium blanks]
def poly_area(pts): return abs(sum(pts[i][0] * pts[i - 1][1] - pts[i - 1][0] * pts[i][1] for i in range(len(pts)))) / 2
def mutcd_signs():
    O = json.load(open(os.path.join(MUTCD_DIR, "faces", "outlines.json")))
    BOTTOM = 7 * 12 * IN                     # 2.13 m to sign bottom (plan s.0, urban with pedestrians) [REF MUTCD 2A.18]
    POST = 2 * IN
    singles = [k for k in O if not k.startswith("d3-1")]
    for k in singles:
        reset(); d = O[k]
        post_m = mat("galv_steel", (150, 152, 154), 0.45, 0.35); back_m = mat("sign_back_alu", (170, 172, 174), 0.5, 0.35)
        face_m = mat(f"face_{k}", (255, 255, 255), 0.35, 0.0, tex=os.path.join(MUTCD_DIR, "faces", k + ".png"))
        cz = BOTTOM + d["h_m"] / 2
        shaped_plate("plate", None, d["outline_uv"], d["w_m"], d["h_m"], cz, face_m, back_m, y0=0.004)
        top = BOTTOM + d["h_m"] - (0.05 if d["kind"] in ("diamond", "octagon", "round", "shield") else 0.0) + 0.03
        top = max(top, BOTTOM + 0.6)
        box("post", (POST, POST, top), (0, 0.004 + 0.0015 + POST / 2, top / 2), post_m)
        col("post", (POST, POST, top), (0, 0.004 + 0.0015 + POST / 2, top / 2)); col("plate", (d["w_m"], 0.02, d["h_m"]), (0, 0.004, cz))
        pk = poly_area([(u * d["w_m"], v * d["h_m"]) for u, v in d["outline_uv"]]) * PLATE_KG_M2
        finish(f"sign_{k}", None, "mutcd_signs", {"panel": d["desc"], "panel_w_m": d["w_m"], "panel_h_m": d["h_m"],
               "bottom_m": round(BOTTOM, 3), "post_top_m": round(top, 3), "knockable": "CE 2026-10-09; see *_breakaway.tscn",
               "mass_note": "post %.1f kg + plate %.2f kg" % (POST_KG, pk)},
               anchors={"post_axis_at_ground": (0, 0.004 + 0.0015 + POST / 2, 0)}, mobile=True, mass=round(POST_KG + pk, 1), tscn=False)
    for a_, b_ in (("d3-1_main_st", "d3-1_oak_ave"), ("d3-1_1st_st", "d3-1_elm_st")):
        reset()
        post_m = mat("galv_steel", (150, 152, 154), 0.45, 0.35); edge_m = mat("sign_back_alu", (170, 172, 174), 0.5, 0.35)
        TOPP = 3.05; box("post", (POST, POST, TOPP), (0, 0, TOPP / 2), post_m)
        for i, k in enumerate((a_, b_)):
            d = O[k]; fm = mat(f"face_{k}", (255, 255, 255), 0.35, 0.0, tex=os.path.join(MUTCD_DIR, "faces", k + ".png"))
            cz = TOPP - 0.12 - i * 0.24
            o = shaped_plate(f"blade_{i}", None, d["outline_uv"], d["w_m"], d["h_m"], cz, fm, edge_m, two_sided=True)
            if i == 1: o.rotation_euler = (0, 0, math.radians(90))
        bpy.context.view_layer.objects.active = o; o.select_set(True)
        bpy.ops.object.transform_apply(rotation=True)
        bw, bh = O[a_]["w_m"], O[a_]["h_m"]
        col("post", (POST, POST, TOPP), (0, 0, TOPP / 2))
        col("blade_0", (bw, 0.02, bh), (0, 0, TOPP - 0.12)); col("blade_1", (0.02, bw, bh), (0, 0, TOPP - 0.36))
        pk = 2 * bw * bh * PLATE_KG_M2
        finish(f"sign_street_name_{a_[5:]}__{b_[5:]}", None, "mutcd_signs",
               {"panel": "2 x D3-1 36x8 in, two-sided, crossed at 90 deg (placeholder names)", "post_top_m": TOPP,
                "blade_bottoms_m": [round(TOPP - 0.12 - 0.1016, 3), round(TOPP - 0.36 - 0.1016, 3)],
                "knockable": "CE 2026-10-09; see *_breakaway.tscn", "mass_note": "post %.1f kg + 2 blades %.2f kg" % (POST_KG, pk)},
               anchors={"post_axis_at_ground": (0, 0, 0)}, mobile=True, mass=round(POST_KG + pk, 1), tscn=False)

# ---------------------------------------------------------------- traffic signal: mast-arm pole, 3-section heads, ped heads
def signal_finish(name, folder, groups, anchors, extra):
    """Like finish() but keeps named nodes: groups = [(node_name, [objs], parent_name|None)], first = static body ('-col')."""
    d = os.path.join(OUT, folder); os.makedirs(d, exist_ok=True)
    objs = [o for o in bpy.data.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    Rz = Matrix.Rotation(math.pi, 4, "Z")
    for o in objs: o.matrix_world = Rz @ o.matrix_world
    anchors = {k: Rz @ Vector(v) for k, v in anchors.items()}
    vs = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    mn = Vector([min(v[i] for v in vs) for i in range(3)]); mx = Vector([max(v[i] for v in vs) for i in range(3)])
    off = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    for o in objs: o.matrix_world = Matrix.Translation(-off) @ o.matrix_world
    anchors = {k: v - off for k, v in anchors.items()}
    bpy.ops.object.select_all(action="SELECT"); bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    made = {}; nodes = []
    for node, group, parent in groups:
        bpy.ops.object.select_all(action="DESELECT")
        for o in group: o.select_set(True)
        bpy.context.view_layer.objects.active = group[0]
        if len(group) > 1: bpy.ops.object.join()
        ob = bpy.context.view_layer.objects.active; ob.name = node; ob.data.name = node; made[node] = ob
        if parent: ob.parent = made[parent]
        nodes.append({"node": node, "parent": parent, "tris": sum(len(p.vertices) - 2 for p in ob.data.polygons)})
    tris = sum(n["tris"] for n in nodes)
    log = {"name": name, "tris": tris, "nodes": nodes, "size_m_xyz_blender": [round(mx[i] - mn[i], 4) for i in range(3)],
           "pivot": "bottom centre of mesh bounds; heads face -Z (Godot)",
           "collision": "'-col' on the pole + mast arm node only -> StaticBody3D trimesh; heads have none",
           "anchors_godot_m": {k: [round(x, 4) for x in _to_godot(v)] for k, v in anchors.items()}}
    log.update(extra)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=os.path.join(d, name + ".glb"), export_format="GLB", use_selection=True,
                              export_yup=True, export_apply=True, export_image_format="AUTO")
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(d, name + ".blend"), compress=True)
    json.dump(log, open(os.path.join(d, name + ".log.json"), "w"), indent=2)
    print("KIT", json.dumps(log))

def _cyl_open(name, r, h, loc, m, verts=12, rot=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=loc, end_fill_type="NOTHING")
    o = bpy.context.active_object; o.name = name
    if rot: o.rotation_euler = rot; bpy.ops.object.transform_apply(rotation=True)
    o.data.materials.append(m); return o

def traffic_signal_one(arm_len, head_x):
    reset()
    galv = mat("galv_steel", (150, 152, 154), 0.45, 0.35)
    housing = mat("signal_housing_black", (34, 36, 34), 0.55, 0.0)
    yel = mat("backplate_border_yellow", (230, 180, 30), 0.45, 0.0)
    lensc = {"red": (120, 18, 16), "yellow": (130, 90, 10), "green": (14, 90, 60)}      # 'off' look; Developer drives emission
    H_POLE, Z_ARM = 7.6, 6.4                          # pole 7.6 m (plan); arm centreline 6.4 m [E]
    static = [cyl("pole", 0.165, H_POLE, (0, 0, H_POLE / 2), galv, verts=16, r2=0.115),
              box("base_plate", (0.6, 0.6, 0.05), (0, 0, 0.025), galv),
              cyl("pole_cap", 0.12, 0.08, (0, 0, H_POLE + 0.04), galv, verts=12, r2=0.06),
              box("arm_clamp", (0.36, 0.36, 0.5), (0, 0, Z_ARM), galv)]
    rise = math.radians(1.5)
    # arm along Blender -X (= Godot +X after the 180 deg turn), tapered, rising slightly
    a = cyl("arm", 0.11, arm_len, (-arm_len / 2, 0, Z_ARM + math.sin(rise) * arm_len / 2), galv, verts=12, r2=0.065,
            rot=(0, math.radians(-90) - rise, 0))
    static.append(a)
    static.append(box("push_button", (0.1, 0.08, 0.16), (0, -0.2, 1.07), mat("button_box_black", (40, 40, 40), 0.5)))
    groups = [("traffic_signal_pole-col", static, None)]
    anchors = {"pole_axis_at_ground": (0, 0, 0), "arm_tip": (-arm_len, 0, Z_ARM + math.sin(rise) * arm_len)}
    LH, LW, LD = 1.07, 0.36, 0.30
    for i, hx in enumerate(head_x, 1):
        x = -hx; zarm = Z_ARM + math.sin(rise) * hx; ztop = zarm - 0.11 - 0.15; zc = ztop - LH / 2
        hn = f"signal_head_{i}"
        parts = [cyl(hn + "_hanger", 0.03, 0.2, (x, 0, ztop + 0.1), galv, verts=8),
                 box(hn + "_housing", (LW, LD, LH), (x, 0, zc), housing),
                 box(hn + "_backplate_y", (0.66, 0.012, 1.37), (x, LD / 2 + 0.01, zc), yel),
                 box(hn + "_backplate", (0.56, 0.014, 1.27), (x, LD / 2 + 0.005, zc), housing)]
        for k, (col_, dz) in enumerate((("red", 0.356), ("yellow", 0.0), ("green", -0.356))):
            parts.append(_cyl_open(hn + "_visor", 0.165, 0.22, (x, -LD / 2 - 0.11, zc + dz), housing, verts=10, rot=(math.radians(90), 0, 0)))
        groups.append((hn, parts, None))
        for col_, dz in (("red", 0.356), ("yellow", 0.0), ("green", -0.356)):
            lm = mat(f"lens_{col_}", lensc[col_], 0.15, 0.0, emit=(lensc[col_], 0.0))
            L = cyl(f"{hn}_{col_}", 0.15, 0.02, (x, -LD / 2 - 0.01, zc + dz), lm, verts=12, rot=(math.radians(90), 0, 0))
            groups.append((f"{hn}_{col_}", [L], hn))
        anchors[hn + "_bottom_centre"] = (x, 0, zc - LH / 2)
    # pedestrian heads on the pole: one facing -Y (front), one facing -X side; bottom 2.4 m [E; MUTCD 4E: 7-10 ft]
    hand_m = mat("ped_hand", (140, 70, 20), 0.2, 0.0, emit=((255, 120, 30), 0.0))
    walk_m = mat("ped_walk", (150, 150, 145), 0.2, 0.0, emit=((240, 240, 230), 0.0))
    for j, (dx, dy, rz) in enumerate(((0, -0.38, 0.0), (0.38, 0, math.radians(90))), 1):
        pn = f"ped_head_{j}"; zc = 2.4 + 0.23
        hb = box(pn + "_housing", (0.46, 0.25, 0.46), (0, 0, 0), housing)
        br = box(pn + "_bracket", (0.08, 0.22, 0.08), (0, 0.2, 0), galv)
        hand = box(pn + "_hand", (0.36, 0.01, 0.17), (0, -0.13, 0.1), hand_m)
        walk = box(pn + "_walk", (0.36, 0.01, 0.17), (0, -0.13, -0.1), walk_m)
        for o in (hb, br, hand, walk):
            o.matrix_world = Matrix.Translation((dx, dy, zc)) @ Matrix.Rotation(rz, 4, "Z") @ o.matrix_world
        groups.append((pn, [hb, br], None)); groups.append((pn + "_hand", [hand], pn)); groups.append((pn + "_walk", [walk], pn))
    name = f"traffic_signal_mast_{arm_len:.1f}".replace(".", "p")
    signal_finish(name, "traffic_signal", groups, anchors,
                  {"pole_m": H_POLE, "arm_m": arm_len, "arm_centre_height_m": Z_ARM, "heads": len(head_x),
                   "head_offsets_from_pole_m": head_x, "lens_d_m": 0.30,
                   "ped_heads": 2, "ped_head_bottom_m": 2.4, "push_button_height_m": 1.07})

def sign_breakaway_base():
    """Anchor sleeve + slip/shear stub left in the ground when a sign is knocked over. 0.1 m tall (<= 4 in stub
    [REF AASHTO breakaway stub-height limit, via FHWA]); no collision: vehicles and the stack ride over it."""
    reset(); galv = mat("galv_steel", (150, 152, 154), 0.45, 0.35); conc = mat("footing_concrete", (150, 147, 140), 0.85, 0.0)
    S = 2.5 * IN
    box("sleeve", (S, S, 0.1), (0, 0, 0.05), galv); box("footing_top", (0.3, 0.3, 0.012), (0, 0, 0.006), conc)
    finish("sign_breakaway_base", None, "mutcd_signs", {"stub_height_m": 0.1, "collision": "none (traversable stub)"},
           mobile=True, mass=0, anchors={"post_axis_at_ground": (0, 0, 0)}, tscn=False)

def traffic_signal():
    traffic_signal_one(9.1, [5.0, 8.4])
    traffic_signal_one(12.2, [5.0, 8.4, 11.6])

for it in ITEMS:
    if it == "speed_signs":
        for s in (10, 20, 25, 30, 35, 40): speed_sign(s)
    else:
        globals()[it]()
