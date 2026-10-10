"""In-house trim sheet (1024², 8 bands of 128 px) + storefront sign faces (fictional names, Overpass OFL). Asset Manager 2026-10-09."""
import random, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "textures")
random.seed(7)
# band: name, albedo sRGB, roughness, metal, noise amp
BANDS = [("coping_precast", (178,172,160), .85, 0, 14), ("metal_flashing", (128,132,136), .45, .3, 6),
         ("trim_bronze", (58,48,40), .5, .3, 5), ("door_dark", (40,44,48), .55, 0, 4),
         ("canopy_fascia", (214,206,186), .6, 0, 6), ("sign_band", (38,40,42), .7, 0, 5),
         ("mullion_alu", (150,154,158), .4, .3, 4), ("cornice_stone", (196,186,166), .8, 0, 16)]
alb = Image.new("RGB", (1024,1024)); orm = Image.new("RGB", (1024,1024))
pa, po = alb.load(), orm.load()
for i,(n,c,r,m,amp) in enumerate(BANDS):
    for y in range(i*128,(i+1)*128):
        edge = (y % 128) in (0,1,126,127)
        for x in range(1024):
            k = random.randint(-amp,amp) - (18 if edge else 0)
            pa[x,y] = tuple(max(0,min(255,v+k)) for v in c)
            po[x,y] = (230 if edge else 255, int(r*255), int(m*255))
alb.save(f"{OUT}/trim/trim_sheet_albedo_1k.png"); orm.save(f"{OUT}/trim/trim_sheet_orm_1k.png")
with open(f"{OUT}/trim/trim_sheet_layout.txt","w") as f:
    for i,b in enumerate(BANDS): f.write(f"band {i}: v {1-(i+1)/8:.3f}..{1-i/8:.3f}  {b[0]}  rough {b[2]} metal {b[3]}\n")
FONT = "/workspace/assets/builds/street_furniture/_fonts/Overpass-Bold.ttf"
SIGNS = [("ELM STREET BAKERY",(120,30,30),(250,236,210)), ("PYLON HARDWARE",(20,60,110),(255,255,255)),
         ("CORNER CAFE",(30,70,45),(240,230,200)), ("MAIN ST BARBER",(25,25,25),(230,200,120)),
         ("RIVERSIDE BOOKS",(70,40,80),(245,240,230)), ("TOWN SAVINGS",(30,45,60),(220,225,230)),
         ("CITY HALL",(205,196,176),(60,52,44))]
for txt,bg,fg in SIGNS:
    im = Image.new("RGB",(2048,256),bg); d = ImageDraw.Draw(im)
    d.rectangle([8,8,2039,247],outline=fg,width=6)
    ft = ImageFont.truetype(FONT,150); w = d.textlength(txt,font=ft)
    d.text(((2048-w)/2,40),txt,font=ft,fill=fg)
    im.save(f"{OUT}/signage/sign_{txt.lower().replace(' ','_')}.png")
print("ok")
