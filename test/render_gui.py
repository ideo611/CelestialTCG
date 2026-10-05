"""Draws the list made by dumpgui.lua into a PNG (sibling order = draw order,
like ZIndexBehavior.Sibling). Images with a known local file are drawn
from it; others show as a tinted placeholder."""
import os
from PIL import Image, ImageDraw, ImageFont

UP = "/root/.claude/uploads/3f999207-c8c9-5a40-855b-873d8eaf8301/"
KNOWN = {
    "79746835811021": UP + "f0d34c96-frame_solar.png",
    "102668499743179": UP + "28858b01-frame_lunar.png",
    "77326985301896": UP + "b6b5037e-cmd-frame-solar.png",
    "85661220983840": UP + "c5966cc1-cmd-frame-lunar.png",
    "83792005053121": UP + "bc3f472b-cmd-sol-01_captain_sol_varro.png",
    "111007143043644": UP + "4119884a-cmd-lun-01_tidekeeper_selene.png",
    "120865299160887": UP + "025b6fc2-mat-solar-forge.png",
    "134304204813444": UP + "23370aa6-button-plate.png",
    # (preview stand-in for the window frame: the zone frame has the same style)
    "86255685203929": UP + "8f23ad69-zone-frame.png",
}
# the stand-in's own corners differ from the real frame's
SLICE_OVERRIDE = {"86255685203929": (150, 150, 874, 1386)}
_cache = {}


def load(path):
    if path not in _cache:
        _cache[path] = Image.open(path).convert("RGBA")
    return _cache[path]


HERE = os.path.dirname(os.path.abspath(__file__))
FAMILY_FILES = {"12187360881": "Audiowide-Regular.ttf", "12187375422": "Rajdhani-Bold.ttf",
                "Sarpanch": "Sarpanch-Bold.ttf", "Michroma": "Michroma-Regular.ttf"}


def family_font(family, size):
    for key, file in FAMILY_FILES.items():
        if family and key in family:
            path = os.path.join(HERE, "fonts", file)
            if os.path.exists(path):
                return ImageFont.truetype(path, max(6, int(size)))
    return None


def font(size, bold, family=None):
    ff = family_font(family, size)
    if ff:
        return ff
    names = ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else
             "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
    for n in names:
        if os.path.exists(n):
            return ImageFont.truetype(n, max(6, int(size)))
    return ImageFont.load_default()


def fit_text(draw, text, w, h, max_size, bold, scaled, family=None):
    size = int(max_size)
    while size > 6:
        f = font(size, bold, family)
        lines = wrap(draw, text, f, w)
        lh = size * 1.15
        if not scaled or (len(lines) * lh <= h and all(draw.textlength(l, font=f) <= w for l in lines)):
            return f, lines, lh
        size -= 1
    f = font(6, bold, family)
    return f, wrap(draw, text, f, w), 7


def wrap(draw, text, f, w):
    out = []
    for para in str(text).split("\n"):
        words, line = para.split(" "), ""
        for word in words:
            test = (line + " " + word).strip()
            if draw.textlength(test, font=f) <= w or not line:
                line = test
            else:
                out.append(line)
                line = word
        out.append(line)
    return out


def nine_slice(src, rect, scale, w, h):
    x0, y0, x1, y1 = [int(v) for v in rect]
    sw, sh = src.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    l, t, r, b = [max(0, int(v * scale)) for v in (x0, y0, sw - x1, sh - y1)]
    if l + r > w:
        k = w / max(1, l + r); l, r = int(l * k), int(r * k)
    if t + b > h:
        k = h / max(1, t + b); t, b = int(t * k), int(b * k)
    xs_src, ys_src = [0, x0, x1, sw], [0, y0, y1, sh]
    xs_dst, ys_dst = [0, l, w - r, w], [0, t, h - b, h]
    for i in range(3):
        for j in range(3):
            sx0, sx1, sy0, sy1 = xs_src[i], xs_src[i + 1], ys_src[j], ys_src[j + 1]
            dx0, dx1, dy0, dy1 = xs_dst[i], xs_dst[i + 1], ys_dst[j], ys_dst[j + 1]
            if sx1 <= sx0 or sy1 <= sy0 or dx1 <= dx0 or dy1 <= dy0:
                continue
            out.paste(src.crop((sx0, sy0, sx1, sy1)).resize((dx1 - dx0, dy1 - dy0)), (dx0, dy0))
    return out


def render(entries, width, height, path, bg=(0, 0, 0)):
    base = Image.new("RGBA", (width, height), bg + (255,))
    for e in entries:
        x, y, w, h = e["X"], e["Y"], e["W"], e["H"]
        if w <= 0 or h <= 0:
            continue
        layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        box = [x, y, x + w, y + h]
        r = e.get("Corner") or 0
        alpha = int(255 * (1 - e["BgT"]) * (1 - e.get("GradT", 0)))
        if alpha > 0:
            if e.get("Grad"):
                g = Image.new("RGBA", (max(1, int(w)), max(1, int(h))))
                c1, c2 = [tuple(int(c[k] * e["Bg"][k] / 255) for k in range(3)) for c in e["Grad"]]
                vertical = abs(e.get("GradRot", 0)) % 180 == 90
                n = g.height if vertical else g.width
                for i in range(n):
                    t = i / max(1, n - 1)
                    c = tuple(int(c1[k] + (c2[k] - c1[k]) * t) for k in range(3)) + (alpha,)
                    if vertical:
                        ImageDraw.Draw(g).line([(0, i), (g.width, i)], fill=c)
                    else:
                        ImageDraw.Draw(g).line([(i, 0), (i, g.height)], fill=c)
                layer.paste(g, (int(x), int(y)))
            else:
                d.rounded_rectangle(box, radius=r, fill=tuple(e["Bg"]) + (alpha,))
        img = e.get("Image")
        if img and e.get("ImageT", 0) < 1:
            ia = int(255 * (1 - e.get("ImageT", 0)))
            key = str(img).replace("rbxassetid://", "")
            if key in KNOWN and int(w) > 0 and int(h) > 0:
                src = load(KNOWN[key])
                tint = e.get("ImageColor")
                if e.get("Slice"):
                    im = nine_slice(src, SLICE_OVERRIDE.get(key, e["Slice"]), e.get("SliceScale", 1), int(w), int(h))
                else:
                    im = src.resize((int(w), int(h)))
                if tint and tuple(tint) != (255, 255, 255):
                    r_, g_, b_, a_ = im.split()
                    r_ = r_.point(lambda v, t=tint[0]: v * t // 255)
                    g_ = g_.point(lambda v, t=tint[1]: v * t // 255)
                    b_ = b_.point(lambda v, t=tint[2]: v * t // 255)
                    im = Image.merge("RGBA", (r_, g_, b_, a_))
                if ia < 255:
                    a = im.split()[3].point(lambda v: v * ia // 255)
                    im.putalpha(a)
                layer.alpha_composite(im, (int(x), int(y)))
            else:
                col = tuple(e.get("ImageColor") or (255, 255, 255))
                d.rectangle(box, fill=(col[0] // 3 + 40, col[1] // 3 + 30, col[2] // 3 + 60, min(ia, 200)))
        if e.get("Stroke") and e.get("StrokeT", 0) < 1:
            sa = int(255 * (1 - e["StrokeT"]))
            d.rounded_rectangle(box, radius=r, outline=tuple(e["Stroke"]) + (sa,), width=max(1, int(e["StrokeW"])))
        if e.get("Text"):
            f, lines, lh = fit_text(d, e["Text"], w, h, e["MaxText"], e["Bold"], e["Scaled"], e.get("Family"))
            total = len(lines) * lh
            ty = y + (h - total) / 2 if e["YAlign"] == "Center" else (y if e["YAlign"] == "Top" else y + h - total)
            ta = int(255 * (1 - e.get("TextT", 0)))
            tcol = tuple(e["TextColor"])
            if e.get("Grad") and e["BgT"] >= 1:
                tcol = tuple(e["Grad"][0])
            for line in lines:
                tw = d.textlength(line, font=f)
                tx = x + (w - tw) / 2 if e["XAlign"] == "Center" else (x if e["XAlign"] == "Left" else x + w - tw)
                d.text((tx, ty), line, font=f, fill=tcol + (ta,))
                ty += lh
        clip = e.get("Clip")
        if clip:
            mask = Image.new("L", (width, height), 0)
            ImageDraw.Draw(mask).rectangle([clip[0], clip[1], clip[0] + clip[2], clip[1] + clip[3]], fill=255)
            empty = Image.new("RGBA", (width, height), (0, 0, 0, 0))
            layer = Image.composite(layer, empty, mask)
        base.alpha_composite(layer)
    base.convert("RGB").save(path)
