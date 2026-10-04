"""Rough 3D view of the shop's parts (boxes only, painter's algorithm).
python3 render3d.py parts.json out.png  eyeX eyeY eyeZ  lookX lookY lookZ"""
import json, math, sys
from PIL import Image, ImageDraw
parts = json.load(open(sys.argv[1]))
eye = [float(v) for v in sys.argv[3:6]]
look = [float(v) for v in sys.argv[6:9]]
W, H, FOV = 1400, 860, 70
def sub(a, b): return [a[0]-b[0], a[1]-b[1], a[2]-b[2]]
def norm(a):
    l = math.sqrt(sum(x*x for x in a)); return [x/l for x in a]
def cross(a, b): return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]
def dot(a, b): return sum(x*y for x, y in zip(a, b))
f = norm(sub(look, eye)); r = norm(cross(f, [0, 1, 0])); u = cross(r, f)
focal = (W / 2) / math.tan(math.radians(FOV / 2))
def proj(p):
    v = sub(p, eye); z = dot(v, f)
    if z < 0.1: return None, z
    return (W/2 + dot(v, r) * focal / z, H/2 - dot(v, u) * focal / z), z
light = norm([0.4, 1, 0.6])
faces = []
skip = {"Roof", "Sidewalk"}
for p in parts:
    if p["name"] in skip or p["t"] >= 0.97: continue
    cx, cy, cz, sx, sy, sz = p["x"], p["y"], p["z"], p["sx"]/2, p["sy"]/2, p["sz"]/2
    for n, corners in [
        ([0,1,0], [(-1,1,-1),(1,1,-1),(1,1,1),(-1,1,1)]), ([0,-1,0], [(-1,-1,-1),(1,-1,-1),(1,-1,1),(-1,-1,1)]),
        ([1,0,0], [(1,-1,-1),(1,1,-1),(1,1,1),(1,-1,1)]), ([-1,0,0], [(-1,-1,-1),(-1,1,-1),(-1,1,1),(-1,-1,1)]),
        ([0,0,1], [(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]), ([0,0,-1], [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1)])]:
        center = [cx + n[0]*sx, cy + n[1]*sy, cz + n[2]*sz]
        if dot(n, sub(eye, center)) <= 0: continue
        pts = [[cx + a*sx, cy + b*sy, cz + c*sz] for a, b, c in corners]
        pr = [proj(q) for q in pts]
        if any(q[0] is None for q in pr): continue
        depth = sum(q[1] for q in pr) / 4
        shade = 0.55 + 0.45 * max(0, dot(n, light))
        col = tuple(min(255, int(c * 255 * shade)) for c in p["c"])
        alpha = int(255 * (1 - p["t"]))
        faces.append((depth, [q[0] for q in pr], col, alpha))
faces.sort(key=lambda x: -x[0])
img = Image.new("RGBA", (W, H), (30, 22, 50, 255))
for depth, poly, col, alpha in faces:
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(layer).polygon(poly, fill=col + (alpha,), outline=(0, 0, 0, 60))
    img.alpha_composite(layer) if alpha < 255 else ImageDraw.Draw(img).polygon(poly, fill=col + (255,), outline=(0, 0, 0, 60))
img.convert("RGB").save(sys.argv[2])
