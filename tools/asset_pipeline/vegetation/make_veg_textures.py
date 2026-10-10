"""In-house foliage + bark textures (PIL, no third-party content). python3 make_veg_textures.py <out_dir>"""
import sys, math, random, os
from PIL import Image, ImageDraw, ImageFilter
out = sys.argv[1]; os.makedirs(out, exist_ok=True)

def leaf_cluster(name, base, spread, n, lmin, lmax, seed, size=512):
    rnd = random.Random(seed)
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    c = size / 2; R = size * 0.47
    for i in range(n):
        r = R * math.sqrt(rnd.random()) ** 0.8; a = rnd.random() * 2 * math.pi
        x, y = c + r * math.cos(a), c + r * math.sin(a)
        L = rnd.uniform(lmin, lmax); W = L * rnd.uniform(0.45, 0.6); t = rnd.random() * math.pi
        shade = 1.0 - 0.35 * (y / size) + rnd.uniform(-0.12, 0.12)        # top lighter, a little variation
        col = tuple(max(0, min(255, int(ch * shade + rnd.uniform(-spread, spread)))) for ch in base) + (255,)
        pts = []
        for k in range(10):
            u = k / 9 * 2 * math.pi
            px, py = L / 2 * math.cos(u), W / 2 * math.sin(u) * (1 - 0.3 * math.cos(u))
            pts.append((x + px * math.cos(t) - py * math.sin(t), y + px * math.sin(t) + py * math.cos(t)))
        d.polygon(pts, fill=col)
        # twig hint
        if i % 60 == 0:
            d.line([(x, y), (c + (x - c) * 0.6, c + (y - c) * 0.6)], fill=(70, 58, 44, 255), width=1)
    im.save(os.path.join(out, name), optimize=True)

def bark(name, base, seed, w=256, h=512):
    rnd = random.Random(seed)
    im = Image.new("RGB", (w, h), base); d = ImageDraw.Draw(im)
    for i in range(160):
        x = rnd.randrange(w); y0 = rnd.randrange(h); L = rnd.randrange(40, 200)
        k = rnd.uniform(-28, 18)
        col = tuple(max(0, min(255, int(ch + k))) for ch in base)
        d.line([(x, y0), (x + rnd.uniform(-4, 4), y0 + L)], fill=col, width=rnd.randrange(2, 7))
    im = im.filter(ImageFilter.GaussianBlur(0.8))
    # make it tile vertically: blend the top/bottom 32 px
    top = im.crop((0, 0, w, 32)); bot = im.crop((0, h - 32, w, h))
    im.paste(Image.blend(bot, top, 0.5), (0, h - 32))
    im.save(os.path.join(out, name), quality=90)

leaf_cluster("foliage_linden_512.png", (72, 96, 46), 14, 900, 22, 38, 1)          # broad heart-shaped leaves, darker
leaf_cluster("foliage_honeylocust_512.png", (118, 138, 58), 16, 2200, 9, 16, 2)   # fine pinnate leaflets, lighter
leaf_cluster("foliage_shrub_512.png", (62, 88, 44), 12, 1400, 12, 22, 3)
bark("bark_grey_brown_256x512.jpg", (92, 84, 74), 4)
print("ok")
