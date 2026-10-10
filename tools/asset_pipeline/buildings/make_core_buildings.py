"""Core buildings still missing from town-core.md §4/§6 (Asset Manager 2026-10-09), built on make_buildings.py's kit helpers.
blender -b --factory-startup --python make_core_buildings.py -- <out_dir> [names...] [--quest]
Rules: walking-surface heights, FLUSH climb edges (CE 2026-10-09 ruling, as for City Hall), 1.07 m guards on non-climb faces,
landings >= 2.0 m (towers 2.5), every climb rise <= 8 m (JD-12 open), storeys 3.1-4.5, pivot bottom-centre, front/climb face -Z,
one '-col' trimesh. Anchors named 'ray|<label>' carry (x, expected_hit_y, z) for the Godot ray check.
--quest swaps window/storefront/curtain/belfry modules for 2-box versions (Quest budget <= 5k tris) and writes <name>_quest."""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
argv = sys.argv[sys.argv.index("--") + 1:]
QUEST = "--quest" in argv; argv = [a for a in argv if a != "--quest"]
OUT_DIR, WANT = argv[0], argv[1:]
src = open(os.path.join(HERE, "make_buildings.py")).read()
src = src.replace('if fn == "belfry": return m_belfry(h, mat, W=mw)',
                  'if fn == "belfry": return m_belfry(h, mat, W=mw)\n            if fn == "baydoor": return m_baydoor(h, mat, W=mw)')
sys.argv = [sys.argv[0], "--", OUT_DIR]
G = {"__file__": os.path.join(HERE, "make_buildings.py"), "NO_MAIN": True, "__name__": "mb"}
exec(compile(src, "make_buildings.py", "exec"), G)
B, place, ring, roof, build, T, MATS = G["B"], G["place"], G["ring"], G["roof"], G["build"], G["T"], G["MATS"]
MATS["door_red"] = ((150, 32, 28), .5, .1)
def m_baydoor(h, mat, W=6.0, dw=4.3, dh=4.3):
    x0, x1 = -dw / 2, dw / 2
    return [B(-W / 2, 0, 0, x0, h, T, mat), B(x1, 0, 0, W / 2, h, T, mat), B(x0, dh, 0, x1, h, T, mat),
            B(x0, 0, 0.15, x1, dh, 0.22, "door_red"), B(x0 - 0.1, dh, -0.02, x1 + 0.1, dh + 0.15, 0.0, "trim_dark")]
G["m_baydoor"] = m_baydoor
if QUEST:   # 2-box modules: wall + proud glass panel
    def q_window(h, mat, W=3.0, ww=1.5, wh=1.8, sill=0.9, glass="glass_dark"):
        return [B(-W / 2, 0, 0, W / 2, h, T, mat), B(-ww / 2, sill, -0.01, ww / 2, sill + wh, 0.0, glass)]
    def q_storefront(h, mat, W=3.0, door=False):
        bx = [B(-W / 2, 0, 0, W / 2, h, T, mat), B(-W / 2 + 0.25, 0.45, -0.01, W / 2 - 0.25, 3.2, 0.0, "glass_dark")]
        if door: bx.append(B(0.03, 0, -0.02, W / 2 - 0.25, 2.45, -0.01, "door_dark"))
        return bx
    def q_curtain(h, W=3.0): return [B(-W / 2, 0, 0.0, W / 2, h, 0.3, "glass_dark")]
    def q_belfry(h, mat, W=3.0, ow=None, oh=None):
        ow = ow or min(3.0, W - 1.2); return [B(-W / 2, 0, 0, W / 2, h, T, mat), B(-ow / 2, 0.5, -0.01, ow / 2, h - 0.5, 0.0, "louvre_dark")]
    G.update(m_window=q_window, m_storefront=q_storefront, m_curtain=q_curtain, m_belfry=q_belfry)
    _b = build
    def build(name, boxes, anchors=None, extra=None, sub="kit", discs=()):
        e = dict(extra or {}); e["variant"] = "Quest (2-box modules)"; return _b(name + "_quest", boxes, anchors, e, sub, discs)
    G["build"] = build
GH = 1.07
def guards(x0, z0, W, D, y, faces, z_from=None, z_to=None):
    """1.07 m guard (0.3 thick, coping cap) on the listed faces of a deck x0..x0+W, z0..z0+D at walking height y."""
    a, b = (z_from if z_from is not None else z0), (z_to if z_to is not None else z0 + D); bx = []
    def seg(xa, za, xb, zb): return [B(xa, y, za, xb, y + GH - 0.06, zb, "coping"), B(xa, y + GH - 0.06, za, xb, y + GH, zb, "coping")]
    if "front" in faces: bx += seg(x0, z0, x0 + W, z0 + T)
    if "back" in faces: bx += seg(x0, z0 + D - T, x0 + W, z0 + D)
    za = a + (T if ("front" in faces and a == z0) else 0); zb = b - (T if ("back" in faces and b == z0 + D) else 0)
    if "left" in faces: bx += seg(x0, za, x0 + T, zb)
    if "right" in faces: bx += seg(x0 + W - T, za, x0 + W, zb)
    return bx
def bulkhead(xc, zc, y, mat="cmu_grey"):   # roof stair/lift bulkhead 4 x 3 x 3 with a door facing -Z (CH-12 / service access)
    return [B(xc - 2, y, zc - 1.5, xc + 2, y + 3.0, zc + 1.5, mat, "roof_membrane"), B(xc - 0.5, y, zc - 1.52, xc + 0.5, y + 2.2, zc - 1.5, "door_dark")]
def stepped(name, nx, depths, storeys, mat, front_ground, upper="window", extra=None, top_extra=(), mwx=3.0):
    """Stacked blocks sharing the back line; each block's front is set back from the one below -> terraces (flush front edge,
    guards on the terrace sides). depths = module counts (3 m) per block, storeys = list of storey lists."""
    D0 = mwx * depths[0] + 2 * T; bx = []; y = 0.0; anchors = {}; rises = []; prev = 0.0; zs = []
    for i, (nd, st) in enumerate(zip(depths, storeys)):
        z0 = (depths[0] - nd) * 3.0
        kinds = None if i == 0 else [upper] * len(st)
        r, yt, W, D = ring(nx, nd, st, mat, front_ground=front_ground if i == 0 else None, kinds=kinds, z0=z0, base=y, mwx=mwx)
        bx += r; zs.append((z0, yt)); y = yt
    for i, (z0, yt) in enumerate(zs):
        last = i == len(zs) - 1
        zn = zs[i + 1][0] if not last else z0 + (D0 - z0)
        if last: bx += guards(0, z0, W, D0 - z0, yt, ("left", "right", "back"))
        else: bx += guards(0, z0, W, D0 - z0, yt, ("left", "right"), z_from=z0, z_to=zn)
        anchors[f"ray|deck{i}"] = (W / 2, yt, (z0 + zn) / 2 if not last else z0 + 1.0)
        anchors[f"ray|edge{i}"] = (W / 2, yt, z0 + 0.05)                      # flush climb edge: hits the deck, no lip
        anchors[f"ray|guard{i}"] = (T / 2, yt + GH, (z0 + zn) / 2 if not last else z0 + 1.0)
        rises.append(round(yt - prev, 2)); prev = yt
        if not last: anchors[f"landing_depth_{i}_m"] = None
    for e in top_extra: bx += e(W, D0, zs[-1])
    anchors["front_face_centre_ground"] = (W / 2, 0, 0)
    anchors = {k: v for k, v in anchors.items() if v is not None}
    ex = {"rises_m": rises, "decks_m": [z[1] for z in zs], "landings_m": [round(zs[i + 1][0] - zs[i][0], 2) for i in range(len(zs) - 1)],
          "climb_face": "-Z, flush edges; guards 1.07 on the other faces", "footprint_m": [round(W, 2), round(D0, 2)]}
    ex.update(extra or {})
    build(name, bx, anchors=anchors, extra=ex, sub="core")
def wing_main(name, wing_nx, main_nx, nz, wing_st, main_st, mat, wing_front, main_front, extra=None, wing_upper="window", wing_kinds=None, wing_mwx=3.0):
    """1-storey wing (climb from the walk, flush front) beside a taller main block whose wing-side wall is the next climb face
    (flush edge over the wing roof). Wing on the left (-X side in these coords), main on the right."""
    wr, yw, Ww, D = ring(wing_nx, nz, wing_st, mat, front_ground=wing_front, x0=0.0, kinds=wing_kinds, mwx=wing_mwx)
    mr, ym, Wm, Dm = ring(main_nx, nz, main_st, mat, front_ground=main_front, x0=Ww - T)
    bx = wr + mr + guards(0, 0, Ww - T, D, yw, ("back", "left"))  # wing deck: front flush (walk climb), main wall on its right
    bx += guards(Ww - T, 0, Wm, D, ym, ("front", "back", "right"))     # main roof: left (over the wing roof) is the flush climb edge
    an = {"ray|wing_deck": (Ww / 2, yw, D / 2), "ray|wing_edge": (Ww / 2, yw, 0.05), "ray|wing_guard_left": (T / 2, yw + GH, D / 2),
          "ray|main_deck": (Ww - T + Wm / 2, ym, D / 2), "ray|main_edge_over_wing": (Ww - T + 0.05, ym, D / 2),
          "ray|main_guard_front": (Ww - T + Wm / 2, ym + GH, T / 2), "ray|main_guard_right": (Ww - T + Wm - T / 2, ym + GH, D / 2),
          "front_face_centre_ground": ((Ww + Wm - T) / 2, 0, 0)}
    ex = {"rises_m": [yw, round(ym - yw, 2)], "decks_m": [yw, ym], "landing_m": round(Ww - 2 * T, 2), "footprint_m": [round(Ww + Wm - T, 2), round(D, 2)],
          "climb": "wing front (-Z) from the walk, then the main block's -X wall from the wing roof; both edges flush"}
    ex.update(extra or {}); return bx, an, ex, (Ww, Wm, D, yw, ym)

def six_a():   # T4 office, 6 storeys: decks 4.5 / 11.5 / 18.5 / 22.0 (+ bulkhead to 25.0); rises 4.5 / 7.0 / 7.0 / 3.5
    stepped("bld_t4_sixstorey_office", 6, [7, 6, 5, 4], [[4.5], [3.5, 3.5], [3.5, 3.5], [3.5]], "metal_panel",
            ["storefront", "storefront", "entry", "entry", "storefront", "storefront"], upper="curtain",
            extra={"tier": "T4 (6 storeys, town-core 'about 24 m')", "top_m": 25.0},
            top_extra=(lambda W, D, z: bulkhead(W / 2, D - 2.5, z[1]),))
def six_b():   # T4 brick apartments over shops, 6 storeys: decks 4.5 / 11.5 / 18.5 / 22.0
    stepped("bld_t4_sixstorey_apartments", 5, [6, 5, 4, 3], [[4.5], [3.5, 3.5], [3.5, 3.5], [3.5]], "brick_buff",
            ["storefront", "entry", "storefront", "entry", "storefront"], upper="window",
            extra={"tier": "T4 (6 storeys, town-core 'about 24 m')", "top_m": 25.0},
            top_extra=(lambda W, D, z: bulkhead(W / 2, D - 2.0, z[1]),))
GAP = 2.4   # CH-12 drop gap in the tower's front roof guard (DECIDED 2026-10-09: >= 2.0 m, centred, flush)
def front_gap(x0, z0, W, y, gap):
    xa, xb = x0 + W / 2 - gap / 2, x0 + W / 2 + gap / 2; bx = []
    for p, q in ((x0, xa), (xb, x0 + W)): bx += [B(p, y, z0, q, y + GH - 0.06, z0 + T, "coping"), B(p, y + GH - 0.06, z0, q, y + GH, z0 + T, "coping")]
    return bx
def tower():   # T5 CH-12 tower: podium deck 4.5 (flush front), 12 tower storeys 3.5 -> roof walking surface 46.5, guards all round,
    #            bulkhead to 49.5. CH-12 roof is reached by stairs/lift (building-height-tiers T5), not by stacking.
    pod, yp, Wp, Dp = ring(9, 9, [4.5], "metal_panel", front_ground=["storefront"] * 3 + ["entry"] * 3 + ["storefront"] * 3)
    tw, yt, Wt, Dt = ring(4, 4, [3.5] * 12, "metal_panel", kinds=["curtain"] * 12, x0=3.0, z0=3.0, base=yp, mwx=5.25, mwz=5.25)
    bx = pod + tw + guards(0, 0, Wp, Dp, yp, ("left", "right", "back")) + guards(3.0, 3.0, Wt, Dt, yt, ("left", "right", "back")) + front_gap(3.0, 3.0, Wt, yt, GAP)
    bx += bulkhead(Wp / 2, 3.0 + Dt - 3.0, yt)
    build("bld_t5_tower_ch12", bx, sub="core",
          anchors={"ray|podium_deck": (Wp / 2, yp, 1.5), "ray|podium_edge": (Wp / 2, yp, 0.05), "ray|podium_guard_left": (T / 2, yp + GH, Dp / 2),
                   "ray|roof_deck": (Wp / 2, yt, 3.0 + 3.0), "ray|roof_guard_front": (Wp / 2 - 4.0, yt + GH, 3.0 + T / 2), "ray|drop_gap_centre_edge": (Wp / 2, yt, 3.0 + 0.05), "ray|drop_gap_left_inside": (Wp / 2 - 1.1, yt, 3.0 + 0.15), "ray|drop_gap_right_inside": (Wp / 2 + 1.1, yt, 3.0 + 0.15), "ray|guard_beside_gap": (Wp / 2 - 1.3, yt + GH, 3.0 + T / 2),
                   "ray|bulkhead_top": (Wp / 2, yt + 3.0, 3.0 + Dt - 3.0), "ch12_drop_gap_centre": (Wp / 2, yt, 3.0),
                   "front_face_centre_ground": (Wp / 2, 0, 0)},
          extra={"tier": "T5 tower (13 storeys)", "roof_walking_m": yt, "top_m": yt + 3.0, "podium_deck_m": yp, "podium_landing_m": 3.0 - T,
                 "climb": "podium only (4.5 from the walk); tower roof by stairs/lift per building-height-tiers T5 (CH-12 is a drop, not a climb)",
                 "ch12_drop_gap_m": GAP, "footprint_m": [round(Wp, 2), round(Dp, 2)]})
def school():  # N ring school: gym wing 1 storey 4.5, classroom block 2 storeys (4.0 + 4.0 = 8.0); rises 4.5 / 3.5
    bx, an, ex, _ = wing_main("bld_school", 4, 12, 6, [4.5], [4.0, 4.0], "brick_red", ["window", "entry", "entry", "window"],
                              ["window"] * 5 + ["entry", "entry"] + ["window"] * 5, extra={"use": "school (N ring); gym wing + 2-storey classrooms"})
    build("bld_school", bx, anchors=an, extra=ex, sub="core")
def police():  # W ring police: 2-bay sally port wing 1 storey 4.5, station 2 storeys 4.5 + 3.5 = 8.0
    bx, an, ex, _ = wing_main("bld_police", 2, 7, 5, [4.5], [4.5, 3.5], "brick_buff", ["baydoor", "baydoor"],
                              ["window", "window", "window", "entry", "window", "window", "window"],
                              extra={"use": "police station + 2-bay sally port (service-sites §3)"}, wing_kinds=None, wing_mwx=6.0)
    build("bld_police", bx, anchors=an, extra=ex, sub="core")
def fire():   # 2 apparatus bays (doors 4.3 x 4.3, 20 m deep) hall 6.0; office wing 1 storey 4.5; training tower to 12.0 on the hall roof
    ow, yo, Wo, D = ring(3, 7, [4.5], "brick_red", front_ground=["window", "entry", "window"])          # office, left
    hl, yh, Wh, Dh = ring(2, 7, [6.0], "brick_red", front_ground=["baydoor", "baydoor"], x0=Wo - T, mwx=6.0)  # hall, 2 x 6 m bays
    tz0 = 9.0; tw, yt, Wt, Dt = ring(2, 3, [3.0, 3.0], "brick_red", kinds=["window", "blank"], x0=Wo - T + 3.0, z0=tz0, base=yh)
    bx = ow + hl + tw
    bx += guards(0, 0, Wo - T, D, yo, ("back", "left"))                    # office deck: front flush (walk), hall wall on its right
    bx += guards(Wo - T, 0, Wh, D, yh, ("front", "back", "right"))         # hall roof: front guard (above the bay doors = apron)
    bx += guards(Wo - T + 3.0, tz0, Wt, Dt, yt, ("left", "right", "back"))  # tower: front (faces the hall-roof landing) flush
    hx = Wo - T
    build("bld_fire_station", bx, sub="core",
          anchors={"ray|office_deck": (Wo / 2, yo, D / 2), "ray|office_edge": (Wo / 2, yo, 0.05), "ray|hall_deck": (hx + Wh / 2, yh, 4.0),
                   "ray|hall_edge_over_office": (hx + 0.05, yh, D / 2), "ray|hall_guard_front": (hx + Wh / 2, yh + GH, T / 2),
                   "ray|tower_deck": (hx + 3.0 + Wt / 2, yt, tz0 + Dt / 2), "ray|tower_edge": (hx + 3.0 + Wt / 2, yt, tz0 + 0.05),
                   "ray|tower_guard_back": (hx + 3.0 + Wt / 2, yt + GH, tz0 + Dt - T / 2), "ray|bay_door_clear": (hx + 3.0, -99, -1.0),
                   "bay_doors_centre_ground": (hx + Wh / 2, 0, 0), "front_face_centre_ground": ((Wo + Wh - T) / 2, 0, 0)},
          extra={"use": "fire station: 2 bays (fire + ambulance, Phase 1 civic depot), training tower (T3 12 m roof goal)",
                 "rises_m": [yo, round(yh - yo, 2), round(yt - yh, 2)], "decks_m": [yo, yh, yt], "bay_doors_m": [4.3, 4.3], "bay_depth_m": round(D, 2),
                 "climb": "office front from the walk (4.5) -> hall roof over the office (1.5) -> tower front from the hall roof (6.0)",
                 "apron": "keep >= 15 m apron in front of the bays; the bay front is NOT a stack pad (driveway)", "footprint_m": [round(Wo + Wh - T, 2), round(D, 2)]})
def hospital():  # 4 storeys: podium 4.5 | +2 -> 11.5 | +1 -> 15.0 (T3); rises 4.5 / 7.0 / 3.5
    stepped("bld_hospital", 8, [7, 5, 4], [[4.5], [3.5, 3.5], [3.5]], "stucco_tan",
            ["window", "window", "entry", "entry", "entry", "entry", "window", "window"], upper="window",
            extra={"use": "hospital (W ring); ambulance canopy is the separate hospital_ambulance_canopy glb"},
            top_extra=(lambda W, D, z: bulkhead(W / 2, D - 2.5, z[1]),))
def canopy():   # drive-through ambulance canopy, clearance 4.3 (H6 overhead hazard), 12 x 8, deck 4.9 (not a climb goal)
    bx = [B(-6, 4.3, -4, 6, 4.9, 4, "canopy_fascia", "roof_membrane")]
    for x in (-5.7, 5.7):
        for z in (-3.7, 3.7): bx.append(B(x - 0.2, 0, z - 0.2, x + 0.2, 4.3, z + 0.2, "canopy_fascia"))
    build("hospital_ambulance_canopy", bx, sub="core",
          anchors={"ray|underside_clear_centre": (0, 4.9, 0), "underside_y": (0, 4.3, 0)},
          extra={"clearance_m": 4.3, "note": "H6 overhead hazard: put the underside in group 'overhead' (layer 1); two 4 x 10 m stalls fit underneath"})
ALL = {"cityhall_quest_only": G["cityhall"], "prefabs_quest_only": G["prefabs"], "six_a": six_a, "six_b": six_b, "tower": tower, "school": school, "police": police, "fire": fire, "hospital": hospital, "canopy": canopy}
for n in (WANT or [k for k in ALL if not k.endswith("_quest_only")]): ALL[n]()
