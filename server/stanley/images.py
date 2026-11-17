from __future__ import annotations

import threading
import warnings
from contextlib import contextmanager
from dataclasses import dataclass
from io import BytesIO

from PIL import Image, ImageOps, UnidentifiedImageError

try:  # HEIC -> JPEG (§9); optional at dev time, required for real iPhone uploads
    from pillow_heif import register_heif_opener

    register_heif_opener()
except ImportError:
    pass

# §9: strip all EXIF except capture timestamp. GPS removal is a hard
# requirement — enforced by allowlisting, not blocklisting.
EXIF_KEEP = {306}  # 306 = DateTime

DERIVATIVE_EDGE = 1080
THUMB_EDGE = 320
AVATAR_EDGE = 512
# A journal's cover photo (build 76): large enough for the opened cover on
# the widest screen, small enough to stay a cover.
COVER_EDGE = 1600
JPEG_QUALITY = 90
# The full-size original is kept at most this long on its longest side
# (build 77, item 13). The app sends no more than 4096 from the library, and
# an untouched camera shot is 4032, so only an oversized upload is made
# smaller; nothing reads the original but the file it is. Bounding it bounds
# the memory a photo can take: 4096 x 3072 is 38 MB of RGB, where 48
# megapixels was 145 MB, and about four times that while being worked on.
ORIGINAL_EDGE = 4096

# How many photos are decoded and encoded at once (build 77, item 13). The
# server is one machine with 1 GB; each photo at work takes up to about
# 150 MB, so two at once leave room for everything else. A third waits, for
# up to IMAGE_WAIT seconds, and is then told to try again (503 `busy`),
# which costs the person nothing: the day is untouched until a photo posts.
IMAGE_JOBS = 2
IMAGE_WAIT = 20.0
_slots = threading.BoundedSemaphore(IMAGE_JOBS)


class Busy(RuntimeError):
    """Every image slot stayed taken for IMAGE_WAIT seconds."""


@contextmanager
def image_slot(wait: float | None = None):
    """Hold one of the IMAGE_JOBS slots while an image is worked on."""
    if not _slots.acquire(timeout=IMAGE_WAIT if wait is None else wait):
        raise Busy("the server is busy with other photos")
    try:
        yield
    finally:
        _slots.release()

# A 48-megapixel photo fits (8064 x 6048 is 48.8M); a "decompression bomb", a
# small file that claims enormous dimensions, doesn't. It's refused from its
# header, before a single pixel is decoded: 12000 x 12000 would be 432 MB of
# RGB on a 1 GB machine.
MAX_PIXELS = 50_000_000

# HEIF brands an iPhone writes (`ftyp` box at byte 4).
_HEIF_BRANDS = {b"heic", b"heix", b"hevc", b"hevx", b"heim", b"heis", b"mif1", b"msf1"}


class BadImage(ValueError):
    pass


def sniff(data: bytes) -> str | None:
    """What the file says it is, from its first bytes, never from its name
    or its Content-Type: JPEG, PNG or HEIF, or None for anything else. The
    phone sends JPEG; PNG and HEIF are what a person might reasonably hand
    over. Everything Pillow could otherwise open (TIFF, BMP, PSD, EPS, ICO
    and the rest) is refused before it reaches a decoder."""
    if data[:3] == b"\xff\xd8\xff":
        return "JPEG"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "PNG"
    if data[4:8] == b"ftyp" and data[8:12] in _HEIF_BRANDS:
        return "HEIF"
    return None


def _open(data: bytes, what: str, longest: int | None = None) -> Image.Image:
    """Decode an upload that is what it claims to be, at a size that's a
    photo. Every failure is a BadImage, never a 500. With `longest`, a JPEG
    larger than twice that is decoded straight at a half, a quarter or an
    eighth of its size (JPEG's own draft decode), never at full size first."""
    kind = sniff(data)
    if kind is None:
        raise BadImage(f"{what} isn't a JPEG, PNG or HEIF")
    try:
        with warnings.catch_warnings():
            # Pillow's own bomb check, a second line behind MAX_PIXELS: as an
            # error, not a warning in the logs.
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            img = Image.open(BytesIO(data), formats=[kind])
            if img.width * img.height > MAX_PIXELS:
                raise BadImage(f"{what} is {img.width}x{img.height}, more than a photo")
            if longest and kind == "JPEG" and max(img.size) > longest:
                # The decoder takes a size it may not go under: ask for the
                # photo's own shape at `longest`, less 2%, so a 48-megapixel
                # photo (8064 wide) decodes at half, 4032, not in full.
                k = 0.98 * longest / max(img.size)
                img.draft("RGB", (int(img.width * k), int(img.height * k)))
            img.load()
    except BadImage:
        raise
    except (
        UnidentifiedImageError, OSError, ValueError, KeyError, SyntaxError,
        Image.DecompressionBombError, Image.DecompressionBombWarning,
    ) as exc:
        # KeyError: a format this server can't decode (HEIF without pillow-heif).
        raise BadImage(f"could not decode {what}: {exc}") from exc
    return img


@dataclass
class ProcessedImage:
    original: bytes
    derivative: bytes
    thumbnail: bytes


@dataclass
class PreparedUpload:
    """A decoded, validated upload: the feed-facing derivatives eagerly, the
    full-size original lazily. The capture endpoint responds after encoding
    only deriv+thumb — the original's re-encode (the heaviest step, and never
    served in any feed) runs after the response."""

    derivative: bytes
    thumbnail: bytes
    _rgb: Image.Image
    _exif: Image.Exif

    def encode_original(self, wait: float | None = None) -> bytes:
        """The original, encoded in an image slot; the pixels are let go
        afterwards, so a waiting photo doesn't hold them longer than it must."""
        with image_slot(wait):
            data = _jpeg(self._rgb, self._exif)
        self._rgb = None
        return data


def _fit(img: Image.Image, edge: int) -> Image.Image:
    """A new image at most `edge` on its longest side (never larger than the
    one given), made without copying the full-size one first."""
    scale = min(1.0, edge / max(img.width, img.height))
    size = (max(1, round(img.width * scale)), max(1, round(img.height * scale)))
    if size == img.size:
        return img.copy()
    return img.resize(size, Image.Resampling.LANCZOS, reducing_gap=2.0)


def _jpeg(img: Image.Image, exif: Image.Exif) -> bytes:
    buf = BytesIO()
    img.save(buf, format="JPEG", quality=JPEG_QUALITY, exif=exif)
    return buf.getvalue()


def prepare_upload(data: bytes) -> PreparedUpload:
    """Decode an upload and make what the feed serves, in one of the image
    slots (item 13): decoded at no more than about twice ORIGINAL_EDGE, the
    original held at most ORIGINAL_EDGE, and the derivative and thumbnail
    made from smaller images rather than copies of the full one."""
    with image_slot():
        img = _open(data, "image", longest=ORIGINAL_EDGE)

        # M1: bake the EXIF orientation into the pixels BEFORE stripping EXIF,
        # or a photo shot sideways would render rotated once the orientation
        # tag is gone. In place: no second full-size image.
        ImageOps.exif_transpose(img, in_place=True)

        src_exif = img.getexif()
        clean_exif = Image.Exif()
        for tag in EXIF_KEEP:
            if tag in src_exif:
                clean_exif[tag] = src_exif[tag]

        if img.mode != "RGB":
            img = img.convert("RGB")
        if max(img.size) > ORIGINAL_EDGE:
            img.thumbnail((ORIGINAL_EDGE, ORIGINAL_EDGE), Image.Resampling.LANCZOS)

        derivative = _fit(img, DERIVATIVE_EDGE)
        thumbnail = _fit(derivative, THUMB_EDGE)
        return PreparedUpload(
            derivative=_jpeg(derivative, clean_exif),
            thumbnail=_jpeg(thumbnail, clean_exif),
            _rgb=img,
            _exif=clean_exif,
        )


def process_upload(data: bytes) -> ProcessedImage:
    """Eager all-three encode, for offline tools (seed, time-travel). The
    request path uses prepare_upload and defers the original."""
    prepared = prepare_upload(data)
    return ProcessedImage(
        original=prepared.encode_original(),
        derivative=prepared.derivative,
        thumbnail=prepared.thumbnail,
    )


def process_avatar(data: bytes) -> bytes:
    with image_slot():
        return _process_avatar(data)


def _process_avatar(data: bytes) -> bytes:
    """Center-crop to a square and downscale. Avatar is identity, not content,
    so all EXIF is dropped (no timestamp kept) and it never decays. The client
    crops too; this just guarantees a square regardless of what arrives."""
    img = _open(data, "avatar", longest=AVATAR_EDGE * 2)

    img = ImageOps.exif_transpose(img)  # M1: honor orientation before stripping
    rgb = img.convert("RGB")
    edge = min(rgb.width, rgb.height)
    left = (rgb.width - edge) // 2
    top = (rgb.height - edge) // 2
    square = rgb.crop((left, top, left + edge, top + edge))
    square.thumbnail((AVATAR_EDGE, AVATAR_EDGE))
    buf = BytesIO()
    square.save(buf, format="JPEG", quality=JPEG_QUALITY)
    return buf.getvalue()


def process_cover(data: bytes) -> bytes:
    with image_slot():
        return _process_cover(data)


def _process_cover(data: bytes) -> bytes:
    """A journal's cover photo, chosen from the phone's library (build 76):
    turned upright, downscaled, every bit of EXIF dropped (GPS above all;
    no timestamp kept either, since a cover isn't a moment). Not cropped:
    the cover changes shape as it opens, and fills itself from the middle."""
    img = _open(data, "cover", longest=COVER_EDGE * 2)
    img = ImageOps.exif_transpose(img)
    rgb = img.convert("RGB")
    rgb.thumbnail((COVER_EDGE, COVER_EDGE))
    buf = BytesIO()
    rgb.save(buf, format="JPEG", quality=JPEG_QUALITY)
    return buf.getvalue()
