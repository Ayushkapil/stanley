from __future__ import annotations

from dataclasses import dataclass
from io import BytesIO

from PIL import Image, UnidentifiedImageError

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
JPEG_QUALITY = 90


class BadImage(ValueError):
    pass


@dataclass
class ProcessedImage:
    original: bytes
    derivative: bytes
    thumbnail: bytes


def process_upload(data: bytes) -> ProcessedImage:
    try:
        img = Image.open(BytesIO(data))
        img.load()
    except (UnidentifiedImageError, OSError, ValueError) as exc:
        raise BadImage(f"could not decode image: {exc}") from exc

    src_exif = img.getexif()
    clean_exif = Image.Exif()
    for tag in EXIF_KEEP:
        if tag in src_exif:
            clean_exif[tag] = src_exif[tag]

    rgb = img.convert("RGB")

    def encode(edge: int | None) -> bytes:
        frame = rgb.copy()
        if edge is not None:
            frame.thumbnail((edge, edge))
        buf = BytesIO()
        frame.save(buf, format="JPEG", quality=JPEG_QUALITY, exif=clean_exif)
        return buf.getvalue()

    return ProcessedImage(
        original=encode(None),
        derivative=encode(DERIVATIVE_EDGE),
        thumbnail=encode(THUMB_EDGE),
    )
