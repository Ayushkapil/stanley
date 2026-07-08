from __future__ import annotations

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
JPEG_QUALITY = 90


class BadImage(ValueError):
    pass


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

    def encode_original(self) -> bytes:
        buf = BytesIO()
        self._rgb.save(buf, format="JPEG", quality=JPEG_QUALITY, exif=self._exif)
        return buf.getvalue()


def prepare_upload(data: bytes) -> PreparedUpload:
    try:
        img = Image.open(BytesIO(data))
        img.load()
    except (UnidentifiedImageError, OSError, ValueError) as exc:
        raise BadImage(f"could not decode image: {exc}") from exc

    # M1: bake the EXIF orientation into the pixels BEFORE stripping EXIF, or a
    # photo shot sideways would render rotated once the orientation tag is gone.
    img = ImageOps.exif_transpose(img)

    src_exif = img.getexif()
    clean_exif = Image.Exif()
    for tag in EXIF_KEEP:
        if tag in src_exif:
            clean_exif[tag] = src_exif[tag]

    rgb = img.convert("RGB")

    def encode(edge: int) -> bytes:
        frame = rgb.copy()
        frame.thumbnail((edge, edge))
        buf = BytesIO()
        frame.save(buf, format="JPEG", quality=JPEG_QUALITY, exif=clean_exif)
        return buf.getvalue()

    return PreparedUpload(
        derivative=encode(DERIVATIVE_EDGE),
        thumbnail=encode(THUMB_EDGE),
        _rgb=rgb,
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
    """Center-crop to a square and downscale. Avatar is identity, not content,
    so all EXIF is dropped (no timestamp kept) and it never decays. The client
    crops too; this just guarantees a square regardless of what arrives."""
    try:
        img = Image.open(BytesIO(data))
        img.load()
    except (UnidentifiedImageError, OSError, ValueError) as exc:
        raise BadImage(f"could not decode avatar: {exc}") from exc

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
