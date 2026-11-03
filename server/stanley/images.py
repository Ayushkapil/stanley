from __future__ import annotations

import warnings
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


def _open(data: bytes, what: str) -> Image.Image:
    """Decode an upload that is what it claims to be, at a size that's a
    photo. Every failure is a BadImage, never a 500."""
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

    def encode_original(self) -> bytes:
        buf = BytesIO()
        self._rgb.save(buf, format="JPEG", quality=JPEG_QUALITY, exif=self._exif)
        return buf.getvalue()


def prepare_upload(data: bytes) -> PreparedUpload:
    img = _open(data, "image")

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
    img = _open(data, "avatar")

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
