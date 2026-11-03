"""Draws the app icon (1024px, no alpha) and writes every size in AppIcon.appiconset."""
import json, math, os, sys
from PIL import Image, ImageDraw

S = 2048  # supersampled
top, bottom = (0x4A, 0x3F, 0x86), (0xF4, 0x8A, 0x5C)
img = Image.new("RGB", (S, S))
px = img.load()
for y in range(S):
    t = y / (S - 1)
    c = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
    for x in range(S):
        px[x, y] = c
d = ImageDraw.Draw(img)
cx = cy = S / 2
# 24 hour ticks; the current hour (17:00) is lit
R1, R2 = S * 0.36, S * 0.43
for h in range(24):
    a = math.radians(h * 15 - 90)
    w = S * 0.022
    color = (255, 255, 255) if h != 17 else (255, 214, 120)
    r1 = R1 if h % 6 else R1 - S * 0.03
    d.line([(cx + r1 * math.cos(a), cy + r1 * math.sin(a)), (cx + R2 * math.cos(a), cy + R2 * math.sin(a))],
           fill=color, width=round(w))
# record button: white ring + red dot
ring = S * 0.25
d.ellipse([cx - ring, cy - ring, cx + ring, cy + ring], fill=(255, 255, 255))
dot = S * 0.17
d.ellipse([cx - dot, cy - dot, cx + dot, cy + dot], fill=(0xFF, 0x3B, 0x30))
icon = img.resize((1024, 1024), Image.LANCZOS)

out = sys.argv[1]
icon.save(os.path.join(out, "..", "..", "..", "..", "assets", "icon-1024.png"))
meta = json.load(open(os.path.join(out, "Contents.json")))
for im in meta["images"]:
    if "filename" not in im:
        continue
    base = float(im["size"].split("x")[0])
    scale = int(im["scale"].rstrip("x"))
    px_ = round(base * scale)
    icon.resize((px_, px_), Image.LANCZOS).save(os.path.join(out, im["filename"]))
print("icons written")
