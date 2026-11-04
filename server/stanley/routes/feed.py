from __future__ import annotations

import base64
import binascii
from collections import defaultdict
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from zoneinfo import ZoneInfo

from .. import physics
from ..deps import (
    active_circle_id,
    get_clock,
    get_current_user,
    get_db,
    get_settings,
    require_membership,
)
from ..models import Photo, ReturnedLog, User
from ..returned import returned_item
from .photos import valid_timezone
from ..serialize import (
    blocked_ids,
    circle_notes,
    photo_payload,
    user_brief,
    weekly_mosaic,
)

router = APIRouter(tags=["feed"])

# The most a page of Today can ask for. The app asks for twenty at a time,
# and for everything it already shows when it refreshes, so a long evening
# of scrolling stays one request.
PAGE_MAX = 200


def _cursor(sort_at: datetime, key: str) -> str:
    raw = f"{sort_at.isoformat()}|{key}".encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def _parse_cursor(cursor: str) -> tuple[datetime, str]:
    """Where the last page ended: the time and id of its last entry. Opaque
    to the app, which only hands it back."""
    try:
        raw = base64.urlsafe_b64decode(cursor + "=" * (-len(cursor) % 4)).decode()
        at, key = raw.split("|", 1)
        when = datetime.fromisoformat(at)
    except (binascii.Error, UnicodeDecodeError, ValueError):
        raise HTTPException(400, {"code": "bad_cursor"})
    if when.tzinfo is None or not key:
        raise HTTPException(400, {"code": "bad_cursor"})
    return when, key


@router.get("/feed/today")
def today(
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
    circle_id: str | None = Depends(active_circle_id),
    limit: int | None = Query(default=None, ge=1, le=PAGE_MAX),
    cursor: str | None = Query(default=None, max_length=200),
):
    """The Today feed: a handful of fading photos from the circle, ordered by
    time and nothing else. Non-goal §7: never reordered by engagement; holding
    never extends visibility (A1) — the query simply has no access to it.

    Photos posted with the same location label on the same local day by 2+
    people are grouped into a 'shared moment' (Part 3): a presentation grouping
    only — each photo keeps its own decay, like, and Held state.

    One circle at a time: the one on screen. Nothing from a person's other
    circles is mixed in, and nothing ranks them against each other.

    Pages (the production audit): with `limit`, at most that many entries,
    newest first, and a `next_cursor` to ask for the ones after them (None
    when there are no more). Paging changes nothing about the order: it's
    still time and nothing else, cut into pieces. The note and the mosaic
    come with the first page only. Without `limit` it's every entry, as a
    build before paging expects. Shared moments are grouped before the
    page is cut, so a moment is never split across two pages, and only
    the page's own photos are serialized.
    """
    membership, circle = require_membership(db, user, circle_id)
    after = _parse_cursor(cursor) if cursor else None
    now = clock.now()
    hidden = blocked_ids(db, user.id)
    photos = db.scalars(
        select(Photo)
        .where(
            Photo.circle_id == membership.circle_id,
            Photo.state.in_(physics.PUBLIC_STATES),
            Photo.deleted_at.is_(None),
        )
        .order_by(Photo.taken_at.desc())
    ).all()
    visible = [p for p in photos if p.owner_id not in hidden]

    # Group by (normalized location label, local capture day).
    groups: dict[tuple[str, object], list[Photo]] = defaultdict(list)
    singles: list[Photo] = []
    for p in visible:
        label = (p.location or "").strip().lower()
        if label:
            groups[(label, p.local_date)].append(p)
        else:
            singles.append(p)

    # Every entry, as (time, id, photos), before anything is serialized. A
    # moment's time and id are its newest photo's.
    entries: list[tuple[datetime, str, list[Photo]]] = []
    for plist in groups.values():
        owners = {p.owner_id for p in plist}
        if len(owners) >= 2:
            plist.sort(key=lambda p: p.taken_at, reverse=True)
            entries.append((plist[0].taken_at, plist[0].id, plist))
        else:
            singles.extend(plist)  # a lone photo at a place is just a photo
    for p in singles:
        entries.append((p.taken_at, p.id, [p]))

    # Newest first; the id only breaks a tie, so the order is total and a
    # cursor lands in exactly one place.
    entries.sort(key=lambda e: (e[0], e[1]), reverse=True)
    if after is not None:
        entries = [e for e in entries if (e[0], e[1]) < after]
    page = entries[:limit] if limit else entries
    more = limit is not None and len(entries) > limit

    items: list[dict] = []
    for _, _, plist in page:
        if len(plist) == 1:  # a moment is two people's photos, at least
            items.append({"kind": "photo", "photo": photo_payload(db, settings, now, plist[0], user, hidden)})
        else:
            items.append(
                {
                    "kind": "moment",
                    "location": plist[0].location,  # original-cased newest label
                    "members": [user_brief(db, p.owner_id, settings, now) for p in plist],
                    "photos": [photo_payload(db, settings, now, p, user, hidden) for p in plist],
                }
            )

    first_page = cursor is None
    notes = circle_notes(db, settings, now, membership.circle_id, user.id) if first_page else []
    return {
        "mosaic": weekly_mosaic(db, settings, now, circle, user.id) if first_page else None,
        # The board (build 27): everyone's note for the day, newest first.
        "notes": notes if first_page else None,
        # A build before the board shows one note: the newest.
        "note": notes[0] if notes else None,
        "items": items,
        "next_cursor": _cursor(page[-1][0], page[-1][1]) if more and page else None,
    }


@router.get("/feed/returned")
def returned(
    tz: str | None = Query(default=None),
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    if tz is not None and not valid_timezone(tz):
        raise HTTPException(400, {"code": "bad_timezone"})
    tz_name = tz or user.tz_last_seen or "UTC"
    if tz:
        user.tz_last_seen = tz
    return {"item": returned_item(db, settings, clock, user, tz_name)}


@router.post("/feed/returned/dismiss", status_code=204)
def dismiss_returned(
    tz: str | None = Query(default=None),
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    """'Not now' — clear today's Returned card without resting it (§14). It may
    surface again another day; only rest stops it forever. Keyed by local day,
    so it naturally resets tomorrow."""
    if tz is not None and not valid_timezone(tz):
        raise HTTPException(400, {"code": "bad_timezone"})
    tz_name = tz or user.tz_last_seen or "UTC"
    today = clock.now().astimezone(ZoneInfo(tz_name)).date()
    log = db.get(ReturnedLog, (user.id, today))
    if log is not None:
        log.dismissed = True
