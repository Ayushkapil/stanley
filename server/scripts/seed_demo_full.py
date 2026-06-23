#!/usr/bin/env python
"""Seed a full, living demo environment for a visual demo run.

Resets the dev database + blob store and rebuilds from scratch: one circle,
eight members with real bios, ~14 photos backdated across the whole decay
lifecycle (LIVE / FADING / LAST_LIGHT / EXPIRED / PURGED), a shared moment,
likes, holds, story-comments, a community note, an eligible Returned item,
and enough history for a milestone. Then runs the decay sweep so every state
is authoritative.

The signed-in demo user is "Ayush" — sign in with that exact name (dev sign-in
is idempotent by name) to land on this circle.

Usage (from the server dir, so var/ resolves):
    .venv/bin/python scripts/seed_demo_full.py
"""
from __future__ import annotations

import io
import os
import shutil
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from PIL import Image, ImageDraw, ImageFont

from stanley import decay, physics
from stanley.clock import SystemClock
from stanley.config import Settings, resolve_secret
from stanley.db import Base, ensure_schema, make_engine, make_sessionmaker
from stanley.images import process_upload
from stanley.models import (
    Anchor,
    Circle,
    Comment,
    CommunityNote,
    Like,
    Membership,
    Photo,
    User,
    new_id,
    new_invite_code,
)
from stanley.notifications import Notifier
from stanley.storage import make_blob_store

NY = "America/New_York"
HOUR = timedelta(hours=1)
DAY = timedelta(days=1)


# --- image generation --------------------------------------------------------

def _font(size: int):
    for path in (
        "/System/Library/Fonts/Supplemental/Georgia.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial.ttf",
    ):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                pass
    return ImageFont.load_default()


def gradient_jpeg(top: tuple[int, int, int], bottom: tuple[int, int, int], label: str) -> bytes:
    """A soft vertical-gradient placeholder with a caption — varied enough that
    the feed reads as real photos at a glance."""
    w, h = 1080, 1440
    img = Image.new("RGB", (w, h))
    draw = ImageDraw.Draw(img)
    for y in range(h):
        t = y / (h - 1)
        draw.line(
            [(0, y), (w, y)],
            fill=(
                int(top[0] * (1 - t) + bottom[0] * t),
                int(top[1] * (1 - t) + bottom[1] * t),
                int(top[2] * (1 - t) + bottom[2] * t),
            ),
        )
    draw.text((70, h - 150), label, fill=(255, 255, 255), font=_font(54))
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=90)
    return buf.getvalue()


# --- reset -------------------------------------------------------------------

def reset(settings: Settings) -> None:
    """Delete the dev SQLite DB (+ WAL/SHM) and the blob store. Guarded to file
    URLs only so this can never touch a real database."""
    url = settings.database_url
    if url.startswith("sqlite:///") and ":memory:" not in url:
        base = url.removeprefix("sqlite:///")
        for suffix in ("", "-wal", "-shm"):
            path = base + suffix
            if os.path.exists(path):
                os.remove(path)
    if os.path.isdir(settings.blob_dir):
        shutil.rmtree(settings.blob_dir)


# --- seed --------------------------------------------------------------------

def main() -> None:
    settings = Settings()
    settings.dev_auth = True
    settings.run_sweeper = False
    settings.secret_key = resolve_secret(settings)

    print(f"Resetting {settings.database_url} and {settings.blob_dir} ...")
    reset(settings)

    engine = make_engine(settings.database_url)
    Base.metadata.create_all(engine)
    ensure_schema(engine)
    Session = make_sessionmaker(engine)
    storage = make_blob_store(settings)
    clock = SystemClock()
    notifier = Notifier()

    now = clock.now()
    circle_birth = now - 100 * DAY  # a ~3-month-old circle (a milestone for Ayush)

    people = {
        "Ayush":   ("ayush",   "CS major, mostly at the climbing gym or up too late debugging something. Will absolutely talk your ear off about pour-over coffee."),
        "Sahana":  ("sahana",  "Bio + studio art. I photograph everything that holds still for half a second. Overcommitted to three clubs and counting."),
        "Ben":     ("benk",    "Econ, intramural soccer, professional ramen enthusiast. Ask me about my fantasy league. Actually, please don't."),
        "Diego":   ("diego",   "Mechanical engineering. I build small useless robots and lose at chess to Aryan every single week."),
        "Aryan":   ("aryan",   "Math + CS, nocturnal by choice. Powered by cold brew and spite. Undefeated vs Diego, for the record."),
        "Katy":    ("katyr",   "Public health, RA on the 3rd floor, plant mom to eleven succulents. I'm the one who organizes the cookouts."),
        "Tanmay":  ("tanmay",  "Physics. Astrophotography on clear nights — the parking garage roof is basically my observatory."),
        "Lavinia": ("lavinia", "Environmental science. Farmers market every Saturday, trail run every Sunday, repeat until graduation."),
    }

    with Session() as s:
        users: dict[str, User] = {}
        for name, (username, bio) in people.items():
            u = User(
                display_name=name,
                username=username,
                bio=bio,
                tz_last_seen=NY,
                created_at=circle_birth - DAY,
            )
            s.add(u)
            users[name] = u
        s.flush()

        ayush = users["Ayush"]
        circle = Circle(
            name="Collins 3rd Floor",
            created_by=ayush.id,
            invite_token=new_invite_code(),
            created_at=circle_birth,
        )
        s.add(circle)
        s.flush()

        for name, u in users.items():
            s.add(
                Membership(
                    circle_id=circle.id,
                    user_id=u.id,
                    joined_at=circle_birth if name == "Ayush" else circle_birth + HOUR,
                    role="creator" if name == "Ayush" else "member",
                )
            )
        s.flush()

        def photo(owner: str, caption: str, location: str | None, hours_ago: float,
                  colors: tuple[tuple[int, int, int], tuple[int, int, int]]) -> Photo:
            taken_at = now - hours_ago * HOUR
            pid = new_id()
            data = gradient_jpeg(colors[0], colors[1], caption)
            proc = process_upload(data)
            keys = {
                "blob_key": f"{pid}/orig.jpg",
                "deriv_key": f"{pid}/deriv.jpg",
                "thumb_key": f"{pid}/thumb.jpg",
            }
            storage.put(keys["blob_key"], proc.original)
            storage.put(keys["deriv_key"], proc.derivative)
            storage.put(keys["thumb_key"], proc.thumbnail)
            p = Photo(
                id=pid,
                owner_id=users[owner].id,
                circle_id=circle.id,
                taken_at=taken_at,
                taken_tz=NY,
                local_date=physics.local_capture_date(taken_at, NY),
                caption=caption,
                location=location,
                state=physics.LIVE,
                state_deadline=physics.state_deadline(physics.LIVE, taken_at),
                created_at=taken_at,
                **keys,
            )
            s.add(p)
            s.flush()
            return p

        def like(p: Photo, *names: str) -> None:
            for n in names:
                s.add(Like(photo_id=p.id, user_id=users[n].id, created_at=now - HOUR))

        def hold(p: Photo, *names: str, days_ago: float | None = None) -> None:
            for n in names:
                at = now - (days_ago * DAY if days_ago is not None else HOUR)
                s.add(Anchor(photo_id=p.id, user_id=users[n].id, created_at=at, note=None))

        def comment(p: Photo, author: str, body: str) -> None:
            s.add(Comment(photo_id=p.id, author_id=users[author].id, body=body, created_at=now - HOUR / 2))

        # LIVE (< 48h) -------------------------------------------------------
        sunset = photo("Sahana", "library sunset", "Wells Library", 6, ((247, 148, 64), (90, 52, 120)))
        like(sunset, "Ben", "Aryan", "Katy")  # owner (Sahana) sees faces, no count

        ramen = photo("Ben", "finally tried the new ramen place", "Ramen House", 10, ((196, 64, 50), (60, 28, 24)))
        comment(ramen, "Diego", "you said you'd never try it 😂")

        # Shared moment at "Collins" today: Ayush + Katy + Diego.
        practice = photo("Ayush", "morning practice", "Collins", 5, ((38, 120, 142), (24, 44, 92)))
        like(practice, "Sahana", "Ben", "Katy")  # so the signed-in demo user sees the faces
        hold(practice, "Ben")                      # someone kept one of Ayush's moments
        photo("Katy", "last one before summer", "Collins", 8, ((86, 168, 78), (212, 196, 64)))
        photo("Diego", "found this in the stacks", "Collins", 12, ((52, 70, 150), (28, 30, 78)))

        # FADING (48–120h) ---------------------------------------------------
        coding = photo("Aryan", "3am coding session", "Luddy Hall", 60, ((30, 26, 64), (96, 44, 120)))
        hold(coding, "Ayush", "Sahana")  # held → shows in Ayush's Held at full saturation

        garage = photo("Tanmay", "sunset from the parking garage", None, 74, ((236, 110, 140), (244, 170, 90)))
        comment(garage, "Lavinia", "we need to go back there")

        photo("Lavinia", "farmers market haul", "Bloomington Community", 88, ((120, 176, 72), (196, 208, 96)))

        # LAST_LIGHT (120–144h) ----------------------------------------------
        photo("Sahana", "first week done", None, 128, ((54, 96, 150), (40, 130, 130)))
        photo("Ben", "bike ride to the lake", "Griffy Lake", 136, ((58, 168, 170), (74, 150, 92)))

        # EXPIRED but held by Ayush → in his Held, never in Today --------------
        robotics = photo("Diego", "robotics finals", "Luddy Hall", 7 * 24, ((120, 124, 132), (60, 66, 78)))
        hold(robotics, "Ayush", days_ago=6.5)
        succulents = photo("Katy", "repotting day", None, 8 * 24, ((96, 142, 84), (132, 140, 70)))
        hold(succulents, "Ayush", days_ago=7.5)

        # EXPIRED + unanchored + old enough to purge → becomes a tombstone -----
        photo("Tanmay", "spring break flight", None, 15 * 24, ((150, 196, 232), (235, 240, 245)))

        # Near-forgotten Returned: a memory Ayush held 100 days ago, unseen since.
        snowday = photo("Sahana", "snow day on the quad", "Collins", 100 * 24, ((214, 226, 240), (150, 178, 214)))
        hold(snowday, "Ayush", days_ago=100)

        # Community note (clears at the end of Katy's local day) --------------
        ny_now = now.astimezone(ZoneInfo(NY))
        midnight = (ny_now + DAY).replace(hour=0, minute=0, second=0, microsecond=0)
        s.add(
            CommunityNote(
                circle_id=circle.id,
                author_id=users["Katy"].id,
                body="cookout at dunn meadow 6pm 🌽",
                expires_at=midnight.astimezone(timezone.utc),
                created_at=now - 2 * HOUR,
            )
        )

        s.commit()
        invite = circle.invite_token
        ayush_id = ayush.id

    # Run the decay engine so every state is server-authoritative.
    with Session() as s:
        advanced = decay.sweep(s, clock, notifier)
        purged = decay.run_purges(s, storage, clock)
        s.commit()

    # Report ----------------------------------------------------------------
    with Session() as s:
        from collections import Counter
        from sqlalchemy import select

        counts = Counter(
            st for (st,) in s.execute(select(Photo.state).where(Photo.circle_id == circle.id)).all()
        )
        print()
        print("Seeded circle:", circle.name)
        print("Invite code:", invite)
        print("Demo user: Ayush  (id", ayush_id + ")")
        print("Members:", ", ".join(people))
        print("Decay sweep advanced", advanced, "transitions;", purged, "photo(s) purged.")
        print("Photo states:", dict(counts))
        print()
        print('Sign in as "Ayush" in the app to land on this circle.')


if __name__ == "__main__":
    main()
