"""The World Today: a cached set of twelve headlines that sits outside
Stanley's physics. The server reads Google News's RSS, clients read the
cache, and with news turned off the whole thing goes quiet."""
from __future__ import annotations

import io
import json
from datetime import timedelta

import pytest

from stanley import news
from stanley.main import refresh_news
from stanley.models import NewsCache

from .conftest import make_user


def item(i: int, **over) -> dict:
    """One parsed feed item, the shape parse_feed returns."""
    base = {
        "title": f"Headline number {i} - Outlet {i}",
        "source": f"Outlet {i}",
        "url": f"https://news.example/articles/story-{i}?oc=5",
        "published": f"Tue, 09 Jun 2026 {i % 24:02d}:00:00 GMT",
    }
    base.update(over)
    return base


def feed_xml(*items: str) -> bytes:
    """A small RSS document shaped like Google News's top stories."""
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"><channel>'
        "<title>Top stories - Google News</title>"
        "<link>https://news.google.com/?hl=en-US&amp;gl=US&amp;ceid=US:en</link>"
        + "".join(items)
        + "</channel></rss>"
    ).encode()


def rss_item(i: int, *, title=None, source=None, link=None, date=None) -> str:
    title = title if title is not None else f"Headline number {i} - Outlet {i}"
    source = source if source is not None else f"Outlet {i}"
    link = link or f"https://news.example/articles/story-{i}?oc=5"
    date = date or f"Tue, 09 Jun 2026 {i % 24:02d}:00:00 GMT"
    return (
        f"<item><title>{title}</title><link>{link}</link>"
        f'<guid isPermaLink="false">g{i}</guid><pubDate>{date}</pubDate>'
        f'<description>&lt;ol&gt;&lt;li&gt;&lt;a href="{link}"&gt;{title}&lt;/a&gt;'
        f"&lt;/li&gt;&lt;/ol&gt;</description>"
        f'<source url="https://outlet{i}.example">{source}</source></item>'
    )


def fetcher(items):
    calls = []

    def fetch():
        calls.append(1)
        return items

    fetch.calls = calls
    return fetch


def failing_fetch():
    raise OSError("feed unreachable")


@pytest.fixture
def enabled(app):
    app.state.settings.news_enabled = True
    return app


@pytest.fixture
def reader(client):
    """Someone signed in. The endpoint asks only for a valid JWT, not a circle."""
    return make_user(client, "dee")


def get_news(reader):
    return reader.client.get("/news/today", headers=reader.h)


# --- parsing the feed ------------------------------------------------------

def test_parse_reads_title_source_link_and_date():
    parsed = news.parse_feed(feed_xml(rss_item(1), rss_item(2)))
    assert parsed == [
        {
            "title": "Headline number 1 - Outlet 1",
            "source": "Outlet 1",
            "url": "https://news.example/articles/story-1?oc=5",
            "published": "Tue, 09 Jun 2026 01:00:00 GMT",
        },
        {
            "title": "Headline number 2 - Outlet 2",
            "source": "Outlet 2",
            "url": "https://news.example/articles/story-2?oc=5",
            "published": "Tue, 09 Jun 2026 02:00:00 GMT",
        },
    ]


def test_google_descriptions_are_not_kept_as_summaries():
    """Google's <description> is a cluster of related headlines as links. It
    would read as the headline again, so a card shows no summary."""
    out = news.normalize(news.parse_feed(feed_xml(rss_item(1))))
    assert out[0]["description"] is None


@pytest.mark.parametrize("body", [b"", b"not xml at all", b"<html><body>Sorry</body></html>"])
def test_a_page_that_is_not_a_feed_is_an_error(body):
    with pytest.raises(news.NewsError):
        news.parse_feed(body)


def test_entities_are_never_resolved():
    """An external entity in a hostile feed is refused, not fetched."""
    hostile = (
        b'<?xml version="1.0"?><!DOCTYPE rss [<!ENTITY x SYSTEM "file:///etc/passwd">]>'
        b"<rss><channel><item><title>&x;</title></item></channel></rss>"
    )
    try:
        parsed = news.parse_feed(hostile)
    except news.NewsError:
        return
    assert "root:" not in json.dumps(parsed)


def test_fetch_asks_google_news_with_no_key(monkeypatch):
    seen = {}

    class Response(io.BytesIO):
        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

    def urlopen(request, timeout):
        seen["url"] = request.full_url
        seen["agent"] = request.get_header("User-agent")
        seen["headers"] = dict(request.header_items())
        seen["timeout"] = timeout
        return Response(feed_xml(rss_item(1)))

    monkeypatch.setattr(news.urllib.request, "urlopen", urlopen)
    parsed = news.fetch_top_headlines()
    assert parsed[0]["title"] == "Headline number 1 - Outlet 1"
    assert seen["url"] == "https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en"
    assert seen["agent"].startswith("Stanley/")
    assert not any("key" in h.lower() for h in seen["headers"])
    assert seen["timeout"] > 0


def test_fetch_refuses_an_oversized_answer(monkeypatch):
    class Response(io.BytesIO):
        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

    big = b"<rss><channel>" + b" " * (news.MAX_FEED_BYTES + 10) + b"</channel></rss>"
    monkeypatch.setattr(news.urllib.request, "urlopen", lambda request, timeout: Response(big))
    with pytest.raises(news.NewsError):
        news.fetch_top_headlines()


# --- fetch + store ---------------------------------------------------------

def test_refresh_fetches_and_stores_the_normalized_set(db, clock):
    fetch = fetcher([item(i) for i in range(1, 6)])
    with db() as s:
        assert news.refresh(s, clock, fetch) is True
        s.commit()
    assert fetch.calls == [1]
    with db() as s:
        row = s.get(NewsCache, 1)
        assert row.fetched_at == clock.now()
        stored = json.loads(row.articles)
    assert len(stored) == 5
    first = stored[0]
    assert set(first) == {"title", "source", "description", "published_at", "url"}
    # The outlet is shown once, on its own line, not repeated in the headline.
    assert first["title"] == "Headline number 5"
    assert first["source"] == "Outlet 5"
    assert first["published_at"] == "2026-06-09T05:00:00+00:00"


def test_refresh_keeps_a_single_row(db, clock):
    with db() as s:
        news.refresh(s, clock, fetcher([item(1)]))
        s.commit()
    clock.advance(timedelta(minutes=30))
    with db() as s:
        news.refresh(s, clock, fetcher([item(2)]))
        s.commit()
    with db() as s:
        assert s.query(NewsCache).count() == 1
        assert json.loads(s.get(NewsCache, 1).articles)[0]["title"] == "Headline number 2"


def test_failed_fetch_keeps_the_last_good_set(db, clock):
    with db() as s:
        news.refresh(s, clock, fetcher([item(1)]))
        s.commit()
    good_at = clock.now()
    clock.advance(timedelta(minutes=30))
    with db() as s:
        assert news.refresh(s, clock, failing_fetch) is False
        # An answer with nothing usable in it doesn't blank the section either.
        assert news.refresh(s, clock, fetcher([item(9, title="")])) is False
        s.commit()
    with db() as s:
        row = s.get(NewsCache, 1)
        assert row.fetched_at == good_at
        assert json.loads(row.articles)[0]["title"] == "Headline number 1"


def test_an_empty_cache_is_always_due_then_the_interval_holds(db, clock):
    every = timedelta(minutes=30)
    fetch = fetcher([item(1)])
    with db() as s:
        assert news.refresh_if_due(s, clock, every, fetch) is True
        s.commit()
    clock.advance(timedelta(minutes=29))
    with db() as s:
        assert news.refresh_if_due(s, clock, every, fetch) is False
    clock.advance(timedelta(minutes=1))
    with db() as s:
        assert news.refresh_if_due(s, clock, every, fetch) is True
    assert len(fetch.calls) == 2


def test_first_background_pass_fills_the_cache(enabled, db, monkeypatch):
    """What startup runs: with an empty cache, the first pass fetches."""
    monkeypatch.setattr(news, "fetch_top_headlines", fetcher([item(1), item(2)]))
    refresh_news(enabled)
    with db() as s:
        assert len(json.loads(s.get(NewsCache, 1).articles)) == 2


def test_background_pass_with_news_off_fetches_nothing(app, db, monkeypatch):
    fetch = fetcher([item(1)])
    monkeypatch.setattr(news, "fetch_top_headlines", fetch)
    refresh_news(app)
    assert fetch.calls == []
    with db() as s:
        assert s.get(NewsCache, 1) is None


def test_news_is_on_unless_turned_off(monkeypatch):
    from stanley.config import Settings

    monkeypatch.delenv("STANLEY_NEWS", raising=False)
    assert Settings().news_enabled is True
    monkeypatch.setenv("STANLEY_NEWS", "0")
    assert Settings().news_enabled is False


# --- normalizing -----------------------------------------------------------

def test_twelve_at_most_newest_first():
    raw = [item(i) for i in range(1, 21)]
    out = news.normalize(raw)
    assert len(out) == news.HEADLINES == 12
    # The feed picks which twelve (its first twelve), and Stanley orders them by time.
    assert {a["url"] for a in out} == {f"https://news.example/articles/story-{i}?oc=5" for i in range(1, 13)}
    times = [a["published_at"] for a in out]
    assert times == sorted(times, reverse=True)


def test_odd_links_and_duplicates_are_dropped_before_counting_twelve():
    raw = (
        [item(0, title="[Removed]", url="https://removed.example/")]
        + [item(99, url="javascript:alert(1)")]
        + [item(98, url="https://news.example/articles/story-1?oc=5")]  # duplicate link
        + [item(i) for i in range(1, 14)]
    )
    out = news.normalize(raw)
    assert len(out) == 12
    urls = [a["url"] for a in out]
    assert "https://removed.example/" not in urls
    assert all(u.startswith("https://") for u in urls)
    assert len(set(urls)) == 12


def test_markup_is_stripped_and_missing_pieces_are_tolerated():
    out = news.normalize([
        item(1, title="Rates &amp; <b>rents</b> rose - Outlet 1"),
        item(2, source=None, published=None, url="https://www.paper.example/a"),
    ])
    by_url = {a["url"]: a for a in out}
    assert by_url["https://news.example/articles/story-1?oc=5"]["title"] == "Rates & rents rose"
    bare = by_url["https://www.paper.example/a"]
    assert bare["published_at"] is None
    assert bare["source"] == "paper.example"


def test_iso_dates_are_accepted_too():
    out = news.normalize([item(1, published="2026-06-09T03:00:00Z")])
    assert out[0]["published_at"] == "2026-06-09T03:00:00+00:00"


def test_a_summary_is_trimmed_to_sixty_words_if_a_source_ever_has_one():
    long = " ".join(f"word{i}" for i in range(100))
    summary = news.normalize([item(1, summary=long)])[0]["description"]
    assert summary.endswith("…")
    assert len(summary.split()) == news.SUMMARY_WORDS == 60


# --- GET /news/today -------------------------------------------------------

def test_endpoint_serves_the_cached_set(enabled, db, clock, reader):
    with db() as s:
        news.refresh(s, clock, fetcher([item(i) for i in range(1, 4)]))
        s.commit()
    r = get_news(reader)
    assert r.status_code == 200
    body = r.json()
    assert [a["title"] for a in body] == ["Headline number 3", "Headline number 2", "Headline number 1"]
    assert body[0] == {
        "title": "Headline number 3",
        "source": "Outlet 3",
        "description": None,
        "published_at": "2026-06-09T03:00:00+00:00",
        "url": "https://news.example/articles/story-3?oc=5",
    }


def test_endpoint_is_the_same_for_everyone(enabled, db, clock, circle, reader):
    with db() as s:
        news.refresh(s, clock, fetcher([item(i) for i in range(1, 4)]))
        s.commit()
    seen = [get_news(u).json() for u in (circle.ana, circle.ben, reader)]
    assert seen[0] == seen[1] == seen[2]


def test_endpoint_needs_a_jwt(enabled, client):
    assert client.get("/news/today").status_code == 401


def test_endpoint_is_empty_when_news_is_off(app, db, clock, reader):
    # Even a cache left over from when news was on is not shown.
    with db() as s:
        news.refresh(s, clock, fetcher([item(1)]))
        s.commit()
    r = get_news(reader)
    assert r.status_code == 200
    assert r.json() == []


def test_endpoint_is_empty_before_the_first_fetch(enabled, reader):
    r = get_news(reader)
    assert r.status_code == 200
    assert r.json() == []


def test_a_stale_set_goes_quiet_rather_than_show_yesterday(enabled, db, clock, reader):
    with db() as s:
        news.refresh(s, clock, fetcher([item(1)]))
        s.commit()
    clock.advance(news.SERVE_FOR)
    assert len(get_news(reader).json()) == 1
    clock.advance(timedelta(minutes=1))
    assert get_news(reader).json() == []


def test_news_never_reaches_today_or_held(enabled, db, clock, circle):
    with db() as s:
        news.refresh(s, clock, fetcher([item(1)]))
        s.commit()
    assert "news.example" not in circle.ana.feed().text
    assert "news.example" not in circle.ana.memories().text
    assert "news.example" not in circle.ana.returned().text
