"""Assemble a 2-quad crossed impostor glb from a Godot-baked RGBA image (impostors/bake.log line).
blender -b --factory-startup --python make_impostor.py -- <bake.log> <out_dir>
Quads are cropped at y = 0 (UVs adjusted) so the pivot is the bottom centre, like the full tree. Alpha MASK, no collision
(the full tree's trunk collider stays loaded, or use a scene capsule; see README)."""
import bpy, bmesh, sys, os, json, math
a = sys.argv[sys.argv.index("--") + 1:]
for line in open(a[0]):
    if not line.startswith("IMPOSTOR "): continue
    d = json.loads(line[9:]); name = d["glb"].replace(".glb", "") + "_impostor"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    m = bpy.data.materials.new(name); m.use_nodes = True; nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(d["png"])
    g = nt.nodes.new("ShaderNodeMath"); g.operation = "GREATER_THAN"; g.inputs[1].default_value = 0.5
    # UNLIT (KHR_materials_unlit): the bake already carries the noon lighting; re-lighting a flat card made it read
    # darker than LOD0 and the edge-on quad showed as a band. Exporter pattern: Mix(fac=alpha, Transparent, Color) -> Output
    nt.nodes.remove(b); outn = nt.nodes["Material Output"]
    tr = nt.nodes.new("ShaderNodeBsdfTransparent"); mx = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(t.outputs["Alpha"], g.inputs[0]); nt.links.new(g.outputs[0], mx.inputs[0])
    nt.links.new(tr.outputs[0], mx.inputs[1]); nt.links.new(t.outputs["Color"], mx.inputs[2]); nt.links.new(mx.outputs[0], outn.inputs["Surface"])
    m.use_backface_culling = False
    W, H, cx, cy = d["img_w_m"], d["img_h_m"], d["img_centre_x_m"], d["img_centre_y_m"]
    y0 = cy - H / 2; top = cy + H / 2; v0 = (0.0 - y0) / H if y0 < 0 else 0.0; yb = max(0.0, y0)
    bm = bmesh.new(); uv = bm.loops.layers.uv.verify()
    for k in range(2):   # two quads at 90 deg; Blender XZ plane and YZ plane (Z up)
        ang = k * math.pi / 2; ca, sa = math.cos(ang), math.sin(ang)
        P = [(-W / 2, yb), (W / 2, yb), (W / 2, top), (-W / 2, top)]
        vs = [bm.verts.new((u * ca, u * sa, z)) for u, z in P]
        f = bm.faces.new(vs)
        for lp, (uu, vv) in zip(f.loops, ((0, v0), (1, v0), (1, 1), (0, 1))): lp[uv].uv = (uu, vv)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    # all normals straight up: the bake already holds the lighting, and a quad seen edge-on to the sun
    # rendered as a dark band in the first Godot check
    if hasattr(me, "use_auto_smooth"): me.use_auto_smooth = True
    me.normals_split_custom_set([(0.0, 0.0, 1.0)] * len(me.loops))
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o); me.materials.append(m)
    out = os.path.join(a[1], name + ".glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True, export_image_format="AUTO")
    log = {"name": name, "tris": 4, "quad_w_m": round(W, 3), "quad_h_m": round(top - yb, 3), "uv_v0": round(v0, 4), "texture": os.path.basename(d["png"])}
    json.dump(log, open(out.replace(".glb", ".log.json"), "w"), indent=2); print("IMP", json.dumps(log))
