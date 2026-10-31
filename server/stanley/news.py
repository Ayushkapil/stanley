"""The World Today: twelve national headlines, in a tab of their own.

A convenience, not a feed. The server reads Google News's top-stories RSS on
a fixed clock and keeps the last good set in a single row. Every client
reads that row, so only the server ever talks to Google, and everyone in
every circle sees the same twelve. Nothing is personalized and nothing is
selected by Stanley: the twelve are Google News's own top stories, shown
newest first.

News sits outside Stanley's physics. It never touches photos, decay, Held or
Returned, because it is ephemeral by nature and there is nothing to keep. It
has no likes, saves, shares or comments, and it never sends a notification.

On by default and keyless. `STANLEY_NEWS=0` turns it off: no fetch, and the
endpoint returns an empty list. A failed fetch keeps the last good set until
that set is too old to call today's, and then the World tab has no stories.

Google's feed says it is made available for "a personal feed reader for
personal, non-commercial use". Serving it to a pilot circle is a judgement
call; revisit the source before anything wider than the pilot.
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
from datetime import datetime, timedelta, timezone
from typing import Callable

from sqlalchemy.orm import Session

from . import __version__
from .clock import Clock
from .models import NewsCache

log = logging.getLogger("stanley")

# Every pilot tester is in the US, so national headlines stand in for
# "nearby". TODO(location): regional news goes here. Google News takes a
# region (gl/ceid) or a topic per coarse location the person chooses to
# share; key the cache by it. Stanley requests no location permission yet.
GOOGLE_NEWS_URL = "https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en"
HEADLINES = 12
SUMMARY_WORDS = 60
# The feed is about 120 KB. Anything far past that is not a news feed, and
# isn't read into memory.
MAX_FEED_BYTES = 2 * 1024 * 1024
# A cached set older than this isn't "today" anymore. Rather than show
# yesterday's world, the section disappears.
SERVE_FOR = timedelta(hours=6)

_CACHE_ROW = 1
_TAGS = re.compile(r"<[^>]+>")
_SPACE = re.compile(r"\s+")

Fetch = Callable[[], list]


class NewsError(RuntimeError):
    """The feed answered, but not with headlines."""


def fetch_top_headlines(*, timeout: float = 10.0) -> list[dict]:
    """Make one request for Google News's top stories and return its items,
    parsed but not yet cleaned up. No key and no account."""
    request = urllib.request.Request(
        GOOGLE_NEWS_URL, headers={"User-Agent": f"Stanley/{__version__}"}
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        body = response.read(MAX_FEED_BYTES + 1)
    if len(body) > MAX_FEED_BYTES:
        raise NewsError("feed too large")
    return parse_feed(body)


def parse_feed(body: bytes) -> list[dict]:
    """RSS 2.0 items as plain dicts: title, source, url, published.

    ElementTree never resolves external entities, and Python's bundled expat
    (2.4.1 and later) caps entity expansion, so a hostile feed can't reach
    the filesystem or blow up memory.

    There is no summary. Google's <description> is a cluster of related
    headlines as links, not a paragraph about the story, so it is dropped."""
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


def normalize(raw: list[dict]) -> list[dict]:
    """Reduce feed items to what a card shows. The rules: text only, at most
    twelve, and only http(s) links, which are the only kind an in-app Safari
    sheet will open. The twelve are taken in the feed's order and then shown
    newest first."""
    picked: list[tuple[datetime | None, dict]] = []
    seen: set[str] = set()
    for item in raw:
        if not isinstance(item, dict):
            continue
        source = _clean(item.get("source"))
        title = _headline(_clean(item.get("title")), source)
        url = (item.get("url") or "").strip()
        if not title or title == "[Removed]" or url in seen:
            continue
        if urllib.parse.urlsplit(url).scheme not in ("http", "https"):
            continue
        if not source:
            source = urllib.parse.urlsplit(url).hostname or ""
            source = source.removeprefix("www.")
        seen.add(url)
        when = _when(item.get("published"))
        summary = trim_words(_clean(item.get("summary"))) or None
        picked.append((when, {
            "title": title,
            "source": source,
            "description": summary,
            "published_at": when.isoformat() if when else None,
            "url": url,
        }))
        if len(picked) == HEADLINES:
            break
    epoch = datetime.min.replace(tzinfo=timezone.utc)
    picked.sort(key=lambda pair: pair[0] or epoch, reverse=True)
    return [article for _, article in picked]


def store(session: Session, articles: list[dict], now: datetime) -> None:
    row = session.get(NewsCache, _CACHE_ROW) or NewsCache(id=_CACHE_ROW)
    row.fetched_at = now
    row.articles = json.dumps(articles)
    session.add(row)


def refresh(session: Session, clock: Clock, fetch: Fetch | None = None) -> bool:
    """Fetch, normalize and store. On any failure, including an answer with
    nothing usable in it, the last good set stays as it was. The fetcher is
    looked up when called, not when defined, so a test can stand in for it."""
    fetch = fetch or fetch_top_headlines
    try:
        articles = normalize(fetch())
    except Exception as exc:
        log.warning("news fetch failed, keeping the last good set: %s", exc)
        return False
    if not articles:
        log.warning("news fetch returned no usable headlines, keeping the last good set")
        return False
    store(session, articles, clock.now())
    log.info("news refreshed: %d headlines", len(articles))
    return True


def refresh_if_due(
    session: Session,
    clock: Clock,
    every: timedelta,
    fetch: Fetch | None = None,
) -> bool:
    """Run one refresh if the cache is empty or older than `every`. An empty
    cache is always due, so a fresh server fills it on its first pass; a
    restart doesn't spend a request on headlines that are still fresh."""
    row = session.get(NewsCache, _CACHE_ROW)
    if row is not None and clock.now() - row.fetched_at < every:
        return False
    return refresh(session, clock, fetch)


def today(session: Session, now: datetime) -> list[dict]:
    """Return the cached twelve, or nothing if no set is fresh enough."""
    row = session.get(NewsCache, _CACHE_ROW)
    if row is None or now - row.fetched_at > SERVE_FOR:
        return []
    return json.loads(row.articles)
