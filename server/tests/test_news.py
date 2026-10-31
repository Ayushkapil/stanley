"""The World Today: cached editions of the news that sit outside Stanley's
physics. A national edition with summaries (PBS in the US, BBC World
elsewhere) and a nearby edition of a town's headlines (Google News). The
server reads the feeds, clients read the cache, and with news turned off the
whole thing goes quiet."""
from __future__ import annotations

import io
import json
from datetime import timedelta

import pytest

from stanley import news
from stanley.main import refresh_news
from stanley.models import NewsEdition

from .conftest import make_user

# The real fetcher, taken before the suite's guard stands in for it.
REAL_FETCH = news.fetch_edition

TOWN = news.nearby("Bloomington, IN", "US")


def item(i: int, **over) -> dict:
    """One parsed feed item, the shape parse_feed returns."""
    base = {
        "title": f"Headline number {i} - Outlet {i}",
        "source": f"Outlet {i}",
        "url": f"https://news.example/articles/story-{i}?oc=5",
        "published": f"Tue, 09 Jun 2026 {i % 24:02d}:00:00 GMT",
        "summary": None,
    }
    base.update(over)
    return base


def told(i: int, **over) -> dict:
    """A broadcaster's item: no <source>, and a real summary."""
    fields = {"title": f"Story number {i}", "source": None, "summary": f"What happened in story {i}."}
    fields.update(over)
    return item(i, **fields)


def feed_xml(*items: str) -> bytes:
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"><channel>'
        "<title>A feed</title><link>https://feed.example/</link>"
        + "".join(items)
        + "</channel></rss>"
    ).encode()


def google_item(i: int) -> str:
    """Shaped like Google News: the outlet in the title and in <source>, and
    a description that is only links to other headlines."""
    title = f"Headline number {i} - Outlet {i}"
    link = f"https://news.example/articles/story-{i}?oc=5"
    return (
        f"<item><title>{title}</title><link>{link}</link>"
        f'<guid isPermaLink="false">g{i}</guid><pubDate>Tue, 09 Jun 2026 {i:02d}:00:00 GMT</pubDate>'
        f'<description>&lt;ol&gt;&lt;li&gt;&lt;a href="{link}"&gt;{title}&lt;/a&gt;'
        f"&lt;/li&gt;&lt;/ol&gt;</description>"
        f'<source url="https://outlet{i}.example">Outlet {i}</source></item>'
    )


def pbs_item(i: int) -> str:
    """Shaped like PBS: no <source>, and a description that is the summary."""
    return (
        f"<item><title>Story number {i}</title>"
        f"<link>https://www.pbs.org/newshour/politics/story-{i}</link>"
        f"<description>What happened in story {i}, in &lt;b&gt;two&lt;/b&gt; sentences. Then why.</description>"
        f"<pubDate>Tue, 09 Jun 2026 {i:02d}:00:00 -0400</pubDate>"
        f'<dc:creator xmlns:dc="http://purl.org/dc/elements/1.1/">A Reporter</dc:creator></item>'
    )


def fetcher(items):
    """A stand-in for the network. `items` is a list, or a function of the
    edition asked for."""
    calls = []

    def fetch(edition, **_):
        calls.append(edition)
        return items(edition) if callable(items) else items

    fetch.calls = calls
    return fetch


def failing_fetch(edition, **_):
    raise OSError("feed unreachable")


def cached(db, edition):
    with db() as s:
        row = s.get(NewsEdition, edition.key)
        return None if row is None else json.loads(row.articles)


@pytest.fixture
def enabled(app):
    app.state.settings.news_enabled = True
    return app


@pytest.fixture
def reader(client):
    """Someone signed in. The endpoints ask only for a valid JWT, not a circle."""
    return make_user(client, "dee")


def get_news(reader, country=None):
    headers = dict(reader.h)
    if country:
        headers["X-Stanley-Country"] = country
    return reader.client.get("/news/today", headers=headers)


def get_nearby(reader, town=None, country="US"):
    headers = dict(reader.h)
    if town is not None:
        headers["X-Stanley-Town"] = town
    if country:
        headers["X-Stanley-Country"] = country
    return reader.client.get("/news/nearby", headers=headers)


# --- the editions ----------------------------------------------------------

@pytest.mark.parametrize("country", [None, "", "US", "us", " US "])
def test_the_us_and_anyone_unsaid_get_pbs(country):
    assert news.national(country) is news.US
    assert news.US.url == "https://www.pbs.org/newshour/feeds/rss/headlines"


@pytest.mark.parametrize("country", ["GB", "in", "ZZ", "nonsense"])
def test_everywhere_else_gets_bbc_world(country):
    assert news.national(country) is news.WORLD
    assert news.WORLD.url == "https://feeds.bbci.co.uk/news/world/rss.xml"


def test_a_town_is_google_news_for_that_town():
    edition = news.nearby("Bloomington, IN", "US")
    assert edition.url == (
        "https://news.google.com/rss/headlines/section/geo/Bloomington%2C%20IN"
        "?hl=en-US&gl=US&ceid=US:en"
    )
    assert edition.count == news.NEARBY == 6
    assert edition.summaries is False
    london = news.nearby("London", "gb")
    assert london.url.endswith("/geo/London?hl=en-GB&gl=GB&ceid=GB:en")


def test_a_town_is_one_row_however_it_is_written():
    assert news.nearby("Bloomington,  IN ", "US").key == news.nearby("bloomington, in", "us").key
    assert news.nearby("Zürich", "CH").url.split("?")[0].endswith("/geo/Z%C3%BCrich")
    assert news.nearby("Coeur d’Alene", "US") is not None
    assert news.nearby("Winston-Salem, NC", "US") is not None


@pytest.mark.parametrize("town,country", [
    ("", "US"),
    (None, "US"),
    ("   ", "US"),
    ("12345", "US"),
    ("x" * 81, "US"),
    ("Bloomington/../../rss", "US"),
    ("Bloomington?q=1", "US"),
    ("Bloomington", "USA"),
    ("Bloomington", "1"),
])
def test_anything_that_is_not_a_town_has_no_edition(town, country):
    assert news.nearby(town, country) is None


# --- parsing the feed ------------------------------------------------------

def test_a_broadcasters_description_is_its_summary():
    parsed = news.parse_feed(feed_xml(pbs_item(1)), summaries=True)
    assert parsed == [{
        "title": "Story number 1",
        "source": None,
        "url": "https://www.pbs.org/newshour/politics/story-1",
        "published": "Tue, 09 Jun 2026 01:00:00 -0400",
        "summary": "What happened in story 1, in <b>two</b> sentences. Then why.",
    }]
    out = news.normalize(parsed, source="PBS News Hour")
    assert out[0]["description"] == "What happened in story 1, in two sentences. Then why."
    assert out[0]["source"] == "PBS News Hour"
    assert out[0]["published_at"] == "2026-06-09T05:00:00+00:00"


def test_googles_descriptions_are_not_kept_as_summaries():
    """Google's <description> is a cluster of related headlines as links. It
    would read as the headline again, so a nearby story has no summary."""
    parsed = news.parse_feed(feed_xml(google_item(1)), summaries=False)
    assert parsed[0]["summary"] is None
    out = news.normalize(parsed)
    assert out[0]["description"] is None
    assert out[0]["title"] == "Headline number 1"
    assert out[0]["source"] == "Outlet 1"


@pytest.mark.parametrize("body", [b"", b"not xml at all", b"<html><body>Sorry</body></html>"])
def test_a_page_that_is_not_a_feed_is_an_error(body):
    with pytest.raises(news.NewsError):
        news.parse_feed(body, summaries=True)


def test_entities_are_never_resolved():
    """An external entity in a hostile feed is refused, not fetched."""
    hostile = (
        b'<?xml version="1.0"?><!DOCTYPE rss [<!ENTITY x SYSTEM "file:///etc/passwd">]>'
        b"<rss><channel><item><title>&x;</title><description>&x;</description></item></channel></rss>"
    )
    try:
        parsed = news.parse_feed(hostile, summaries=True)
    except news.NewsError:
        return
    assert "root:" not in json.dumps(parsed)


class Response(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


@pytest.mark.parametrize("edition", [news.US, news.WORLD, TOWN], ids=["pbs", "bbc", "town"])
def test_fetch_asks_the_editions_feed_with_no_key(monkeypatch, edition):
    seen = {}

    def urlopen(request, timeout):
        seen["url"] = request.full_url
        seen["agent"] = request.get_header("User-agent")
        seen["headers"] = dict(request.header_items())
        seen["timeout"] = timeout
        return Response(feed_xml(pbs_item(1)))

    monkeypatch.setattr(news.urllib.request, "urlopen", urlopen)
    parsed = REAL_FETCH(edition)
    assert parsed[0]["title"] == "Story number 1"
    assert (parsed[0]["summary"] is not None) == edition.summaries
    assert seen["url"] == edition.url
    assert seen["agent"].startswith("Stanley/")
    assert not any("key" in h.lower() for h in seen["headers"])
    assert seen["timeout"] > 0


def test_fetch_refuses_an_oversized_answer(monkeypatch):
    big = b"<rss><channel>" + b" " * (news.MAX_FEED_BYTES + 10) + b"</channel></rss>"
    monkeypatch.setattr(news.urllib.request, "urlopen", lambda request, timeout: Response(big))
    with pytest.raises(news.NewsError):
        REAL_FETCH(news.US)


# --- fetch + store ---------------------------------------------------------

def test_refresh_fetches_and_stores_the_normalized_set(db, clock):
    fetch = fetcher([told(i) for i in range(1, 6)])
    with db() as s:
        assert news.refresh(s, clock, news.US, fetch) is True
        s.commit()
    assert fetch.calls == [news.US]
    with db() as s:
        row = s.get(NewsEdition, "national:us")
        assert row.fetched_at == clock.now()
        stored = json.loads(row.articles)
    assert len(stored) == 5
    first = stored[0]
    assert set(first) == {"title", "source", "description", "published_at", "url"}
    assert first["title"] == "Story number 5"
    assert first["source"] == "PBS News Hour"
    assert first["description"] == "What happened in story 5."
    assert first["published_at"] == "2026-06-09T05:00:00+00:00"


def test_each_edition_keeps_a_row_of_its_own(db, clock):
    with db() as s:
        news.refresh(s, clock, news.US, fetcher([told(1)]))
        news.refresh(s, clock, TOWN, fetcher([item(2)]))
        s.commit()
    clock.advance(timedelta(minutes=30))
    with db() as s:
        news.refresh(s, clock, news.US, fetcher([told(3)]))
        s.commit()
    with db() as s:
        assert s.query(NewsEdition).count() == 2
    assert cached(db, news.US)[0]["title"] == "Story number 3"
    assert cached(db, TOWN)[0]["title"] == "Headline number 2"


def test_two_people_filling_the_same_new_town_at_once_is_fine(db, clock):
    """Both asked before either stored. The second write replaces the first
    instead of failing on the key."""
    with db() as first, db() as second:
        assert first.get(NewsEdition, TOWN.key) is None
        assert second.get(NewsEdition, TOWN.key) is None
        news.store(first, TOWN, [{"title": "one"}], clock.now())
        first.commit()
        news.store(second, TOWN, [{"title": "two"}], clock.now())
        second.commit()
    assert cached(db, TOWN) == [{"title": "two"}]


def test_failed_fetch_keeps_the_last_good_set(db, clock):
    with db() as s:
        news.refresh(s, clock, news.US, fetcher([told(1)]))
        s.commit()
    good_at = clock.now()
    clock.advance(timedelta(minutes=30))
    with db() as s:
        assert news.refresh(s, clock, news.US, failing_fetch) is False
        # An answer with nothing usable in it doesn't blank the section either.
        assert news.refresh(s, clock, news.US, fetcher([told(9, title="")])) is False
        s.commit()
    with db() as s:
        row = s.get(NewsEdition, "national:us")
        assert row.fetched_at == good_at
        assert json.loads(row.articles)[0]["title"] == "Story number 1"


def test_an_uncached_edition_is_always_due_then_the_interval_holds(db, clock):
    every = timedelta(minutes=30)
    fetch = fetcher([told(1)])
    with db() as s:
        assert news.refresh_if_due(s, clock, every, news.US, fetch) is True
        s.commit()
    clock.advance(timedelta(minutes=29))
    with db() as s:
        assert news.refresh_if_due(s, clock, every, news.US, fetch) is False
    clock.advance(timedelta(minutes=1))
    with db() as s:
        assert news.refresh_if_due(s, clock, every, news.US, fetch) is True
    assert len(fetch.calls) == 2


def test_first_background_pass_fills_the_us_edition(enabled, db, monkeypatch):
    """What startup runs: with nothing cached, the first pass fetches PBS,
    and only PBS. Other editions wait until someone asks for them."""
    fetch = fetcher([told(1), told(2)])
    monkeypatch.setattr(news, "fetch_edition", fetch)
    refresh_news(enabled)
    assert fetch.calls == [news.US]
    assert len(cached(db, news.US)) == 2
    assert cached(db, news.WORLD) is None


def test_background_pass_with_news_off_fetches_nothing(app, db, monkeypatch):
    fetch = fetcher([told(1)])
    monkeypatch.setattr(news, "fetch_edition", fetch)
    refresh_news(app)
    assert fetch.calls == []
    assert cached(db, news.US) is None


def test_background_pass_forgets_towns_nobody_asks_about(enabled, db, clock, monkeypatch):
    other = news.nearby("Columbus, OH", "US")
    with db() as s:
        news.refresh(s, clock, news.US, fetcher([told(1)]))
        news.refresh(s, clock, TOWN, fetcher([item(1)]))
        s.commit()
    clock.advance(news.FORGET_TOWN_AFTER)
    with db() as s:
        news.refresh(s, clock, other, fetcher([item(2)]))
        s.commit()
    clock.advance(timedelta(seconds=1))
    monkeypatch.setattr(news, "fetch_edition", fetcher([told(3)]))
    refresh_news(enabled)
    assert cached(db, TOWN) is None
    assert cached(db, other) is not None
    assert cached(db, news.US) is not None


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


def test_a_town_gets_six():
    out = news.normalize([item(i) for i in range(1, 21)], TOWN.count)
    assert len(out) == 6


def test_odd_links_and_repeats_are_dropped_before_counting():
    raw = (
        [item(0, title="[Removed]", url="https://removed.example/")]
        + [item(99, url="javascript:alert(1)")]
        + [item(1), item(2)]
        + [item(98, url="https://news.example/articles/story-1?oc=5")]  # repeated link
        # The same story again under another link.
        + [item(97, title="Headline number 2 - Outlet 2", source="Outlet 2", url="https://elsewhere.example/2")]
        + [item(i) for i in range(3, 14)]
    )
    out = news.normalize(raw)
    assert len(out) == 12
    urls = [a["url"] for a in out]
    assert "https://removed.example/" not in urls
    assert "https://elsewhere.example/2" not in urls
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


def test_a_summary_is_trimmed_to_sixty_words():
    long = " ".join(f"word{i}" for i in range(100))
    summary = news.normalize([told(1, summary=long)])[0]["description"]
    assert summary.endswith("…")
    assert len(summary.split()) == news.SUMMARY_WORDS == 60


# --- GET /news/today -------------------------------------------------------

def test_the_first_reader_fills_the_edition_and_the_next_read_the_cache(
    enabled, monkeypatch, circle, reader
):
    fetch = fetcher([told(i) for i in range(1, 4)])
    monkeypatch.setattr(news, "fetch_edition", fetch)
    r = get_news(reader)
    assert r.status_code == 200
    body = r.json()
    assert [a["title"] for a in body] == ["Story number 3", "Story number 2", "Story number 1"]
    assert body[0] == {
        "title": "Story number 3",
        "source": "PBS News Hour",
        "description": "What happened in story 3.",
        "published_at": "2026-06-09T03:00:00+00:00",
        "url": "https://news.example/articles/story-3?oc=5",
    }
    # Everyone after reads the cache, and sees the same stories.
    assert get_news(circle.ana).json() == get_news(circle.ben).json() == body
    assert fetch.calls == [news.US]


def test_a_phone_outside_the_us_gets_bbc_world(enabled, monkeypatch, reader):
    fetch = fetcher(lambda e: [told(1, url=f"https://{e.key.replace(':', '-')}.example/1")])
    monkeypatch.setattr(news, "fetch_edition", fetch)
    body = get_news(reader, country="GB").json()
    assert fetch.calls == [news.WORLD]
    assert body[0]["source"] == "BBC News"
    assert body[0]["url"] == "https://national-world.example/1"


def test_endpoints_need_a_jwt(enabled, client):
    assert client.get("/news/today").status_code == 401
    assert client.get("/news/nearby", headers={"X-Stanley-Town": "Bloomington"}).status_code == 401


def test_endpoints_are_empty_when_news_is_off(app, db, clock, reader):
    # Even a cache left over from when news was on is not shown.
    with db() as s:
        news.refresh(s, clock, news.US, fetcher([told(1)]))
        news.refresh(s, clock, TOWN, fetcher([item(1)]))
        s.commit()
    assert get_news(reader).json() == []
    assert get_nearby(reader, "Bloomington, IN").json() == []


def test_an_unreachable_feed_is_an_empty_edition_not_an_error(enabled, monkeypatch, reader):
    monkeypatch.setattr(news, "fetch_edition", failing_fetch)
    r = get_news(reader)
    assert r.status_code == 200
    assert r.json() == []


def test_a_stale_set_goes_quiet_rather_than_show_yesterday(enabled, db, clock, monkeypatch, reader):
    with db() as s:
        news.refresh(s, clock, news.US, fetcher([told(1)]))
        s.commit()
    # The feed has been down ever since.
    monkeypatch.setattr(news, "fetch_edition", failing_fetch)
    clock.advance(news.SERVE_FOR)
    assert len(get_news(reader).json()) == 1
    clock.advance(timedelta(minutes=1))
    assert get_news(reader).json() == []


# --- GET /news/nearby ------------------------------------------------------

def test_a_town_gets_its_local_headlines(enabled, monkeypatch, reader):
    fetch = fetcher([item(i) for i in range(1, 10)])
    monkeypatch.setattr(news, "fetch_edition", fetch)
    # Percent-encoded, as the phone sends it.
    r = get_nearby(reader, "Bloomington%2C%20IN")
    assert r.status_code == 200
    body = r.json()
    assert len(body) == 6
    assert body[0] == {
        "title": "Headline number 6",
        "source": "Outlet 6",
        "description": None,
        "published_at": "2026-06-09T06:00:00+00:00",
        "url": "https://news.example/articles/story-6?oc=5",
    }
    assert [e.url for e in fetch.calls] == [TOWN.url]
    # Asked again within the half hour: from the cache.
    get_nearby(reader, "Bloomington, IN")
    assert len(fetch.calls) == 1


def test_no_town_means_no_nearby_and_no_fetch(enabled, monkeypatch, reader):
    fetch = fetcher([item(1)])
    monkeypatch.setattr(news, "fetch_edition", fetch)
    assert get_nearby(reader).json() == []
    assert get_nearby(reader, "").json() == []
    assert get_nearby(reader, "Bloomington%2F..%2Frss").json() == []
    assert get_nearby(reader, "Bloomington", country="USA").json() == []
    assert fetch.calls == []


def test_the_cache_stops_taking_new_towns_when_full(enabled, db, clock, monkeypatch, reader):
    with db() as s:
        for i in range(news.MAX_TOWNS):
            news.store(s, news.nearby(f"Town {i}", "US"), [{"title": f"t{i}"}], clock.now())
        s.commit()
    fetch = fetcher([item(1)])
    monkeypatch.setattr(news, "fetch_edition", fetch)
    assert get_nearby(reader, "Bloomington, IN").json() == []
    assert fetch.calls == []
    # A town it already holds is still served.
    assert get_nearby(reader, "Town 3").json() == [{"title": "t3"}]


def test_a_town_is_kept_by_name_never_by_who_asked(enabled, db, monkeypatch, reader):
    monkeypatch.setattr(news, "fetch_edition", fetcher([item(1)]))
    get_nearby(reader, "Bloomington, IN")
    with db() as s:
        keys = [row.key for row in s.query(NewsEdition)]
    assert keys == ["nearby:US:bloomington, in"]
    assert reader.id not in json.dumps(keys)


def test_news_never_reaches_today_or_held(enabled, db, clock, circle):
    with db() as s:
        news.refresh(s, clock, news.US, fetcher([told(1)]))
        news.refresh(s, clock, TOWN, fetcher([item(1)]))
        s.commit()
    for text in (circle.ana.feed().text, circle.ana.memories().text, circle.ana.returned().text):
        assert "news.example" not in text
