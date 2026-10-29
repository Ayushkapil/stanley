"""Who someone is when we don't know their name yet.

Apple hands over a name only on the very first authorization, and only if the
person agrees to share it. Decline, and `display_name` is NULL — an ordinary
state for a brand-new member. `user_brief` used to fold that into the same
placeholder it uses for a deleted account, so a real circle on real hardware
saw a member who had just arrived labelled as having left.
"""
from __future__ import annotations

from stanley.models import User
from stanley.serialize import DEPARTED, UNNAMED

from .conftest import START


def test_nameless_member_reads_as_new_not_departed(circle, db):
    pid = circle.ana.post_photo(caption="first one").json()["id"]
    with db() as session:
        session.get(User, circle.ana.id).display_name = None
        session.commit()

    owner = circle.ben.feed_photos()[0]["owner"]
    assert owner["display_name"] == UNNAMED == "New member"
    # Still a person in the circle: the id survives, so the face still resolves.
    assert owner["id"] == circle.ana.id
    assert pid  # the photo itself is untouched by any of this


def test_departed_still_means_departed(circle, db):
    """The other half of the split. A deleted account is gone, and says so."""
    circle.ana.post_photo(caption="last one")
    with db() as session:
        session.get(User, circle.ana.id).deleted_at = START
        session.commit()

    assert circle.ben.feed_photos()[0]["owner"]["display_name"] == DEPARTED == "departed"


def test_a_name_wins_over_both_placeholders(circle):
    """The ordinary case, pinned so neither placeholder can leak into it."""
    circle.ana.post_photo(caption="hello")
    assert circle.ben.feed_photos()[0]["owner"]["display_name"] == "ana"
