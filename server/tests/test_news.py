"""The World Today: a cached set of twelve headlines that sits outside
Stanley's physics. The server fetches the headlines, clients read the cache,
and with no key the whole thing goes quiet."""
from __future__ import annotations

import io
import json
from datetime import timedelta

import pytest

from stanley import news
from stanley.main import refresh_news
from stanley.models import NewsCache

from .conftest import make_user

KEY = "test-news-key"


def article(i: int, **over) -> dict:
    """One NewsAPI-shaped article."""
    base = {
        "source": {"id": None, "name": f"Outlet {i}"},
        "author": "Someone",
        "title": f"Headline number {i} - Outlet {i}",
        "description": f"What happened in story {i}.",
        "url": f"https://example.com/story-{i}",
        "urlToImage": f"https://example.com/story-{i}.jpg",
        "publishedAt": f"2026-06-09T{i % 24:02d}:00:00Z",
        "content": "Body text [+1234 chars]",
    }
    base.update(over)
    return base


def fetcher(articles):
    calls = []

    def fetch(api_key):
        calls.append(api_key)
        return articles

    fetch.calls = calls
    return fetch


def failing_fetch(api_key):
    raise OSError("newsapi unreachable")


@pytest.fixture
def keyed(app):
    app.state.settings.news_api_key = KEY
    return app


@pytest.fixture
def reader(client):
    """Someone signed in. The endpoint asks only for a valid JWT, not a circle."""
    return make_user(client, "dee")


def get_news(reader):
    return reader.client.get("/news/today", headers=reader.h)


# --- fetch + store ---------------------------------------------------------

def test_refresh_fetches_and_stores_the_normalized_set(keyed, db, clock):
    fetch = fetcher([article(i) for i in range(1, 6)])
    with db() as s:
        assert news.refresh(s, clock, KEY, fetch) is True
        s.commit()
    assert fetch.calls == [KEY]
    with db() as s:
        row = s.get(NewsCache, 1)
        assert row.fetched_at == clock.now()
        stored = json.loads(row.articles)
    assert len(stored) == 5
    first = stored[0]
    assert set(first) == {"title", "source", "description", "published_at", "url"}
    # Text only: nothing from the article's image survives.
    assert "urlToImage" not in json.dumps(stored)
    # The outlet is shown once, on its own line, not repeated in the headline.
    assert first["title"] == "Headline number 5"
    assert first["source"] == "Outlet 5"


def test_refresh_keeps_a_single_row(keyed, db, clock):
    with db() as s:
        news.refresh(s, clock, KEY, fetcher([article(1)]))
        s.commit()
    clock.advance(timedelta(minutes=30))
    with db() as s:
        news.refresh(s, clock, KEY, fetcher([article(2)]))
        s.commit()
    with db() as s:
        assert s.query(NewsCache).count() == 1
        assert json.loads(s.get(NewsCache, 1).articles)[0]["title"] == "Headline number 2"


def test_failed_fetch_keeps_the_last_good_set(keyed, db, clock):
    with db() as s:
        news.refresh(s, clock, KEY, fetcher([article(1)]))
        s.commit()
    good_at = clock.now()
    clock.advance(timedelta(minutes=30))
    with db() as s:
        assert news.refresh(s, clock, KEY, failing_fetch) is False
        # An answer with nothing usable in it doesn't blank the section either.
        assert news.refresh(s, clock, KEY, fetcher([article(9, title="[Removed]")])) is False
        s.commit()
    with db() as s:
        row = s.get(NewsCache, 1)
        assert row.fetched_at == good_at
        assert json.loads(row.articles)[0]["title"] == "Headline number 1"


def test_refresh_if_due_waits_out_the_interval(keyed, db, clock):
    every = timedelta(minutes=30)
    fetch = fetcher([article(1)])
    with db() as s:
        assert news.refresh_if_due(s, clock, KEY, every, fetch) is True
        s.commit()
    clock.advance(timedelta(minutes=29))
    with db() as s:
        assert news.refresh_if_due(s, clock, KEY, every, fetch) is False
    clock.advance(timedelta(minutes=1))
    with db() as s:
        assert news.refresh_if_due(s, clock, KEY, every, fetch) is True
    assert len(fetch.calls) == 2


def test_no_key_means_no_fetch(db, clock):
    fetch = fetcher([article(1)])
    with db() as s:
        assert news.refresh_if_due(s, clock, None, timedelta(minutes=30), fetch) is False
        assert news.refresh_if_due(s, clock, "", timedelta(minutes=30), fetch) is False
    assert fetch.calls == []


def test_background_pass_without_a_key_leaves_the_cache_empty(app, db):
    app.state.settings.news_api_key = None
    refresh_news(app)
    with db() as s:
        assert s.get(NewsCache, 1) is None


def test_fetch_sends_the_key_in_a_header_and_asks_for_us_headlines(monkeypatch):
    seen = {}

    class Response(io.BytesIO):
        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

    def urlopen(request, timeout):
        seen["url"] = request.full_url
        seen["key"] = request.get_header("X-api-key")
        seen["timeout"] = timeout
        return Response(json.dumps({"status": "ok", "articles": [article(1)]}).encode())

    monkeypatch.setattr(news.urllib.request, "urlopen", urlopen)
    assert news.fetch_top_headlines(KEY) == [article(1)]
    assert seen["url"].startswith("https://newsapi.org/v2/top-headlines?")
    assert "country=us" in seen["url"]
    assert KEY not in seen["url"]
    assert seen["key"] == KEY
    assert seen["timeout"] > 0


def test_fetch_raises_on_a_newsapi_error(monkeypatch):
    class Response(io.BytesIO):
        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

    body = {"status": "error", "code": "apiKeyInvalid", "message": "bad key"}
    monkeypatch.setattr(
        news.urllib.request, "urlopen",
        lambda request, timeout: Response(json.dumps(body).encode()),
    )
    with pytest.raises(news.NewsError):
        news.fetch_top_headlines(KEY)


# --- normalizing -----------------------------------------------------------

def test_twelve_at_most_newest_first():
    raw = [article(i) for i in range(1, 21)]
    out = news.normalize(raw)
    assert len(out) == news.HEADLINES == 12
    # NewsAPI picks which twelve (its first twelve), and Stanley orders them by time.
    assert {a["url"] for a in out} == {f"https://example.com/story-{i}" for i in range(1, 13)}
    times = [a["published_at"] for a in out]
    assert times == sorted(times, reverse=True)


def test_removed_stubs_and_odd_links_are_dropped_before_counting_twelve():
    raw = (
        [article(0, title="[Removed]", url="https://removed.com/")]
        + [article(99, url="javascript:alert(1)")]
        + [article(98, url="https://example.com/story-1")]  # duplicate link
        + [article(i) for i in range(1, 14)]
    )
    out = news.normalize(raw)
    assert len(out) == 12
    urls = [a["url"] for a in out]
    assert "https://removed.com/" not in urls
    assert all(u.startswith("https://") for u in urls)
    assert len(set(urls)) == 12


def test_summary_is_trimmed_to_sixty_words():
    long = " ".join(f"word{i}" for i in range(100))
    out = news.normalize([article(1, description=long)])
    summary = out[0]["description"]
    assert summary.endswith("…")
    assert len(summary.split()) == news.SUMMARY_WORDS == 60
    short = news.normalize([article(1, description="Just a few words.")])
    assert short[0]["description"] == "Just a few words."


def test_markup_is_stripped_and_missing_pieces_are_tolerated():
    out = news.normalize([
        article(1, description="<p>Rates &amp; <b>rents</b> rose.</p>"),
        article(2, description=None, publishedAt=None, source={"name": None},
                url="https://www.paper.example/a"),
    ])
    by_url = {a["url"]: a for a in out}
    assert by_url["https://example.com/story-1"]["description"] == "Rates & rents rose."
    bare = by_url["https://www.paper.example/a"]
    assert bare["description"] is None
    assert bare["published_at"] is None
    assert bare["source"] == "paper.example"


# --- GET /news/today -------------------------------------------------------

def test_endpoint_serves_the_cached_set(keyed, db, clock, reader):
    with db() as s:
        news.refresh(s, clock, KEY, fetcher([article(i) for i in range(1, 4)]))
        s.commit()
    r = get_news(reader)
    assert r.status_code == 200
    body = r.json()
    assert [a["title"] for a in body] == ["Headline number 3", "Headline number 2", "Headline number 1"]
    assert body[0] == {
        "title": "Headline number 3",
        "source": "Outlet 3",
        "description": "What happened in story 3.",
        "published_at": "2026-06-09T03:00:00+00:00",
        "url": "https://example.com/story-3",
    }


def test_endpoint_is_the_same_for_everyone(keyed, db, clock, circle, reader):
    with db() as s:
        news.refresh(s, clock, KEY, fetcher([article(i) for i in range(1, 4)]))
        s.commit()
    seen = [get_news(u).json() for u in (circle.ana, circle.ben, reader)]
    assert seen[0] == seen[1] == seen[2]


def test_endpoint_needs_a_jwt(keyed, client):
    assert client.get("/news/today").status_code == 401


def test_endpoint_is_empty_when_no_key_is_set(app, db, clock, reader):
    # Even a cache left over from when a key was set is not shown.
    with db() as s:
        news.refresh(s, clock, KEY, fetcher([article(1)]))
        s.commit()
    app.state.settings.news_api_key = None
    r = get_news(reader)
    assert r.status_code == 200
    assert r.json() == []


def test_endpoint_is_empty_before_the_first_fetch(keyed, reader):
    r = get_news(reader)
    assert r.status_code == 200
    assert r.json() == []


def test_a_stale_set_goes_quiet_rather_than_show_yesterday(keyed, db, clock, reader):
    with db() as s:
        news.refresh(s, clock, KEY, fetcher([article(1)]))
        s.commit()
    clock.advance(news.SERVE_FOR)
    assert len(get_news(reader).json()) == 1
    clock.advance(timedelta(minutes=1))
    assert get_news(reader).json() == []


def test_news_never_reaches_today_or_held(keyed, db, clock, circle):
    with db() as s:
        news.refresh(s, clock, KEY, fetcher([article(1)]))
        s.commit()
    assert "example.com/story-1" not in circle.ana.feed().text
    assert "example.com/story-1" not in circle.ana.memories().text
    assert "example.com/story-1" not in circle.ana.returned().text
