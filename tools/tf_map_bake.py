#!/usr/bin/env python3
"""Bake the Twin Falls playtest map base from the terrain tiles.

Rerun from the repo root after tiles, water.json, or the slice bounds change:

    python tools/tf_map_bake.py

Writes world/twin_falls/data/map/:
  map_base.png     hypsometric tint, NW hillshade, river, canyon rim (~2 m/px)
  map_height.png   terrain y packed in R (high) and G (low): y = (R*256+G)*0.01 - 50
  contours.json    10 m contours (50 m majors) in world x, z_north

The whole 5 x 8 km slice is one image. On a 1080p screen, 1x fits the slice
and 32x is about 4 px/m, which is what the base is for.
"""

from __future__ import annotations

import json
import os
from collections import defaultdict

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DATA = os.path.join(ROOT, "world", "twin_falls", "data")
OUT = os.path.join(DATA, "map")

WORLD_W = 5000.0
WORLD_H = 8000.0
MPP = 2.0
W = int(WORLD_W / MPP)
H = int(WORLD_H / MPP)
TILE_SP = 500.0 / 128.0
RIVER_HALF_M = 20.0


def load_mosaic() -> np.ndarray:
    """Tile samples, row 0 at the north edge, col 0 at the west edge."""
    rows = 16 * 128 + 1
    cols = 10 * 128 + 1
    mosaic = np.zeros((rows, cols), np.float32)
    for cx in range(10):
        for cz in range(16):
            path = os.path.join(DATA, "tiles", "c_%d_%d.png" % (cx, cz))
            tile = np.array(Image.open(path), dtype=np.float32) * 0.01 - 50.0
            if tile.shape != (129, 129):
                raise SystemExit("bad tile shape %s %s" % (path, tile.shape))
            r0 = (15 - cz) * 128
            c0 = cx * 128
            mosaic[r0 : r0 + 129, c0 : c0 + 129] = tile
    return mosaic


def resample(mosaic: np.ndarray) -> np.ndarray:
    """Bilinear sample at pixel centres. Pixel (col, row) covers the 2 m cell."""
    xs = (np.arange(W, dtype=np.float32) + 0.5) * MPP
    zns = WORLD_H - (np.arange(H, dtype=np.float32) + 0.5) * MPP
    col = xs / TILE_SP
    row = ((WORLD_H - zns) / TILE_SP).reshape(-1, 1)
    col = col.reshape(1, -1)
    c0 = np.floor(col).astype(np.int32)
    r0 = np.floor(row).astype(np.int32)
    c0 = np.clip(c0, 0, mosaic.shape[1] - 2)
    r0 = np.clip(r0, 0, mosaic.shape[0] - 2)
    tx = col - c0
    ty = row - r0
    h00 = mosaic[r0, c0]
    h10 = mosaic[r0, c0 + 1]
    h01 = mosaic[r0 + 1, c0]
    h11 = mosaic[r0 + 1, c0 + 1]
    return (h00 * (1.0 - tx) + h10 * tx) * (1.0 - ty) + (h01 * (1.0 - tx) + h11 * tx) * ty


def hypsometric(height: np.ndarray) -> np.ndarray:
    stops_y = np.array([-12.0, 10.0, 45.0, 90.0, 130.0, 165.0, 210.0], np.float32)
    stops_c = np.array(
        [
            [22, 58, 62],
            [34, 86, 74],
            [62, 128, 68],
            [118, 146, 74],
            [164, 136, 82],
            [184, 154, 108],
            [214, 190, 148],
        ],
        np.float32,
    )
    flat = height.ravel()
    channels = [np.interp(flat, stops_y, stops_c[:, i]).reshape(height.shape) for i in range(3)]
    return np.stack(channels, axis=-1)


def hillshade(height: np.ndarray) -> np.ndarray:
    """Sun from the northwest, 45 degrees above the horizon. 1 = full light."""
    gy, gx = np.gradient(height, MPP)
    d_east = gx
    d_north = -gy
    nx = -d_east
    ny = np.ones_like(height)
    nz = -d_north
    norm = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx /= norm
    ny /= norm
    nz /= norm
    alt = np.deg2rad(45.0)
    az = np.deg2rad(315.0)
    sun_e = np.sin(az) * np.cos(alt)
    sun_n = np.cos(az) * np.cos(alt)
    sun_u = np.sin(alt)
    shade = nx * sun_e + ny * sun_u + nz * sun_n
    return np.clip(shade, 0.0, 1.0).astype(np.float32)


def water_mask() -> np.ndarray:
    water = json.load(open(os.path.join(DATA, "water.json"), encoding="utf-8"))
    img = Image.new("L", (W, H), 0)
    draw = ImageDraw.Draw(img)
    width_px = int(round(RIVER_HALF_M * 2.0 / MPP))
    pts = []
    for v in water["vertices"]:
        x = float(v["x"])
        zn = float(v["z_north"])
        px = x / MPP
        py = (WORLD_H - zn) / MPP
        pts.append((px, py))
    if len(pts) >= 2:
        draw.line(pts, fill=255, width=width_px, joint="curve")
    r = width_px * 0.5
    for px, py in pts:
        draw.ellipse((px - r, py - r, px + r, py + r), fill=255)
    return np.array(img) > 0


def rim_mask(height: np.ndarray) -> np.ndarray:
    gy, gx = np.gradient(height, MPP)
    slope = np.degrees(np.arctan(np.hypot(gx, gy)))
    steep = slope > 32.0
    eroded = steep.copy()
    eroded[1:-1, 1:-1] = (
        steep[1:-1, 1:-1]
        & steep[:-2, 1:-1]
        & steep[2:, 1:-1]
        & steep[1:-1, :-2]
        & steep[1:-1, 2:]
    )
    return steep & ~eroded & (height > 40.0)


def paint(height: np.ndarray) -> np.ndarray:
    shade = hillshade(height)
    rgb = hypsometric(height) * (0.40 + 0.60 * shade)[..., None]
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)
    rim = rim_mask(height)
    rgb[rim] = np.array([42, 34, 30], np.uint8)
    wet = water_mask()
    rgb[wet] = np.array([0x4A, 0x90, 0xC8], np.uint8)
    return rgb


def world_of(row: float, col: float, step: float) -> tuple[float, float]:
    x = col * step
    zn = WORLD_H - row * step
    return (float(x), float(zn))


def march(height: np.ndarray, level: float, step: float) -> list[list[tuple[float, float]]]:
    """Marching squares. height row 0 is north. Returns polylines of (x, z_north)."""
    nw = height[:-1, :-1]
    ne = height[:-1, 1:]
    se = height[1:, 1:]
    sw = height[1:, :-1]
    code = (
        (nw >= level).astype(np.uint8)
        | ((ne >= level).astype(np.uint8) << 1)
        | ((se >= level).astype(np.uint8) << 2)
        | ((sw >= level).astype(np.uint8) << 3)
    )
    edge = (code != 0) & (code != 15)
    rs, cs = np.nonzero(edge)
    segs: list[tuple[tuple[float, float], tuple[float, float]]] = []

    def lerp(v0: float, v1: float, p0: tuple[float, float], p1: tuple[float, float]) -> tuple[float, float]:
        den = v1 - v0
        t = 0.5 if abs(den) < 1e-6 else (level - v0) / den
        t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
        return (p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t)

    # Saddle split: average of the four corners picks the diagonal.
    for r, c in zip(rs.tolist(), cs.tolist()):
        k = int(code[r, c])
        va = float(nw[r, c])
        vb = float(ne[r, c])
        vc = float(se[r, c])
        vd = float(sw[r, c])
        n = world_of(r, c, step)
        e = world_of(r, c + 1, step)
        s = world_of(r + 1, c + 1, step)
        w = world_of(r + 1, c, step)
        top = lerp(va, vb, n, e)
        right = lerp(vb, vc, e, s)
        bottom = lerp(vd, vc, w, s)
        left = lerp(va, vd, n, w)
        pairs = {
            1: [(left, top)],
            2: [(top, right)],
            3: [(left, right)],
            4: [(right, bottom)],
            5: [(left, top), (right, bottom)] if (va + vb + vc + vd) * 0.25 >= level else [(top, right), (left, bottom)],
            6: [(top, bottom)],
            7: [(left, bottom)],
            8: [(bottom, left)],
            9: [(bottom, top)],
            10: [(top, right), (left, bottom)] if (va + vb + vc + vd) * 0.25 >= level else [(left, top), (right, bottom)],
            11: [(bottom, right)],
            12: [(right, left)],
            13: [(right, top)],
            14: [(top, left)],
        }
        for p0, p1 in pairs.get(k, []):
            segs.append((p0, p1))
    return _stitch(segs)


def _key(p: tuple[float, float]) -> tuple[int, int]:
    return (int(round(p[0] * 4.0)), int(round(p[1] * 4.0)))


def _stitch(segs: list[tuple[tuple[float, float], tuple[float, float]]]) -> list[list[tuple[float, float]]]:
    adj: dict[tuple[int, int], list[tuple[int, int]]] = defaultdict(list)
    pos: dict[tuple[int, int], tuple[float, float]] = {}
    for a, b in segs:
        ka, kb = _key(a), _key(b)
        if ka == kb:
            continue
        adj[ka].append(kb)
        adj[kb].append(ka)
        pos[ka] = a
        pos[kb] = b
    used: set[tuple[tuple[int, int], tuple[int, int]]] = set()
    lines: list[list[tuple[float, float]]] = []

    def take(a: tuple[int, int], b: tuple[int, int]) -> bool:
        edge = (a, b) if a < b else (b, a)
        if edge in used:
            return False
        used.add(edge)
        return True

    for start in list(adj.keys()):
        if len(adj[start]) != 1:
            continue
        nxts = [n for n in adj[start] if take(start, n)]
        if not nxts:
            continue
        chain = [start, nxts[0]]
        while True:
            cur = chain[-1]
            prev = chain[-2]
            nxts = [n for n in adj[cur] if n != prev and take(cur, n)]
            if not nxts:
                break
            chain.append(nxts[0])
        lines.append([pos[k] for k in chain])
    for start in list(adj.keys()):
        nxts = [n for n in adj[start] if take(start, n)]
        if not nxts:
            continue
        chain = [start, nxts[0]]
        while True:
            cur = chain[-1]
            prev = chain[-2]
            nxts = [n for n in adj[cur] if n != prev and take(cur, n)]
            if not nxts:
                break
            chain.append(nxts[0])
            if chain[-1] == chain[0]:
                break
        lines.append([pos[k] for k in chain])
    return lines


def _dist_point_seg(p, a, b) -> float:
    abx, aby = b[0] - a[0], b[1] - a[1]
    apx, apy = p[0] - a[0], p[1] - a[1]
    den = abx * abx + aby * aby
    t = 0.0 if den < 1e-8 else max(0.0, min(1.0, (apx * abx + apy * aby) / den))
    dx, dy = a[0] + abx * t - p[0], a[1] + aby * t - p[1]
    return (dx * dx + dy * dy) ** 0.5


def simplify(pts: list[tuple[float, float]], eps: float) -> list[tuple[float, float]]:
    if len(pts) < 3:
        return pts
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        i0, i1 = stack.pop()
        if i1 <= i0 + 1:
            continue
        best_i = i0
        best_d = -1.0
        a, b = pts[i0], pts[i1]
        for i in range(i0 + 1, i1):
            d = _dist_point_seg(pts[i], a, b)
            if d > best_d:
                best_d = d
                best_i = i
        if best_d > eps:
            keep[best_i] = True
            stack.append((i0, best_i))
            stack.append((best_i, i1))
    return [p for p, k in zip(pts, keep) if k]


def build_contours(height: np.ndarray) -> dict:
    step = 4.0
    small = height[::2, ::2]
    lines = []
    for level in range(0, 211, 10):
        raw = march(small, float(level), step)
        major = level % 50 == 0
        eps = 6.0 if major else 10.0
        for pts in raw:
            if len(pts) < 4:
                continue
            span = abs(pts[0][0] - pts[-1][0]) + abs(pts[0][1] - pts[-1][1])
            if span < 40.0 and len(pts) < 8:
                continue
            simp = simplify(pts, eps)
            if len(simp) < 2:
                continue
            flat: list[float] = []
            for x, zn in simp:
                flat.append(round(x, 1))
                flat.append(round(zn, 1))
            lines.append({"y": level, "major": major, "pts": flat})
    return {"step_m": step, "lines": lines}


def write_height(height: np.ndarray) -> None:
    u = np.clip(np.round((height + 50.0) / 0.01), 0, 65535).astype(np.uint16)
    hi = (u >> 8).astype(np.uint8)
    lo = (u & 255).astype(np.uint8)
    rgb = np.dstack([hi, lo, np.zeros_like(hi)])
    Image.fromarray(rgb, "RGB").save(os.path.join(OUT, "map_height.png"), optimize=True)


def sample_check(height: np.ndarray) -> None:
    def at(x: float, zn: float) -> float:
        c = x / MPP - 0.5
        r = (WORLD_H - zn) / MPP - 0.5
        c0 = int(np.clip(np.floor(c), 0, W - 2))
        r0 = int(np.clip(np.floor(r), 0, H - 2))
        tx = float(c - c0)
        ty = float(r - r0)
        return float(
            height[r0, c0] * (1 - tx) * (1 - ty)
            + height[r0, c0 + 1] * tx * (1 - ty)
            + height[r0 + 1, c0] * (1 - tx) * ty
            + height[r0 + 1, c0 + 1] * tx * ty
        )

    print("spawn_y", round(at(3320.0, 6531.5), 2))
    print("bridge_water_y", round(at(3363.62, 6805.5), 2))
    print("h_range", round(float(height.min()), 2), round(float(height.max()), 2))


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    print("mosaic")
    mosaic = load_mosaic()
    print("resample", W, H)
    height = resample(mosaic)
    sample_check(height)
    print("paint")
    rgb = paint(height)
    Image.fromarray(rgb, "RGB").save(os.path.join(OUT, "map_base.png"), optimize=True)
    print("height png")
    write_height(height)
    print("contours")
    contours = build_contours(height)
    with open(os.path.join(OUT, "contours.json"), "w", encoding="utf-8") as f:
        json.dump(contours, f, separators=(",", ":"))
    print("contour_lines", len(contours["lines"]))
    print("done", OUT)


if __name__ == "__main__":
    main()
