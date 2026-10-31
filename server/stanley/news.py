"""The World Today: the news, in a tab of its own, in two editions.

The national edition is a broadcaster's own list of its latest stories, each
with the one- or two-sentence summary it was published with, so a story can
be read without leaving Stanley: PBS News Hour for phones in the US, BBC
News's world edition everywhere else. The nearby edition is Google News's
local headlines for the town the phone is in. Google's feeds carry no
summaries (a story's description is a list of other outlets' links), so a
nearby story is a headline, a source and a time.

The phone names where it is only as a town ("Bloomington, IN") and a
country code, and names a town only if the person allowed location. The
server uses the town to choose a feed and keys the cache by the town, never
by who asked. Nothing is selected by Stanley: each edition is its source's
own pick, shown newest first.

Each edition is cached in one row and refetched once it is half an hour old.
A background loop keeps the US national edition warm, so it is ready before
anyone asks. The others are fetched the first time someone asks for them and
whenever they are due after that. A failed fetch keeps the last good set
until it is too old to call today's, and then that edition is empty.

News sits outside Stanley's physics. It never touches photos, decay, Held or
Returned, because it is ephemeral by nature and there is nothing to keep. It
has no likes, saves, shares or comments, and it never sends a notification.
On by default and keyless; `STANLEY_NEWS=0` turns it off.

Google's feed says it is made available for "a personal feed reader for
personal, non-commercial use". PBS's and the BBC's feed terms haven't been
checked. Serving any of them to a pilot circle is a judgement call; revisit
the sources before anything wider than the pilot.
"""
from __future__ import annotations

import email.utils
import html
import json
import logging
import re
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Callable

from sqlalchemy import delete, func, select
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.orm import Session

from . import __version__
from .clock import Clock
from .models import NewsEdition

log = logging.getLogger("stanley")

PBS_URL = "https://www.pbs.org/newshour/feeds/rss/headlines"
BBC_WORLD_URL = "https://feeds.bbci.co.uk/news/world/rss.xml"
# Google answers a town's name with a redirect to that town's local topic.
GOOGLE_NEARBY_URL = "https://news.google.com/rss/headlines/section/geo/{town}?{region}"

HEADLINES = 12
NEARBY = 6
SUMMARY_WORDS = 60
# The feeds are 15 to 120 KB. Anything far past that is not a news feed, and
# isn't read into memory.
MAX_FEED_BYTES = 2 * 1024 * 1024
# A cached set older than this isn't "today" anymore. Rather than show
# yesterday's world, the edition goes empty.
SERVE_FOR = timedelta(hours=6)
# A pilot circle lives in a town or two. The cap keeps a client from making
# the server fetch the whole map.
MAX_TOWNS = 50
# A town nobody has asked about in this long is dropped from the cache.
FORGET_TOWN_AFTER = timedelta(days=1)
# How long someone opening the World tab waits on a feed that isn't cached.
ASKED_TIMEOUT = 5.0

_TAGS = re.compile(r"<[^>]+>")
_SPACE = re.compile(r"\s+")
_COUNTRY = re.compile(r"^[A-Za-z]{2}$")
# Starts with a letter. After that, letters, digits, spaces and . , ' ’ -
_TOWN = re.compile(r"^[^\W\d_][\w .,'’-]*$")


@dataclass(frozen=True)
class Edition:
    """One feed and the row that caches it."""

    key: str
    url: str
    count: int
    summaries: bool
    # The outlet, for feeds whose items don't each name one.
    source: str = ""


US = Edition("national:us", PBS_URL, HEADLINES, summaries=True, source="PBS News Hour")
WORLD = Edition("national:world", BBC_WORLD_URL, HEADLINES, summaries=True, source="BBC News")


def national(country: str | None) -> Edition:
    """PBS for phones in the US, and for clients that don't say where they
    are; BBC World everywhere else."""
    return US if (country or "US").strip().upper() == "US" else WORLD


def nearby(town: str | None, country: str | None) -> Edition | None:
    """The local edition for a town, or None if what was sent isn't a town."""
    town = _SPACE.sub(" ", town or "").strip()
    code = (country or "US").strip().upper()
    if not town or len(town) > 80 or not _TOWN.match(town) or not _COUNTRY.match(code):
        return None
    region = "hl=en-US&gl=US&ceid=US:en" if code == "US" else f"hl=en-{code}&gl={code}&ceid={code}:en"
    url = GOOGLE_NEARBY_URL.format(town=urllib.parse.quote(town, safe=""), region=region)
    return Edition(f"nearby:{code}:{town.casefold()}", url, NEARBY, summaries=False)


Fetch = Callable[[Edition], list]


class NewsError(RuntimeError):
    """The feed answered, but not with stories."""


def fetch_edition(edition: Edition, *, timeout: float = 10.0) -> list[dict]:
    """Make one request for an edition's feed and return its items, parsed
    but not yet cleaned up. No key and no account."""
    request = urllib.request.Request(
        edition.url, headers={"User-Agent": f"Stanley/{__version__}"}
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        body = response.read(MAX_FEED_BYTES + 1)
    if len(body) > MAX_FEED_BYTES:
        raise NewsError("feed too large")
    return parse_feed(body, summaries=edition.summaries)


def parse_feed(body: bytes, *, summaries: bool) -> list[dict]:
    """RSS 2.0 items as plain dicts: title, source, url, published, summary.

    ElementTree never resolves external entities, and Python's bundled expat
    (2.4.1 and later) caps entity expansion, so a hostile feed can't reach
    the filesystem or blow up memory.

    A broadcaster's <description> is the story's summary. Google's is a
    cluster of related headlines as links, not a paragraph about the story,
    so for Google's feeds it is dropped."""
    try:
        root = ET.fromstring(body)
    except ET.ParseError as exc:
        raise NewsError(f"not a feed: {exc}") from exc
    channel = root.find("channel")
    if channel is None:
        raise NewsError("not an RSS feed")
    items = []
    for item in channel.findall("item"):
        items.append({
            "title": item.findtext("title"),
            "source": item.findtext("source"),
            "url": item.findtext("link"),
            "published": item.findtext("pubDate"),
            "summary": item.findtext("description") if summaries else None,
        })
    return items


def _clean(text: str | None) -> str:
    if not text:
        return ""
    return _SPACE.sub(" ", html.unescape(_TAGS.sub(" ", text))).strip()


def trim_words(text: str, limit: int = SUMMARY_WORDS) -> str:
    words = text.split()
    if len(words) <= limit:
        return " ".join(words)
    return " ".join(words[:limit]).rstrip(",;:.-—") + "…"


def _headline(title: str, source: str) -> str:
    """Google's titles end with the outlet's name ("Headline - Outlet"). The
    card puts the source on a line of its own, so drop the repeat."""
    if source:
        for sep in (" - ", " | ", " — "):
            suffix = f"{sep}{source}"
            if title.lower().endswith(suffix.lower()) and len(title) > len(suffix):
                return title[: -len(suffix)].rstrip()
    return title


def _when(raw) -> datetime | None:
    """RSS dates are RFC 822 ("Fri, 30 Oct 2026 21:19:23 GMT"). ISO 8601 is
    accepted too, so a different feed could be swapped in."""
    if not isinstance(raw, str) or not raw.strip():
        return None
    try:
        when = email.utils.parsedate_to_datetime(raw)
    except (TypeError, ValueError):
        try:
            when = datetime.fromisoformat(raw.strip().replace("Z", "+00:00"))
        except ValueError:
            return None
    if when.tzinfo is None:
        when = when.replace(tzinfo=timezone.utc)
    return when.astimezone(timezone.utc)


def normalize(raw: list[dict], count: int = HEADLINES, source: str = "") -> list[dict]:
    """Reduce feed items to what a card shows. The rules: text only, at most
    `count`, no repeats, and only http(s) links, which are the only kind an
    in-app Safari sheet will open. `source` names the outlet for items that
    don't. The stories are taken in the feed's order and then shown newest
    first."""
    picked: list[tuple[datetime | None, dict]] = []
    seen: set[str] = set()
    for item in raw:
        if not isinstance(item, dict):
            continue
        outlet = _clean(item.get("source")) or source
        title = _headline(_clean(item.get("title")), outlet)
        url = (item.get("url") or "").strip()
        if not title or title == "[Removed]" or url in seen or title.casefold() in seen:
            continue
        if urllib.parse.urlsplit(url).scheme not in ("http", "https"):
            continue
        if not outlet:
            outlet = urllib.parse.urlsplit(url).hostname or ""
            outlet = outlet.removeprefix("www.")
        seen.update((url, title.casefold()))
        when = _when(item.get("published"))
        summary = trim_words(_clean(item.get("summary"))) or None
        picked.append((when, {
            "title": title,
            "source": outlet,
            "description": summary,
            "published_at": when.isoformat() if when else None,
            "url": url,
        }))
        if len(picked) == count:
            break
    epoch = datetime.min.replace(tzinfo=timezone.utc)
    picked.sort(key=lambda pair: pair[0] or epoch, reverse=True)
    return [article for _, article in picked]


def store(session: Session, edition: Edition, articles: list[dict], now: datetime) -> None:
    """Write an edition's row. An upsert, because two people opening the
    World tab in the same town at the same moment both fetch it."""
    payload = json.dumps(articles)
    session.execute(
        sqlite_insert(NewsEdition)
        .values(key=edition.key, fetched_at=now, articles=payload)
        .on_conflict_do_update(
            index_elements=[NewsEdition.key], set_={"fetched_at": now, "articles": payload}
        )
    )


def refresh(
    session: Session,
    clock: Clock,
    edition: Edition = US,
    fetch: Fetch | None = None,
) -> bool:
    """Fetch, normalize and store. On any failure, including an answer with
    nothing usable in it, the last good set stays as it was. The fetcher is
    looked up when called, not when defined, so a test can stand in for it."""
    fetch = fetch or fetch_edition
    try:
        articles = normalize(fetch(edition), edition.count, edition.source)
    except Exception as exc:
        log.warning("news fetch for %s failed, keeping the last good set: %s", edition.key, exc)
        return False
    if not articles:
        log.warning("news fetch for %s had no usable stories, keeping the last good set", edition.key)
        return False
    store(session, edition, articles, clock.now())
    log.info("news refreshed: %d stories for %s", len(articles), edition.key)
    return True


def refresh_if_due(
    session: Session,
    clock: Clock,
    every: timedelta,
    edition: Edition = US,
    fetch: Fetch | None = None,
) -> bool:
    """Run one refresh if the edition isn't cached or is older than `every`.
    An edition that isn't cached is always due, so a fresh server fills the
    US edition on its first pass; a restart doesn't spend a request on
    stories that are still fresh."""
    row = session.get(NewsEdition, edition.key)
    if row is not None and clock.now() - row.fetched_at < every:
        return False
    return refresh(session, clock, edition, fetch)


def stories(session: Session, edition: Edition, now: datetime) -> list[dict]:
    """An edition's cached stories, or nothing if no set is fresh enough."""
    row = session.get(NewsEdition, edition.key, populate_existing=True)
    if row is None or now - row.fetched_at > SERVE_FOR:
        return []
    return json.loads(row.articles)


def today(
    session: Session,
    clock: Clock,
    edition: Edition,
    every: timedelta,
    fetch: Fetch | None = None,
) -> list[dict]:
    """What someone opening the World tab sees: the edition, fetched first
    if it is due. A town the cache doesn't hold yet isn't fetched once the
    cache holds as many towns as it may."""
    if edition.key.startswith("nearby:") and session.get(NewsEdition, edition.key) is None:
        towns = session.scalar(
            select(func.count()).select_from(NewsEdition).where(NewsEdition.key.startswith("nearby:"))
        )
        if towns >= MAX_TOWNS:
            return []
    fetch = fetch or (lambda e: fetch_edition(e, timeout=ASKED_TIMEOUT))
    refresh_if_due(session, clock, every, edition, fetch)
    return stories(session, edition, clock.now())


def forget_towns(session: Session, now: datetime) -> int:
    """Drop the towns nobody has asked about lately. A town that is still
    being asked about is refetched whenever it's due, so its row stays new."""
    result = session.execute(
        delete(NewsEdition).where(
            NewsEdition.key.startswith("nearby:"),
            NewsEdition.fetched_at < now - FORGET_TOWN_AFTER,
        )
    )
    return result.rowcount or 0
