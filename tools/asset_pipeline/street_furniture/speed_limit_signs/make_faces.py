"""R2-1 SPEED LIMIT sign faces (in-house, PIL). 24 x 30 in panel -> 512 x 640 px (~840 px/m).
Layout approximates FHWA Standard Highway Signs R2-1 (24x30): 3/8" black border inset 1/2", 1.5" corner radius,
"SPEED" / "LIMIT" ~4" caps, numerals ~10" tall [E: proportions approximated, not traced from the SHS drawing].
Font: Overpass Bold (SIL OFL 1.1) as a Highway-Gothic-like stand-in.
python3 make_faces.py <font.ttf> <out_dir> 10 20 25 30 35 40"""
import sys, os
from PIL import Image, ImageDraw, ImageFont
font, out = sys.argv[1], sys.argv[2]; speeds = sys.argv[3:]
W, H = 512, 640; ppi = W / 24.0                    # px per inch
WHITE, BLACK = (236, 236, 232), (24, 24, 24)        # retro sheeting white / legend black (sRGB), style-guide §7 caps
def inch(v): return int(round(v * ppi))
def text_center(d, txt, cap_in, y_top_in, f):
    # size so the cap height ~= cap_in inches
    size = 10
    while True:
        F = ImageFont.truetype(f, size); b = F.getbbox("H")
        if b[3] - b[1] >= inch(cap_in): break
        size += 1
    bb = d.textbbox((0, 0), txt, font=F)
    w = bb[2] - bb[0]; capt = F.getbbox("H")[1]
    d.text(((W - w) / 2 - bb[0], inch(y_top_in) - capt), txt, font=F, fill=BLACK)
os.makedirs(out, exist_ok=True)
for s in speeds:
    im = Image.new("RGB", (W, H), WHITE); d = ImageDraw.Draw(im)
    d.rounded_rectangle([inch(0.5), inch(0.5), W - 1 - inch(0.5), H - 1 - inch(0.5)], radius=inch(1.5), outline=BLACK, width=inch(0.375))
    text_center(d, "SPEED", 4.0, 3.0, font)
    text_center(d, "LIMIT", 4.0, 8.5, font)
    text_center(d, s, 10.0, 15.0, font)
    im.save(os.path.join(out, f"r2-1_speed_{s}_512x640.png"))
    print("face", s)
