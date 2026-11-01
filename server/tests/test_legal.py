"""The Terms and the Privacy Policy (build 18): public pages for App Store
Connect, and the same words the app shows."""
from __future__ import annotations

from pathlib import Path

from stanley import legal

SWIFT = Path(__file__).resolve().parents[2] / "ios" / "Stanley" / "Legal.swift"


def test_both_pages_are_public_and_plain(client):
    for path, title in (("/terms", "Terms of Use"), ("/privacy", "Privacy Policy")):
        r = client.get(path)  # no sign-in
        assert r.status_code == 200
        assert r.headers["content-type"].startswith("text/html")
        assert f"<h1>{title}</h1>" in r.text
        assert legal.CONTACT in r.text
        # Nothing that runs, nothing fetched from elsewhere.
        assert "<script" not in r.text and "http" not in r.text.split("<body>")[1]


def test_the_policy_says_what_stanley_does_with_location_and_notifications(client):
    text = client.get("/privacy").text
    assert "never receive GPS coordinates" in text
    assert "notification token" in text
    assert "to train AI models" in text
    assert "Effective November 1, 2026" in text
    assert "<h3>What we don&#x27;t collect</h3>" in text  # subheadings render


def test_both_documents_are_complete():
    """The brief's sections, in order: eleven in the policy, and the
    terms' seventeen plus Apple's minimum terms before Contact."""
    assert [h.split(". ")[0] for h, _ in legal.PRIVACY] == [str(i) for i in range(1, 12)]
    assert [h.split(". ")[0] for h, _ in legal.TERMS] == [str(i) for i in range(1, 19)]
    assert legal.PRIVACY[-1][0] == "11. Contact" and legal.TERMS[-1][0] == "18. Contact"


def test_the_app_shows_the_same_words():
    """A change to either copy goes in both: the app's Legal.swift carries
    every heading and line of legal.py, verbatim."""
    swift = SWIFT.read_text()
    assert f'"{legal.EFFECTIVE}"' in swift
    for sections in (legal.TERMS, legal.PRIVACY):
        for heading, lines in sections:
            if heading:
                assert f'"{heading}"' in swift, heading
            for line in lines:
                assert f'"{line}"' in swift, line
