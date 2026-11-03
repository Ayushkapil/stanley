"""Writing things down (build 26): a private journal entry on your own
photo, a reflection at the end of your week, and the circle's question of
the week, answered privately and read together. Pure functions only, like
`physics.py`: the weeks, the limits, and the forty questions.

What each one is, and who reads it:

- A journal entry ("Anything else about today?") is the photo's owner's
  alone: never in the feed, never in a payload anyone else gets. It lives
  exactly as long as the photo does for its owner: while the photo is in
  Today, and after that only if the owner held it. Deleted, purged or let go
  of, it goes with the photo (`decay.py`).
- A reflection ("How was your week?") is the writer's alone too, and doesn't
  decay. It's kept until they delete it or their account.
- The circle's question is one per circle per week, Monday to Monday in
  UTC (a circle spans time zones, so its week can't be anyone's local one).
  Answers stay sealed until Saturday 00:00 UTC, then everyone in the circle
  can read them together, whether they answered or not. Answering closes
  when they open: nobody answers having read the others first. A member
  reads the weeks they were in the circle for, not the ones before they
  joined, so an answer is never read by someone it wasn't written for.

None of them counts anything, and none sends a notification.
"""
from __future__ import annotations

import random
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

JOURNAL_MAX = 1000
REFLECTION_MAX = 500
ANSWER_MAX = 300

# A reflection is written on Sunday evening (the app asks from 6pm until
# midnight). One sent in the small hours of Monday still belongs to the week
# it's about, so a slow send at 00:01 isn't filed under a week that has
# barely begun, and doesn't take that week's place.
REFLECTION_GRACE = timedelta(hours=6)

# The circle's question opens on Monday and its answers on Saturday, 00:00
# UTC both.
REVEAL_AFTER = timedelta(days=5)

QUESTIONS = [
    "What's something you believed at the start of this week that you're not sure about anymore?",
    "What moment this week would you relive if you could?",
    "What's something you didn't say this week but wanted to?",
    "If this week had a title, what would it be and why?",
    "What's something you noticed that nobody else seemed to?",
    "What felt heavy this week, and did it get lighter?",
    "What would your week look like from someone else's eyes?",
    "What's a conversation you had this week that stuck with you?",
    "What are you carrying into next week that you wish you could leave behind?",
    "What's something small that happened that might matter more than you think?",
    "Where did your mind keep going this week when it wandered?",
    "What's something you did for the first time, even if it was tiny?",
    "What would you want to remember about this week five years from now?",
    "What's something you're figuring out right now?",
    "Who were you closest to this week, and why?",
    "What made you feel most like yourself?",
    "What's something you're not ready to talk about but could write about?",
    "What surprised you about yourself this week?",
    "If you could give this week a color, what would it be?",
    "What are you slowly becoming?",
    "What question should you be asking yourself right now?",
    "What's something you let go of this week?",
    "What's the difference between who you were on Monday and who you are now?",
    "What does your week look like if you only count the quiet moments?",
    "What's one thing you want to be true about next week?",
    "What are you pretending is fine?",
    "What did you make time for, and what made time for itself?",
    "What would you write on a postcard to your future self about this week?",
    "What's a feeling you had this week that you don't have a word for?",
    "What are you building, even if nobody can see it yet?",
    "What mattered more than you expected?",
    "What's something you keep coming back to in your head?",
    "What would this week's photo look like if you could only take one?",
    "What are you grateful for that you didn't expect?",
    "What's the most honest thing you could say about where you are right now?",
    "What did you learn about someone in your circle this week?",
    "What's something you want but haven't admitted to yourself?",
    "What does rest look like for you right now?",
    "What question would you want your circle to answer honestly?",
    "What's one line you'd write in a letter to the person you were a year ago?",
]


def _monday(day: date) -> date:
    return day - timedelta(days=day.weekday())


def question_week(now: datetime) -> date:
    """The Monday (UTC) of the circle's current week."""
    return _monday(now.astimezone(timezone.utc).date())


def reveals_at(week_start: date) -> datetime:
    """When a week's answers open: its Saturday, 00:00 UTC."""
    return datetime.combine(week_start, time(0), tzinfo=timezone.utc) + REVEAL_AFTER


def revealed(week_start: date, now: datetime) -> bool:
    return now >= reveals_at(week_start)


def last_revealed_week(now: datetime) -> date:
    """The newest week whose answers are open: this one from Saturday on,
    otherwise last week."""
    week = question_week(now)
    return week if revealed(week, now) else week - timedelta(days=7)


def reflection_week(now: datetime, tz_name: str) -> date:
    """The Monday of the person's own week, in their time zone, for a
    reflection written now. Until 6am on Monday it's still the week just
    ended (`REFLECTION_GRACE`)."""
    local = now.astimezone(ZoneInfo(tz_name)) - REFLECTION_GRACE
    return _monday(local.date())


def week_end(week_start: date) -> date:
    """The week's Sunday."""
    return week_start + timedelta(days=6)


def pick_question(recent: list[str], rng: random.Random | None = None) -> str:
    """This week's question for a circle: any of the forty that isn't among
    its last thirty-nine, so none comes round again within forty weeks.
    `recent` is the circle's questions, newest first."""
    rng = rng or random.SystemRandom()
    used = set(recent[: len(QUESTIONS) - 1])
    fresh = [q for q in QUESTIONS if q not in used]
    return rng.choice(fresh or QUESTIONS)
