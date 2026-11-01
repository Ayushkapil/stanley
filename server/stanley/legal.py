"""Terms of Use and the Privacy Policy, served as plain pages at /terms and
/privacy (build 18): App Store Connect asks for a privacy policy URL, and
these are it. The app shows the same words natively (`ios/Stanley/
Legal.swift`); `tests/test_legal.py` fails if the two ever differ.

Each document is a list of sections, each a heading (or None) and its
lines. A line starting with "- " is a list item.
"""
from __future__ import annotations

from html import escape

CONTACT = "ayushkapileshwar@gmail.com"
UPDATED = "November 1, 2026"

TERMS: list[tuple[str | None, list[str]]] = [
    (
        "By using Stanley, you agree to:",
        [
            "- Post only photos you have the right to share",
            "- Treat your circle with respect",
            "- Not use Stanley to harass, threaten, or harm anyone",
            "- Not upload illegal content",
        ],
    ),
    (
        None,
        [
            "There's no tolerance for objectionable content or abusive behavior. You can block anyone in your circle and report any photo or story; reports are reviewed within 24 hours.",
            "Stanley reserves the right to remove content or accounts that violate these terms. Your photos are stored on our servers and deleted when they fade (unless someone in your circle keeps them), when you delete them, or when you delete your account.",
            f"For questions, contact {CONTACT}.",
        ],
    ),
]

PRIVACY: list[tuple[str | None, list[str]]] = [
    (
        "What Stanley collects:",
        [
            "- Your name and username (from Sign in with Apple or entered by you), and the profile photo and few words about yourself you choose to add",
            "- Photos you post, with their captions and the stories your circle adds (stored on our servers, deleted when they fade unless someone in your circle keeps them, and deleted everywhere when you delete them or your account)",
            "- Place names on your photos, typed by you or suggested from where your phone is, which you can change or clear (your phone works out the name; Stanley's servers never receive GPS coordinates, and Stanley never tracks your location)",
            "- The name of your town, if you allow location, to show headlines from near you (sent with the request and not stored with your account)",
            "- A notification token for your phone, only if you turn on a notification (removed when you sign out on that phone or delete your account)",
            "- Crash reports (anonymous, via Sentry)",
        ],
    ),
    (
        "What Stanley does not collect:",
        [
            "- Your email address",
            "- Your contacts",
            "- Browsing or usage analytics",
            "- GPS or precise location data",
        ],
    ),
    (
        "Your data:",
        [
            "- Your photos are seen only by the circle you post them to",
            "- You can export your held memories anytime from Settings",
            "- You can delete your account anytime from Settings, which removes all your data within 24 hours",
            "- Stanley does not sell, share, or use your data for advertising",
            "- Photos are not used to train AI models",
        ],
    ),
    (None, [f"For questions, contact {CONTACT}."]),
]


def page(title: str, sections: list[tuple[str | None, list[str]]]) -> str:
    """A plain, readable page: no scripts, no trackers, no external assets."""
    parts: list[str] = []
    for heading, lines in sections:
        if heading:
            parts.append(f"<h2>{escape(heading)}</h2>")
        items: list[str] = []
        for line in lines + [""]:
            if line.startswith("- "):
                items.append(f"<li>{escape(line[2:])}</li>")
                continue
            if items:
                parts.append("<ul>" + "".join(items) + "</ul>")
                items = []
            if line:
                parts.append(f"<p>{escape(line)}</p>")
    body = "\n".join(parts)
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Stanley — {escape(title)}</title>
<style>
:root {{ color-scheme: light dark; }}
body {{ font: 17px/1.55 -apple-system, system-ui, sans-serif; max-width: 640px;
       margin: 0 auto; padding: 32px 20px 64px; background: #F8F6F1; color: #2A2724; }}
@media (prefers-color-scheme: dark) {{ body {{ background: #000; color: #F2EFEA; }} }}
h1 {{ font-weight: 600; margin-bottom: 4px; }} h2 {{ font-size: 18px; margin-top: 28px; }}
.updated {{ opacity: .6; font-size: 14px; }} li {{ margin: 6px 0; }}
</style></head>
<body><h1>{escape(title)}</h1><p class="updated">Stanley · Updated {UPDATED}</p>
{body}
</body></html>"""
