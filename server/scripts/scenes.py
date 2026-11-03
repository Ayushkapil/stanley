"""Photographs drawn in code, for App Store screenshots and demos (the
production audit, November 2026): skies, lights, water and hills, with grain
and a lens's falloff, so a seeded circle looks lived in without anyone's
real photos, a stock licence or an image model. Pillow only, deterministic
per seed.

    .venv/bin/python scripts/scenes.py /tmp/sheet.jpg   # a contact sheet
"""
from __future__ import annotations

import io
import math
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps

W, H = 1200, 1600  # 3:4, the shape every Stanley photo is cropped to

Color = tuple[int, int, int]


# --- tools ---------------------------------------------------------------------


def vgrad(stops: list[tuple[float, Color]], w: int = W, h: int = H) -> Image.Image:
    """A vertical gradient through color stops (position 0..1 down the frame)."""
    col = Image.new("RGB", (1, h))
    px = col.load()
    for y in range(h):
        t = y / (h - 1)
        for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
            if p0 <= t <= p1:
                f = 0 if p1 == p0 else (t - p0) / (p1 - p0)
                f = f * f * (3 - 2 * f)  # smoothstep, so bands don't show
                px[0, y] = tuple(int(a + (b - a) * f) for a, b in zip(c0, c1))
                break
        else:
            px[0, y] = stops[-1][1] if t > stops[-1][0] else stops[0][1]
    return col.resize((w, h), Image.BILINEAR)


def glow(img: Image.Image, center: tuple[float, float], radius: float, color: Color, strength: float = 1.0) -> Image.Image:
    """Light added (screen) as a soft disc: a sun, a lamp, a moon's halo."""
    layer = Image.new("RGB", img.size, (0, 0, 0))
    d = ImageDraw.Draw(layer)
    x, y = center
    for i in range(10, 0, -1):
        r = radius * i / 10
        k = strength * (1 - i / 11) ** 1.6
        d.ellipse([x - r, y - r, x + r, y + r], fill=tuple(int(c * k) for c in color))
    layer = layer.filter(ImageFilter.GaussianBlur(radius / 6))
    return ImageChops.screen(img, layer)


def bokeh(img: Image.Image, rng: random.Random, n: int, colors: list[Color], rmin: float, rmax: float,
          blur: float, area: tuple[float, float, float, float] = (0, 0, 1, 1), alpha: float = 0.8) -> Image.Image:
    """Out-of-focus lights: discs with a brighter rim, as a fast lens draws them."""
    layer = Image.new("RGB", img.size, (0, 0, 0))
    d = ImageDraw.Draw(layer)
    x0, y0, x1, y1 = area
    for _ in range(n):
        r = rng.uniform(rmin, rmax)
        x = rng.uniform(x0, x1) * img.width
        y = rng.uniform(y0, y1) * img.height
        c = rng.choice(colors)
        k = rng.uniform(0.35, 1.0) * alpha
        d.ellipse([x - r, y - r, x + r, y + r], fill=tuple(int(v * k) for v in c))
        d.ellipse([x - r * 0.86, y - r * 0.86, x + r * 0.86, y + r * 0.86], fill=tuple(int(v * k * 0.72) for v in c))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    return ImageChops.screen(img, layer)


def ridge(rng: random.Random, w: int, base: float, rough: float, steps: int = 9) -> list[float]:
    """A skyline of hills by midpoint displacement: heights for x in 0..w."""
    pts = [base + rng.uniform(-rough, rough), base + rng.uniform(-rough, rough)]
    amp = rough
    for _ in range(steps):
        nxt = []
        for a, b in zip(pts, pts[1:]):
            nxt += [a, (a + b) / 2 + rng.uniform(-amp, amp)]
        nxt.append(pts[-1])
        pts = nxt
        amp *= 0.55
    out = []
    for x in range(w + 1):
        f = x / w * (len(pts) - 1)
        i = min(int(f), len(pts) - 2)
        out.append(pts[i] + (pts[i + 1] - pts[i]) * (f - i))
    return out


def silhouette(img: Image.Image, heights: list[float], color: Color, blur: float = 0.0) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    poly = [(x, y) for x, y in enumerate(heights)] + [(img.width, img.height), (0, img.height)]
    ImageDraw.Draw(mask).polygon(poly, fill=255)
    if blur:
        mask = mask.filter(ImageFilter.GaussianBlur(blur))
    return Image.composite(Image.new("RGB", img.size, color), img, mask)


def haze(img: Image.Image, y: float, height: float, color: Color, strength: float) -> Image.Image:
    """A band of mist lying across the frame at height y (0..1)."""
    mask = Image.new("L", (1, img.height), 0)
    px = mask.load()
    for row in range(img.height):
        t = (row / img.height - y) / height
        px[0, row] = int(255 * strength * math.exp(-t * t))
    mask = mask.resize(img.size)
    return Image.composite(Image.new("RGB", img.size, color), img, mask)


def smear(img: Image.Image, factor: int = 40) -> Image.Image:
    """Horizontal streaks, the way water draws what's above it."""
    small = img.resize((max(1, img.width // factor), img.height), Image.BILINEAR)
    return small.resize(img.size, Image.BICUBIC)


def finish(img: Image.Image, rng: random.Random, grain: float = 9, vignette: float = 0.35, warm: float = 0.0) -> Image.Image:
    """Film grain, a lens's falloff toward the corners, a touch of softness."""
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    if warm:
        r, g, b = img.split()
        r = r.point(lambda v: min(255, int(v * (1 + warm))))
        b = b.point(lambda v: int(v * (1 - warm)))
        img = Image.merge("RGB", (r, g, b))
    falloff = Image.radial_gradient("L").resize(img.size, Image.BICUBIC)
    falloff = falloff.point(lambda v: int(min(255, max(0, (v - 90) * 1.6)) * vignette))
    img = Image.composite(Image.new("RGB", img.size, (0, 0, 0)), img, falloff)
    noise = Image.effect_noise(img.size, grain).convert("RGB")
    random.seed(rng.random())
    return ImageChops.add(img, noise, 1.0, -128)


def jpeg(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=92)
    return buf.getvalue()


# --- scenes ---------------------------------------------------------------------


def sunset_lake(rng: random.Random) -> Image.Image:
    horizon = int(H * 0.57)
    sky = vgrad([(0, (38, 46, 98)), (0.3, (112, 72, 128)), (0.62, (236, 120, 74)), (1, (255, 196, 110))], W, horizon)
    sky = glow(sky, (W * 0.58, horizon - 10), 300, (255, 214, 140), 1.0)
    sky = glow(sky, (W * 0.58, horizon - 10), 70, (255, 248, 220), 1.0)
    # Far hills on the horizon, low and blue with distance.
    hills = [horizon - 30 - 26 * math.sin(x / 190) - 14 * math.sin(x / 61) for x in range(W + 1)]
    sky = silhouette(sky, hills, (70, 44, 74), 1.5)
    img = Image.new("RGB", (W, H))
    img.paste(sky, (0, 0))
    water = smear(ImageOps.flip(sky), 50).resize((W, H - horizon))
    water = Image.blend(water, Image.new("RGB", water.size, (26, 20, 40)), 0.42)
    img.paste(water, (0, horizon))
    d = ImageDraw.Draw(img)
    for _ in range(520):  # the sun's path broken up on the water
        y = rng.uniform(horizon + 4, H * 0.97)
        spread = 24 + (y - horizon) * 0.5
        x = W * 0.58 + rng.gauss(0, spread / 2.2)
        ln = rng.uniform(6, 34) * (0.5 + (y - horizon) / (H - horizon))
        c = rng.choice([(255, 220, 150), (255, 190, 120), (255, 240, 200), (240, 150, 100)])
        d.line([(x - ln, y), (x + ln, y)], fill=c, width=rng.choice([1, 2, 2, 3]))
    for _ in range(70):  # reeds in the foreground
        x = rng.uniform(0, W * 0.3)
        top = rng.uniform(H * 0.74, H * 0.88)
        d.line([(x, H), (x + rng.uniform(-24, 24), top)], fill=(14, 10, 18), width=rng.choice([2, 3, 4]))
    return finish(img, rng, warm=0.03)


def misty_mountains(rng: random.Random) -> Image.Image:
    img = vgrad([(0, (176, 196, 220)), (0.35, (234, 214, 206)), (0.55, (246, 226, 208)), (1, (200, 206, 216))])
    img = glow(img, (W * 0.3, H * 0.3), 260, (255, 236, 210), 0.7)
    layers = [(0.42, 70, (150, 160, 182)), (0.5, 80, (118, 130, 158)), (0.6, 90, (88, 100, 132)),
              (0.72, 90, (58, 70, 100)), (0.86, 70, (32, 40, 62))]
    for base, rough, color in layers:
        img = silhouette(img, ridge(rng, W, H * base, rough), color, 2.0)
        img = haze(img, base + 0.035, 0.05, (232, 226, 226), 0.55)
    return finish(img, rng, grain=7, vignette=0.25)


def city_bokeh(rng: random.Random) -> Image.Image:
    img = vgrad([(0, (8, 10, 24)), (0.6, (22, 16, 30)), (1, (10, 8, 14))])
    img = glow(img, (W * 0.2, H * 0.75), 420, (80, 40, 30), 0.6)
    img = bokeh(img, rng, 34, [(255, 176, 90), (255, 214, 150), (255, 120, 80), (180, 200, 255)], 40, 110, 7,
                (0, 0.35, 1, 0.95), 0.7)
    img = bokeh(img, rng, 40, [(255, 200, 120), (255, 240, 210), (120, 170, 255)], 8, 24, 2.5, (0, 0.4, 1, 0.9), 0.9)
    # A street's edge, out of focus at the bottom of the frame.
    img = silhouette(img, [H * 0.9 + 6 * math.sin(x / 90) for x in range(W + 1)], (6, 6, 10), 8)
    return finish(img, rng, grain=11, vignette=0.3)


def starry_hill(rng: random.Random) -> Image.Image:
    img = vgrad([(0, (4, 6, 20)), (0.55, (16, 26, 58)), (0.8, (40, 52, 86)), (1, (40, 52, 86))])
    band = Image.effect_noise((W // 8, H // 8), 40).resize((W, H), Image.BICUBIC).filter(ImageFilter.GaussianBlur(40))
    band_mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(band_mask).polygon([(W * 0.1, 0), (W * 0.55, 0), (W * 0.95, H * 0.7), (W * 0.5, H * 0.7)], fill=110)
    band_mask = band_mask.filter(ImageFilter.GaussianBlur(120))
    img = Image.composite(ImageChops.screen(img, Image.merge("RGB", [band.point(lambda v: int(v * 0.5))] * 3)), img, band_mask)
    d = ImageDraw.Draw(img)
    for _ in range(1400):
        x, y = rng.uniform(0, W), rng.uniform(0, H * 0.8)
        b = int(rng.uniform(90, 255) * rng.random() ** 0.5)
        r = rng.choice([0.6, 0.8, 1.0, 1.2, 1.6])
        d.ellipse([x - r, y - r, x + r, y + r], fill=(b, b, min(255, b + 20)))
    for _ in range(14):
        img = glow(img, (rng.uniform(0, W), rng.uniform(0, H * 0.6)), rng.uniform(10, 22), (200, 210, 255), 0.9)
    hill = [H * 0.8 - 90 * math.sin(math.pi * x / W) + rng.uniform(-1, 1) for x in range(W + 1)]
    img = silhouette(img, hill, (6, 8, 14))
    d = ImageDraw.Draw(img)
    tx, ty = W * 0.66, H * 0.8 - 90 * math.sin(math.pi * 0.66)
    d.line([(tx, ty + 4), (tx - 4, ty - 170)], fill=(6, 8, 14), width=12)
    for _ in range(26):
        bx, by = tx + rng.gauss(0, 60), ty - 150 + rng.gauss(0, 55)
        d.line([(tx - 3, ty - 120), (bx, by)], fill=(6, 8, 14), width=4)
        r = rng.uniform(22, 48)
        d.ellipse([bx - r, by - r * 0.8, bx + r, by + r * 0.8], fill=(6, 8, 14))
    return finish(img, rng, grain=10, vignette=0.3)


def golden_field(rng: random.Random) -> Image.Image:
    img = vgrad([(0, (250, 226, 180)), (0.45, (252, 200, 120)), (0.6, (214, 150, 70)), (1, (90, 62, 26))])
    img = glow(img, (W * 0.72, H * 0.5), 420, (255, 230, 170), 1.0)
    img = glow(img, (W * 0.72, H * 0.5), 90, (255, 252, 230), 1.0)
    img = silhouette(img, ridge(rng, W, H * 0.56, 12), (170, 120, 64), 6)
    d = ImageDraw.Draw(img)
    for i in range(1800):
        x = rng.uniform(-20, W + 20)
        base_y = rng.uniform(H * 0.6, H * 1.02)
        depth = (base_y - H * 0.6) / (H * 0.42)
        ln = 10 + depth * 120 * rng.uniform(0.6, 1.2)
        lean = rng.uniform(-0.25, 0.25) * ln
        shade = int(40 + 60 * (1 - depth) + rng.uniform(-15, 15))
        lit = rng.random() < 0.25
        c = (min(255, shade + 160), min(255, shade + 110), shade + 30) if lit else (shade + 40, shade + 22, max(0, shade - 20))
        d.line([(x, base_y), (x + lean, base_y - ln)], fill=c, width=1 if depth < 0.4 else 2)
    img = bokeh(img, rng, 18, [(255, 236, 190)], 14, 40, 5, (0.45, 0.35, 1, 0.75), 0.6)
    return finish(img, rng, warm=0.04)


def overcast_sea(rng: random.Random) -> Image.Image:
    img = vgrad([(0, (120, 130, 146)), (0.5, (196, 202, 208)), (0.501, (92, 112, 126)), (0.72, (120, 138, 146)),
                 (0.73, (200, 190, 170)), (1, (160, 148, 128))])
    clouds = Image.effect_noise((W // 30, H // 60), 60).resize((W, H), Image.BICUBIC).filter(ImageFilter.GaussianBlur(30))
    cmask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(cmask).rectangle([0, 0, W, H * 0.48], fill=120)
    cmask = cmask.filter(ImageFilter.GaussianBlur(60))
    img = Image.composite(Image.merge("RGB", [clouds.point(lambda v: int(150 + v * 0.35))] * 3), img, cmask)
    d = ImageDraw.Draw(img)
    for _ in range(500):  # waves
        y = rng.uniform(H * 0.505, H * 0.73)
        x = rng.uniform(0, W)
        ln = rng.uniform(10, 70) * (0.4 + (y - H * 0.5) / (H * 0.23))
        d.line([(x, y), (x + ln, y)], fill=(rng.randint(150, 220),) * 3, width=1)
    foam = [H * 0.73 + 10 * math.sin(x / 70) + rng.uniform(-2, 2) for x in range(W + 1)]
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).line(list(enumerate(foam)), fill=230, width=8)
    img = Image.composite(Image.new("RGB", (W, H), (236, 236, 232)), img, mask.filter(ImageFilter.GaussianBlur(3)))
    return finish(img, rng, grain=8, vignette=0.2)


def dusk_rooftops(rng: random.Random) -> Image.Image:
    img = vgrad([(0, (40, 34, 92)), (0.4, (122, 82, 150)), (0.7, (236, 150, 150)), (1, (250, 196, 160))])
    mx, my, mr = W * 0.68, H * 0.24, 46
    moon = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(moon)
    md.ellipse([mx - mr, my - mr, mx + mr, my + mr], fill=255)
    md.ellipse([mx - mr + 22, my - mr - 10, mx + mr + 22, my + mr - 10], fill=0)
    img = glow(img, (mx, my), 120, (90, 80, 120), 0.6)
    img = Image.composite(Image.new("RGB", (W, H), (252, 246, 226)), img, moon.filter(ImageFilter.GaussianBlur(1.2)))
    d = ImageDraw.Draw(img)
    x = -20
    roofs = []
    while x < W:
        bw = rng.uniform(110, 240)
        top = rng.uniform(H * 0.58, H * 0.72)
        roofs.append((x, top, bw))
        d.rectangle([x, top, x + bw, H], fill=(28, 20, 40))
        if rng.random() < 0.5:
            d.polygon([(x - 6, top), (x + bw / 2, top - rng.uniform(40, 90)), (x + bw + 6, top)], fill=(28, 20, 40))
        if rng.random() < 0.5:
            cx = x + rng.uniform(15, bw - 30)
            d.rectangle([cx, top - rng.uniform(40, 70), cx + 18, top], fill=(28, 20, 40))
        x += bw + rng.uniform(-10, 4)
    for x, top, bw in roofs:
        for _ in range(int(bw // 40)):
            if rng.random() < 0.45:
                wx, wy = x + rng.uniform(10, bw - 30), rng.uniform(top + 30, H - 40)
                d.rectangle([wx, wy, wx + 18, wy + 26], fill=(255, 196, 110))
    img = glow(img, (W * 0.3, H * 0.9), 300, (60, 30, 20), 0.5)
    return finish(img, rng, grain=10, vignette=0.3)


def autumn_bokeh(rng: random.Random) -> Image.Image:
    img = vgrad([(0, (120, 66, 30)), (0.5, (166, 92, 34)), (1, (70, 36, 20))])
    img = bokeh(img, rng, 60, [(255, 150, 40), (240, 90, 30), (255, 200, 80), (200, 60, 30)], 60, 150, 14, alpha=0.7)
    img = bokeh(img, rng, 40, [(255, 220, 120), (255, 170, 60)], 20, 50, 4, alpha=0.8)
    d = ImageDraw.Draw(img)
    pts = [(W * -0.05, H * 0.3)]
    for i in range(1, 9):
        pts.append((W * i / 8, H * 0.3 + rng.uniform(-30, 30) + i * 14))
    d.line(pts, fill=(44, 26, 16), width=16)
    for px, py in pts[1:-1]:
        for _ in range(3):
            lx, ly = px + rng.uniform(-60, 60), py + rng.uniform(20, 120)
            d.line([(px, py), (lx, ly)], fill=(44, 26, 16), width=4)
            s = rng.uniform(26, 44)
            leaf = [(lx, ly - s), (lx + s * 0.6, ly), (lx, ly + s), (lx - s * 0.6, ly)]
            d.polygon(leaf, fill=rng.choice([(214, 84, 28), (236, 128, 36), (190, 50, 30), (240, 170, 50)]))
    return finish(img, rng, warm=0.02)


def rainy_window(rng: random.Random) -> Image.Image:
    img = vgrad([(0, (16, 26, 40)), (1, (30, 36, 50))])
    img = bokeh(img, rng, 50, [(255, 170, 80), (90, 180, 220), (255, 90, 80), (230, 230, 255)], 50, 140, 18,
                (0, 0.2, 1, 1), 0.7)
    drops = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(drops)
    for _ in range(520):
        x, y = rng.uniform(0, W), rng.uniform(0, H)
        r = rng.uniform(2, 9) * rng.uniform(0.6, 1.0)
        d.ellipse([x - r, y - r * 1.15, x + r, y + r * 1.15], fill=(46, 54, 68))
        d.ellipse([x - r * 0.45, y - r * 0.7, x + r * 0.05, y - r * 0.25], fill=(170, 182, 206))
    for _ in range(14):  # a few drops that ran
        x, y = rng.uniform(0, W), rng.uniform(0, H * 0.7)
        pts = [(x + math.sin(i / 3) * 3, y + i * 9) for i in range(int(rng.uniform(10, 30)))]
        d.line(pts, fill=(40, 48, 62), width=5)
    img = ImageChops.screen(img, drops.filter(ImageFilter.GaussianBlur(1.2)))
    return finish(img, rng, grain=10, vignette=0.35)


def desk_lamp(rng: random.Random) -> Image.Image:
    img = vgrad([(0, (26, 20, 18)), (0.62, (44, 32, 26)), (0.621, (92, 62, 40)), (1, (48, 30, 18))])
    img = glow(img, (W * 0.22, H * 0.36), 640, (255, 170, 90), 0.9)
    grain_wood = Image.effect_noise((W // 2, 40), 50).resize((W, int(H * 0.38)), Image.BICUBIC)
    desk = img.crop((0, int(H * 0.62), W, H))
    desk = Image.blend(desk, Image.merge("RGB", [grain_wood.point(lambda v: int(v * 0.6))] * 3), 0.12)
    img.paste(desk, (0, int(H * 0.62)))
    d = ImageDraw.Draw(img)
    mx, my = W * 0.6, H * 0.6  # a mug
    d.rounded_rectangle([mx, my - 230, mx + 190, my + 10], radius=24, fill=(214, 206, 196))
    d.ellipse([mx + 160, my - 180, mx + 260, my - 70], outline=(214, 206, 196), width=22)
    d.ellipse([mx + 6, my - 246, mx + 184, my - 214], fill=(70, 44, 30))
    shade = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shade).rectangle([mx + 100, my - 230, mx + 190, my + 10], fill=110)
    img = Image.composite(Image.new("RGB", (W, H), (60, 50, 44)), img, shade.filter(ImageFilter.GaussianBlur(30)))
    for i, (bw, color) in enumerate([(520, (120, 40, 40)), (480, (40, 70, 90)), (500, (180, 150, 90))]):
        y = H * 0.62 + 30 - i * 54
        d.rectangle([W * 0.03, y - 50, W * 0.03 + bw, y], fill=color)
        d.line([(W * 0.03, y - 50), (W * 0.03 + bw, y - 50)], fill=tuple(min(255, c + 50) for c in color), width=3)
    img = glow(img, (mx + 95, my - 300), 90, (90, 70, 60), 0.4)  # steam, barely
    return finish(img, rng, grain=11, warm=0.03)


def bonfire(rng: random.Random) -> Image.Image:
    img = vgrad([(0, (6, 6, 14)), (0.7, (20, 12, 16)), (1, (34, 16, 10))])
    cx, cy = W * 0.5, H * 0.8
    img = glow(img, (cx, cy), 700, (160, 60, 20), 0.8)
    flames = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(flames)
    for _ in range(90):
        h = rng.uniform(120, 420)
        w = rng.uniform(30, 90)
        x = cx + rng.gauss(0, 70)
        c = rng.choice([(255, 120, 30), (255, 170, 60), (255, 220, 120), (230, 70, 20)])
        d.polygon([(x - w / 2, cy), (x + rng.uniform(-30, 30), cy - h), (x + w / 2, cy)], fill=c)
    img = ImageChops.screen(img, flames.filter(ImageFilter.GaussianBlur(14)))
    img = glow(img, (cx, cy - 80), 160, (255, 230, 170), 0.9)
    d = ImageDraw.Draw(img)
    for _ in range(140):  # sparks
        x, y = cx + rng.gauss(0, 160), cy - rng.uniform(150, 1100)
        r = rng.uniform(1, 3)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, rng.randint(150, 220), 90))
    for ang in (-0.35, 0.3, 0.05):  # logs
        lx, ly = cx + math.sin(ang) * 40, cy + 20
        d.line([(lx - 220 * math.cos(ang), ly + 30), (lx + 220 * math.cos(ang), ly - 10)], fill=(30, 16, 10), width=46)
    img = silhouette(img, [H * 0.9 + 14 * math.sin(x / 140) for x in range(W + 1)], (12, 8, 8), 3)
    return finish(img, rng, grain=12, vignette=0.4)


def string_lights(rng: random.Random) -> Image.Image:
    img = vgrad([(0, (30, 20, 22)), (1, (54, 34, 28))])
    img = bokeh(img, rng, 40, [(255, 190, 110), (255, 160, 90)], 60, 130, 20, (0, 0.4, 1, 1), 0.55)
    lights = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(lights)
    for k, (y0, sag) in enumerate([(0.12, 0.08), (0.3, 0.1), (0.46, 0.07)]):
        pts = [(x, H * (y0 + sag * math.sin(math.pi * x / W))) for x in range(-20, W + 40, 6)]
        d.line(pts, fill=(40, 32, 26), width=3)
        for x, y in pts[::14]:
            r = 9 - k * 2
            d.ellipse([x - r, y, x + r, y + r * 2.2], fill=(255, 214, 140))
    img = ImageChops.screen(img, lights)
    img = ImageChops.screen(img, lights.filter(ImageFilter.GaussianBlur(18)))
    return finish(img, rng, grain=11, warm=0.03)


def fog_lamps(rng: random.Random) -> Image.Image:
    img = vgrad([(0, (40, 52, 70)), (0.6, (70, 84, 100)), (1, (30, 34, 40))])
    for i in range(6):
        t = i / 5
        x = W * (0.18 + 0.6 * t ** 1.2)
        top = H * (0.32 + 0.16 * t)
        base = H * (0.92 - 0.25 * t)
        width = 14 * (1 - t * 0.75)
        c = (int(20 + 50 * t), int(24 + 54 * t), int(30 + 60 * t))
        d = ImageDraw.Draw(img)
        d.line([(x, top), (x, base)], fill=c, width=int(width))
        img = glow(img, (x, top), 260 * (1 - t * 0.6), (255, 196, 130), 0.9 - t * 0.4)
    img = haze(img, 0.6, 0.25, (120, 128, 140), 0.45)
    img = silhouette(img, [H * 0.92 - (H * 0.25) * (x / W) ** 1.2 * 0.2 for x in range(W + 1)], (22, 24, 28), 2)
    return finish(img, rng, grain=10, vignette=0.35)


SCENES = {
    "sunset_lake": sunset_lake, "misty_mountains": misty_mountains, "city_bokeh": city_bokeh,
    "starry_hill": starry_hill, "golden_field": golden_field, "overcast_sea": overcast_sea,
    "dusk_rooftops": dusk_rooftops, "autumn_bokeh": autumn_bokeh, "rainy_window": rainy_window,
    "desk_lamp": desk_lamp, "bonfire": bonfire, "string_lights": string_lights, "fog_lamps": fog_lamps,
}


def scene(name: str, seed: int = 1) -> Image.Image:
    return SCENES[name](random.Random(f"{name}:{seed}"))


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "scenes.jpg"
    names = list(SCENES)
    cols, tw, th = 5, 300, 400
    sheet = Image.new("RGB", (cols * tw, math.ceil(len(names) / cols) * th), (255, 255, 255))
    for i, name in enumerate(names):
        sheet.paste(scene(name).resize((tw, th)), ((i % cols) * tw, (i // cols) * th))
    sheet.save(out, quality=88)
    print(out)
