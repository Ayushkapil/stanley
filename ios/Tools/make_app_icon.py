#!/usr/bin/env python
"""Generate Stanley's app icon into Assets.xcassets/AppIcon.appiconset.

The icon is the sun that the Today tab already uses, in the warm end of the
seasonal palette from `Atmosphere.swift`: one light, drawn as an outline so it
reads as a mark rather than a blob. Everything is drawn once at 4x and
downsampled, so the stroke stays even at 20pt.

Usage (any Python with Pillow):
    python ios/Tools/make_app_icon.py
"""
from __future__ import annotations

import json
import math
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Stanley", "Assets.xcassets", "AppIcon.appiconset")

# Atmosphere.swift, warm → fall: the amber the app already tints itself with.
TOP = (242, 178, 74)
BOTTOM = (191, 92, 44)

SS = 4096           # supersampled canvas; the master is 1024
MASTER = 1024
SIZES = [1024, 180, 120, 87, 80, 60, 58, 40, 29, 20]


def gradient(size: int) -> Image.Image:
    """A soft corner-to-corner wash. Built tiny and scaled up — a gradient is
    exactly the thing that survives interpolation perfectly, and 16M per-pixel
    Python operations is exactly the thing that does not."""
    small = Image.new("RGB", (64, 64))
    px = small.load()
    for y in range(64):
        for x in range(64):
            t = (x + y) / 126.0
            px[x, y] = tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
    return small.resize((size, size), Image.BICUBIC)


def draw_sun(img: Image.Image) -> None:
    d = ImageDraw.Draw(img)
    c = SS / 2
    stroke = 176          # 44pt at 1024 — heavy enough to hold at 20pt
    radius = 760
    ray_in, ray_out = 1060, 1470
    white = (255, 255, 255)

    d.ellipse([c - radius, c - radius, c + radius, c + radius],
              outline=white, width=stroke)

    cap = stroke / 2
    for i in range(8):
        a = math.radians(i * 45)
        dx, dy = math.cos(a), math.sin(a)
        x0, y0 = c + dx * ray_in, c + dy * ray_in
        x1, y1 = c + dx * ray_out, c + dy * ray_out
        d.line([x0, y0, x1, y1], fill=white, width=stroke)
        # Pillow has no round line caps; add them.
        for x, y in ((x0, y0), (x1, y1)):
            d.ellipse([x - cap, y - cap, x + cap, y + cap], fill=white)


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
    big = gradient(SS)
    draw_sun(big)
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
