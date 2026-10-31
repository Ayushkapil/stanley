from __future__ import annotations

import urllib.parse
from datetime import timedelta

from fastapi import APIRouter, Depends, Header
from sqlalchemy.orm import Session

from .. import news
from ..deps import get_clock, get_current_user, get_db, get_settings
from ..models import User

router = APIRouter(tags=["news"])

# Where the phone is comes in headers, not the query string, so it never
# lands in an access log. The town is percent-encoded, because a header is
# ASCII and a town ("Zürich") may not be.
COUNTRY = Header(None, alias="X-Stanley-Country")
TOWN = Header(None, alias="X-Stanley-Town")


@router.get("/news/today")
def world_today(
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
    country: str | None = COUNTRY,
) -> list[dict]:
    """The national edition: PBS for phones in the US, and for a client that
    doesn't say where it is; BBC World anywhere else. The same stories for
    everyone in a country, and nothing to do to one but read it. With news
    turned off (STANLEY_NEWS=0) this is an empty list, and the World tab then
    says there are no stories right now."""
    if not settings.news_enabled:
        return []
    every = timedelta(seconds=settings.news_interval_seconds)
    return news.today(db, clock, news.national(country), every)


@router.get("/news/nearby")
def world_nearby(
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
    country: str | None = COUNTRY,
    town: str | None = TOWN,
) -> list[dict]:
    """The nearby edition: Google News's local headlines for the town the
    phone says it is in. A phone without location permission sends no town
    and gets an empty list, and so does anything that isn't a town. Only
    the town is used, to pick the feed; it isn't stored against anyone."""
    if not settings.news_enabled:
        return []
    edition = news.nearby(urllib.parse.unquote(town or ""), country)
    if edition is None:
        return []
    every = timedelta(seconds=settings.news_interval_seconds)
    return news.today(db, clock, edition, every)
