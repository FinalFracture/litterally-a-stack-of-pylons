"""In-house street trees and shrubs (Asset Manager): trunk + branches + alpha-tested leaf-cluster cards.
blender -b --factory-startup --python make_vegetation.py -- <out_dir> <tex_dir> [items...]
items: tree_linden tree_honeylocust shrub_060 shrub_100 shrub_150 (default all)
Standard (2026-10-09): bottom-centre pivot, -Z forward (trees are radially symmetric), static collision as a
'<name>_trunk-col' node (trunk only; the crown has no collision). Card normals are bent outward from the crown
centre so the crown shades like a volume (glTF custom normals).
Each tree also gets '<name>_lod1.glb' (40% of the cards, no branches) for a visibility-range swap; the impostor
card is baked separately (Godot) and assembled by make_impostor.py.
"""
import bpy, bmesh, sys, os, json, math, random
from mathutils import Vector, Matrix
a = sys.argv[sys.argv.index("--") + 1:]
OUT, TEX = a[0], a[1]
ITEMS = a[2:] or ["tree_linden", "tree_honeylocust", "shrub_060", "shrub_100", "shrub_150"]

def srgb(c): return tuple((x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in [v / 255 for v in c])
def reset(): bpy.ops.wm.read_factory_settings(use_empty=True)

def tex_mat(name, img, alpha_clip=False, rough=0.85):
    m = bpy.data.materials.new(name); m.use_nodes = True; nt = m.node_tree
    b = nt.nodes["Principled BSDF"]; b.inputs["Roughness"].default_value = rough
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(os.path.join(TEX, img))
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    if alpha_clip:   # Image alpha -> (Math: Greater Than 0.5) -> BSDF alpha  => glTF alphaMode MASK
        g = nt.nodes.new("ShaderNodeMath"); g.operation = "GREATER_THAN"; g.inputs[1].default_value = 0.5
        nt.links.new(t.outputs["Alpha"], g.inputs[0]); nt.links.new(g.outputs[0], b.inputs["Alpha"])
        m.use_backface_culling = False
    return m

def mesh_obj(name, bm, mat):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o); me.materials.append(mat); return o

def tapered(bm, p0, p1, r0, r1, sides):
    """open-ended tapered tube from p0 to p1 with UVs (u around, v along length in metres / 2)"""
    axis = (p1 - p0); L = axis.length; z = axis.normalized()
    x = z.orthogonal().normalized(); y = z.cross(x)
    uv = bm.loops.layers.uv.verify()
    ring0 = [bm.verts.new(p0 + (x * math.cos(2 * math.pi * i / sides) + y * math.sin(2 * math.pi * i / sides)) * r0) for i in range(sides)]
    ring1 = [bm.verts.new(p1 + (x * math.cos(2 * math.pi * i / sides) + y * math.sin(2 * math.pi * i / sides)) * r1) for i in range(sides)]
    for i in range(sides):
        j = (i + 1) % sides
        f = bm.faces.new((ring0[i], ring0[j], ring1[j], ring1[i]))
        for lp, (u, v) in zip(f.loops, ((i / sides, 0), ((i + 1) / sides, 0), ((i + 1) / sides, L / 2), (i / sides, L / 2))):
            lp[uv].uv = (u, v)
    return ring1

def cards(bm, centres, rnd, smin, smax, crown_c):
    uv = bm.loops.layers.uv.verify(); outward = []
    for c in centres:
        s = rnd.uniform(smin, smax); base = Matrix.Rotation(rnd.random() * math.pi, 3, "Z")
        for k in range(3):   # three intersecting quads per cluster
            R = base @ Matrix.Rotation(k * math.pi / 3, 3, "Z") @ Matrix.Rotation(rnd.uniform(-0.5, 0.5) + math.pi / 2, 3, "X")
            vs = [bm.verts.new(c + R @ Vector((dx * s / 2, dy * s / 2, 0))) for dx, dy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            f = bm.faces.new(vs)
            for lp, (u, v) in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))): lp[uv].uv = (u, v)
            outward.append((f, (c - crown_c)))
    return outward

def bend_normals(obj, crown_c, radii):
    me = obj.data; ns = []
    for lp in me.loops:
        p = me.vertices[lp.vertex_index].co
        d = Vector(((p.x - crown_c.x) / radii.x, (p.y - crown_c.y) / radii.y, (p.z - crown_c.z) / radii.z))
        ns.append((d.normalized() if d.length > 1e-4 else Vector((0, 0, 1)))[:])
    if hasattr(me, "use_auto_smooth"): me.use_auto_smooth = True
    me.normals_split_custom_set(ns)

def ellipsoid_points(rnd, n, c, radii, rmin):
    pts = []
    while len(pts) < n:
        v = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1)))
        if rmin ** 2 <= v.length_squared <= 1.0:
            pts.append(Vector((c.x + v.x * radii.x, c.y + v.y * radii.y, c.z + v.z * radii.z)))
    return pts

def export(path, objs, log):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs: o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
                              export_image_format="AUTO")

def tris_of(o): return sum(len(p.vertices) - 2 for p in o.data.polygons)

def tree(name, H, crown_d, clear, trunk_d, leaf_img, n_clusters, card_min, card_max, crown_rz_frac, seed, lod1=False):
    reset(); rnd = random.Random(seed)
    bark = tex_mat("bark_grey_brown", "bark_grey_brown_256x512.jpg", rough=0.9)
    leaf = tex_mat("foliage_" + name.split("_")[1], leaf_img, alpha_clip=True)
    crown_rz = (H - clear) / 2 * crown_rz_frac
    crown_c = Vector((0, 0, H - crown_rz)); radii = Vector((crown_d / 2, crown_d / 2, crown_rz))
    # trunk: ground to the crown fork
    bm = bmesh.new(); fork = clear + 1.2
    tapered(bm, Vector((0, 0, 0)), Vector((0, 0, fork)), trunk_d / 2 * 1.1, trunk_d / 2 * 0.75, 8)
    tapered(bm, Vector((0, 0, fork)), Vector((0, 0, crown_c.z + crown_rz * 0.3)), trunk_d / 2 * 0.75, trunk_d / 2 * 0.25, 6)
    trunk = mesh_obj(name + "_trunk-col", bm, bark)
    objs = [trunk]
    bm = bmesh.new()
    if not lod1:   # main scaffold branches
        for i in range(6):
            ang = i / 6 * 2 * math.pi + rnd.uniform(-0.3, 0.3)
            end = Vector((math.cos(ang) * radii.x * 0.7, math.sin(ang) * radii.y * 0.7, crown_c.z + rnd.uniform(-0.2, 0.5) * crown_rz))
            tapered(bm, Vector((0, 0, fork + i * 0.25)), end, trunk_d * 0.22, trunk_d * 0.07, 5)
    centres = ellipsoid_points(rnd, int(n_clusters * (0.4 if lod1 else 1.0)), crown_c, radii * 0.9, 0.45)
    s_mul = 1.35 if lod1 else 1.0
    nv0 = len(bm.verts)
    cards(bm, centres, rnd, card_min * s_mul, card_max * s_mul, crown_c)
    bm.verts.ensure_lookup_table()
    cv = bm.verts[nv0:]                                   # re-centre the leaf cards on the trunk axis so the
    cx = (min(v.co.x for v in cv) + max(v.co.x for v in cv)) / 2   # bounds bottom-centre = trunk base (standard)
    cy = (min(v.co.y for v in cv) + max(v.co.y for v in cv)) / 2
    for v in cv: v.co.x -= cx; v.co.y -= cy
    crown = mesh_obj(name + "_crown", bm, leaf)
    if not lod1:   # branches use bark: split material per face (branch faces have 4 verts with no leaf UV square... simpler: second slot)
        pass
    crown.data.materials.append(bark)
    # faces created before the cards belong to branches: give them slot 1 (bark)
    nb = 0 if lod1 else 6 * 5
    for i, p in enumerate(crown.data.polygons):
        p.material_index = 1 if i < nb else 0
    bend_normals(crown, crown_c, radii)
    objs.append(crown)
    log = {"name": name + ("_lod1" if lod1 else ""), "height_m": H, "crown_d_m": crown_d, "clear_trunk_m": clear,
           "trunk_d_m": trunk_d, "clusters": len(centres), "tris_trunk": tris_of(trunk), "tris_crown": tris_of(crown),
           "tris": tris_of(trunk) + tris_of(crown), "textures": ["bark_grey_brown_256x512.jpg", leaf_img],
           "collision": "'_trunk-col' -> StaticBody3D trimesh of the trunk only; crown has none"}
    d = os.path.join(OUT, name); os.makedirs(d, exist_ok=True)
    fn = name + ("_lod1" if lod1 else "")
    export(os.path.join(d, fn + ".glb"), objs, log)
    if not lod1:
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(d, fn + ".blend"), compress=True)
    json.dump(log, open(os.path.join(d, fn + ".log.json"), "w"), indent=2)
    print("VEG", json.dumps(log))

def shrub(name, H, D, leaf_img, n, seed):
    reset(); rnd = random.Random(seed)
    leaf = tex_mat("foliage_shrub", leaf_img, alpha_clip=True)
    c = Vector((0, 0, H * 0.5)); radii = Vector((D / 2, D / 2, H / 2))
    bm = bmesh.new()
    centres = ellipsoid_points(rnd, n, c, radii * 0.8, 0.0)
    s = max(0.35, H * 0.55)
    cards(bm, centres, rnd, s * 0.8, s * 1.2, c)
    o = mesh_obj(name, bm, leaf)
    # clamp below ground: shift so min z = 0
    mz = min(v.co.z for v in o.data.vertices)
    cx = (min(v.co.x for v in o.data.vertices) + max(v.co.x for v in o.data.vertices)) / 2
    cy = (min(v.co.y for v in o.data.vertices) + max(v.co.y for v in o.data.vertices)) / 2
    for v in o.data.vertices: v.co.z -= mz; v.co.x -= cx; v.co.y -= cy
    c.z -= mz
    bend_normals(o, c, radii)
    objs = [o]; colnote = "none (groundcover < 0.6 m)"
    if H >= 0.6:   # CE 2026-10-09: shrubs/hedges >= 0.6 m get one simple collider -> 8-sided cylinder, convex, invisible
        hgt = max(v.co.z for v in o.data.vertices) * 0.85; r = D / 2 * 0.7
        cb = bmesh.new(); bmesh.ops.create_cone(cb, cap_ends=True, segments=8, radius1=r, radius2=r, depth=hgt)
        for v in cb.verts: v.co.z += hgt / 2
        cm = bpy.data.meshes.new(name + "_body"); cb.to_mesh(cm); cb.free()
        co = bpy.data.objects.new(name + "_body-convcolonly", cm); bpy.context.scene.collection.objects.link(co); objs.append(co)
        colnote = "'%s_body-convcolonly' -> StaticBody3D with one 16-point convex cylinder, r %.2f m, h %.2f m" % (name, r, hgt)
    log = {"name": name, "height_m": round(max(v.co.z for v in o.data.vertices), 3), "spread_m": D, "clusters": n,
           "tris": tris_of(o), "textures": [leaf_img], "collision": colnote}
    d = os.path.join(OUT, "shrubs"); os.makedirs(d, exist_ok=True)
    export(os.path.join(d, name + ".glb"), objs, log)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(d, name + ".blend"), compress=True)
    json.dump(log, open(os.path.join(d, name + ".log.json"), "w"), indent=2)
    print("VEG", json.dumps(log))

for it in ITEMS:
    if it == "tree_linden":        # 2026-10-09: clear 2.6 -> 2.9 so the lowest leaf is >= 2.5 m (walk min 2.4). little-leaf linden: dense, rounded-oval crown [E: 10-14 m street tree, crown 8 m]
        for l1 in (False, True): tree("tree_linden", 12.0, 8.0, 2.9, 0.30, "foliage_linden_512.png", 120, 1.7, 2.5, 1.0, 11, l1)
    elif it == "tree_linden_lifted":   # CE 2026-10-09: trees within 1.5 m of the curb face -> crown >= 4.3 m (box trucks, buses)
        for l1 in (False, True): tree("tree_linden_lifted", 13.5, 8.0, 5.0, 0.30, "foliage_linden_512.png", 110, 1.7, 2.5, 1.0, 12, l1)
    elif it == "tree_honeylocust_lifted":   # same rule; the standard honey locust's lowest leaf card is ~4.2 m
        for l1 in (False, True): tree("tree_honeylocust_lifted", 13.0, 8.5, 4.0, 0.30, "foliage_honeylocust_512.png", 90, 1.8, 2.8, 0.8, 23, l1)
    elif it == "tree_honeylocust": # thornless honey locust: airy, broad vase/umbrella crown
        for l1 in (False, True): tree("tree_honeylocust", 12.0, 8.5, 3.0, 0.30, "foliage_honeylocust_512.png", 95, 1.8, 2.8, 0.8, 22, l1)
    elif it == "shrub_060": shrub("shrub_060", 0.6, 0.8, "foliage_shrub_512.png", 9, 31)
    elif it == "shrub_100": shrub("shrub_100", 1.0, 1.2, "foliage_shrub_512.png", 14, 32)
    elif it == "shrub_150": shrub("shrub_150", 1.5, 1.6, "foliage_shrub_512.png", 20, 33)
