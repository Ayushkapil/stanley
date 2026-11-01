"""A report tells the person who runs Stanley that it's waiting (build 18):
one fixed line to REPORT_WEBHOOK_URL (an ntfy.sh topic), after the report is
committed, with nothing in it about who, what or why. Unset, it's only logged,
and a webhook that fails never costs anyone their report."""
from __future__ import annotations

import logging

from sqlalchemy import select

from stanley import alerts
from stanley.models import Report

TOPIC = "https://ntfy.sh/stanley-reports-test"


def _sent(monkeypatch, db=None, status=200):
    sent = []

    def post(url, body):
        # By the time it goes, the report is already committed.
        if db is not None:
            with db() as s:
                sent.append((url, body, len(s.scalars(select(Report)).all())))
        else:
            sent.append((url, body))
        return status

    monkeypatch.setattr(alerts, "_post", post)
    return sent


def test_a_report_says_only_that_it_is_waiting(circle, app, db, monkeypatch):
    app.state.settings.report_webhook_url = TOPIC
    sent = _sent(monkeypatch, db)
    pid = circle.ben.post_photo(caption="secret caption").json()["id"]
    assert circle.ana.report(photo_id=pid, reason="the private reason").status_code == 201
    assert sent == [(TOPIC, "A report is waiting for review", 1)]


def test_without_a_url_a_report_is_only_logged(circle, caplog):
    # The autouse guard fails this test if anything is posted.
    pid = circle.ben.post_photo().json()["id"]
    with caplog.at_level(logging.WARNING, logger="stanley"):
        assert circle.ana.report(photo_id=pid, reason="x").status_code == 201
    assert any("A report is waiting for review" in r.message for r in caplog.records)


def test_a_refused_report_sends_nothing(circle, app, monkeypatch):
    app.state.settings.report_webhook_url = TOPIC
    sent = _sent(monkeypatch)
    assert circle.ana.report(photo_id="nope", reason="x").status_code == 404
    assert sent == []


def test_a_webhook_that_fails_never_costs_the_report(circle, app, db, monkeypatch, caplog):
    app.state.settings.report_webhook_url = TOPIC

    def down(url, body):
        raise OSError("ntfy is down")

    monkeypatch.setattr(alerts, "_post", down)
    pid = circle.ben.post_photo().json()["id"]
    with caplog.at_level(logging.WARNING, logger="stanley"):
        assert circle.ana.report(photo_id=pid, reason="x").status_code == 201
    with db() as s:
        assert len(s.scalars(select(Report)).all()) == 1
    # Logged without the URL: the topic name is the secret.
    assert not any("ntfy.sh" in r.getMessage() for r in caplog.records)


def test_a_webhook_that_says_no_is_logged(monkeypatch, caplog):
    _sent(monkeypatch, status=429)
    with caplog.at_level(logging.WARNING, logger="stanley"):
        alerts.report_waiting(TOPIC)
    assert any("429" in r.getMessage() for r in caplog.records)
