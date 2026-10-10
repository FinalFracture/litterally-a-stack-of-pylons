"""In-house clock face (PIL): off-white dial, 12 bar markers, hands at 10:10. 512 px = the 3.0 m disc."""
from PIL import Image, ImageDraw
import math
N, S = 512, 2; im = Image.new("RGB", (N * S, N * S), (60, 58, 52)); d = ImageDraw.Draw(im); c = N * S / 2
d.ellipse([8 * S, 8 * S, (N - 8) * S, (N - 8) * S], fill=(238, 232, 214)); d.ellipse([40 * S, 40 * S, (N - 40) * S, (N - 40) * S], outline=(40, 38, 34), width=4 * S)
for k in range(60):
    a = math.radians(k * 6); r0 = (200 if k % 5 == 0 else 222) * S; r1 = 236 * S; w = (12 if k % 5 == 0 else 3) * S
    d.line([(c + r0 * math.sin(a), c - r0 * math.cos(a)), (c + r1 * math.sin(a), c - r1 * math.cos(a))], fill=(30, 28, 26), width=w)
for ang, L, w in ((math.radians(305), 130, 16), (math.radians(60), 190, 10)):   # hour ~10:10, minute 10
    d.line([(c, c), (c + L * S * math.sin(ang), c - L * S * math.cos(ang))], fill=(25, 24, 22), width=w * S)
d.ellipse([c - 14 * S, c - 14 * S, c + 14 * S, c + 14 * S], fill=(25, 24, 22))
im.resize((N, N), Image.LANCZOS).save("textures/clock_face_512.png"); print("ok")
