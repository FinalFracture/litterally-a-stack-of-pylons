"""Facade kit T0-T4, prefab tier buildings and strip-mall bays (in-house, scripted; Asset Manager).
blender -b --factory-startup --python make_buildings.py -- <out_dir> [groups: kit prefabs stripmall]
Coordinates are GODOT (x, y-up, z), front (street / climb face) = -Z; converted to Blender (x, -z, y), exported +Y up.
Everything is static -> one node '<name>-col' (Godot: mesh + StaticBody3D trimesh). Pivot = bottom-centre of the AABB.
UVs are in metres (1 UV unit = 1 m) so the Developer can apply 2-4 m brick/stucco/metal textures with uv1_scale = 1/tile.
Rules applied (world bible 02 s.10 / 05): storeys 3.1-4.5 m; climb-face parapets 0.5 m tall x 0.3 m thick; other faces 1.07 m
guard [REF IBC 1015 via 02]; landings >= 2.0 m (towers 2.5); rises <= 8 m per climb step (JD-12, still open); no projections
> 0.03 m over a stack pad. Strip mall per 05 s.1: 21.3 deep, 7.3 bay, canopy 3.0/3.6 over a 3.0 m walk, roof 5.5, front parapet
6.1, rear parapet 0.5."""
import bpy, bmesh, sys, os, json, math
args = sys.argv[sys.argv.index("--") + 1:]; OUT = args[0]; GROUPS = args[1:] or ["kit", "prefabs", "stripmall", "cityhall"]
os.makedirs(OUT, exist_ok=True)
def srgb(c): c = c / 255; return c / 12.92 if c <= 0.04045 else ((c + .055) / 1.055) ** 2.4
MATS = {  # name: (sRGB, roughness, metallic)  - flat factors, override freely
    "brick_red": ((150, 80, 62), .85, 0), "brick_buff": ((196, 172, 134), .85, 0), "stucco_tan": ((206, 192, 162), .9, 0),
    "metal_panel": ((138, 146, 152), .5, .3), "cmu_grey": ((160, 158, 150), .9, 0), "glass_dark": ((42, 58, 68), .08, .3),
    "mullion_alu": ((168, 170, 172), .4, .3), "coping": ((172, 169, 162), .8, 0), "roof_membrane": ((186, 186, 181), .85, 0),
    "door_dark": ((58, 60, 62), .5, .1), "sign_band": ((232, 230, 222), .5, 0), "canopy_fascia": ((226, 222, 214), .6, 0),
    "trim_dark": ((70, 70, 72), .6, 0), "stone_limestone": ((204, 196, 178), .85, 0), "louvre_dark": ((40, 40, 38), .8, 0),
    "louvre_slat": ((120, 116, 108), .7, 0), "clock_bezel": ((60, 58, 52), .5, .3), "clock_face": ((255, 255, 255), .6, 0)}
TEX = {"clock_face": "textures/clock_face_512.png"}
def make_mat(n):
    c, r, mt = MATS[n]; m = bpy.data.materials.new(n); m.use_nodes = True; m.use_backface_culling = True
    b = m.node_tree.nodes["Principled BSDF"]; b.inputs["Base Color"].default_value = (*[srgb(v) for v in c], 1)
    b.inputs["Roughness"].default_value = r; b.inputs["Metallic"].default_value = mt
    if n in TEX:
        t = m.node_tree.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(os.path.join(os.path.dirname(os.path.abspath(__file__)), TEX[n]))
        m.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"])
    return m

# ---- box lists: (mn, mx, mat, top_mat) in Godot coords
def B(x0, y0, z0, x1, y1, z1, m, top=None): return ((min(x0, x1), min(y0, y1), min(z0, z1)), (max(x0, x1), max(y0, y1), max(z0, z1)), m, top)
def place(boxes, rot=0, off=(0, 0, 0)):
    out = []; c, s = round(math.cos(math.radians(rot))), round(math.sin(math.radians(rot)))
    for mn, mx, m, t in boxes:
        pts = [(x * c + z * s, y, -x * s + z * c) for x in (mn[0], mx[0]) for y in (mn[1], mx[1]) for z in (mn[2], mx[2])]
        a = [min(p[i] for p in pts) for i in range(3)]; b = [max(p[i] for p in pts) for i in range(3)]
        out.append(B(a[0] + off[0], a[1] + off[1], a[2] + off[2], b[0] + off[0], b[1] + off[1], b[2] + off[2], m, t))
    return out

# ---- facade modules: W wide (x -W/2..W/2), wall 0.3 thick (z 0..0.3), front at z = 0
T = 0.3
def m_blank(h, mat, W=3.0): return [B(-W / 2, 0, 0, W / 2, h, T, mat)]
def m_window(h, mat, W=3.0, ww=1.5, wh=1.8, sill=0.9, glass="glass_dark"):
    x0, x1, y0, y1 = -ww / 2, ww / 2, sill, sill + wh; r = 0.12
    return [B(-W / 2, 0, 0, x0, h, T, mat), B(x1, 0, 0, W / 2, h, T, mat), B(x0, 0, 0, x1, y0, T, mat), B(x0, y1, 0, x1, h, T, mat),
            B(x0, y0, r, x1, y1, r + 0.04, glass), B(x0 - 0.02, y0 - 0.06, -0.03, x1 + 0.02, y0, r, "coping"),
            B(-0.03, y0, r - 0.01, 0.03, y1, r, "mullion_alu")]
def m_curtain(h, W=3.0):
    bx = [B(-W / 2, 0, 0.05, W / 2, h, 0.3, "glass_dark")]
    for x in (-W / 2, 0): bx.append(B(x, 0, 0.0, x + 0.08, h, 0.05, "mullion_alu"))
    bx.append(B(-W / 2, h - 0.25, 0.0, W / 2, h, 0.05, "mullion_alu")); return bx
def m_storefront(h, mat, W=3.0, door=False):
    bx = [B(-W / 2, 0, 0, -W / 2 + 0.25, h, T, mat), B(W / 2 - 0.25, 0, 0, W / 2, h, T, mat),
          B(-W / 2 + 0.25, 3.2, 0, W / 2 - 0.25, h, T, mat), B(-W / 2 + 0.25, 0, 0.1, W / 2 - 0.25, 0.45, T, "trim_dark", None)]
    bx += [B(-W / 2 + 0.25, 0.45, 0.15, W / 2 - 0.25, 3.2, 0.19, "glass_dark")]
    for x in (-W / 2 + 0.25, 0.0, W / 2 - 0.25): bx.append(B(x - 0.03, 0.0 if door else 0.45, 0.12, x + 0.03, 3.2, 0.15, "mullion_alu"))
    bx.append(B(-W / 2 + 0.25, 2.45, 0.12, W / 2 - 0.25, 2.51, 0.15, "mullion_alu"))
    if door:
        bx = [b for b in bx if not (b[2] == "trim_dark" and True)]
        bx += [B(-W / 2 + 0.25, 0, 0.1, -0.03, 0.45, T, "trim_dark"), B(0.03, 0, 0.14, W / 2 - 0.25, 2.45, 0.2, "door_dark"),
               B(0.6, 1.0, 0.11, 0.65, 1.15, 0.14, "mullion_alu")]
    return bx
def m_parapet(h, W=3.0, mat="coping"):  # top segment sits on the deck; coping 0.06
    return [B(-W / 2, 0, 0, W / 2, h - 0.06, T, mat), B(-W / 2, h - 0.06, 0, W / 2, h, T, "coping")]
def corner(h, mat): return [B(0, 0, 0, T, h, T, mat)]
def m_belfry(h, mat, W=3.0, ow=None, oh=None):
    """Louvred belfry opening: piers + lintel + sill, dark recess and horizontal slats."""
    ow = ow or min(3.0, W - 1.2); oh = oh or h - 1.0; x0, x1, y0, y1 = -ow / 2, ow / 2, 0.5, 0.5 + oh
    bx = [B(-W / 2, 0, 0, x0, h, T, mat), B(x1, 0, 0, W / 2, h, T, mat), B(x0, 0, 0, x1, y0, T, mat), B(x0, y1, 0, x1, h, T, mat),
          B(x0, y0, 0.25, x1, y1, T, "louvre_dark")]
    n = int(oh / 0.35)
    for i in range(n): bx.append(B(x0, y0 + 0.1 + i * 0.35, 0.08, x1, y0 + 0.18 + i * 0.35, 0.25, "louvre_slat"))
    return bx
def roof(x0, z0, x1, z1, y): return [B(x0, y - 0.3, z0, x1, y, z1, "roof_membrane", "roof_membrane")]

# ---- build + export
# trim-sheet bands (textures/trim/trim_sheet_layout.txt, band 0 = top row of the image)
TRIM_BANDS = {"coping": 0, "louvre_slat": 1, "trim_dark": 2, "door_dark": 3, "canopy_fascia": 4, "sign_band": 5, "mullion_alu": 6}
def build(name, boxes, anchors=None, extra=None, sub="kit", discs=()):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    names = sorted({b[2] for b in boxes} | {b[3] for b in boxes if b[3]} | {d[4] for d in discs} | {d[5] for d in discs}); idx = {n: i for i, n in enumerate(names)}
    bm = bmesh.new(); uvl = bm.loops.layers.uv.new("UVMap")
    for mn, mx, m, top in boxes:
        x0, y0, z0 = mn; x1, y1, z1 = mx
        V = lambda x, y, z: bm.verts.new((x, -z, y))
        quads = {"top": ([(x0, y1, z0), (x0, y1, z1), (x1, y1, z1), (x1, y1, z0)], 1),
                 "bot": ([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], 1),
                 "front": ([(x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (x1, y0, z0)], 2),
                 "back": ([(x1, y0, z1), (x1, y1, z1), (x0, y1, z1), (x0, y0, z1)], 2),
                 "left": ([(x0, y0, z1), (x0, y1, z1), (x0, y1, z0), (x0, y0, z0)], 0),
                 "right": ([(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], 0)}
        for k, (q, ax) in quads.items():
            if k == "bot" and y0 <= 0.001: continue
            mname = top if (k == "top" and top) else m
            f = bm.faces.new([V(*p) for p in q]); f.material_index = idx[mname]
            uvs = [(p[2], p[1]) if ax == 0 else (p[0], p[2]) if ax == 1 else (p[0], p[1]) for p in q]
            if mname in TRIM_BANDS:   # trim UVs (2026-10-09): u = metres / 4 along the run, v squeezed into the face's band
                b = TRIM_BANDS[mname]; lo, hi = 1 - (b + 1) / 8 + 0.008, 1 - b / 8 - 0.008
                vmin = min(v for _, v in uvs); vmax = max(v for _, v in uvs); sp = (vmax - vmin) or 1.0
                uvs = [(u * 0.25, lo + (v - vmin) / sp * (hi - lo)) for u, v in uvs]
            for l, uv in zip(f.loops, uvs): l[uvl].uv = uv
    for (cx_, cy_, cz_), facing, rad, dep, mface, mrim in discs:   # facing: '-z' '+z' '-x' '+x'; disc proud of the wall by dep
        n = 24; sgn = -1 if facing[0] == "-" else 1; ax = facing[1]
        flip = -1 if facing in ("-z", "+x") else 1                   # texture reads correctly from outside
        def P3(u, v, w): return (cx_ + u, cy_ + v, cz_ + sgn * w) if ax == "z" else (cx_ + sgn * w, cy_ + v, cz_ + u)
        uv_ = [(rad * math.cos(2 * math.pi * k / n), rad * math.sin(2 * math.pi * k / n)) for k in range(n)]
        vf = [bm.verts.new((lambda p: (p[0], -p[2], p[1]))(P3(u, v, dep))) for u, v in uv_]
        vb = [bm.verts.new((lambda p: (p[0], -p[2], p[1]))(P3(u, v, 0))) for u, v in uv_]
        out_b = (0, -sgn, 0) if ax == "z" else (sgn, 0, 0)            # outward normal in Blender coords
        f = bm.faces.new(vf); f.material_index = idx[mface]; f.normal_update()
        if f.normal.dot(__import__("mathutils").Vector(out_b)) < 0: f.normal_flip()
        for l in f.loops:
            k = vf.index(l.vert); u, v = uv_[k]; l[uvl].uv = (0.5 + flip * u / (2 * rad), 0.5 + v / (2 * rad))
        cen = __import__("mathutils").Vector((lambda p: (p[0], -p[2], p[1]))(P3(0, 0, dep / 2)))
        for k in range(n):
            q = bm.faces.new([vf[k], vb[k], vb[(k + 1) % n], vf[(k + 1) % n]]); q.material_index = idx[mrim]; q.normal_update()
            if q.normal.dot(q.calc_center_median() - cen) < 0: q.normal_flip()
            for l in q.loops: l[uvl].uv = (0, 0)
    bm.normal_update()
    # sanity: make every face point away from its box centre (winding above is hand-written; enforce)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:]) if False else None
    xs = [v.co.x for v in bm.verts]; ys = [v.co.y for v in bm.verts]; zs = [v.co.z for v in bm.verts]
    cx, cyb = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    for v in bm.verts: v.co.x -= cx; v.co.y -= cyb; v.co.z -= min(zs)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name); bm.to_mesh(me); tris = len(bm.faces); bm.free()
    for n in names: me.materials.append(make_mat(n))
    ob = bpy.data.objects.new(name + "-col", me); bpy.context.scene.collection.objects.link(ob)
    d = os.path.join(OUT, sub); os.makedirs(d, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(d, name + ".glb"), export_format="GLB", export_yup=True)
    gzc = -cyb
    log = {"name": name, "tris": tris, "materials": names,
           "size_godot_m": [round(max(xs) - min(xs), 3), round(max(zs) - min(zs), 3), round(max(ys) - min(ys), 3)],
           "pivot_shift_applied": [round(-cx, 4), 0, round(-gzc, 4)],
           "anchors": {k: [round(a[0] - cx, 3), round(a[1], 3), round(a[2] - gzc, 3)] for k, a in (anchors or {}).items()},
           "collision": "'-col' -> StaticBody3D trimesh of the visible mesh", "uv": "metres (1 UV = 1 m)"}
    if extra: log.update(extra)
    json.dump(log, open(os.path.join(d, name + ".log.json"), "w"), indent=1)
    print("BLD", json.dumps({"name": name, "tris": tris, "size": log["size_godot_m"]}))

# ---- kit
def kit():
    build("fk_storefront_g40", m_storefront(4.0, "brick_red"), extra={"module": "3.0 x 4.0 ground storefront"})
    build("fk_storefront_g45", m_storefront(4.5, "brick_red"), extra={"module": "3.0 x 4.5 ground storefront"})
    build("fk_entry_g40", m_storefront(4.0, "brick_red", door=True), extra={"module": "3.0 x 4.0 ground entry (door + sidelight)"})
    build("fk_entry_g45", m_storefront(4.5, "brick_red", door=True), extra={"module": "3.0 x 4.5 ground entry"})
    build("fk_window_g40", m_window(4.0, "brick_red", sill=1.0), extra={"module": "3.0 x 4.0 ground punched window"})
    build("fk_window_u35", m_window(3.5, "brick_red"), extra={"module": "3.0 x 3.5 upper punched window 1.5 x 1.8, sill 0.9"})
    build("fk_blank_g40", m_blank(4.0, "brick_red"), extra={"module": "3.0 x 4.0 blank"})
    build("fk_blank_u35", m_blank(3.5, "brick_red"), extra={"module": "3.0 x 3.5 blank"})
    build("fk_curtain_u35", m_curtain(3.5), extra={"module": "3.0 x 3.5 glass curtain wall (T4)"})
    build("fk_parapet_climb_0p5", m_parapet(0.5), extra={"module": "3.0 x 0.5 x 0.3 climb-face parapet (<= 0.5 tall, <= 0.3 thick)"})
    build("fk_parapet_guard_1p07", m_parapet(1.07), extra={"module": "3.0 x 1.07 x 0.3 guard parapet (non-climb faces)"})
    build("fk_corner_pier_3p5", corner(3.5, "brick_red"), extra={"module": "0.3 x 0.3 corner pier, 3.5 tall (also 4.0/4.5 via scale_y)"})
    build("fk_roof_slab_3x3", roof(-1.5, -1.5, 1.5, 1.5, 0.3), extra={"module": "3 x 3 x 0.3 roof slab (membrane top)"})

# ---- prefab tier buildings (assembled from the same modules)
def ring(nx, nz, storeys, mat, ground="storefront", front_ground=None, upper="window", x0=0.0, z0=0.0, base=0.0, climb="front", mwx=3.0, mwz=3.0, kinds=None):
    """Walls on a (3*nx + 0.6) x (3*nz + 0.6) footprint, front edge at z0, left edge at x0. storeys: list of heights.
    Returns boxes + the roof deck height."""
    bx = []; W, D = mwx * nx + 2 * T, mwz * nz + 2 * T; y = base
    for si, h in enumerate(storeys):
        g = si == 0
        def mod(face, k):
            mw = mwx if face in ("front", "back") else mwz
            if kinds: fn = kinds[si]
            elif g and face == "front": fn = (front_ground or ["storefront"] * nx)[k]
            elif g: fn = "blank" if k % 2 else "window"
            else: fn = upper
            if fn == "storefront": return m_storefront(h, mat, W=mw)
            if fn == "entry": return m_storefront(h, mat, W=mw, door=True)
            if fn == "window": return m_window(h, mat, W=mw, sill=1.0 if g else 0.9)
            if fn == "tallwindow": return m_window(h, mat, W=mw, ww=min(1.6, mw - 1.0), wh=h - 1.6, sill=0.9)
            if fn == "curtain": return m_curtain(h, W=mw)
            if fn == "belfry": return m_belfry(h, mat, W=mw)
            return m_blank(h, mat, W=mw)
        for k in range(nx):
            bx += place(mod("front", k), 0, (x0 + T + mwx / 2 + mwx * k, y, z0))
            bx += place(mod("back", k), 180, (x0 + T + mwx / 2 + mwx * k, y, z0 + D))
        for k in range(nz):
            bx += place(mod("side", k), 90, (x0, y, z0 + T + mwz / 2 + mwz * k))
            bx += place(mod("side", k), -90, (x0 + W, y, z0 + T + mwz / 2 + mwz * k))
        for cxz in ((x0, z0), (x0 + W - T, z0), (x0, z0 + D - T), (x0 + W - T, z0 + D - T)):
            bx += place(corner(h, mat), 0, (cxz[0], y, cxz[1]))
        y += h
    bx += roof(x0 + T, z0 + T, x0 + W - T, z0 + D - T, y)
    return bx, y, W, D
def parapets(x0, z0, W, D, y, climb_faces=("front",)):
    bx = []
    def run(face, L):   # CE 2026-10-09: climb faces are FLUSH (no parapet); 1.07 m guards on the other faces
        if face in climb_faces: return []
        hgt = 1.07
        return [B(0, 0, 0, L, hgt - 0.06, T, "coping"), B(0, hgt - 0.06, 0, L, hgt, T, "coping")]
    for b in run("front", W): bx += place([b], 0, (x0, y, z0))
    for b in run("back", W): bx += place([b], 0, (x0, y, z0 + D - T))
    for b in run("left", D - 2 * T): bx += place([b], -90, (x0 + T, y, z0 + T))
    for b in run("right", D - 2 * T): bx += place([b], -90, (x0 + W, y, z0 + T))
    return bx
def prefabs():
    # T0 kiosk: 3.6 x 3.0, parapet top 3.0 (T0 2.5-3.5)
    bx = [B(0, 0, 0, 3.6, 3.0, 3.0, "metal_panel", "roof_membrane"), B(0.4, 0, -0.02, 3.2, 2.2, 0.0, "glass_dark"),
          B(0.3, 2.3, -0.6, 3.3, 2.45, 0.0, "canopy_fascia")]   # small awning (T0 is itself the step; no pad under it)
    bx += parapets(0, 0, 3.6, 3.0, 2.7, climb_faces=("front", "back", "left", "right")) if False else \
          [B(0, 2.94, 0, 3.6, 3.0, 3.0, "coping")]   # CE 2026-10-09: flush deck at 3.0, coping band only
    build("bld_t0_kiosk", bx, anchors={"front_face_centre_ground": (1.8, 0, 0)}, extra={"tier": "T0", "deck_m": 3.0, "climb": "all faces flush", "note": "awning 2.3-2.45 m projects 0.6 m: not a stack pad face"}, sub="prefabs")
    # T1: 1 storey 4.0 + 0.5 climb parapet = 4.5 (02 table: T1 roof 4.5)
    bx, y, W, D = ring(4, 5, [4.5], "stucco_tan", front_ground=["storefront", "entry", "storefront", "storefront"])
    bx += parapets(0, 0, W, D, y)
    build("bld_t1_shop", bx, anchors={"front_face_centre_ground": (W / 2, 0, 0)}, extra={"tier": "T1", "deck_m": y, "climb_face": "front (-Z), flush", "rises_m": [y]}, sub="prefabs")
    # T2: 4.0 + 3.5 = 7.5 + 0.5 = 8.0
    bx, y, W, D = ring(4, 5, [4.5, 3.5], "brick_red", front_ground=["storefront", "storefront", "entry", "storefront"])
    bx += parapets(0, 0, W, D, y)
    build("bld_t2_mixed", bx, anchors={"front_face_centre_ground": (W / 2, 0, 0)}, extra={"tier": "T2", "deck_m": y, "climb_face": "front (-Z), flush", "rises_m": [y]}, sub="prefabs")
    # T3: podium (ground 4.5, projects 2.5 m, parapet top 5.0) + 2 upper storeys set back -> deck 11.5, parapet 12.0
    pod, yp, Wp, Dp = ring(5, 1, [4.5], "brick_buff", front_ground=["storefront", "storefront", "entry", "storefront", "storefront"])
    pod = [b for b in pod if not (b[2] == "roof_membrane")] + roof(T, T, Wp - T, Dp, yp)
    up, yu, Wu, Du = ring(5, 5, [4.5, 3.75, 3.75], "brick_buff", front_ground=["blank"] * 5, z0=Dp - T)
    bx = pod + [b for b in up if not (b[0][2] < Dp - T + 0.01 and b[1][1] <= 4.5 + 0.001)] + parapets(0, 0, Wp, Dp, yp, ("front", "back")) + \
         parapets(0, Dp - T, Wu, Du, yu)
    build("bld_t3_midrise", bx, anchors={"front_face_centre_ground": (Wp / 2, 0, 0), "podium_terrace_front_centre": (Wp / 2, yp, T)},
          extra={"tier": "T3", "podium_deck_m": yp, "terrace_depth_m": round(Dp - T, 2),
                 "deck_m": yu, "climb_face": "front (-Z), flush", "rises_m": [yp, round(yu - yp, 2)]}, sub="prefabs")
    # T4: podium 4.5 (proj 2.5) -> 2 storeys to deck 11.5 (setback terrace 2.5) -> 2 storeys curtain wall to deck 18.5, parapet 19.0
    pod, yp, Wp, Dp = ring(6, 1, [4.5], "metal_panel", front_ground=["storefront", "storefront", "entry", "entry", "storefront", "storefront"])
    pod = [b for b in pod if b[2] != "roof_membrane"] + roof(T, T, Wp - T, Dp, yp)
    mid, ym, Wm, Dm = ring(6, 6, [4.5, 3.75, 3.75], "metal_panel", front_ground=["blank"] * 6, z0=Dp - T)
    mid = [b for b in mid if not (b[0][2] < Dp - T + 0.01 and b[1][1] <= 4.5 + 0.001)]
    mid = [b for b in mid if b[2] != "roof_membrane"]
    top, yt, Wt, Dt = ring(6, 5, [3.5, 3.5], "metal_panel", upper="curtain", z0=Dp - T + 3.0 - T, base=ym)
    # T4 'top' ring storeys are upper storeys; front of the middle block's roof (3.0 - 0.3 deep terrace = 2.7 m) is the setback landing
    bx = pod + parapets(0, 0, Wp, Dp, yp, ("front", "back")) + mid + roof(T, Dp, Wm - T, Dp - T + 3.0, ym) + \
         [b for b in parapets(0, Dp - T, Wm, Dm, ym, ("front",)) if b[0][2] < Dp + 0.01] + top + parapets(0, Dp - T + 3.0 - T, Wt, Dt, yt)
    # roof under the top block: middle ring's deck behind the terrace
    bx += roof(T, Dp - T + 3.0, Wm - T, Dp - T + Dm - T, ym)
    build("bld_t4_office", bx, anchors={"front_face_centre_ground": (Wp / 2, 0, 0)},
          extra={"tier": "T4", "podium_deck_m": yp, "setback_deck_m": ym,
                 "setback_terrace_depth_m": 2.7, "deck_m": yt, "climb_face": "front (-Z), flush",
                 "rises_m": [yp, round(ym - yp, 2), round(yt - ym, 2)]}, sub="prefabs")

# ---- strip mall (bay 7.3 x 21.3 + 3.0 canopy over the walk)
BW, BD, DECK, PF, PR, CU, CT, CW = 7.3, 21.3, 5.5, 6.1, 6.0, 3.0, 3.6, 3.0
def strip_bay(variant):
    h = BW / 2; bx = []
    bx.append(B(-h, 0, T, h, DECK, BD, "stucco_tan", "roof_membrane"))                       # mass behind the front wall
    bx += [B(-h, 0, 0, -h + 0.45, CU, T, "stucco_tan"), B(h - 0.45, 0, 0, h, CU, T, "stucco_tan")]   # piers
    bx.append(B(-h, CU, 0, h, PF - 0.08, T, "stucco_tan")); bx.append(B(-h, PF - 0.08, 0, h, PF, T, "coping"))  # wall + front parapet
    bx.append(B(-h + 0.45, 0, 0.1, h - 0.45, 0.45, T, "trim_dark"))
    bx.append(B(-h + 0.45, 0.45, 0.15, h - 0.45, CU, 0.19, "glass_dark"))
    door_x = 1.2 if variant == "a" else -2.2
    bx.append(B(door_x, 0, 0.12, door_x + 1.0, 2.45, 0.2, "door_dark"))
    for x in (-h + 0.45, -1.6, 0.0, 1.6, h - 0.45, door_x, door_x + 1.0):
        bx.append(B(x - 0.03, 0.45 if not (door_x - 0.05 <= x <= door_x + 1.05) else 0.0, 0.11, x + 0.03, CU, 0.15, "mullion_alu"))
    bx.append(B(-h + 0.45, 2.45, 0.11, h - 0.45, 2.51, 0.15, "mullion_alu"))
    bx.append(B(-h + 0.6, 4.0, -0.02, h - 0.6, 5.0, 0.0, "sign_band"))                          # tenant sign band, 2 cm proud
    bx.append(B(-h, CU, -CW, h, CT, 0.0, "canopy_fascia", "roof_membrane"))                    # canopy
    bx.append(B(-h, 0, -CW, -h + 0.3, CU, -CW + 0.3, "canopy_fascia"))                          # canopy column (left edge)
    bx.append(B(-h, DECK - 0.06, BD - 0.25, h, DECK, BD, "coping"))   # CE 2026-10-09: rear climb edge flush at the deck (5.5)
    bx.append(B(-h + 1.0, 0, BD, -h + 2.0, 2.2, BD + 0.03, "door_dark"))                        # rear service door
    return bx
def strip_end(side):
    s = 1 if side == "right" else -1; h = BW / 2   # piece sits beyond x = s*h of the last bay; local x 0..0.3 outward
    bx = [B(0, 0, 0, T, DECK, BD, "stucco_tan"), B(0, DECK - 0.06, T, T, DECK, BD, "coping")]   # flush side edge (CE 2026-10-09)
    bx.append(B(0, DECK, 0, T, PF, T, "stucco_tan"))
    if side == "right": bx.append(B(0, 0, -CW, T, CU, -CW + T, "canopy_fascia"))
    bx.append(B(0, CU, -CW, T, CT, 0, "canopy_fascia", "roof_membrane"))
    return bx if s > 0 else place(bx, 180, (0, 0, BD - CW)) if False else [B(-b[1][0], b[0][1], b[0][2], -b[0][0], b[1][1], b[1][2], b[2], b[3]) for b in bx]
def stripmall():
    for v in ("a", "b"):
        build(f"strip_mall_bay_7p3_{v}", strip_bay(v), sub="stripmall",
              anchors={"storefront_line_left": (-BW / 2, 0, 0), "storefront_line_right": (BW / 2, 0, 0), "canopy_edge_centre": (0, CT, -CW),
                       "rear_wall_centre": (0, 0, BD)},
              extra={"bay_w_m": BW, "depth_m": BD, "covered_walk_m": CW, "canopy_underside_m": CU, "canopy_top_m": CT, "roof_deck_m": DECK,
                     "front_parapet_top_m": PF, "rear_edge": "flush at deck 5.5 (CE 2026-10-09)", "door": "right" if v == "a" else "left",
                     "tiling": "place bays at x = k * 7.3 (anchor storefront_line_* coincide); add strip_mall_end_left/right at the ends"})
    for sd in ("left", "right"):
        build(f"strip_mall_end_{sd}", strip_end(sd), sub="stripmall",
              anchors={"attach_storefront_line": (0, 0, 0)},
              extra={"thickness_m": T, "side_edge": "flush at deck 5.5",
                     "note": "attach_storefront_line meets the outer storefront_line_* of the end bay; right end adds the last canopy column"})
    # a 4-bay demo row (for renders / as a ready prefab): end_left + a b a b + end_right
    bx = []
    for k, v in enumerate("abab"): bx += place(strip_bay(v), 0, (BW / 2 + k * BW, 0, 0))
    bx += place(strip_end("left"), 0, (0, 0, 0)); bx += place(strip_end("right"), 0, (4 * BW, 0, 0))
    build("strip_mall_row_4bay", bx, sub="stripmall", anchors={"storefront_line_centre": (2 * BW, 0, 0), "canopy_edge_centre": (2 * BW, CT, -CW)},
          extra={"bays": 4, "length_m": 4 * BW + 2 * T})

# ---- City Hall + clock tower (world bible 06 TW-1; CE 2026-10-09): all TW-1 heights are walking surfaces, every climb (-Z)
# edge flush (no lips), 1.07 m guards on non-climb faces only -> rises 4.33 (from the 0.175 walk) / 7.5 / 8.0 / 8.0.
def rails(x0, z0, W, D, y, front_h, other_h, t=0.15, mat="stone_limestone"):
    bx = []
    def seg(h): return [] if h <= 0 else [B(0, 0, 0, 1, h - 0.06, t, mat), B(0, h - 0.06, 0, 1, h, t, "coping")]
    for b in seg(front_h): bx += [B(x0, y + b[0][1], z0, x0 + W, y + b[1][1], z0 + t, b[2])]
    for b in seg(other_h):
        bx += [B(x0, y + b[0][1], z0 + D - t, x0 + W, y + b[1][1], z0 + D, b[2]),
               B(x0, y + b[0][1], z0 + (t if front_h > 0 else 0), x0 + t, y + b[1][1], z0 + D - t, b[2]),
               B(x0 + W - t, y + b[0][1], z0 + (t if front_h > 0 else 0), x0 + W, y + b[1][1], z0 + D - t, b[2])]
    return bx
def cityhall():
    S = "stone_limestone"
    main, ym, Wm, Dm = ring(10, 8, [4.5, 3.75, 3.75], S, front_ground=["tallwindow"] * 3 + ["entry"] * 4 + ["tallwindow"] * 3,
                            x0=-15.0, z0=0.0, mwx=2.94, mwz=2.925)
    bx = main + rails(-15.0, 0.0, 30.0, 24.0, ym, 0.0, 1.07)
    # portico 12 x 4, deck top 4.5, six columns, flush front edge, guards on the two sides
    bx.append(B(-6.0, 3.9, -4.0, 6.0, 4.5, 0.0, S, "roof_membrane"))
    for x in (-5.25, -3.15, -1.05, 1.05, 3.15, 5.25): bx.append(B(x - 0.3, 0.0, -3.85, x + 0.3, 3.9, -3.25, S))
    bx.append(B(-6.0, 0.0, -4.0, 6.0, 0.15, 0.0, S, S))                                        # portico floor / step
    bx += [B(-6.0, 4.5, -4.0, -5.85, 5.51, 0.0, S), B(-6.0, 5.51, -4.0, -5.85, 5.57, 0.0, "coping"),
           B(5.85, 4.5, -4.0, 6.0, 5.51, 0.0, S), B(5.85, 5.51, -4.0, 6.0, 5.57, 0.0, "coping")]
    # tower lower shaft 11 x 11 centred on the main roof, 12.0 -> 20.0
    sh, ys, Ws, Ds = ring(3, 3, [4.0, 4.0], S, kinds=["tallwindow", "window"], x0=-5.5, z0=6.5, base=ym, mwx=(11 - 0.6) / 3, mwz=(11 - 0.6) / 3)
    bx += sh + rails(-5.5, 6.5, 11.0, 11.0, ys, 0.0, 1.07)
    # upper stage 5.7 x 5.7 (CE 2026-10-09: belfry deck clear depth >= 2.5 inside the 0.15 rails): belfry storey (louvres) +
    # clock storey -> gallery walking surface 28.0, flush on the climb face, 1.07 rails on the other 3 sides
    US = 5.7; ux0, uz0 = -US / 2, 6.5 + (11.0 - US) / 2
    st, yu, Wu, Du = ring(1, 1, [4.0, 4.0], S, kinds=["belfry", "blank"], x0=ux0, z0=uz0, base=ys, mwx=US - 0.6, mwz=US - 0.6)
    bx += st + rails(ux0, uz0, US, US, yu, 0.0, 1.07)
    cy = ys + 4.0 + 2.0
    discs = [((0, cy, uz0), "-z", 1.5, 0.02, "clock_face", "clock_bezel"), ((0, cy, uz0 + US), "+z", 1.5, 0.02, "clock_face", "clock_bezel"),
             ((ux0, cy, uz0 + US / 2), "-x", 1.5, 0.02, "clock_face", "clock_bezel"), ((-ux0, cy, uz0 + US / 2), "+x", 1.5, 0.02, "clock_face", "clock_bezel")]
    build("city_hall_tw1", bx, sub="cityhall", discs=discs,
          anchors={"portico_face_pad_centre": (0, 0, -4.0), "portico_deck_centre": (0, 4.5, -2.0), "main_roof_pad_at_tower": (0, ym, 6.0),
                   "belfry_deck_front_centre": (0, ys, 7.8), "gallery_centre_summit": (0, yu, 12.0), "clock_front_centre": (0, cy, uz0 - 0.02)},
          extra={"source": "world bible 06 TW-1", "portico": "12 x 4 m, deck 4.5", "main_block": "30 x 24 m, roof 12.0 (storeys 4.5/3.75/3.75)",
                 "tower": "shaft 11 x 11 to 20.0 (1.07 x 0.15 rails on 3 sides, 2.5 m clear inside them); upper stage 5.7 x 5.7 (2.65 m setback); gallery walking surface 28.0, flush climb edge, 1.07 rails on 3 sides",
                 "clock_faces": "4 x D 3.0 m, centre %.2f m" % cy, "rises_m_from_ground": [4.5, 7.5, 8.0, 8.0], "rise_from_0p175_walk_m": 4.325, "climb_face": "-Z (front); all climb edges flush (CE 2026-10-09)"})

if not globals().get("NO_MAIN"):
    for g in GROUPS: globals()[g]()
