"""The suggestions over a new page in the app (build 63) are the circle's
forty questions of the week, carried in `ios/Stanley/WritingPrompts.swift`.
A change to the questions goes in both, as the Terms do."""

import re
from pathlib import Path

from stanley import journal

SWIFT = Path(__file__).resolve().parents[2] / "ios" / "Stanley" / "WritingPrompts.swift"


def _app_prompts() -> list[str]:
    source = SWIFT.read_text()
    block = source[source.index("static let all: [String] = [") : source.index("    ]\n")]
    return re.findall(r'^\s+"(.*)",$', block, flags=re.M)


def test_the_app_suggests_the_circle_s_questions_word_for_word_in_order():
    assert _app_prompts() == journal.QUESTIONS


def test_no_suggestion_could_break_its_swift_literal():
    for question in journal.QUESTIONS:
        assert '"' not in question and "\\" not in question, question
