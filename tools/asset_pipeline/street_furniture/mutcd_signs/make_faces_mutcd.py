"""MUTCD sign faces + plate outlines (in-house, PIL). Proportions approximate the FHWA Standard Highway Signs layouts
[E: not traced from the SHS drawings]; colours are sRGB approximations of retroreflective sheeting [E].
Font: Overpass Bold (SIL OFL 1.1, ../_fonts) as a Highway-Gothic-like stand-in.
Writes faces/<id>.png and faces/outlines.json (plate outline in UV 0..1, v up; plate size in metres).
python3 make_faces_mutcd.py ../_fonts/Overpass-Bold.ttf"""
import sys, os, json, math
from PIL import Image, ImageDraw, ImageFont
FONT = sys.argv[1]; IN = 0.0254; SS = 2
RED, YEL, GRN, BLU = (176, 32, 42), (240, 186, 20), (0, 106, 72), (0, 58, 128)
WHT, BLK = (236, 236, 232), (24, 24, 24)
os.makedirs("faces", exist_ok=True); OUT = {}

def canvas(px_w, px_h, bg=(0, 0, 0)):
    im = Image.new("RGB", (px_w * SS, px_h * SS), bg); return im, ImageDraw.Draw(im)
def P(d, uv, W, H): return [(u * W * SS, (1 - v) * H * SS) for u, v in uv]
def inset(poly, k):   # scale polygon about its centroid (good enough for convex outlines)
    cx = sum(p[0] for p in poly) / len(poly); cy = sum(p[1] for p in poly) / len(poly)
    return [(cx + (x - cx) * k, cy + (y - cy) * k) for x, y in poly]
def text(d, s, cap_px, cx, cy, fill, W):
    size = 8
    while ImageFont.truetype(FONT, size).getbbox("H")[3] - ImageFont.truetype(FONT, size).getbbox("H")[1] < cap_px * SS: size += 2
    F = ImageFont.truetype(FONT, size); bb = d.textbbox((0, 0), s, font=F); hb = F.getbbox("H")
    while bb[2] - bb[0] > 0.86 * W * SS and size > 8:
        size -= 2; F = ImageFont.truetype(FONT, size); bb = d.textbbox((0, 0), s, font=F); hb = F.getbbox("H")
    d.text((cx * SS - (bb[2] - bb[0]) / 2 - bb[0], cy * SS - (hb[3] + hb[1]) / 2), s, font=F, fill=fill)
def save(id_, im, px_w, px_h, outline, w_m, h_m, kind, desc):
    im.resize((px_w, px_h), Image.LANCZOS).save(f"faces/{id_}.png")
    OUT[id_] = {"outline_uv": [[round(u, 4), round(v, 4)] for u, v in outline], "w_m": round(w_m, 4), "h_m": round(h_m, 4),
                "kind": kind, "desc": desc, "px": [px_w, px_h]}

oct_uv = [(0.5 + 0.5 * math.cos(math.radians(22.5 + 45 * k)), 0.5 + 0.5 * math.sin(math.radians(22.5 + 45 * k))) for k in range(8)]
oct_uv = [((u - 0.5) / math.cos(math.radians(22.5)) + 0.5, (v - 0.5) / math.cos(math.radians(22.5)) + 0.5) for u, v in oct_uv]
dia_uv = [(0.5, 1.0), (0.0, 0.5), (0.5, 0.0), (1.0, 0.5)]
tri_uv = [(0.0, 1.0), (0.5, 0.0), (1.0, 1.0)]
circ_uv = [(0.5 + 0.5 * math.cos(2 * math.pi * k / 32), 0.5 + 0.5 * math.sin(2 * math.pi * k / 32)) for k in range(32)]
rect_uv = [(0, 0), (1, 0), (1, 1), (0, 1)]

# R1-1 STOP 30x30
N = 512; im, d = canvas(N, N); o = P(d, oct_uv, N, N)
d.polygon(o, fill=WHT); d.polygon(inset(o, 0.94), fill=RED)
text(d, "STOP", 0.34 * N, N / 2, N / 2, WHT, N * 0.92); save("r1-1_stop", im, N, N, oct_uv, 30 * IN, 30 * IN, "octagon", "R1-1 STOP 30 in")
# R1-2 YIELD 36 in triangle (point down)
Wt, Ht = 512, 444; im, d = canvas(Wt, Ht); o = P(d, tri_uv, Wt, Ht)
d.polygon(o, fill=WHT); d.polygon(inset(o, 0.95), fill=RED); d.polygon(inset(o, 0.56), fill=WHT)
text(d, "YIELD", 0.09 * Ht, Wt / 2, Ht * 0.26, RED, Wt * 0.36)
save("r1-2_yield", im, Wt, Ht, tri_uv, 36 * IN, 36 * IN * math.sqrt(3) / 2, "triangle", "R1-2 YIELD 36 in")

def diamond(id_, desc, draw):
    im, d = canvas(N, N); o = P(d, dia_uv, N, N)
    d.polygon(o, fill=YEL); d.polygon(inset(o, 0.93), fill=BLK); d.polygon(inset(o, 0.90), fill=YEL)
    draw(d); save(id_, im, N, N, dia_uv, 30 * IN, 30 * IN, "diamond", desc)
S = SS
def ped(d):   # W11-2 pedestrian silhouette (no face)
    d.ellipse([238 * S, 118 * S, 278 * S, 158 * S], fill=BLK)
    d.line([(258 * S, 165 * S), (248 * S, 270 * S)], fill=BLK, width=34 * S)
    d.line([(252 * S, 185 * S), (200 * S, 245 * S)], fill=BLK, width=20 * S); d.line([(256 * S, 185 * S), (305 * S, 240 * S)], fill=BLK, width=20 * S)
    d.line([(248 * S, 265 * S), (205 * S, 380 * S)], fill=BLK, width=24 * S); d.line([(250 * S, 265 * S), (300 * S, 378 * S)], fill=BLK, width=24 * S)
def curve(d):  # W1-2R curve right
    d.arc([150 * S, 170 * S, 420 * S, 520 * S], 180, 270, fill=BLK, width=40 * S)
    d.line([(170 * S, 330 * S), (170 * S, 410 * S)], fill=BLK, width=40 * S)
    d.polygon([(285 * S, 120 * S), (285 * S, 230 * S), (350 * S, 175 * S)], fill=BLK)
def signal(d):  # W3-3 signal ahead
    d.rounded_rectangle([212 * S, 120 * S, 300 * S, 392 * S], radius=14 * S, fill=BLK)
    for k, c in enumerate([(205, 40, 40), (245, 190, 30), (40, 170, 90)]):
        cy = 165 + k * 91; d.ellipse([228 * S, (cy - 32) * S, 284 * S, (cy + 32) * S], fill=c)
def lowclr(d):  # W12-2 low clearance 12'-6"
    text(d, "12'-6\"", 0.17 * N, N / 2, N / 2, BLK, N * 0.62)
    for y, dn in ((150, False), (362, True)):
        d.line([(256 * S, (y - 40) * S), (256 * S, (y + 40) * S)], fill=BLK, width=12 * S)
        tip = y + 45 if dn else y - 45; b = y + 10 if dn else y - 10
        d.polygon([(256 * S, tip * S), (236 * S, b * S), (276 * S, b * S)], fill=BLK)
diamond("w11-2_pedestrian", "W11-2 pedestrian crossing 30 in", ped)
diamond("w1-2r_curve", "W1-2R curve right 30 in", curve)
diamond("w3-3_signal_ahead", "W3-3 signal ahead 30 in", signal)
diamond("w12-2_low_clearance", "W12-2 low clearance 30 in (legend 12'-6\")", lowclr)
# W10-1 railroad advance warning, 36 in round
im, d = canvas(N, N); d.ellipse([0, 0, N * S - 1, N * S - 1], fill=BLK); d.ellipse([10 * S, 10 * S, (N - 10) * S, (N - 10) * S], fill=YEL)
d.ellipse([22 * S, 22 * S, (N - 22) * S, (N - 22) * S], outline=BLK, width=10 * S)
d.line([(170 * S, 70 * S), (342 * S, 442 * S)], fill=BLK, width=44 * S); d.line([(342 * S, 70 * S), (170 * S, 442 * S)], fill=BLK, width=44 * S)
text(d, "R", 0.17 * N, 112, 256, BLK, N); text(d, "R", 0.17 * N, 400, 256, BLK, N)
save("w10-1_railroad", im, N, N, circ_uv, 36 * IN, 36 * IN, "round", "W10-1 railroad advance warning 36 in")
# D3-1 street-name blades 36 x 8 in (two-sided)
for nm in ["MAIN ST", "OAK AVE", "1ST ST", "ELM ST"]:
    Wb, Hb = 1024, 228; im, d = canvas(Wb, Hb, GRN)
    d.rounded_rectangle([8 * S, 8 * S, (Wb - 8) * S, (Hb - 8) * S], radius=20 * S, outline=WHT, width=8 * S)
    text(d, nm, 0.53 * Hb, Wb / 2, Hb / 2, WHT, Wb * 0.95)
    save("d3-1_" + nm.lower().replace(" ", "_"), im, Wb, Hb, rect_uv, 36 * IN, 8 * IN, "blade", f"D3-1 street name '{nm}' 36x8 in (placeholder name)")
# route shields 24 x 24 in
shield_i = [(0.04, 0.86), (0.25, 0.96), (0.5, 0.88), (0.75, 0.96), (0.96, 0.86), (0.98, 0.55), (0.86, 0.24), (0.5, 0.02), (0.14, 0.24), (0.02, 0.55)]
im, d = canvas(N, N); o = P(d, shield_i, N, N); d.polygon(o, fill=WHT); d.polygon(inset(o, 0.95), fill=BLU)
red = [p for p in inset(o, 0.95)]; d.rectangle([0, 0, N * S, int(0.30 * N * S)], fill=None)
top = Image.new("L", im.size, 0); ImageDraw.Draw(top).polygon(inset(o, 0.95), fill=255)
band = Image.new("L", im.size, 0); ImageDraw.Draw(band).rectangle([0, 0, N * S, int(0.33 * N * S)], fill=255)
from PIL import ImageChops
im.paste(RED, mask=ImageChops.multiply(top, band)); d = ImageDraw.Draw(im)
text(d, "INTERSTATE", 0.055 * N, N / 2, 0.2 * N, WHT, N * 0.55); text(d, "80", 0.30 * N, N / 2, 0.58 * N, WHT, N * 0.7)
save("m1-1_interstate_80", im, N, N, shield_i, 24 * IN, 24 * IN, "shield", "M1-1 Interstate shield 24 in (route number placeholder)")
us = [(0.12, 0.92), (0.88, 0.92), (0.86, 0.62), (0.92, 0.40), (0.70, 0.16), (0.5, 0.08), (0.30, 0.16), (0.08, 0.40), (0.14, 0.62)]
im, d = canvas(N, N, BLK); d.polygon(P(d, us, N, N), fill=WHT); text(d, "41", 0.34 * N, N / 2, 0.52 * N, BLK, N * 0.6)
save("m1-4_us_41", im, N, N, rect_uv, 24 * IN, 24 * IN, "square", "M1-4 US route shield 24 in (route number placeholder)")
im, d = canvas(N, N, BLK); d.ellipse([60 * S, 60 * S, (N - 60) * S, (N - 60) * S], fill=WHT); text(d, "12", 0.34 * N, N / 2, N / 2, BLK, N * 0.6)
save("m1-5_state_12", im, N, N, rect_uv, 24 * IN, 24 * IN, "square", "M1-5 state route 24 in, generic circle design (state-specific in reality)")
json.dump(OUT, open("faces/outlines.json", "w"), indent=1)
# contact sheet
ims = [Image.open(f"faces/{k}.png").convert("RGB") for k in OUT]; th = 200
row = [im.resize((int(im.width * th / im.height), th)) for im in ims]
sheet = Image.new("RGB", (sum(i.width for i in row) + 10 * len(row), th + 20), (128, 128, 128)); x = 5
for i in row: sheet.paste(i, (x, 10)); x += i.width + 10
sheet.save("faces_sheet.png"); print("faces", len(OUT))
