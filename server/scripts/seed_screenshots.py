#!/usr/bin/env python
"""A circle for App Store screenshots (the production audit, November 2026).

Eight people on a dorm floor, "Third Floor", three days of photos (two from
tonight, a shared moment at Griffy Lake yesterday, a fading Sunday), stories
with a mention, likes, who-was-there faces, a note on the board, and a Held
page with memories from late October. Every photo is drawn in code
(`scenes.py`): nobody's real photos, no stock licence. Times are relative to
now, so the journal reads "Today" and "Yesterday" whenever it's run.

It builds a fresh database in its own folder and refuses to touch one that
exists unless told to reset it, so the dev database is never at risk:

    .venv/bin/python scripts/seed_screenshots.py --data-dir /tmp/stanley-shots --reset
    STANLEY_DATA_DIR=/tmp/stanley-shots STANLEY_DEV_AUTH=1 STANLEY_SECRET_KEY=dev \\
        .venv/bin/python -m uvicorn --factory stanley.main:create_app

Then sign in on the simulator (Debug build) as "Maya Chen".
"""
from __future__ import annotations

import argparse
import io
import os
import shutil
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from scenes import scene  # noqa: E402

from stanley import decay, physics  # noqa: E402
from stanley.clock import SystemClock  # noqa: E402
from stanley.config import Settings  # noqa: E402
from stanley.db import Base, ensure_schema, make_engine, make_sessionmaker  # noqa: E402
from stanley.images import process_avatar, process_upload  # noqa: E402
from stanley.models import (  # noqa: E402
    Anchor, Circle, Comment, CommunityNote, Like, Membership, Photo, PhotoTag, User, new_id,
)
from stanley.notifications import Notifier  # noqa: E402
from stanley.storage import make_blob_store  # noqa: E402

NY = ZoneInfo("America/New_York")

PEOPLE = {
    # display name: (username, bio, avatar scene or None)
    "Maya Chen": ("maya.c", "Third floor, room 312. Usually the one with the camera.", "misty_mountains"),
    "Jonah Reyes": ("jonah", "Geology. Will hike anywhere with a view.", "sunset_lake"),
    "Priya Nair": ("priya.n", "8am classes and early light.", None),
    "Theo Brooks": ("theo.b", "Library regular. Closing shift, every night.", "desk_lamp"),
    "Ines Moreau": ("ines", "Architecture. Rooftops are my thing.", "dusk_rooftops"),
    "Sam Okafor": ("sam.o", "Takes the 6 bus everywhere.", None),
    "Ruby Alvarez": ("ruby", "Runs movie night. Bring blankets.", "string_lights"),
    "Marcus Lee": ("marcus", "Physics. Out on the roof when it's clear.", "starry_hill"),
}


def jpeg(img) -> bytes:
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=92)
    return buf.getvalue()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--data-dir", required=True, help="a folder of its own, never the dev var/")
    parser.add_argument("--reset", action="store_true", help="delete what's in --data-dir first")
    args = parser.parse_args()

    data = Path(args.data_dir).resolve()
    if data == (Path(__file__).resolve().parents[1] / "var").resolve():
        sys.exit("refusing to seed the dev database's folder")
    if (data / "stanley.db").exists():
        if not args.reset:
            sys.exit(f"{data} already has a database; pass --reset to replace it")
        shutil.rmtree(data)
    data.mkdir(parents=True, exist_ok=True)

    settings = Settings(
        data_dir=str(data), database_url=f"sqlite:///{data}/stanley.db", blob_dir=str(data / "blobs"),
        secret_key="screenshots", dev_auth=True, run_sweeper=False,
    )
    engine = make_engine(settings.database_url)
    Base.metadata.create_all(engine)
    ensure_schema(engine)
    Session = make_sessionmaker(engine)
    storage = make_blob_store(settings)
    clock = SystemClock()
    now = clock.now()
    local_now = now.astimezone(NY)
    midnight = local_now.replace(hour=0, minute=0, second=0, microsecond=0)

    def at(days_ago: int, hour: int, minute: int) -> datetime:
        day = (local_now - timedelta(days=days_ago)).date()
        return datetime(day.year, day.month, day.day, hour, minute, tzinfo=NY).astimezone(timezone.utc)

    def tonight(minutes_ago: int) -> datetime:
        # Today's photos are from tonight, but never before midnight.
        return max(now - timedelta(minutes=minutes_ago), midnight + timedelta(minutes=7)).astimezone(timezone.utc)

    born = at(120, 19, 0)  # the circle began in July

    with Session() as s:
        users: dict[str, User] = {}
        for name, (username, bio, face) in PEOPLE.items():
            u = User(display_name=name, username=username, bio=bio, tz_last_seen="America/New_York",
                     created_at=born - timedelta(days=1))
            s.add(u)
            s.flush()
            if face:
                square = scene(face, 7).crop((150, 300, 1050, 1200))
                key = f"avatars/{u.id}.jpg"
                storage.put(key, process_avatar(jpeg(square)))
                u.avatar_key = key
            users[name.split()[0]] = u
        maya = users["Maya"]
        circle = Circle(name="Third Floor", created_by=maya.id, created_at=born)
        s.add(circle)
        s.flush()
        for i, u in enumerate(users.values()):
            s.add(Membership(circle_id=circle.id, user_id=u.id, joined_at=born + timedelta(hours=i),
                             role="creator" if u is maya else "member"))
        s.flush()

        def photo(owner: str, look: str, taken_at: datetime, caption: str, place: str | None, seed: int = 1) -> Photo:
            pid = new_id()
            proc = process_upload(jpeg(scene(look, seed)))
            keys = {"blob_key": f"{pid}/orig.jpg", "deriv_key": f"{pid}/deriv.jpg", "thumb_key": f"{pid}/thumb.jpg"}
            storage.put(keys["blob_key"], proc.original)
            storage.put(keys["deriv_key"], proc.derivative)
            storage.put(keys["thumb_key"], proc.thumbnail)
            p = Photo(
                id=pid, owner_id=users[owner].id, circle_id=circle.id, taken_at=taken_at,
                taken_tz="America/New_York", local_date=physics.local_capture_date(taken_at, "America/New_York"),
                caption=caption, location=place, state=physics.LIVE,
                state_deadline=physics.state_deadline(physics.LIVE, taken_at), created_at=taken_at, **keys,
            )
            s.add(p)
            s.flush()
            return p

        def story(p: Photo, who: str, words: str, minutes_after: int) -> None:
            s.add(Comment(photo_id=p.id, author_id=users[who].id, body=words,
                          created_at=min(now, p.taken_at + timedelta(minutes=minutes_after))))

        def like(p: Photo, *who: str) -> None:
            for w in who:
                s.add(Like(photo_id=p.id, user_id=users[w].id, created_at=now - timedelta(minutes=5)))

        def hold(p: Photo, who: str, days_after: float = 0.1) -> None:
            s.add(Anchor(photo_id=p.id, user_id=users[who].id,
                         created_at=min(now, p.taken_at + timedelta(days=days_after))))

        # Tonight.
        # Tonight's first is a light one (a library photo from the weekend):
        # iOS 26's glass tab bar darkens over a dark photo, and the selected
        # tab's ink vanishes into it.
        drive = photo("Theo", "misty_mountains", tonight(34), "still thinking about the fall break drive",
                      "Brown County", seed=2)
        snack = photo("Ruby", "city_bokeh", tonight(71), "midnight snack run, no regrets", "Kirkwood Ave")
        story(snack, "Sam", "you didn't bring me one", 12)
        like(drive, "Maya")

        # Yesterday: a shared moment at Griffy Lake, and the rest of the day.
        sunset = photo("Jonah", "sunset_lake", at(1, 17, 48), "the sky did that", "Griffy Lake")
        golden = photo("Ines", "golden_field", at(1, 17, 31), "golden hour from the trail in", "Griffy Lake")
        movie = photo("Maya", "string_lights", at(1, 21, 12), "movie night, take one", "3rd floor lounge")
        bus = photo("Sam", "rainy_window", at(1, 14, 20), "the 6 bus, again", "Kirkwood Ave")
        fog = photo("Priya", "fog_lamps", at(1, 7, 55), "fog on the way to the 8am", "Sample Gates")
        story(sunset, "Priya", "we ran up the hill for this", 6)
        story(sunset, "Ines", f"@[{maya.id}] you missed it by five minutes", 14)
        story(sunset, "Maya", "next time I'm coming", 40)
        story(sunset, "Theo", "framing this one", 95)
        story(movie, "Jonah", "best decision of the week", 30)
        story(movie, "Ruby", "who brought the popcorn??", 44)
        story(bus, "Marcus", "the 6 is always late", 20)
        story(fog, "Ines", "it looks like a painting", 50)
        like(sunset, "Maya")
        like(golden, "Maya")
        like(movie, "Jonah", "Ruby", "Priya", "Ines")
        for w in ("Jonah", "Ruby", "Priya"):
            s.add(PhotoTag(photo_id=movie.id, tagged_user_id=users[w].id, created_at=movie.taken_at))

        # Sunday, fading.
        stars = photo("Marcus", "starry_hill", at(2, 23, 40), "no clouds for once", "the roof")
        leaves = photo("Ruby", "autumn_bokeh", at(2, 15, 58), "last of the leaves", "Dunn Meadow")
        lake = photo("Theo", "overcast_sea", at(2, 12, 6), "gray day at the lake", "Lake Monroe")
        story(leaves, "Priya", "these colors", 25)
        story(stars, "Maya", "how is this from our roof", 18)

        # Late October: gone from Today, kept in Maya's Held.
        # Light, as Held's first page ends under the tab bar (see "Tonight").
        bonfire = photo("Jonah", "golden_field", at(10, 17, 30), "the trail at Griffy", "Griffy Lake", seed=5)
        walk = photo("Theo", "desk_lamp", at(7, 23, 5), "late night at Wells", "Wells Library")
        roofs = photo("Ines", "dusk_rooftops", at(14, 18, 20), "view from 312", None)
        for p in (sunset, stars, bonfire, walk, roofs, leaves):
            hold(p, "Maya")
        hold(movie, "Jonah")
        hold(movie, "Ruby")
        # One that faded with nobody holding it: purged, and gone.
        photo("Sam", "overcast_sea", at(16, 9, 0), "rainy monday", None, seed=3)

        s.add(CommunityNote(
            circle_id=circle.id, author_id=users["Ruby"].id, body="movie night in the lounge at 9, bring blankets",
            expires_at=(midnight + timedelta(days=1)).astimezone(timezone.utc), created_at=tonight(50),
        ))
        s.commit()

    with Session() as s:
        decay.sweep(s, clock, Notifier())
        decay.run_purges(s, storage, clock)
        s.commit()
        states = sorted((p.state, p.caption or "(tombstone)") for p in s.query(Photo).all())
    for state, caption in states:
        print(f"{state:<11} {caption}")
    print(f"\nSeeded {data}. Sign in as \"Maya Chen\".")


if __name__ == "__main__":
    main()
