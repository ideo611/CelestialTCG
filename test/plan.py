"""Plan (top-down) render of the shop's parts, plus a list of new parts that
overlap other parts (axis-aligned boxes; rotations ignored)."""
import json, sys
from PIL import Image, ImageDraw
parts = json.load(open(sys.argv[1]))
out = sys.argv[2]
X0, X1, Z0, Z1 = -40, 40, -80, -20  # world coords around the shop (origin z=-50)
S = 14
img = Image.new("RGB", (int((X1 - X0) * S), int((Z1 - Z0) * S)), (20, 20, 25))
d = ImageDraw.Draw(img)
skip = {"Floor", "Roof", "PlayRug", "RugBorder", "Sidewalk", "Baseplate", "Parapet", "OverWindow", "OverDoor"}
for p in sorted(parts, key=lambda p: p["y"] + p["sy"] / 2):
    if p["name"] in skip or p["t"] >= 0.95:
        continue
    x0 = (p["x"] - p["sx"] / 2 - X0) * S; x1 = (p["x"] + p["sx"] / 2 - X0) * S
    z0 = (p["z"] - p["sz"] / 2 - Z0) * S; z1 = (p["z"] + p["sz"] / 2 - Z0) * S
    c = tuple(int(v * 255) for v in p["c"])
    d.rectangle([x0, z0, x1, z1], fill=c, outline=(0, 0, 0))
img.save(out)
