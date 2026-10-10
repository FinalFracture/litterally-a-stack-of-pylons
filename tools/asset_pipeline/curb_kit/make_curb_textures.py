"""In-house PIL texture: detectable warning surface (truncated domes), 512 px = one 0.61 x 0.61 m tile.
12 x 12 domes -> 50.8 mm centre spacing; dome base 0.58 x spacing = 29.5 mm (ADA 2010 Standards s.705.1 as I recall it: base 23-36 mm, spacing 41-61 mm [verify]).
Colour: 'federal yellow' approximation sRGB (226,176,36) [estimate; FED-STD-595 33538 not colour-matched]."""
from PIL import Image, ImageDraw, ImageFilter
N, n = 512, 12; sp = N / n; r = 0.58 * sp / 2
img = Image.new("RGB", (N, N), (214, 165, 30)); d = ImageDraw.Draw(img)
for i in range(n):
    for j in range(n):
        cx, cy = (i + .5) * sp, (j + .5) * sp
        d.ellipse([cx - r + 1.5, cy - r + 2.5, cx + r + 1.5, cy + r + 2.5], fill=(168, 128, 22))   # soft shadow
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(232, 184, 40))
        d.ellipse([cx - r * .55, cy - r * .55, cx + r * .45, cy + r * .45], fill=(242, 198, 64))  # flat top, lit
img = img.filter(ImageFilter.GaussianBlur(0.6)); img.save("textures/detectable_warning_512.png")
print("ok", sp, r)
