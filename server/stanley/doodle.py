"""The circle's doodle (build 39): one shared canvas a week, one line each a
day. Everyone in the circle may draw a single stroke a day, finger down to
finger up, in their own color; over the week the canvas fills with
everyone's marks, and on Saturday it's finished and becomes a page of the
circle journal.

- The week is the circle's week, the same one its question keeps
  (`journal.question_week`): Monday to Monday in UTC, since a circle spans
  time zones and has no local time of its own. Drawing closes when the
  question's answers open, Saturday 00:00 UTC (`journal.reveals_at`), and a
  new canvas starts on Monday.
- The day is the drawer's own calendar day, as a photo's is: one stroke per
  person per circle per local date, kept by a UNIQUE constraint, so a double
  send is a 409 and never a second line.
- A stroke is only its points, each 0 to 1 across a square canvas, and a
  color. It can't be edited, undone or deleted by anyone in the circle:
  the imperfection is the point. It goes only with its author's account, or
  when the operator takes it down after a report.
- No image exists while the week is open. When it closes, the finished
  canvas is drawn once (`render`) and stored; that picture is what the
  journal shows.

Nothing here counts anything, and nothing here sends a notification.
"""
from __future__ import annotations

import io
import logging
import math
import re
from datetime import date, datetime

from PIL import Image, ImageDraw
from sqlalchemy import delete, select, update
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.orm import Session

from . import journal
from .models import DoodleArchive, DoodleStroke, Report

log = logging.getLogger("stanley")

# A stroke the app sends is thinned to a few hundred points at most. More
# than this isn't a finger's line.
POINTS_MAX = 600
# Ink for a stroke whose color didn't come through as one: a soft graphite.
# An odd color never costs someone their day's line (as with a photo's
# filter name).
PENCIL = "#6B6257"
_HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")

# How the finished canvas is drawn: a square, the line about 3pt on a phone's
# canvas (0.9% of its side), each point nudged a little so the line isn't
# perfectly smooth. The phone draws the open canvas the same way, from the
# same numbers, so the picture kept on Saturday is the one people drew.
IMAGE_SIDE = 1024
LINE = 0.009
JITTER = 0.0022
_SUPERSAMPLE = 2


def closes_at(week_start: date) -> datetime:
    """When a week's canvas is finished: when its question's answers open."""
    return journal.reveals_at(week_start)


def is_open(week_start: date, now: datetime) -> bool:
    return now < closes_at(week_start)


def clean_color(color: str | None) -> str:
    """The stroke's color as #RRGGBB, or pencil when it isn't one."""
    return color.upper() if color and _HEX.match(color) else PENCIL


def clean_points(points: list[dict]) -> list[dict] | None:
    """The stroke's points, each held to the canvas and rounded to a ten
    thousandth of its side. None when it isn't a line: fewer than two
    points, or anything that isn't a finite number."""
    out: list[dict] = []
    for point in points:
        try:
            x, y = float(point["x"]), float(point["y"])
        except (KeyError, TypeError, ValueError):
            return None
        if not (math.isfinite(x) and math.isfinite(y)):
            return None
        spot = {"x": round(min(1.0, max(0.0, x)), 4), "y": round(min(1.0, max(0.0, y)), 4)}
        if not out or out[-1] != spot:
            out.append(spot)
    return out if len(out) >= 2 else None


# --- Drawing the finished canvas ---------------------------------------------

_MASK = 0xFFFFFFFFFFFFFFFF


def _seed(stroke_id: str) -> int:
    """FNV-1a over the stroke's id: the same wobble for the same stroke,
    here and on every phone."""
    h = 0xCBF29CE484222325
    for byte in stroke_id.encode():
        h = ((h ^ byte) * 0x100000001B3) & _MASK
    return h or 1


def jittered(stroke_id: str, points: list[dict]) -> list[tuple[float, float]]:
    """The stroke's points, each nudged up to `JITTER` either way by an
    xorshift run seeded from its id. The phone does the same arithmetic."""
    state = _seed(stroke_id)
    out = []
    for point in points:
        nudge = []
        for _ in range(2):
            state ^= (state << 13) & _MASK
            state ^= state >> 7
            state ^= (state << 17) & _MASK
            nudge.append(((state >> 11) % 2001 / 1000.0 - 1.0) * JITTER)
        out.append((point["x"] + nudge[0], point["y"] + nudge[1]))
    return out


def _smoothed(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """The line through the points the way the phone draws it: quadratic
    curves from midpoint to midpoint, flattened into short segments."""
    if len(points) < 3:
        return points
    out = [points[0]]
    mid = lambda a, b: ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)  # noqa: E731
    start = mid(points[0], points[1])
    out.append(start)
    for i in range(1, len(points) - 1):
        control, end = points[i], mid(points[i], points[i + 1])
        for step in (0.25, 0.5, 0.75, 1.0):
            a, b = 1 - step, step
            out.append((
                a * a * start[0] + 2 * a * b * control[0] + b * b * end[0],
                a * a * start[1] + 2 * a * b * control[1] + b * b * end[1],
            ))
        start = end
    out.append(points[-1])
    return out


def render(strokes: list[DoodleStroke], colors: dict[str, str] | None = None) -> bytes:
    """The canvas as a PNG: every stroke in its color on nothing at all (the
    phone lays it on its own paper, light or dark), oldest first so later
    lines cross over earlier ones. `colors` overrides a stroke's color by id,
    for the operator's look at a reported one."""
    side = IMAGE_SIDE * _SUPERSAMPLE
    image = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    width = max(2, round(LINE * side))
    for stroke in strokes:
        color = (colors or {}).get(stroke.id, stroke.stroke_color)
        path = [(x * side, y * side) for x, y in _smoothed(jittered(stroke.id, stroke.stroke_data))]
        draw.line(path, fill=color, width=width, joint="curve")
        for x, y in (path[0], path[-1]):
            draw.ellipse((x - width / 2, y - width / 2, x + width / 2, y + width / 2), fill=color)
    image = image.resize((IMAGE_SIDE, IMAGE_SIDE), Image.LANCZOS)
    out = io.BytesIO()
    image.save(out, "PNG", optimize=True)
    return out.getvalue()


# --- Keeping the finished canvas ----------------------------------------------


def week_strokes(session: Session, circle_id: str, week_start: date) -> list[DoodleStroke]:
    """A week's strokes in the order they were drawn."""
    return list(session.scalars(
        select(DoodleStroke)
        .where(DoodleStroke.circle_id == circle_id, DoodleStroke.week_start == week_start)
        .order_by(DoodleStroke.created_at, DoodleStroke.id)
    ).all())


def image_key(circle_id: str, week_start: date) -> str:
    return f"doodles/{circle_id}/{week_start.isoformat()}.png"


def ensure_archive(session: Session, storage, circle_id: str, week_start: date, now: datetime) -> DoodleArchive | None:
    """The finished week's picture, drawn and stored the first time it's
    wanted (the sweep usually gets there first). None for a week still open,
    or one nobody drew on."""
    if is_open(week_start, now):
        return None
    found = session.get(DoodleArchive, (circle_id, week_start))
    if found is not None:
        return found
    strokes = week_strokes(session, circle_id, week_start)
    if not strokes:
        return None
    key = image_key(circle_id, week_start)
    storage.put(key, render(strokes))
    # Two requests may both draw it; one row is kept, and the file is the same.
    session.execute(
        sqlite_insert(DoodleArchive)
        .values(circle_id=circle_id, week_start=week_start, image_key=key, created_at=now)
        .on_conflict_do_nothing(index_elements=["circle_id", "week_start"])
    )
    session.flush()
    return session.get(DoodleArchive, (circle_id, week_start))


def freeze_due(session: Session, storage, clock) -> int:
    """Every finished canvas that has no picture yet gets one. Run by the
    sweep, so Saturday's page is there within a quarter hour; idempotent."""
    now = clock.now()
    last = journal.last_revealed_week(now)
    due = session.execute(
        select(DoodleStroke.circle_id, DoodleStroke.week_start)
        .where(DoodleStroke.week_start <= last)
        .where(
            ~select(DoodleArchive.circle_id)
            .where(
                DoodleArchive.circle_id == DoodleStroke.circle_id,
                DoodleArchive.week_start == DoodleStroke.week_start,
            )
            .exists()
        )
        .distinct()
    ).all()
    for circle_id, week_start in due:
        ensure_archive(session, storage, circle_id, week_start, now)
    if due:
        log.info("event=doodles_frozen canvases=%d", len(due))
    return len(due)


def forget_strokes(session: Session, storage, strokes: list[DoodleStroke]) -> None:
    """Take strokes off their canvases for good: an account being deleted,
    or the operator's takedown. A report about one outlives it, so it can
    still be closed. A finished canvas they were on loses its picture, and
    is drawn again without them the next time it's wanted."""
    for circle_id, week_start in {(s.circle_id, s.week_start) for s in strokes}:
        archive = session.get(DoodleArchive, (circle_id, week_start))
        if archive is not None:
            storage.delete(archive.image_key)
            session.delete(archive)
    ids = [s.id for s in strokes]
    if ids:
        session.execute(update(Report).where(Report.stroke_id.in_(ids)).values(stroke_id=None))
        session.execute(delete(DoodleStroke).where(DoodleStroke.id.in_(ids)))
        session.flush()
