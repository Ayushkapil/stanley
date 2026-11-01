"""Telling the person who runs Stanley that a report is waiting (build 18).

The Terms promise every report is read within a day, and nothing else says
one has come in. So each report POSTs one fixed line to
`REPORT_WEBHOOK_URL`: an ntfy.sh topic (`https://ntfy.sh/<topic>`, which the
ntfy app on a phone subscribes to), or anything else that takes a plain-text
POST. The words and nothing else: never who reported, who or what was
reported, or why. Unset, a report is only logged, as before.

It runs after the report is committed and the response has gone, and a
failed send is logged and dropped, so a slow or missing ntfy never costs
anyone their report.

An ntfy topic can be read by anyone who knows its name, so the name is the
secret: a long random suffix, set on Fly with `fly secrets set`, never
committed, and never logged here.
"""
from __future__ import annotations

import logging

import httpx

log = logging.getLogger("stanley")

REPORT_WAITING = "A report is waiting for review"


def _post(url: str, body: str) -> int:
    """The one network call, kept apart so the tests can stand in for it."""
    return httpx.post(url, content=body.encode(), headers={"Title": "Stanley"}, timeout=5).status_code


def report_waiting(url: str | None) -> None:
    if not url:
        return
    try:
        status = _post(url, REPORT_WAITING)
    except Exception:
        log.warning("report alert: the webhook didn't answer")
        return
    if status >= 400:
        log.warning("report alert: the webhook answered %s", status)
