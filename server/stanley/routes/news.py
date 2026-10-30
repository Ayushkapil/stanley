from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from .. import news
from ..deps import get_clock, get_current_user, get_db, get_settings
from ..models import User

router = APIRouter(tags=["news"])


@router.get("/news/today")
def world_today(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
) -> list[dict]:
    """The World Today: the cached headlines, the same twelve for everyone.
    Nothing about the caller changes the list, and there is nothing to do to
    an article but read it. With no key configured this is an empty list, and
    the World tab then says there are no stories right now."""
    if not settings.news_api_key:
        return []
    return news.today(db, clock.now())
