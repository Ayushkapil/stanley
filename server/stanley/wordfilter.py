"""A word filter for what a circle reads (the production audit, November
2026; App Review Guideline 1.2 asks an app with user content for "a method
for filtering objectionable material").

It's a blocklist, not a model: slurs aimed at people for their race,
ethnicity, religion, sexuality, gender identity or disability, and a few
unambiguous harassment phrases ("kill yourself"). Not profanity: swearing
among friends is the circle's business. A story, caption, place, note,
name, username, bio or circle name that carries one is refused, said in
words by the app, and nothing is stored. Reports are never filtered, since
a report may need to quote what it's about, and hold notes aren't, since
only their writer ever reads them.

The list is kept as salted SHA-256 digests (`blocklist.txt`), so the repo
doesn't print slurs in plain sight; it isn't a secret, and anyone can check
a word against it. To add a word, or see whether text would be refused:

    .venv/bin/python -m stanley.wordfilter hash <word> [<word>...]
    .venv/bin/python -m stanley.wordfilter check "<some text>"

Matching is on whole words, after folding what people do to slip past a
filter: case, accents, look-alike digits and symbols ("n1gg3r", "f@g"),
letters spaced out or punctuated ("k y s", "f.a.g"), stretched letters
("faaaggot") and two words run together ("porch monkey"). Whole words only,
so "Scunthorpe", "Niger" and "spicy" are fine, and so are the ambiguous
words a filter like this can't tell apart from ordinary speech ("chink in
the armor", "dyke" the levee, "homo sapiens"), which are left to reporting.
"""
from __future__ import annotations

import hashlib
import re
import sys
import unicodedata
from functools import lru_cache
from pathlib import Path

SALT = "stanley-blocklist:"
BLOCKLIST = Path(__file__).with_name("blocklist.txt")

# Look-alikes for letters, as typed to get round a filter.
_LEET = str.maketrans(
    {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b",
     "@": "a", "$": "s", "!": "i", "|": "i", "+": "t"}
)
_LETTERS = re.compile(r"[a-z]+")
_STRETCH = re.compile(r"(.)\1{2,}")


def digest(word: str) -> str:
    return hashlib.sha256((SALT + word).encode()).hexdigest()


@lru_cache(maxsize=1)
def _blocked() -> frozenset[str]:
    lines = BLOCKLIST.read_text().splitlines()
    return frozenset(line.strip() for line in lines if line.strip() and not line.startswith("#"))


def _fold(chunk: str) -> str:
    """Lowercase ASCII where it can be: accents dropped, look-alikes mapped."""
    decomposed = unicodedata.normalize("NFKD", chunk)
    bare = "".join(ch for ch in decomposed if not unicodedata.combining(ch))
    return bare.casefold().translate(_LEET)


def _tokens(text: str) -> set[str]:
    """Every whole word the text could be read as."""
    chunks = [_fold(chunk) for chunk in text.split()]
    # A chunk with its punctuation taken out ("f.a.g"), and its pieces
    # ("class/act" is "class" and "act").
    joined = ["".join(_LETTERS.findall(chunk)) for chunk in chunks]
    out: set[str] = set()
    for chunk, whole in zip(chunks, joined):
        out.add(whole)
        out.update(_LETTERS.findall(chunk))
    # Two words run together: "porch monkey", "kill yourself".
    for first, second in zip(joined, joined[1:]):
        if first and second:
            out.add(first + second)
    # Letters spaced out: "k y s".
    run: list[str] = []
    for whole in joined + [""]:
        if len(whole) == 1:
            run.append(whole)
            continue
        if len(run) >= 3:
            out.add("".join(run))
        run = []
    out.discard("")
    return out


def _variants(token: str) -> set[str]:
    """A word as written, with stretched letters cut back ("faaaggot"), and
    without a plural ending."""
    forms = {token, _STRETCH.sub(lambda m: m.group(1) * 2, token), _STRETCH.sub(lambda m: m.group(1), token)}
    for form in list(forms):
        if len(form) > 3 and form[-1] in "sz":
            forms.add(form[:-1])
        if len(form) > 4 and form.endswith("es"):
            forms.add(form[:-2])
    return forms


def is_objectionable(*texts: str | None) -> bool:
    """Whether any of the texts carries a word on the list."""
    blocked = _blocked()
    for text in texts:
        if not text:
            continue
        for token in _tokens(text):
            if any(digest(form) in blocked for form in _variants(token)):
                return True
    return False


def _main(argv: list[str]) -> int:
    if len(argv) >= 2 and argv[0] == "hash":
        for word in argv[1:]:
            print(digest("".join(_LETTERS.findall(_fold(word)))))
        return 0
    if len(argv) == 2 and argv[0] == "check":
        refused = is_objectionable(argv[1])
        print("refused" if refused else "fine")
        return 1 if refused else 0
    print(__doc__.split("\n\n")[3] if __doc__ else "", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv[1:]))
