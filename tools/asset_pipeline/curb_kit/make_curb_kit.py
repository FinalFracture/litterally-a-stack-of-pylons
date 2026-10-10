"""Curb / gutter / ramp / driveway / median kit (in-house, scripted). Run:
  blender -b --factory-startup --python make_curb_kit.py -- <out_dir>
Coordinates below are GODOT (x, y-up, z); road side = -Z. Converted to Blender as (x, -z, y), exported glTF +Y up.
Section (05 / plan s.0): 0.15 m barrier curb, 0.6 m gutter; piece bottom y 0, road + gutter top y 0.025, curb/walk top y 0.175.
Curb pieces carry a 2.44 m walk band behind the curb face (so ramps/driveways tile with straights); the walk falls 1.5 %\ntoward the curb (CE 2026-10-09): y 0.175 at the curb face, 0.2116 at the back of the band.
Static -> node '<piece>-col' (Godot: visible mesh + StaticBody3D trimesh). Pivot: bottom-centre of the AABB. Anchors -> <piece>.log.json."""
import bpy, bmesh, sys, os, json, math
OUT = sys.argv[sys.argv.index("--") + 1]; os.makedirs(OUT, exist_ok=True)
HERE = os.path.dirname(os.path.abspath(__file__))
G0, G, T = 0.0, 0.025, 0.175          # bottom, road/gutter top, curb/walk top
GW, CT, BAND = 0.6, 0.15, 2.44        # gutter width, curb top width (median), walk band behind curb face
TILE = 2.1                            # concrete UV tile (gravel_concrete_03 published 2.1 m)
XS = 0.015                            # CE 2026-10-09: walk cross slope <= 2 %, falling toward the curb -> 1.5 % design value
TB = T + XS * BAND                    # back edge of the walk band: 0.2116
def WY(s): return T + XS * s          # walk top at distance s behind the curb face

def srgb(c): c = c / 255; return c / 12.92 if c <= 0.04045 else ((c + .055) / 1.055) ** 2.4
def mat(name, rgb, rough=0.85, tex=None):
    m = bpy.data.materials.new(name); m.use_nodes = True; m.use_backface_culling = True; b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*[srgb(v) for v in rgb], 1); b.inputs["Roughness"].default_value = rough
    if tex:
        t = m.node_tree.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(tex)
        m.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"])
    return m

class Piece:
    def __init__(s, name): s.name = name; s.faces = []; s.over = []; s.anchors = {}
    def f(s, pts, mi=0): s.faces.append((pts, mi))          # shell face (closed solid incl. bottom)
    def o(s, pts, mi, uvs): s.over.append((pts, mi, uvs))     # overlay face (not in shell), explicit uvs

def build(p, mats, smooth_angle=None):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    M = [mat(*m) for m in mats]
    bm = bmesh.new(); vmap = {}
    def V(q):
        k = tuple(round(c, 4) for c in q)
        if k not in vmap: vmap[k] = bm.verts.new((q[0], -q[2], q[1]))
        return vmap[k]
    for pts, mi in p.faces:
        vs = []
        for q in pts:
            v = V(q)
            if not vs or vs[-1] is not v: vs.append(v)
        if len(vs) > 1 and vs[0] is vs[-1]: vs.pop()
        if len(vs) < 3: continue
        try: fc = bm.faces.new(vs); fc.material_index = mi
        except ValueError: pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()
    bmesh.ops.delete(bm, geom=[fc for fc in bm.faces if all(abs(v.co.z) < 1e-6 for v in fc.verts) and fc.normal.z < -0.9], context="FACES")
    shell_n = len(bm.faces)
    uvl = bm.loops.layers.uv.new("UVMap")
    for fc in bm.faces:
        n = fc.normal; ax = max(range(3), key=lambda i: abs(n[i]))
        for l in fc.loops:
            x, by, z = l.vert.co; gx, gy, gz = x, z, -by
            l[uvl].uv = ((gx, gz) if ax == 2 else (gz, gy) if ax == 0 else (gx, gy))
            l[uvl].uv = (l[uvl].uv[0] / TILE, l[uvl].uv[1] / TILE)
    for pts, mi, uvs in p.over:
        vs = [bm.verts.new((q[0], -q[2], q[1])) for q in pts]; fc = bm.faces.new(vs); fc.material_index = mi
        for l, uv in zip(fc.loops, uvs): l[uvl].uv = uv
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    # recentre XZ on the AABB, keep y min 0
    xs = [v.co.x for v in bm.verts]; ys = [v.co.y for v in bm.verts]; zs = [v.co.z for v in bm.verts]
    cx, cyb = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2; gzc = -cyb
    for v in bm.verts: v.co.x -= cx; v.co.y -= cyb; v.co.z -= min(zs)
    me = bpy.data.meshes.new(p.name); bm.to_mesh(me); tris = len(bm.faces); bm.free()
    for m in M: me.materials.append(m)
    if smooth_angle:
        me.shade_smooth(); me.set_sharp_from_angle(angle=math.radians(smooth_angle))
    ob = bpy.data.objects.new(p.name + "-col", me); bpy.context.scene.collection.objects.link(ob)
    out = os.path.join(OUT, p.name + ".glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True, export_image_format="AUTO")
    anchors = {k: {"pos": [round(a[0] - cx, 4), round(a[1], 4), round(a[2] - gzc, 4)], "dir": a[3]} for k, a in p.anchors.items()}
    log = {"name": p.name, "tris": tris, "materials": [m[0] for m in mats],
           "size_godot_m": [round(max(xs) - min(xs), 4), round(max(zs) - min(zs), 4), round(max(ys) - min(ys), 4)],
           "pivot_shift_applied": [round(-cx, 4), 0, round(-gzc, 4)], "anchors": anchors,
           "collision": "'-col' -> StaticBody3D trimesh of the visible mesh"}
    json.dump(log, open(os.path.join(OUT, p.name + ".log.json"), "w"), indent=1)
    print("PIECE", json.dumps({"name": p.name, "tris": tris, "size": log["size_godot_m"]}))

# ---------- sweeps ----------
def sweep(p, prof, mis, place, n_st, cap_mi=0):
    """prof: closed list of (s, y); mis[k] material of edge k->k+1; place(i, s) -> (x, z)."""
    P = lambda i, k: (place(i, prof[k][0])[0], prof[k][1], place(i, prof[k][0])[1])
    K = len(prof)
    for i in range(n_st - 1):
        for k in range(K):
            k2 = (k + 1) % K
            p.f([P(i, k), P(i, k2), P(i + 1, k2), P(i + 1, k)], mis[k])
    p.f([P(0, k) for k in range(K)], cap_mi); p.f([P(n_st - 1, k) for k in range(K)][::-1], cap_mi)

CURB_PROF = [(-GW, G0), (-GW, G), (0.0, G), (0.0, T), (BAND, TB), (BAND, G0)]   # s: + = behind curb face
CURB_MATS = [("concrete_curb", (150, 147, 140))]

def curb_straight(L=3.66):
    p = Piece("curb_straight_3p66")
    sweep(p, CURB_PROF, [0] * 6, lambda i, s: ((-L / 2, L / 2)[i], s), 2)
    p.anchors = {"port_w": (-L / 2, G, 0.0, [-1, 0, 0]), "port_e": (L / 2, G, 0.0, [1, 0, 0])}
    build(p, CURB_MATS); return p

def curb_return(R, seg):
    tag = f"{R:.1f}".replace(".", "p"); p = Piece(f"curb_return_r{tag}")
    def place(i, s):
        th = math.radians(-90 + 90 * i / seg); r = R - s
        return (r * math.cos(th), r * math.sin(th))
    sweep(p, CURB_PROF, [0] * 6, place, seg + 1)
    p.anchors = {"port_start_curbface": (0.0, G, -R, [-1, 0, 0]), "port_end_curbface": (R, G, 0.0, [0, 0, 1]),
                 "arc_centre": (0.0, G, 0.0, None)}
    build(p, CURB_MATS, smooth_angle=30); return p

def curb_ramp(name, half, wing, run, panel=True):
    """Perpendicular curb ramp (CE 2026-10-09): opening |x| <= half (>= 1.22 m wide) flush with the gutter at the curb line,
    ramp rises at <= 1:12 to meet the 1.5 %-sloped walk at s = run; flared side wings (<= 1:10 along the curb);
    0.61 m detectable warning panel at the bottom. Behind the ramp the walk band continues to BAND."""
    p = Piece(name); X = half + wing; xs = [-X, -half, half, X]; yr = WY(run)
    for a, b in zip(xs, xs[1:]): p.f([(a, G, -GW), (b, G, -GW), (b, G, 0), (a, G, 0)])
    p.f([(-half, G, 0), (half, G, 0), (half, yr, run), (-half, yr, run)])
    for sg in (1, -1):
        a, b = sg * half, sg * X
        p.f([(a, G, 0), (b, T, 0), (a, yr, run)]); p.f([(b, T, 0), (b, yr, run), (a, yr, run)])
        p.f([(a, G, 0), (b, G, 0), (b, T, 0)])
    for a, b in zip(xs, xs[1:]): p.f([(a, yr, run), (b, yr, run), (b, TB, BAND), (a, TB, BAND)])
    for sg in (1, -1):
        x = sg * X; p.f([(x, G0, -GW), (x, G, -GW), (x, G, 0), (x, T, 0), (x, yr, run), (x, TB, BAND), (x, G0, BAND)])
    p.f([(-X, G0, -GW), (X, G0, -GW), (X, G, -GW), (half, G, -GW), (-half, G, -GW), (-X, G, -GW)])
    p.f([(-X, G0, BAND), (X, G0, BAND), (X, TB, BAND), (half, TB, BAND), (-half, TB, BAND), (-X, TB, BAND)])
    p.f([(-X, G0, -GW), (X, G0, -GW), (X, G0, BAND), (-X, G0, BAND)])
    if panel:   # detectable warning: 0.61 m deep, 0.15 m behind the curb line, opening width less 0.05 margins, 5 mm proud
        s0, s1, hw = 0.15, 0.76, half - 0.05
        hy = lambda s_: G + (yr - G) * s_ / run + 0.005
        p.o([(-hw, hy(s1), s1), (hw, hy(s1), s1), (hw, hy(s0), s0), (-hw, hy(s0), s0)], 1,
            [(0, 1), (2 * hw / 0.61, 1), (2 * hw / 0.61, 0), (0, 0)])
    p.anchors = {"port_w": (-X, G, 0.0, [-1, 0, 0]), "port_e": (X, G, 0.0, [1, 0, 0]), "route_top_centre": (0.0, yr, run, [0, 0, 1])}
    mats = CURB_MATS + [("detectable_warning", (255, 255, 255), 0.7, os.path.join(HERE, "textures/detectable_warning_512.png"))]
    build(p, mats); return p, (yr - G) / run

def driveway_flush(name, half, wing):
    """Flush driveway (CE 2026-10-09): across the full driveway width |x| <= half the walk drops to road grade (y 0.025)
    over the whole band depth; the walk returns to its 1.5 % section over 'wing' on each side (<= 1:12 along the walk)."""
    p = Piece(name); X = half + wing; xs = [-X, -half, half, X]
    for a, b in zip(xs, xs[1:]): p.f([(a, G, -GW), (b, G, -GW), (b, G, 0), (a, G, 0)])
    p.f([(-half, G, 0), (half, G, 0), (half, G, BAND), (-half, G, BAND)])
    for sg in (1, -1):
        a, b = sg * half, sg * X
        p.f([(a, G, 0), (b, T, 0), (b, TB, BAND)]); p.f([(a, G, 0), (b, TB, BAND), (a, G, BAND)])
        p.f([(a, G, 0), (b, G, 0), (b, T, 0)])
    for sg in (1, -1):
        x = sg * X; p.f([(x, G0, -GW), (x, G, -GW), (x, G, 0), (x, T, 0), (x, TB, BAND), (x, G0, BAND)])
    p.f([(-X, G0, -GW), (X, G0, -GW), (X, G, -GW), (half, G, -GW), (-half, G, -GW), (-X, G, -GW)])
    p.f([(-X, G0, BAND), (X, G0, BAND), (X, TB, BAND), (half, G, BAND), (-half, G, BAND), (-X, TB, BAND)])
    p.f([(-X, G0, -GW), (X, G0, -GW), (X, G0, BAND), (-X, G0, BAND)])
    p.anchors = {"port_w": (-X, G, 0.0, [-1, 0, 0]), "port_e": (X, G, 0.0, [1, 0, 0]), "driveway_back_centre": (0.0, G, BAND, [0, 0, 1])}
    build(p, CURB_MATS); return p, (TB - G) / wing

FILL = {"concrete": ("median_fill_concrete", (142, 139, 132)), "grass": ("median_fill_grass", (96, 109, 48))}
def median_prof(W):   # across width t in [-W/2, W/2]; edge materials: 0 concrete, 1 fill
    h = W / 2
    prof = [(-h, G0), (-h, T), (-h + CT, T), (h - CT, T), (h, T), (h, G0)]
    return prof, [0, 0, 1, 0, 0, 0]

def median_straight(W, L=3.66, fill="grass", well=False):
    tag = f"{W:.2f}".replace(".", "p"); p = Piece(f"median_{'treewell' if well else 'straight'}_{tag}")
    prof, mis = median_prof(W)
    sweep(p, prof, mis, lambda i, t: ((-L / 2, L / 2)[i], t), 2)
    p.anchors = {"port_w": (-L / 2, T, 0.0, [-1, 0, 0]), "port_e": (L / 2, T, 0.0, [1, 0, 0])}
    mats = CURB_MATS + [FILL[fill]]
    if well:   # mulch disc O 1.52 m, 4 mm proud; tree pivot anchor
        n, r, y = 16, 0.76, T + 0.004
        pts = [(r * math.cos(2 * math.pi * k / n), y, r * math.sin(2 * math.pi * k / n)) for k in range(n)][::-1]
        p.o(pts, 2, [((q[0] / r + 1) / 2, (q[2] / r + 1) / 2) for q in pts])
        mats.append(("mulch", (92, 62, 40), 0.95)); p.anchors["tree"] = (0.0, T, 0.0, None)
    build(p, mats); return p

def median_nose(W, seg=12, fill="grass"):
    tag = f"{W:.2f}".replace(".", "p"); p = Piece(f"median_nose_{tag}"); h = W / 2
    prof = [(0.0, G0), (0.0, T), (h - CT, T), (h, T), (h, G0)]; mis = [1, 1, 0, 0, 0]
    def place(i, r):
        th = math.radians(-90 + 180 * i / seg); return (r * math.cos(th), r * math.sin(th))
    sweep(p, prof, mis, place, seg + 1)
    p.anchors = {"port_w_flat_end": (0.0, T, 0.0, [-1, 0, 0]), "nose_tip": (h, T, 0.0, [1, 0, 0])}
    build(p, CURB_MATS + [FILL[fill]], smooth_angle=35); return p

curb_straight()
for R, seg in ((4.6, 12), (6.1, 14), (7.6, 16), (9.1, 18)): curb_return(R, seg)
_, rs = curb_ramp("curb_ramp_perpendicular", 0.61, 1.83, 2.25); print("SLOPE ramp 1:%.2f" % (1 / rs))
_, ws = driveway_flush("driveway_flush_3p66", 1.83, 2.25); print("SLOPE driveway wing (back edge) 1:%.2f" % (1 / ws))
for W in (1.8, 4.07, 4.27):
    median_straight(W, fill="concrete" if W < 2 else "grass"); median_nose(W, fill="concrete" if W < 2 else "grass")
for W in (4.07, 4.27): median_straight(W, well=True)
