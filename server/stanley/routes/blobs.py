from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, Response

from ..deps import get_clock, get_settings, get_storage
from ..storage import verify

router = APIRouter(tags=["blobs"])


@router.get("/blobs/{key:path}")
def get_blob(
    key: str,
    exp: int = Query(...),
    sig: str = Query(...),
    storage=Depends(get_storage),
    settings=Depends(get_settings),
    clock=Depends(get_clock),
):
    """§9/§15: every read is a short-TTL signed URL; no public URLs ever."""
    if not verify(settings.secret_key, key, exp, sig, clock.now()):
        raise HTTPException(403, "invalid or expired signature")
    try:
        if not storage.exists(key):
            raise HTTPException(404, "not found")
        data = storage.get(key)
    except ValueError:
        raise HTTPException(404, "not found")
    return Response(
        content=data,
        media_type="image/jpeg",
        headers={"Cache-Control": "private, max-age=300"},
    )
