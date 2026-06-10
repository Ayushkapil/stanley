#!/usr/bin/env python
"""Seed a demo circle against a running dev server, so the app's first session
opens onto a living feed (circle-first onboarding, §4).

Usage:
    .venv/bin/python scripts/seed_demo.py [base_url]

Creates fresh users ana + ben, a circle, two photos and a comment, then prints
the invite code to paste into the iOS app. Each run seeds a brand-new circle.
"""
from __future__ import annotations

import io
import sys

import httpx
from PIL import Image, ImageDraw


def jpeg(color: tuple[int, int, int], label: str) -> bytes:
    img = Image.new("RGB", (1080, 1440), color)
    draw = ImageDraw.Draw(img)
    draw.text((60, 700), label, fill="white")
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=90)
    return buf.getvalue()


def main() -> None:
    base = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"
    with httpx.Client(base_url=base, timeout=30) as client:

        def auth(name: str) -> dict:
            r = client.post("/auth/dev", json={"display_name": name})
            r.raise_for_status()
            return {"Authorization": f"Bearer {r.json()['token']}"}

        ana, ben = auth("ana"), auth("ben")

        r = client.post("/circles", json={"name": "demo circle"}, headers=ana)
        r.raise_for_status()
        circle = r.json()
        client.post(
            f"/circles/{circle['id']}/join",
            json={"invite_token": circle["invite_token"]},
            headers=ben,
        ).raise_for_status()

        posts = [
            (ana, (90, 60, 140), "ana's tuesday"),
            (ben, (20, 110, 130), "ben's bike ride"),
        ]
        photo_ids = []
        for headers, color, caption in posts:
            r = client.post(
                "/photos",
                files={"file": ("photo.jpg", jpeg(color, caption), "image/jpeg")},
                data={"tz": "America/New_York", "caption": caption},
                headers=headers,
            )
            r.raise_for_status()
            photo_ids.append(r.json()["id"])

        client.post(
            f"/photos/{photo_ids[0]}/comments",
            json={"body": "that light!"},
            headers=ben,
        ).raise_for_status()

        print("Circle seeded: ana + ben, two photos, one story-comment.")
        print()
        print(f"Invite code (paste into the app):")
        print(f"  {circle['id']}.{circle['invite_token']}")


if __name__ == "__main__":
    main()
