#!/usr/bin/env python
"""Generate Stanley's app icon into Assets.xcassets/AppIcon.appiconset.

The icon is a bookmark drawn in ink on paper (build 23): the classic ribbon
with a V cut from its foot, the mark of the hold gesture, sketched as one
thin pen line on the journal's cream (#F6F0E4, Auto's light floor) in a
dark brown ink (#3B2F25). It is an outline, never a fill, drawn a little
off true the way a hand draws, with a lighter crease across the top where
the ribbon folds over the page. Everything is drawn once at 4x and
downsampled, so the line stays even at 20pt. The wobble comes from a fixed
seed, so running this again writes the same bytes.

Usage (any Python with Pillow; the server's venv has it):
    server/.venv/bin/python ios/Tools/make_app_icon.py
"""
from __future__ import annotations

import json
import math
import os
import random

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Stanley", "Assets.xcassets", "AppIcon.appiconset")

PAPER = (246, 240, 228)   # #F6F0E4, the journal's cream
INK = (59, 47, 37)        # #3B2F25, a dark brown pen

SS = 4096                 # supersampled canvas; the master is 1024
MASTER = 1024
K = SS // MASTER
# Exactly the sizes Contents.json references — no orphans for the asset
# compiler to warn about.
SIZES = [1024, 180, 120, 87, 80, 60, 58, 40]

# The ribbon, in 1024 units: a band 360 wide from y=206 to 838 with a notch
# 106 deep, set a touch below centre so the notch's missing weight doesn't
# leave it sitting high. Well inside the corners iOS rounds off.
LEFT, RIGHT = 332, 692
TOP, BOTTOM = 206, 838
NOTCH = (512, 732)
STROKE = 24               # a fineliner: 4px on a 60pt icon at 3x, under 1px at 20pt
CREASE_Y = TOP + 84

# One seed, so the hand draws the same lines every time.
rng = random.Random(7)


def wander(amp: float):
    """A smooth, small sideways drift along a stroke: two slow sines with
    seeded phases, so no two edges wander the same way."""
    f1, f2 = rng.uniform(0.6, 1.3), rng.uniform(2.0, 3.4)
    p1, p2 = rng.uniform(0, math.tau), rng.uniform(0, math.tau)
    a2 = amp * rng.uniform(0.2, 0.35)
    return lambda t: (amp * math.sin(math.tau * f1 * t + p1)
                      + a2 * math.sin(math.tau * f2 * t + p2))


def stroke(d: ImageDraw.ImageDraw, p0, p1, width: float, color,
           amp: float = 1.8, overshoot=(3.5, 3.5)) -> None:
    """One pen stroke from p0 to p1 (1024 units), drawn at SS. It runs a
    little past each end as a hand's does, thinning as the pen lifts, drifts
    sideways by up to `amp`, and thickens and thins by about a tenth along
    the way. Round joints make it one line."""
    (x0, y0), (x1, y1) = p0, p1
    dx, dy = x1 - x0, y1 - y0
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length      # along the stroke
    nx, ny = -uy, ux                       # across it
    o0 = rng.uniform(0.4, 1.0) * overshoot[0]
    o1 = rng.uniform(0.4, 1.0) * overshoot[1]
    drift = wander(amp)
    wf, wp = rng.uniform(0.8, 1.6), rng.uniform(0, math.tau)

    steps = max(24, int(length / 4))
    pts = []
    for i in range(steps + 1):
        t = i / steps
        s = -o0 + t * (length + o0 + o1)   # distance along, past both ends
        w = drift(t)
        x = (x0 + ux * s + nx * w) * K
        y = (y0 + uy * s + ny * w) * K
        thick = width * (1 + 0.1 * math.sin(math.tau * wf * t + wp)) * K
        # The pen lands and lifts: half width at the very ends, full by 6%.
        edge = min(t, 1 - t)
        if edge < 0.06:
            thick *= 0.5 + 0.5 * (edge / 0.06)
        pts.append((x, y, thick))

    for (xa, ya, wa), (xb, yb, wb) in zip(pts, pts[1:]):
        d.line([xa, ya, xb, yb], fill=color, width=int(round((wa + wb) / 2)))
    for x, y, w in pts:
        # Pillow has no round joints; add them.
        r = w / 2
        d.ellipse([x - r, y - r, x + r, y + r], fill=color)


def draw_bookmark(img: Image.Image) -> None:
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # The crease first, lighter and thinner, a touch off level; the outline
    # goes over it, since drawing replaces pixels rather than blending.
    crease = INK + (104,)
    stroke(d, (LEFT, CREASE_Y + 3), (RIGHT, CREASE_Y - 3), STROKE * 0.5, crease,
           amp=1.2, overshoot=(0, 0))

    # Around the ribbon, one edge per stroke, the pen lifting at each corner.
    # The two edges that meet at the notch barely run past it, so the apex
    # stays a point rather than a little cross.
    ink = INK + (236,)
    tl, tr, br, bl = (LEFT, TOP), (RIGHT, TOP), (RIGHT, BOTTOM), (LEFT, BOTTOM)
    stroke(d, tl, tr, STROKE, ink)
    stroke(d, tr, br, STROKE, ink)
    stroke(d, br, NOTCH, STROKE, ink, overshoot=(3.5, 1.0))
    stroke(d, NOTCH, bl, STROKE, ink, overshoot=(1.0, 3.5))
    stroke(d, bl, tl, STROKE, ink)

    img.alpha_composite(layer)


def contents_json() -> dict:
    """The slots iOS actually uses on an iPhone-only app, by point size and
    scale. The 20pt and 29pt @1x files exist for completeness but have no
    iPhone slot, so they are not referenced here."""
    entries = [
        ("20x20", "2x", 40), ("20x20", "3x", 60),
        ("29x29", "2x", 58), ("29x29", "3x", 87),
        ("40x40", "2x", 80), ("40x40", "3x", 120),
        ("60x60", "2x", 120), ("60x60", "3x", 180),
    ]
    images = [
        {"idiom": "iphone", "size": size, "scale": scale, "filename": "icon-%d.png" % px}
        for size, scale, px in entries
    ]
    images.append({"idiom": "ios-marketing", "size": "1024x1024", "scale": "1x",
                   "filename": "icon-1024.png"})
    return {"images": images, "info": {"author": "xcode", "version": 1}}


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    big = Image.new("RGBA", (SS, SS), PAPER + (255,))
    draw_bookmark(big)
    master = big.resize((MASTER, MASTER), Image.LANCZOS).convert("RGB")

    for size in SIZES:
        img = master if size == MASTER else master.resize((size, size), Image.LANCZOS)
        # App icons must carry no alpha channel — the store rejects RGBA.
        img.convert("RGB").save(os.path.join(OUT, "icon-%d.png" % size), "PNG")

    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump(contents_json(), f, indent=2)
        f.write("\n")

    root = os.path.join(OUT, "..", "Contents.json")
    with open(root, "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")

    print("wrote %d icons to %s" % (len(SIZES), os.path.normpath(OUT)))


if __name__ == "__main__":
    main()
