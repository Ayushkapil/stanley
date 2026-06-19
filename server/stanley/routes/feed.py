from __future__ import annotations

from collections import defaultdict

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from zoneinfo import ZoneInfo

from .. import physics
from ..deps import get_clock, get_current_user, get_db, get_settings, require_membership
from ..models import Photo, ReturnedLog, User
from ..returned import returned_item
from ..serialize import (
    blocked_ids,
    community_note_payload,
    photo_payload,
    user_brief,
    weekly_mosaic,
)

router = APIRouter(tags=["feed"])


@router.get("/feed/today")
def today(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    """The Today feed: a handful of fading photos from the circle, ordered by
    time and nothing else. Non-goal §7: never reordered by engagement; holding
    never extends visibility (A1) — the query simply has no access to it.

    Photos posted with the same location label on the same local day by 2+
    people are grouped into a 'shared moment' (Part 3): a presentation grouping
    only — each photo keeps its own decay, like, and Held state.
    """
    membership, circle = require_membership(db, user)
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

    items: list[dict] = []
    for plist in groups.values():
        owners = {p.owner_id for p in plist}
        if len(owners) >= 2:
            plist.sort(key=lambda p: p.taken_at, reverse=True)
            items.append(
                {
                    "kind": "moment",
                    "location": plist[0].location,  # original-cased newest label
                    "members": [user_brief(db, p.owner_id, settings, now) for p in plist],
                    "sort_at": plist[0].taken_at,
                    "photos": [photo_payload(db, settings, now, p, user) for p in plist],
                }
            )
        else:
            singles.extend(plist)  # a lone photo at a place is just a photo

    for p in singles:
        items.append(
            {"kind": "photo", "sort_at": p.taken_at, "photo": photo_payload(db, settings, now, p, user)}
        )

    items.sort(key=lambda i: i["sort_at"], reverse=True)
    for i in items:
        i.pop("sort_at")

    return {
        "mosaic": weekly_mosaic(db, settings, now, circle, user.id),
        "note": community_note_payload(db, settings, now, membership.circle_id),
        "items": items,
    }


@router.get("/feed/returned")
def returned(
    tz: str | None = Query(default=None),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    tz_name = tz or user.tz_last_seen or "UTC"
    if tz:
        user.tz_last_seen = tz
    return {"item": returned_item(db, settings, clock, user, tz_name)}


@router.post("/feed/returned/dismiss", status_code=204)
def dismiss_returned(
    tz: str | None = Query(default=None),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    """'Not now' — clear today's Returned card without resting it (§14). It may
    surface again another day; only rest stops it forever. Keyed by local day,
    so it naturally resets tomorrow."""
    tz_name = tz or user.tz_last_seen or "UTC"
    today = clock.now().astimezone(ZoneInfo(tz_name)).date()
    log = db.get(ReturnedLog, (user.id, today))
    if log is not None:
        log.dismissed = True
