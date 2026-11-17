"""Item 13 (build 77): a photo can't take the 1 GB machine down. Two images
are worked on at once and no more; a third waits and is then told to try
again with nothing spent; a large JPEG is decoded at a reduced size; the
original is kept at most 4096 on its longest side."""
from __future__ import annotations

import subprocess
import sys
import threading
import time
from io import BytesIO
from pathlib import Path

import pytest
from PIL import Image
from sqlalchemy import select

from stanley import images
from stanley.models import Photo


def jpeg(width: int, height: int, *, exif_datetime: str | None = None) -> bytes:
    img = Image.linear_gradient("L").resize((width, height)).convert("RGB")
    exif = Image.Exif()
    if exif_datetime:
        exif[306] = exif_datetime
    buf = BytesIO()
    img.save(buf, format="JPEG", quality=85, exif=exif)
    return buf.getvalue()


def test_no_more_than_two_images_at_once():
    running, most = 0, 0
    lock = threading.Lock()

    def work():
        nonlocal running, most
        with images.image_slot(wait=5):
            with lock:
                running += 1
                most = max(most, running)
            time.sleep(0.05)
            with lock:
                running -= 1

    threads = [threading.Thread(target=work) for _ in range(6)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert most == images.IMAGE_JOBS == 2


def test_a_third_photo_is_told_to_try_again_with_the_day_unspent(circle, db, monkeypatch):
    monkeypatch.setattr(images, "IMAGE_WAIT", 0.05)
    taken = [images._slots.acquire(), images._slots.acquire()]
    try:
        r = circle.ana.post_photo()
        assert r.status_code == 503 and r.json()["detail"]["code"] == "busy"
        with db() as session:
            assert not session.scalars(select(Photo).where(Photo.owner_id == circle.ana.id)).all()
    finally:
        for _ in taken:
            images._slots.release()
    # The day was never spent: the same photo goes up now.
    assert circle.ana.post_photo().status_code == 201


def test_the_slots_are_given_back_when_an_image_is_refused():
    for _ in range(images.IMAGE_JOBS + 2):
        with pytest.raises(images.BadImage):
            images.prepare_upload(b"\xff\xd8\xff not really a jpeg")
    with images.image_slot(wait=0.01):
        pass


def test_a_large_photo_keeps_an_original_no_larger_than_4096():
    for (w, h), want in (((4032, 3024), (4032, 3024)), ((5712, 4284), (4096, 3072)), ((8064, 6048), (4032, 3024))):
        prepared = images.prepare_upload(jpeg(w, h, exif_datetime="2026:11:17 10:00:00"))
        original = Image.open(BytesIO(prepared.encode_original()))
        assert original.size == want, (w, h)
        assert set(original.getexif().keys()) <= {306}
        assert Image.open(BytesIO(prepared.derivative)).size == (1080, 810)
        assert Image.open(BytesIO(prepared.thumbnail)).size == (320, 240)


def test_a_small_photo_is_never_made_larger():
    prepared = images.prepare_upload(jpeg(600, 800))
    assert Image.open(BytesIO(prepared.derivative)).size == (600, 800)
    assert Image.open(BytesIO(prepared.thumbnail)).size == (240, 320)
    assert Image.open(BytesIO(prepared.encode_original())).size == (600, 800)


MEASURE = """
import resource, sys, platform
sys.path.insert(0, sys.argv[2])
from stanley.images import prepare_upload
data = open(sys.argv[1], "rb").read()
base = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
prepare_upload(data).encode_original()
peak = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
scale = 2**20 if platform.system() == "Darwin" else 1024
print((peak - base) / scale)
"""


def test_a_48_megapixel_photo_takes_far_less_than_it_did(tmp_path):
    """Measured in a process of its own, so nothing else counts: 48
    megapixels took about 600 MB before item 13."""
    path = tmp_path / "48mp.jpg"
    path.write_bytes(jpeg(8064, 6048))
    server = str(Path(__file__).resolve().parent.parent)
    out = subprocess.run([sys.executable, "-c", MEASURE, str(path), server], capture_output=True, text=True, check=True)
    added_mb = float(out.stdout.strip())
    assert added_mb < 200, f"a 48 MP photo took {added_mb:.0f} MB"
