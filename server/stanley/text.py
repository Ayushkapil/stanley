"""What people write, made safe to keep and to show (the production audit,
November 2026).

Every free-text field passes through `clean` before it's stored: captions,
place names, stories, the community note, names, usernames, bios, circle
names, hold notes and report reasons. It never rewrites what someone said.
It only drops characters that aren't words:

- control characters (NUL, escape, the C1 block), which no keyboard types
  and which can break a log line, a JSON reader or a terminal. A newline is
  kept where the field is multi-line (a caption, a story, a bio); a tab
  becomes a space.
- the bidirectional embedding, override and isolate controls (U+202A to
  U+202E, U+2066 to U+2069), which let a name display backwards ("Trojan
  Source" spoofing). The marks that right-to-left writing actually needs
  (U+200E, U+200F) stay, and so does the zero-width joiner that holds
  emoji like a family or a flag together.

Text is stored in Unicode's composed form (NFC), so "é" typed two ways is one
word, and a username check can't be dodged by a decomposed accent.
"""
from __future__ import annotations

import unicodedata

_BIDI_CONTROLS = frozenset(chr(c) for c in (*range(0x202A, 0x202F), *range(0x2066, 0x206A)))


def clean(value: str | None, *, multiline: bool = False) -> str | None:
    """`value` without control or bidi-override characters, in NFC, with
    surrounding whitespace trimmed. None stays None. An all-whitespace value
    comes back empty, and each caller decides what empty means."""
    if value is None:
        return None
    out: list[str] = []
    for ch in unicodedata.normalize("NFC", value):
        if ch in _BIDI_CONTROLS:
            continue
        if ch == "\n" and multiline:
            out.append(ch)
        elif ch == "\r":
            continue  # \r\n arrives from some keyboards; \n is the line break
        elif ch == "\t":
            out.append(" ")
        elif unicodedata.category(ch) == "Cc":
            continue  # NUL, ESC, DEL, the C1 block, and \n where it isn't allowed
        else:
            out.append(ch)
    return "".join(out).strip()


def clean_optional(value: str | None, *, multiline: bool = False) -> str | None:
    """Like `clean`, but blank is None: an optional field left empty."""
    cleaned = clean(value, multiline=multiline)
    return cleaned or None
