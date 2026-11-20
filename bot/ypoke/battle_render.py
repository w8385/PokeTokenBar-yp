"""Matchup pictures for the battle log: both active Pokémon side by side, uploaded to Slack as private files.

Slack files: https://docs.slack.dev/messaging/working-with-files
"""

import logging
import time
import urllib.request
from collections.abc import Callable, Iterable
from concurrent.futures import ThreadPoolExecutor
from functools import partial
from io import BytesIO
from pathlib import Path
from uuid import uuid4

from PIL import Image, ImageOps

from ypoke.narration import Matchup, Portrait
from ypoke.store import Store

CANVAS = (640, 320)
SPRITE_BOX = 280
UPLOAD_WORKERS = 6
FETCH_TIMEOUT = 10
CACHE_PREFIX = "matchup:v1"
SETTLE_SECONDS = 3.0

log = logging.getLogger(__name__)


class MatchupPictures:
    """Draws each matchup once, uploads it once and keeps its Slack file id in the store's cache, so a rematch
    reuses it. Fetched sprites and drawn pictures stay in `directory`."""

    def __init__(self, store: Store, directory: Path, fetch: Callable[[str], bytes] | None = None,
                 pause: Callable[[float], None] = time.sleep):
        self._store = store
        self._directory = directory
        self._fetch = fetch or _download
        self._pause = pause

    def image_blocks(self, client, matchups: Iterable[Matchup]) -> dict[Matchup, dict]:
        """An `image` block per matchup that could be drawn and uploaded; the others are left out."""
        unique = list(dict.fromkeys(matchups))
        if not unique:
            return {}
        with ThreadPoolExecutor(max_workers=min(UPLOAD_WORKERS, len(unique))) as pool:
            blocks = list(pool.map(partial(self._image_block, client), unique))
        return {matchup: block for matchup, block in zip(unique, blocks) if block is not None}

    def settle(self) -> None:
        """Give Slack time to finish processing fresh uploads before a refused message is sent again."""
        self._pause(SETTLE_SECONDS)

    def forget(self, matchups: Iterable[Matchup]) -> None:
        """Drop the file ids of pictures Slack refused, so the next battle uploads them again."""
        for matchup in matchups:
            self._store.cache(cache_key(matchup), None)

    def _image_block(self, client, matchup: Matchup) -> dict | None:
        try:
            file_id = self._file_id(client, matchup)
        except Exception:
            log.warning("could not draw or upload a matchup picture", exc_info=True)
            return None
        return image_block(file_id, matchup)

    def _file_id(self, client, matchup: Matchup) -> str:
        key = cache_key(matchup)
        cached = self._store.cached(key)
        if isinstance(cached, str):
            return cached
        response = client.files_upload_v2(
            content=self._picture(matchup), filename=f"{key.replace(':', '-')}.png", title=matchup.caption,
        )
        file_id = response["file"]["id"]
        self._store.cache(key, file_id)
        return file_id

    def _picture(self, matchup: Matchup) -> bytes:
        path = self._directory / "matchups" / f"{cache_key(matchup).replace(':', '-')}.png"
        if path.exists():
            return path.read_bytes()
        png = composite(self._sprite(matchup.left), self._sprite(matchup.right))
        _write(path, png)
        return png

    def _sprite(self, portrait: Portrait) -> bytes:
        url = portrait.url
        path = self._directory / "sprites" / "-".join(url.split("/")[-2:])
        if path.exists():
            return path.read_bytes()
        png = self._fetch(url)
        _write(path, png)
        return png


def cache_key(matchup: Matchup) -> str:
    left, right = matchup.left, matchup.right
    return f"{CACHE_PREFIX}:{left.form_id}:{int(left.shiny)}:{right.form_id}:{int(right.shiny)}"


def composite(left: bytes, right: bytes) -> bytes:
    """One transparent PNG: `left` mirrored to face right on the left half, `right` as drawn (official artwork faces
    left) on the right half, each trimmed to its visible pixels, scaled into `SPRITE_BOX` and standing on one line."""
    canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    half = CANVAS[0] // 2
    for png, mirrored, centre in ((left, True, half // 2), (right, False, half + half // 2)):
        sprite = _fitted(png)
        if mirrored:
            sprite = ImageOps.mirror(sprite)
        bottom = (CANVAS[1] + SPRITE_BOX) // 2
        canvas.alpha_composite(sprite, (centre - sprite.width // 2, bottom - sprite.height))
    out = BytesIO()
    canvas.save(out, format="PNG", optimize=True)
    return out.getvalue()


def image_block(file_id: str, matchup: Matchup) -> dict:
    return {
        "type": "image", "slack_file": {"id": file_id}, "alt_text": matchup.caption,
        "title": {"type": "plain_text", "text": matchup.caption},
    }


def _fitted(png: bytes) -> Image.Image:
    sprite = Image.open(BytesIO(png)).convert("RGBA")
    box = sprite.getbbox()
    if box is not None:
        sprite = sprite.crop(box)
    scale = SPRITE_BOX / max(sprite.width, sprite.height)
    size = (max(1, round(sprite.width * scale)), max(1, round(sprite.height * scale)))
    return sprite.resize(size, Image.Resampling.LANCZOS)


def _download(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "ypoke-bot"})
    with urllib.request.urlopen(request, timeout=FETCH_TIMEOUT) as response:
        return response.read()


def _write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    staging = path.with_name(f"{path.name}.{uuid4().hex}.part")
    staging.write_bytes(data)
    staging.replace(path)
