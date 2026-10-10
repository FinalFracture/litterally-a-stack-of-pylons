"""In-house road-marking quads (Asset Manager 2026-10-09). blender -b --factory-startup --python make_road_markings.py -- <out_dir>
Godot coords: x across the road, z along it; direction of travel = +Z (arrow tips and SCHOOL read toward +Z drivers... read from -Z).
Every quad lies at local y = 0.027 (2 mm above the kit road surface 0.025) with the piece origin at (0, 0, 0) on the ground datum.
So place pieces at world y 0, the same datum as the curb kit. One material 'road_marking' (atlas, alpha clip), no collision,
single-sided facing +Y. Dimensions per MUTCD 2009 Part 3 [REF]: lines 0.10-0.15, broken 3.05 / 9.14 gap (10/30 ft), stop bar 0.45
(12-24 in), crosswalk bars 0.6 (continental), arrows ~2.7 m [EST urban], word legend 2.4 m letters (8 ft), stalls 2.74 x 5.49 (9 x 18 ft) [EST]."""
import bpy, bmesh, sys, os, json
OUT = sys.argv[sys.argv.index("--") + 1]; os.makedirs(OUT, exist_ok=True)
HERE = os.path.dirname(os.path.abspath(__file__)); ATLAS = os.path.join(HERE, "textures/road_markings_atlas_2k.png"); Y = 0.027; S = 2048
def mat():
    m = bpy.data.materials.new("road_marking"); m.use_nodes = True; b = m.node_tree.nodes["Principled BSDF"]
    t = m.node_tree.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(ATLAS)
    m.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"]); m.node_tree.links.new(t.outputs["Alpha"], b.inputs["Alpha"])
    b.inputs["Roughness"].default_value = 0.7
    for attr, val in (("blend_method", "CLIP"), ("surface_render_method", "DITHERED")):
        try: setattr(m, attr, val)
        except Exception: pass
    return m
# cell = pixel rect (px0, py0, px1, py1) in the atlas; rot = strip runs across x instead of along z
STRIP = {"white": (0, 63), "yellow": (64, 127), "white_worn": (128, 191), "yellow_worn": (192, 255)}
def strip_cell(colour, length_m): x0, x1 = STRIP[colour]; return (x0 + 2, 0, x1 - 2, min(S, int(length_m * 200)))
ARROW = {k: i for i, k in enumerate(["through", "left", "right", "through_left", "through_right"])}
def piece(name, rects, info):
    bpy.ops.wm.read_factory_settings(use_empty=True); M = mat(); bm = bmesh.new(); uvl = bm.loops.layers.uv.new("UVMap")
    for (x0, z0, x1, z1), (px0, py0, px1, py1), rot in rects:
        u0, u1, vt, vb = px0 / S, px1 / S, 1 - py0 / S, 1 - py1 / S       # image top (py0) -> +Z end of the quad
        corners = [((x0, z0), (u1, vb)), ((x1, z0), (u0, vb)), ((x1, z1), (u0, vt)), ((x0, z1), (u1, vt))]   # image left -> +X (driver's left when travelling +Z)
        if rot: corners = [((x0, z0), (u0, vt)), ((x1, z0), (u0, vb)), ((x1, z1), (u1, vb)), ((x0, z1), (u1, vt))]
        vs = [bm.verts.new((x, -z, Y)) for (x, z), _ in corners]           # Blender (x, -z, y)
        f = bm.faces.new(vs); f.normal_update()
        if f.normal.z < 0: f.normal_flip(); corners = corners  # keep +Y facing
        for l in f.loops:
            k = vs.index(l.vert); l[uvl].uv = corners[k][1]
    me = bpy.data.meshes.new(name); bm.to_mesh(me); tris = sum(len(p.vertices) - 2 for p in me.polygons); bm.free(); me.materials.append(M)
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB", export_yup=True, export_image_format="NONE")
    xs = [r[0][0] for r in rects] + [r[0][2] for r in rects]; zs = [r[0][1] for r in rects] + [r[0][3] for r in rects]
    log = {"name": name, "tris": tris, "y_m": Y, "extent_x_m": [round(min(xs), 3), round(max(xs), 3)], "extent_z_m": [round(min(zs), 3), round(max(zs), 3)],
           "material": "road_marking", "collision": "none", "pivot": "(0,0,0) ground datum; quad at y 0.027, centred in x/z", "travel": "+Z"}
    log.update(info); json.dump(log, open(os.path.join(OUT, name + ".log.json"), "w"), indent=1); print("RM", json.dumps({"name": name, "tris": tris}))
for worn in ("", "_worn"):
    w, yel = "white" + worn, "yellow" + worn
    piece("rm_lane_broken_white_3p05" + worn, [((-0.05, -1.525, 0.05, 1.525), strip_cell(w, 3.05), False)], {"repeat_m": 12.19, "note": "3.05 line + 9.14 gap"})
    piece("rm_lane_solid_white_3p66" + worn, [((-0.05, -1.83, 0.05, 1.83), strip_cell(w, 3.66), False)], {"width_m": 0.10, "tile_m": 3.66})
    piece("rm_edge_line_white_3p66" + worn, [((-0.075, -1.83, 0.075, 1.83), strip_cell(w, 3.66), False)], {"width_m": 0.15, "tile_m": 3.66})
    piece("rm_centre_double_yellow_3p66" + worn, [((-0.15, -1.83, -0.05, 1.83), strip_cell(yel, 3.66), False), ((0.05, -1.83, 0.15, 1.83), strip_cell(yel, 3.66), False)], {"lines": "2 x 0.10 with 0.10 gap", "tile_m": 3.66})
    piece("rm_centre_broken_yellow_3p05" + worn, [((-0.05, -1.525, 0.05, 1.525), strip_cell(yel, 3.05), False)], {"repeat_m": 12.19})
    piece("rm_stop_bar_3p66" + worn, [((-1.83, -0.225, 1.83, 0.225), strip_cell(w, 3.66), True)], {"depth_m": 0.45, "across_m": 3.66, "place": "1.2 m before the crosswalk, across one lane"})
    piece("rm_crosswalk_continental_3p66x3p0" + worn, [((x - 0.3, -1.5, x + 0.3, 1.5), strip_cell(w, 3.0), False) for x in (-1.2, 0.0, 1.2)],
          {"bars": "3 x 0.6 wide, 0.6 gaps, 3.0 long (crosswalk width)", "tile_across_m": 3.66, "note": "tile per lane; bars avoid wheel paths only approximately"})
    piece("rm_crosswalk_transverse_3p66x3p0" + worn, [((-1.83, -1.5, 1.83, -1.2), strip_cell(w, 3.66), True), ((-1.83, 1.2, 1.83, 1.5), strip_cell(w, 3.66), True)],
          {"lines": "2 x 0.30, outer edges 3.0 apart", "tile_across_m": 3.66})
    for k, i in ARROW.items():
        py0 = 0 if not worn else 768
        piece(f"rm_arrow_{k}" + worn, [((-0.45, -1.35, 0.45, 1.35), (256 + 256 * i, py0, 256 + 256 * (i + 1), py0 + 768), False)], {"size_m": [0.9, 2.7]})
    piece("rm_parking_stall_line_5p49" + worn, [((-0.05, -2.745, 0.05, 2.745), strip_cell(w, 5.49), False)], {"stall_m": [2.74, 5.49]})
    piece("rm_parking_row_4stalls" + worn, [((x - 0.05, -2.745, x + 0.05, 2.745), strip_cell(w, 5.49), False) for x in (-5.48, -2.74, 0.0, 2.74, 5.48)],
          {"stalls": 4, "stall_m": [2.74, 5.49], "row_width_m": 11.06})
    piece("rm_legend_school" + worn, [((-1.5, -1.2, 1.5, 1.2), (1536, 0 if not worn else 512, 2048, 512 if not worn else 1024), False)],
          {"size_m": [3.0, 2.4], "note": "SCHOOL, elongated letters, reads for a driver travelling +Z"})
