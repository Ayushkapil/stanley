"""The World Today: twelve national headlines at the foot of Today.

A convenience, not a feed. The server fetches NewsAPI's top headlines on a
fixed clock and keeps the last good set in a single row. Every client reads
that row, so only the server ever talks to NewsAPI, and everyone in every
circle sees the same twelve. Nothing is personalized and nothing is selected
by Stanley: the twelve are NewsAPI's own top stories, shown newest first.

News sits outside Stanley's physics. It never touches photos, decay, Held or
Returned, because it is ephemeral by nature and there is nothing to keep. It
has no likes, saves, shares or comments, and it never sends a notification.

Optional end to end. With no NEWS_API_KEY there is no fetch and the endpoint
returns an empty list. A failed fetch keeps the last good set until that set
is too old to call today's, and then the section just goes quiet.
"""
from __future__ import annotations

import html
import json
import logging
import re
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from typing import Callable

from sqlalchemy.orm import Session

from . import __version__
from .clock import Clock
from .models import NewsCache

log = logging.getLogger("stanley")

NEWSAPI_URL = "https://newsapi.org/v2/top-headlines"
# Every pilot tester is in the US, so national headlines stand in for
# "nearby". TODO(location): regional news goes here. Derive a country, or a
# city query, from a coarse location the person chooses to share, and key the
# cache by it. Stanley requests no location permission yet.
COUNTRY = "us"
HEADLINES = 12
# Ask for more than we show. NewsAPI pads top-headlines with "[Removed]"
# stubs, and there should still be twelve after those are dropped.
FETCH_SIZE = 20
SUMMARY_WORDS = 60
# A cached set older than this isn't "today" anymore. Rather than show
# yesterday's world, the section disappears.
SERVE_FOR = timedelta(hours=6)

_CACHE_ROW = 1
_TAGS = re.compile(r"<[^>]+>")
_SPACE = re.compile(r"\s+")

Fetch = Callable[[str], list]


class NewsError(RuntimeError):
    """NewsAPI answered, but not with headlines."""


def fetch_top_headlines(api_key: str, *, timeout: float = 10.0) -> list[dict]:
    """Make one NewsAPI call and return its raw articles. The key travels in a
    header rather than the query string, so it never shows up in a URL log or
    in an error message."""
    query = urllib.parse.urlencode({"country": COUNTRY, "pageSize": FETCH_SIZE})
    request = urllib.request.Request(
        f"{NEWSAPI_URL}?{query}",
        headers={"X-Api-Key": api_key, "User-Agent": f"Stanley/{__version__}"},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        body = json.load(response)
    if body.get("status") != "ok":
        raise NewsError(body.get("code") or "newsapi_error")
    return body.get("articles") or []


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
    """NewsAPI titles usually end with the outlet's name ("Headline - Outlet").
    The card puts the source on a line of its own, so drop the repeat."""
    if source:
        for sep in (" - ", " | ", " — "):
            suffix = f"{sep}{source}"
            if title.lower().endswith(suffix.lower()) and len(title) > len(suffix):
                return title[: -len(suffix)].rstrip()
    return title


def _when(raw) -> datetime | None:
    if not isinstance(raw, str):
        return None
    try:
        when = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None
    if when.tzinfo is None:
        when = when.replace(tzinfo=timezone.utc)
    return when.astimezone(timezone.utc)


def normalize(raw: list[dict]) -> list[dict]:
    """Reduce NewsAPI's articles to what a card shows. The rules: text only,
    at most twelve, summaries of at most sixty words, and only http(s) links,
    which are the only kind an in-app Safari sheet will open. The twelve are
    taken in NewsAPI's order and then shown newest first."""
    picked: list[tuple[datetime | None, dict]] = []
    seen: set[str] = set()
    for item in raw:
        if not isinstance(item, dict):
            continue
        source = _clean((item.get("source") or {}).get("name"))
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
        when = _when(item.get("publishedAt"))
        picked.append((when, {
            "title": title,
            "source": source,
            "description": trim_words(_clean(item.get("description"))) or None,
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


def refresh(
    session: Session, clock: Clock, api_key: str, fetch: Fetch = fetch_top_headlines
) -> bool:
    """Fetch, normalize and store. On any failure, including an answer with
    nothing usable in it, the last good set stays as it was."""
    try:
        articles = normalize(fetch(api_key))
    except Exception as exc:
        log.warning("news fetch failed, keeping the last good set: %s", exc)
        return False
    if not articles:
        log.warning("news fetch returned no usable headlines, keeping the last good set")
        return False
    store(session, articles, clock.now())
    return True


def refresh_if_due(
    session: Session,
    clock: Clock,
    api_key: str | None,
    every: timedelta,
    fetch: Fetch = fetch_top_headlines,
) -> bool:
    """Run one refresh if the cache is older than `every`. A restart doesn't
    spend a request on headlines that are still fresh."""
    if not api_key:
        return False
    row = session.get(NewsCache, _CACHE_ROW)
    if row is not None and clock.now() - row.fetched_at < every:
        return False
    return refresh(session, clock, api_key, fetch)


def today(session: Session, now: datetime) -> list[dict]:
    """Return the cached twelve, or nothing if no set is fresh enough."""
    row = session.get(NewsCache, _CACHE_ROW)
    if row is None or now - row.fetched_at > SERVE_FOR:
        return []
    return json.loads(row.articles)
