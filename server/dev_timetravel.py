#!/usr/bin/env python
"""Dev-only: spread the existing photos across the whole decay timeline so all
stages are visible in the Today feed at once, then sweep so states update.

    .venv/bin/python dev_timetravel.py

Targets the SAME database the API uses — server/var/stanley.db, resolved
relative to this file, never the working directory — and refuses to run if it
doesn't exist yet (it will not create a fresh one).

Ages assigned (newest photo first); if fewer than five photos exist, labeled
synthetic ones are inserted to fill the spread:

    ~12h  LIVE          fresh, fully visible
    ~60h  FADING        early fade
   ~110h  FADING        deep fade
   ~130h  LAST_LIGHT    barely visible, final rescue window
   ~145h  EXPIRED       gone from Today (that absence is the demo)

Idempotent: re-running reassigns the same spread relative to "now", clearing
stale purge-queue entries first. Dev only — production time moves one way.
"""
from __future__ import annotations

import io
import itertools
import os
import sys
from datetime import timedelta
from pathlib import Path

from PIL import Image, ImageDraw
from sqlalchemy import delete, select

from stanley import decay, physics
from stanley.clock import SystemClock
from stanley.db import make_engine, make_sessionmaker
from stanley.images import process_upload
from stanley.models import Membership, Photo, PurgeQueueItem, User, new_id
from stanley.notifications import Notifier
from stanley.storage import BlobStore

SPREAD = [
    (12.0, "fresh"),
    (60.0, "early fading"),
    (110.0, "deep fading"),
    (130.0, "last light"),
    (145.0, "just expired"),
]

SERVER_DIR = Path(__file__).resolve().parent


def _database_url() -> str:
    env = os.environ.get("STANLEY_DATABASE_URL")
    if env:
        return env
    db_path = SERVER_DIR / "var" / "stanley.db"
    if not db_path.is_file():
        sys.exit(
            f"no database at {db_path} — start the server and run "
            "scripts/seed_demo.py first (this tool never creates one)"
        )
    return f"sqlite:///{db_path}"


def _blob_dir() -> str:
    return os.environ.get("STANLEY_BLOB_DIR", str(SERVER_DIR / "var" / "blobs"))


def _dev_jpeg(label: str) -> bytes:
    img = Image.new("RGB", (1080, 1440), (40, 52, 70))
    ImageDraw.Draw(img).text((60, 680), f"dev · {label}", fill="white")
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=90)
    return buf.getvalue()


def _synthesize(session, storage, circle_id, owner, label, now) -> Photo:
    photo_id = new_id()
    processed = process_upload(_dev_jpeg(label))
    keys = {
        "blob_key": f"{photo_id}/orig.jpg",
        "deriv_key": f"{photo_id}/deriv.jpg",
        "thumb_key": f"{photo_id}/thumb.jpg",
    }
    storage.put(keys["blob_key"], processed.original)
    storage.put(keys["deriv_key"], processed.derivative)
    storage.put(keys["thumb_key"], processed.thumbnail)
    tz = owner.tz_last_seen or "UTC"
    photo = Photo(
        id=photo_id,
        owner_id=owner.id,
        circle_id=circle_id,
        taken_at=now,
        taken_tz=tz,
        local_date=physics.local_capture_date(now, tz),
        caption=f"dev · {label}",
        state=physics.LIVE,
        state_deadline=physics.state_deadline(physics.LIVE, now),
        created_at=now,
        **keys,
    )
    session.add(photo)
    return photo


def _place(photo: Photo, age_hours: float, now, taken_dates: set) -> None:
    """Backdate one photo, nudging by 3h while the day-slot would collide with
    another of the owner's photos (3h never crosses a stage boundary for the
    SPREAD ages). `taken_dates` is the owner's set of occupied local dates,
    maintained in memory so nothing is flushed mid-placement."""
    tz = photo.taken_tz or "UTC"
    taken_at = now - timedelta(hours=age_hours)
    for _ in range(8):
        if physics.local_capture_date(taken_at, tz) not in taken_dates:
            break
        taken_at -= timedelta(hours=3)
    photo.taken_at = taken_at
    photo.local_date = physics.local_capture_date(taken_at, tz)
    taken_dates.add(photo.local_date)
    photo.state = physics.LIVE
    photo.state_deadline = physics.state_deadline(physics.LIVE, taken_at)
    photo.purge_after = None
    photo.last_light_notified_at = None


def main() -> None:
    engine = make_engine(_database_url())
    storage = BlobStore(_blob_dir())
    clock = SystemClock()
    now = clock.now()

    with make_sessionmaker(engine)() as session:
        photos = session.scalars(
            select(Photo)
            .where(Photo.state != physics.PURGED, Photo.deleted_at.is_(None))
            .order_by(Photo.taken_at.desc())
        ).all()
        if not photos:
            sys.exit("no photos in the database — run scripts/seed_demo.py first")

        existing_targets = photos[: len(SPREAD)]
        target_ids = {p.id for p in existing_targets}
        session.execute(
            delete(PurgeQueueItem).where(PurgeQueueItem.photo_id.in_(target_ids))
        )

        # Day-slots already occupied per owner (every row counts, including
        # purged tombstones), minus the targets themselves — they're moving.
        occupied: dict[str, set] = {}
        for pid, oid, local_date in session.execute(
            select(Photo.id, Photo.owner_id, Photo.local_date)
        ).all():
            if oid is not None and pid not in target_ids:
                occupied.setdefault(oid, set()).add(local_date)

        targets = list(existing_targets)
        if len(targets) < len(SPREAD):
            circle_id = targets[0].circle_id
            owners = session.scalars(
                select(User)
                .join(Membership, Membership.user_id == User.id)
                .where(Membership.circle_id == circle_id, User.deleted_at.is_(None))
            ).all()
            owner_cycle = itertools.cycle(owners)
            with session.no_autoflush:
                for _, label in SPREAD[len(targets):]:
                    targets.append(
                        _synthesize(session, storage, circle_id, next(owner_cycle), label, now)
                    )

        with session.no_autoflush:
            for photo, (age_hours, _) in zip(targets, SPREAD):
                _place(photo, age_hours, now, occupied.setdefault(photo.owner_id, set()))
        session.commit()

        transitions = decay.sweep(session, clock, Notifier())
        session.commit()

        print(f"sweep: {transitions} transitions\n")
        print(f"{'owner':<10} {'caption':<22} {'age':>7}  state")
        print("-" * 56)
        for photo in targets:
            owner = session.get(User, photo.owner_id)
            age = (now - photo.taken_at).total_seconds() / 3600
            name = (owner.display_name if owner else "?") or "departed"
            note = "  (left Today)" if photo.state == physics.EXPIRED else ""
            print(f"{name:<10} {(photo.caption or '—'):<22} {age:6.1f}h  {photo.state}{note}")
        print("\npull to refresh the Today feed to see the spread.")


if __name__ == "__main__":
    main()
