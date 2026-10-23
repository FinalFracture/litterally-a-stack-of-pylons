#!/usr/bin/env python3
"""Write the RoadLab roads and the synthetic ground ops.

The dev area is 600 m by 600 m: x 100..700, z -2200..-1600 (Godot z, north is
negative). Seed heights are authored here. Strategy 0 grades them; it does not
grow curbs, sidewalks, signals, or a gate. Those stay in sites.json as
"not supported by strategy 0".
"""

from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ROADS_PATH = ROOT / "world/twin_falls/data/road_lab/roads.json"
TERRAIN_PATH = ROOT / "world/twin_falls/data/road_lab/terrain.json"

BASE = 120.0
X0, X1 = 100.0, 700.0
Z_N, Z_S = -2200.0, -1600.0


def r3(v: float) -> float:
    return round(v, 3)


def dist2(a, b) -> float:
    return math.hypot(a[0] - b[0], a[2] - b[2])


def sample_line(a, b, step=8.0):
    n = max(1, int(math.ceil(dist2(a, b) / step)))
    out = []
    for i in range(1, n + 1):
        t = i / n
        out.append(tuple(a[k] + (b[k] - a[k]) * t for k in range(3)))
    return out


def catmull(p0, p1, p2, p3, t):
    t2 = t * t
    t3 = t2 * t
    def ax(i):
        return 0.5 * (
            (2.0 * p1[i])
            + (-p0[i] + p2[i]) * t
            + (2.0 * p0[i] - 5.0 * p1[i] + 4.0 * p2[i] - p3[i]) * t2
            + (-p0[i] + 3.0 * p1[i] - 3.0 * p2[i] + p3[i]) * t3
        )
    return (ax(0), ax(1), ax(2))


def curve(controls, step=8.0):
    n = len(controls)
    ext = [controls[0], *controls, controls[-1]]
    pts = []
    for i in range(1, n):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        chord = dist2(p1, p2)
        steps = max(1, int(math.ceil(chord / step)))
        for s in range(steps):
            pts.append(catmull(p0, p1, p2, p3, s / steps))
    pts.append(controls[-1])
    clean = [pts[0]]
    for p in pts[1:]:
        if dist2(clean[-1], p) > 0.4:
            clean.append(p)
    return [(r3(p[0]), r3(p[1]), r3(p[2])) for p in clean]


class Net:
    def __init__(self):
        self.roads = []
        self.rails = []
        self.junctions = []
        self._n = 0

    def add(self, rid, name, cls, lanes, lane_w, points, segments=None, speed=25, note=""):
        pts = [(r3(p[0]), r3(p[1]), r3(p[2])) for p in points]
        segs = segments or [[0, len(pts) - 1, "grade"]]
        ids = [f"{rid}.s{i}" for i in range(len(segs))]
        self.roads.append({
            "id": rid,
            "name": name,
            "class": cls,
            "speed_mph": speed,
            "lanes": lanes,
            "lane_width_m": lane_w,
            "oneway": False,
            "bridge": any(s[2] == "bridge" for s in segs),
            "tunnel": False,
            "source": "ROADLAB",
            "note": note,
            "polyline": [list(p) for p in pts],
            "segments": segs,
            "segment_ids": ids,
        })
        return rid

    def add_rail(self, rid, name, points, note=""):
        pts = [(r3(p[0]), r3(p[1]), r3(p[2])) for p in points]
        self.rails.append({
            "id": rid,
            "name": name,
            "source": "ROADLAB",
            "gauge_m": 1.435,
            "max_grade": 0.015,
            "note": note,
            "polyline": [list(p) for p in pts],
            "segments": [[0, len(pts) - 1, "grade"]],
            "segment_ids": [f"{rid}.s0"],
        })

    def junction(self, roads, pos, note=""):
        self._n += 1
        self.junctions.append({
            "id": f"lab_{self._n:03d}",
            "pos": [r3(pos[0]), r3(pos[1]), r3(pos[2])],
            "roads": roads,
            "note": note,
        })


def grid(net: Net):
    xs = [120.0, 175.0, 230.0, 285.0]
    zs = [-2175.0, -2120.0, -2065.0, -2010.0]
    y = BASE
    for i, x in enumerate(xs):
        net.add(
            f"lab_nw_st_{i}",
            f"RoadLab {i + 1}st",
            "downtown",
            2,
            3.3,
            [(x, y, zs[0]), (x, y, zs[-1])],
            speed=25,
            note="NW downtown grid street. Curbs, sidewalks and ADA ramps are not geometry.",
        )
    for i, z in enumerate(zs):
        net.add(
            f"lab_nw_av_{i}",
            f"RoadLab {i + 1} Ave",
            "downtown",
            2,
            3.3,
            [(xs[0], y, z), (xs[-1], y, z)],
            speed=25,
            note="NW downtown grid avenue.",
        )
    # Diagonal across the blocks, corner to corner.
    net.add(
        "lab_nw_diag",
        "RoadLab Diagonal",
        "downtown",
        2,
        3.3,
        [(xs[0], y, zs[0]), (xs[-1], y, zs[-1])],
        note="NW diagonal through the 3x3 blocks.",
    )
    for ix, x in enumerate(xs):
        for iz, z in enumerate(zs):
            net.junction(
                [f"lab_nw_st_{ix}", f"lab_nw_av_{iz}"],
                (x, y, z),
                "downtown crossing. 6 m returns, crosswalks, ADA ramps: not supported by strategy 0",
            )
    # Bus bay just south of the south avenue, between streets 1 and 2.
    bay_z = zs[-1] + 7.0
    net.add(
        "lab_nw_bus_bay",
        "RoadLab Bus Bay",
        "downtown",
        1,
        3.3,
        [(xs[1], y, zs[-1]), (xs[1], y, bay_z), (xs[2], y, bay_z), (xs[2], y, zs[-1])],
        note="Bus pullout centreline. Shelter pad is not supported by strategy 0.",
    )
    net.junction(["lab_nw_bus_bay", "lab_nw_st_1", "lab_nw_av_3"], (xs[1], y, zs[-1]), "bus bay west tie-in")
    net.junction(["lab_nw_bus_bay", "lab_nw_st_2", "lab_nw_av_3"], (xs[2], y, zs[-1]), "bus bay east tie-in")
    return (xs[-1], y, zs[-1])


def arterial(net: Net):
    y = BASE
    cross = (560.0, y, -2100.0)
    net.add(
        "lab_ne_two_lane",
        "RoadLab Arterial West",
        "urban_arterial",
        2,
        3.6,
        [(430.0, y, -2100.0), cross],
        speed=40,
        note="2-lane side of the signalised junction. Stop bars are not supported by strategy 0.",
    )
    # 50 m past the east edge (x = 700).
    net.add(
        "lab_ne_four_lane",
        "RoadLab Arterial East",
        "urban_arterial",
        4,
        3.6,
        [cross, (750.0, y, -2100.0)],
        speed=40,
        note="4-lane side. Strategy 0 tapers where this road ends at the junction. The run past x=700 is the dev-area exit, not the Twin Falls map edge.",
    )
    # 50 m past the north edge (z = -2200).
    net.add(
        "lab_ne_cross",
        "RoadLab Cross Street",
        "urban_arterial",
        2,
        3.6,
        [(560.0, y, -2250.0), (560.0, y, -1980.0)],
        speed=35,
        note="Cross street. North end runs 50 m past the dev-area edge. Signals and 12-15 m return arcs are not supported by strategy 0.",
    )
    net.junction(
        ["lab_ne_two_lane", "lab_ne_four_lane", "lab_ne_cross"],
        cross,
        "signalised arterial junction. Signals, stop bars, 12-15 m returns: not supported by strategy 0",
    )


def centre(net: Net):
    # Lab control points, scaled into the middle of the dev area.
    # Origin is the lab's (48, 35). Scale keeps the S, hairpins, T, Y and 6-leg.
    scale = 0.40
    ox, oz = 310.0, -2035.0

    def lab(lx, off, lz):
        return (ox + (lx - 48.0) * scale, BASE + off * 0.35, oz + (lz - 35.0) * scale)

    def on_line(dist, offset):
        rad = math.radians(-30.0)
        return lab(400.0 + math.cos(rad) * dist, offset, 340.0 + math.sin(rad) * dist)

    def ray(angle, dist, offset):
        rad = math.radians(angle)
        return lab(400.0 + math.cos(rad) * dist, offset, 340.0 + math.sin(rad) * dist)

    split = lab(300, 1.2, 270)
    tee = lab(230, 0.8, 230)
    merge = on_line(-170.0, -0.7)
    junction = on_line(0.0, -1.2)
    south_bend = lab(455, 1.0, 210)
    y_point = lab(340, 0.5, 80)
    spine = [
        lab(48, 0.0, 70),
        lab(125, 0.8, 125),
        lab(190, 1.6, 55),
        lab(270, 2.6, 145),
        lab(330, 2.0, 210),
        split,
        tee,
        lab(145, 0.3, 300),
        lab(185, -0.2, 370),
        merge,
        on_line(-110.0, -0.95),
        on_line(-55.0, -1.2),
        junction,
        on_line(55.0, -1.2),
        on_line(100.0, -0.4),
        south_bend,
        lab(490, 1.6, 150),
        lab(430, 1.1, 100),
        y_point,
    ]
    net.add("lab_c_spine", "RoadLab S-curve", "collector", 2, 3.3, curve(spine), speed=25,
            note="Centre S-curve, hairpins and the spine of the 6-leg. Reused from the strategy lab layout.")
    net.add("lab_c_bypass", "RoadLab Bypass", "collector", 2, 3.3, curve([
        split, lab(365, 0.6, 305), lab(330, 0.0, 345), merge,
    ]), note="Bypass that merges back.")
    net.add("lab_c_tee", "RoadLab T Spur", "local", 2, 3.3, curve([
        tee, lab(60, 0.2, 155),
    ]), note="T spur off the hairpin.")
    net.add("lab_c_ns", "RoadLab North-South", "collector", 2, 3.3, curve([
        ray(90.0, 130.0, 0.2), ray(90.0, 55.0, -1.2), junction, ray(270.0, 55.0, -1.2), ray(270.0, 130.0, 0.2),
    ]), note="North-south leg of the 6-leg junction.")
    net.add("lab_c_diag", "RoadLab Six-leg Diagonal", "local", 2, 3.3, curve([
        ray(35.0, 95.0, 0.0), ray(35.0, 50.0, -1.2), junction,
    ]), note="Diagonal into the 6-leg.")
    net.add("lab_c_fork", "RoadLab Fork", "local", 2, 3.3, curve([
        junction, ray(-60.0, 36.0, -1.2), ray(-60.0, 72.0, 0.1),
    ]), note="Short fork off the 6-leg.")
    net.add("lab_c_y_west", "RoadLab Y West", "local", 2, 3.3, curve([
        y_point, lab(230, 0.0, 35),
    ]), note="West arm of the Y.")
    net.add("lab_c_y_east", "RoadLab Y East", "local", 2, 3.3, curve([
        y_point, lab(430, 0.9, 35),
    ]), note="East arm of the Y.")
    net.add("lab_c_spur", "RoadLab Short Spur", "local", 1, 3.3, curve([
        south_bend, lab(400, 1.4, 150),
    ]), note="Short spur off the south bend.")
    net.junction(["lab_c_spine", "lab_c_bypass"], split, "bypass split")
    net.junction(["lab_c_spine", "lab_c_tee"], tee, "T junction")
    net.junction(["lab_c_spine", "lab_c_bypass"], merge, "bypass merge")
    net.junction(
        ["lab_c_spine", "lab_c_ns", "lab_c_diag", "lab_c_fork"],
        junction,
        "6-leg junction. Corner arcs are not supported by strategy 0.",
    )
    net.junction(["lab_c_spine", "lab_c_y_west", "lab_c_y_east"], y_point, "Y junction")
    net.junction(["lab_c_spine", "lab_c_spur"], south_bend, "south spur")
    return spine[0]


def canyon(net: Net):
    pts = [(160.0, 145.0, -1845.0)]

    def line_to(x, z, grade=0.10):
        a = pts[-1]
        b = (x, a[1] - grade * math.hypot(x - a[0], z - a[2]), z)
        pts.extend(sample_line(a, b, 8.0))

    def hairpin(cx, cz, radius, a0, a1, steps=12, grade=0.10):
        sweep = a1 - a0
        length = abs(sweep) * radius
        y0 = pts[-1][1]
        y1 = y0 - grade * length
        for i in range(1, steps + 1):
            t = i / steps
            a = a0 + sweep * t
            pts.append((cx + radius * math.cos(a), y0 + (y1 - y0) * t, cz + radius * math.sin(a)))

    line_to(160.0, -1760.0)
    # Bulge west, into the rock, then leave heading north.
    hairpin(173.0, -1760.0, 13.0, math.pi, 0.0)
    line_to(186.0, -1825.0)
    hairpin(199.0, -1825.0, 13.0, math.pi, 2.0 * math.pi)
    line_to(212.0, -1705.0)
    end_y = pts[-1][1]
    # Flat pad road, no grade.
    pad = [(212.0, end_y, -1705.0), (150.0, end_y, -1688.0), (150.0, end_y, -1662.0)]
    net.add(
        "lab_sw_grade",
        "RoadLab Canyon Grade",
        "grade",
        2,
        3.05,
        pts,
        speed=25,
        note="10% grade, 13 m hairpins. 3 m benches on the 76 degree cut are not supported by strategy 0.",
    )
    net.add(
        "lab_sw_pad",
        "RoadLab Level Pad",
        "service",
        1,
        3.3,
        pad,
        note="Flat pad at the bottom of the grade.",
    )
    net.junction(["lab_sw_grade", "lab_sw_pad"], pts[-1], "grade meets the level pad")
    return pts[0], end_y


def rim(net: Net):
    y = BASE
    net.add(
        "lab_se_rim",
        "RoadLab Rim",
        "rim_local",
        2,
        3.3,
        [(430.0, y, -1788.0), (680.0, y, -1788.0)],
        speed=25,
        note="Rim road. The ground drops more than 30 m just north of the edge. A distinct 0.8 m concrete barrier is not supported by strategy 0; the builder may emit its guard wall.",
    )
    # Approaches and a pinned deck across the slot.
    west = [(430.0, y, -1735.0), (500.0, y, -1735.0), (519.0, y, -1735.0)]
    # 19 m deck is the last authored span. Indices 1..2.
    net.add(
        "lab_se_approach_w",
        "RoadLab Bridge Approach West",
        "urban_arterial",
        2,
        3.6,
        west,
        segments=[[0, 1, "grade"], [1, 2, "deck"]],
        speed=35,
        note="19 m approach slab is the deck-kind tail. Abutment fill is not supported by strategy 0.",
    )
    net.add(
        "lab_se_bridge",
        "RoadLab Bridge",
        "urban_arterial",
        2,
        3.6,
        [(519.0, y, -1735.0), (641.0, y, -1735.0)],
        segments=[[0, 1, "bridge"]],
        note="Pinned deck at y=120. Strategy 0 emits the bridge shoulder parapets. It is not the Perrine asset.",
    )
    east = [(641.0, y, -1735.0), (660.0, y, -1735.0), (700.0, y, -1735.0)]
    net.add(
        "lab_se_approach_e",
        "RoadLab Bridge Approach East",
        "urban_arterial",
        2,
        3.6,
        east,
        segments=[[0, 1, "deck"], [1, 2, "grade"]],
        note="19 m approach slab is the deck-kind head.",
    )
    net.junction(["lab_se_approach_w", "lab_se_bridge"], (519.0, y, -1735.0), "west abutment line")
    net.junction(["lab_se_bridge", "lab_se_approach_e"], (641.0, y, -1735.0), "east abutment line")
    net.add(
        "lab_se_closure",
        "RoadLab Lane Closure Pad",
        "service",
        1,
        3.3,
        [(470.0, y, -1755.0), (530.0, y, -1755.0)],
        note="Flat pad beside the approach. Closure furniture is not supported by strategy 0.",
    )
    net.add_rail(
        "lab_se_rail",
        "RoadLab Freight",
        [(450.0, y, -1695.0), (690.0, y, -1665.0)],
        note="Freight line. Crossing panels are visual in strategy 0 and are not a solid crossing.",
    )
    net.add(
        "lab_se_crossing_road",
        "RoadLab Rail Crossing",
        "local",
        2,
        3.3,
        [(540.0, y, -1710.0), (575.0, y, -1655.0)],
        note="Road across the freight line. The crossing surface is not supported by strategy 0.",
    )
    # 4.9 m between the upper road (120) and the lower road (115.1). No shared junction.
    net.add(
        "lab_se_overpass",
        "RoadLab Overpass",
        "urban_arterial",
        2,
        3.6,
        [(610.0, y, -1840.0), (610.0, y, -1760.0)],
        note="Upper road of the underpass. The 4.9 m structure is not supported by strategy 0.",
    )
    net.add(
        "lab_se_underpass",
        "RoadLab Underpass",
        "local",
        2,
        3.3,
        [(560.0, 115.1, -1800.0), (680.0, 115.1, -1800.0)],
        note="Lower road. Clearance to the overpass centreline is 4.9 m. Strategy 0 does not build the structure.",
    )


def south(net: Net):
    y = BASE
    stem = [(340.0, y, -1685.0), (340.0, y, -1632.0)]
    # 12 m bulb. The stem arrives from the north at angle -pi/2 in this
    # parameterisation (centre + (0, -12) is the north tie).
    cx, cz, rad = 340.0, -1620.0, 12.0
    bulb = [stem[-1]]
    steps = 16
    for i in range(1, steps + 1):
        a = -math.pi / 2.0 + (2.0 * math.pi * i / steps)
        bulb.append((cx + rad * math.cos(a), y, cz + rad * math.sin(a)))
    net.add("lab_s_stem", "RoadLab Cul-de-sac Stem", "local", 2, 3.3, stem,
            note="Dead-end stem into the 12 m bulb.")
    net.add("lab_s_bulb", "RoadLab Cul-de-sac Bulb", "local", 2, 3.3, bulb,
            note="12 m bulb. The gravel apron and the end-of-road sign are not supported by strategy 0.")
    net.junction(["lab_s_stem", "lab_s_bulb"], stem[-1], "bulb tie-in")
    net.add(
        "lab_s_service",
        "RoadLab Service",
        "service",
        1,
        3.0,
        [(390.0, y, -1648.0), (470.0, y, -1636.0)],
        speed=10,
        note="Fictional service road. The gate is not supported by strategy 0.",
    )


def links(net: Net, nw_corner, centre_start, sw_start):
    y = BASE
    # Tie the downtown grid's southeast corner to the S-curve start.
    net.add(
        "lab_link_nw",
        "RoadLab Link Northwest",
        "local",
        2,
        3.3,
        [nw_corner, centre_start],
        note="Connects the downtown grid to the centre spine.",
    )
    net.junction(["lab_link_nw", "lab_nw_st_3", "lab_nw_av_3"], nw_corner, "grid to centre")
    net.junction(["lab_link_nw", "lab_c_spine"], centre_start, "centre spine start")
    # Centre's south end is the Y. Tie the west Y arm's end toward the canyon start
    # with a road whose ends are the Y-west end and the canyon start. The Y-west
    # end is whatever the curve wrote; look it up.
    y_west = next(r for r in net.roads if r["id"] == "lab_c_y_west")
    y_end = tuple(y_west["polyline"][-1])
    net.add(
        "lab_link_sw",
        "RoadLab Link Southwest",
        "collector",
        2,
        3.3,
        [y_end, sw_start],
        note="Connects the centre Y to the canyon grade.",
    )
    net.junction(["lab_link_sw", "lab_c_y_west"], y_end, "Y to the grade link")
    net.junction(["lab_link_sw", "lab_sw_grade"], sw_start, "canyon grade start")
    # East link from the 4-lane's west junction neighborhood down to the rim.
    net.add(
        "lab_link_se",
        "RoadLab Link Southeast",
        "collector",
        2,
        3.3,
        [(560.0, y, -1980.0), (500.0, y, -1788.0)],
        note="Connects the arterial cross street to the rim road.",
    )
    net.junction(["lab_link_se", "lab_ne_cross"], (560.0, y, -1980.0), "cross street south end")
    # South stem up to the rim so the cul-de-sac is on the same component.
    net.add(
        "lab_link_s",
        "RoadLab Link South",
        "local",
        2,
        3.3,
        [(500.0, y, -1788.0), (340.0, y, -1685.0)],
        note="Connects the rim to the cul-de-sac stem.",
    )
    net.junction(["lab_link_s", "lab_se_rim", "lab_link_se"], (500.0, y, -1788.0), "rim south link")
    # The service road's west end is tied to the stem so the dev area is one component.
    # The gate itself is not a mesh.
    net.roads.append({
        "id": "lab_link_service",
        "name": "RoadLab Service Tie",
        "class": "service",
        "speed_mph": 10,
        "lanes": 1,
        "lane_width_m": 3.0,
        "oneway": False,
        "bridge": False,
        "tunnel": False,
        "source": "ROADLAB",
        "note": "Ties the gated service road into the stem. The gate itself is not supported by strategy 0.",
        "polyline": [[340.0, y, -1685.0], [390.0, y, -1648.0]],
        "segments": [[0, 1, "grade"]],
        "segment_ids": ["lab_link_service.s0"],
    })
    net.junction(["lab_link_service", "lab_s_stem", "lab_link_s"], (340.0, y, -1685.0), "service tie")
    net.junction(["lab_link_service", "lab_s_service"], (390.0, y, -1648.0), "service road west end")


def terrain(pad_y: float):
    return {
        "seed": 20261008,
        "base_y": BASE,
        "note": "Synthetic lidar for RoadLab. Ops apply in order. z0 is the north edge (more negative).",
        "ops": [
            {
                "op": "plane",
                "x0": 110.0, "z0": -1850.0, "x1": 360.0, "z1": -1640.0,
                "y_at_z0": 145.0, "y_at_z1": 128.0,
                "note": "SW hillside, about 8% across the block. The road is authored at 10%.",
            },
            {
                "op": "add",
                "x0": 110.0, "z0": -1835.0, "x1": 200.0, "z1": -1700.0,
                "dy": 25.0,
                "note": "Benched-rock mass, about 25 m of relief. Strategy 0 does not cut 3 m benches.",
            },
            {
                "op": "add",
                "x0": 230.0, "z0": -1800.0, "x1": 340.0, "z1": -1680.0,
                "dy": -8.0,
                "note": "Fill side of the grade.",
            },
            {
                "op": "flat",
                "x0": 130.0, "z0": -1700.0, "x1": 200.0, "z1": -1655.0,
                "y": r3(pad_y),
                "note": "Level pad. The road's authored end sets the real pad height; this is the ground.",
            },
            {
                "op": "slot",
                "x0": 500.0, "z0": -1765.0, "x1": 660.0, "z1": -1705.0,
                "floor_y": 86.0, "lip_m": 6.0,
                "note": "Bridge gorge, 34 m below the deck.",
            },
            {
                "op": "drop_north",
                "z_line": -1782.0,
                "x0": 430.0, "x1": 690.0,
                "floor_y": 86.0, "lip_m": 5.0,
                "note": "Rim drop just north of the rim road. More than 30 m.",
            },
        ],
    }


def main():
    net = Net()
    nw_corner = grid(net)
    arterial(net)
    centre_start = centre(net)
    sw_start, pad_y = canyon(net)
    rim(net)
    south(net)
    links(net, nw_corner, centre_start, sw_start)
    # Drop the bogus junction inserted by the `if False` placeholder if any
    # duplicate ids slipped in. Junction ids are unique by counter.
    doc = {
        "map": "RoadLab",
        "generated": "2026-10-23",
        "source": "ROADLAB",
        "seed": 20261008,
        "coords": "[x, y, z_godot]; dev area x 100..700, z -2200..-1600",
        "note": "Synthetic network for the bake-off. Segment ids are stable. Features strategy 0 cannot build are listed in tools/road_bakeoff/sites.json.",
        "roads": net.roads,
        "intersections": net.junctions,
        "railways": net.rails,
    }
    ROADS_PATH.parent.mkdir(parents=True, exist_ok=True)
    ROADS_PATH.write_text(json.dumps(doc, indent=1) + "\n")
    TERRAIN_PATH.write_text(json.dumps(terrain(pad_y), indent=1) + "\n")
    print(f"pad_y {pad_y:.2f}")
    print(f"roads {len(net.roads)} rails {len(net.rails)} junctions {len(net.junctions)}")
    print(f"wrote {ROADS_PATH}")
    print(f"wrote {TERRAIN_PATH}")
    # Bounds
    xs, zs = [], []
    for road in net.roads + net.rails:
        for p in road["polyline"]:
            xs.append(p[0])
            zs.append(p[2])
    print(f"span x {min(xs):.1f}..{max(xs):.1f}  z {min(zs):.1f}..{max(zs):.1f}")


if __name__ == "__main__":
    main()
