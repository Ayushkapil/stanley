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
    assert f"Effective {legal.PRIVACY_EFFECTIVE}" in text
    # The crash report's trail is said, and what it never carries.
    assert "a short trail of what the app did just before" in text
    assert f"Effective {legal.EFFECTIVE}" in client.get("/terms").text
    # What the journal keeps, and who reads it (build 26).
    assert "Only you ever see these" in text
    assert "sealed until that week&#x27;s answers open" in text
    assert "<h3>What we don&#x27;t collect</h3>" in text  # subheadings render


def test_the_pages_are_set_for_reading(client):
    """The URLs App Store Connect links: a white page in a 680px column, the
    system's sans-serif at 16px, Stanley's name at the top, the effective
    date under the title, the contact address a mailto link, and a phone's
    width honored."""
    for path, effective in (("/terms", legal.EFFECTIVE), ("/privacy", legal.PRIVACY_EFFECTIVE)):
        text = client.get(path).text
        assert '<meta name="viewport" content="width=device-width, initial-scale=1">' in text
        assert "background: #ffffff" in text and "max-width: 680px" in text
        assert "16px/1.65 -apple-system" in text and "sans-serif" in text
        head, body = text.split("<body>")
        assert body.index('<p class="brand">Stanley</p>') < body.index("<h1>")
        assert f'<p class="effective">Effective {effective}</p>' in body
        assert f'<a href="mailto:{legal.CONTACT}">{legal.CONTACT}</a>' in body
        assert "@media (max-width: 480px)" in head


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
    assert f'"{legal.PRIVACY_EFFECTIVE}"' in swift
    for sections in (legal.TERMS, legal.PRIVACY):
        for heading, lines in sections:
            if heading:
                assert f'"{heading}"' in swift, heading
            for line in lines:
                assert f'"{line}"' in swift, line
