"""In-house road-marking atlas, 2048² RGBA (Asset Manager 2026-10-09). Layout (px, origin top-left):
 strips (full height): x 0-63 white, 64-127 yellow, 128-191 white worn, 192-255 yellow worn
 arrows 256 x 768 cells, x 256 + 256*i (i: through, left, right, through_left, through_right); y 0-767 clean, 768-1535 worn
 SCHOOL word 512 x 512: x 1536-2047, y 0-511 clean, y 512-1023 worn
 Colours: MUTCD white / yellow, slightly off for asphalt realism."""
import random, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageOps
random.seed(3); W = (238, 238, 232, 255); Y = (232, 176, 32, 255)
im = Image.new("RGBA", (2048, 2048), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
d.rectangle([0, 0, 63, 2047], fill=W); d.rectangle([64, 0, 127, 2047], fill=Y)
d.rectangle([128, 0, 191, 2047], fill=W); d.rectangle([192, 0, 255, 2047], fill=Y)
def arrow(cx, top, kind):   # cell 256 x 768 = 0.9 m x 2.7 m (shaft 0.15 m = 43 px)
    sh = 22; head_h = 260; y0 = top + 40; y1 = top + 728
    def up(x):  d.rectangle([x - sh, y0 + head_h, x + sh, y1], fill=W); d.polygon([(x, y0), (x - 100, y0 + head_h), (x + 100, y0 + head_h)], fill=W)
    def turn(x, s):   # shaft up, then a 90-degree arm with a sideways head
        ya = y0 + 300
        d.rectangle([x - sh, ya - sh, x + sh, y1], fill=W)
        d.rectangle([min(x, x + s * 70), ya - sh, max(x, x + s * 70), ya + sh], fill=W)
        d.polygon([(x + s * 125, ya), (x + s * 65, ya - 75), (x + s * 65, ya + 75)], fill=W)
    if kind == "through": up(cx)
    if kind == "left": turn(cx, -1)
    if kind == "right": turn(cx, 1)
    if kind == "through_left": up(cx + 30); turn(cx + 30, -1)
    if kind == "through_right": up(cx - 30); turn(cx - 30, 1)
for i, k in enumerate(["through", "left", "right", "through_left", "through_right"]):
    arrow(256 + 256 * i + 128, 0, k); arrow(256 + 256 * i + 128, 768, k)
F = "/workspace/assets/builds/street_furniture/_fonts/Overpass-Bold.ttf"
for top in (0, 512):   # SCHOOL, letters elongated 2.5:1 along travel (MUTCD elongated legend)
    t = Image.new("RGBA", (1200, 300), (0, 0, 0, 0)); td = ImageDraw.Draw(t); ft = ImageFont.truetype(F, 260)
    w = td.textlength("SCHOOL", font=ft); td.text(((1200 - w) / 2, -40), "SCHOOL", font=ft, fill=W)
    t = t.resize((500, 500)); im.alpha_composite(t, (1542, top + 6))
# wear: erode alpha in the worn regions with blotchy noise
px = im.load()
def wear(x0, y0, x1, y1, strength=0.45):
    n = ImageOps.autocontrast(Image.effect_noise((x1 - x0 + 1, y1 - y0 + 1), 120).filter(ImageFilter.GaussianBlur(5))); nl = n.load()
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            r, g, b, a = px[x, y]
            if a and nl[x - x0, y - y0] + random.randint(-30, 30) < 255 * strength: px[x, y] = (r, g, b, 0)
            elif a: px[x, y] = (int(r * .92), int(g * .92), int(b * .9), a)
wear(128, 0, 255, 2047); wear(256, 768, 1535, 1535); wear(1536, 512, 2047, 1023)
im.save("textures/road_markings_atlas_2k.png"); print("ok")
