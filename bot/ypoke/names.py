"""Slack display names for the upload response, cached so an upload never waits on Slack twice for one user."""

import logging
import threading
import time
from collections.abc import Callable, Iterable

SUCCESS_TTL = 3600
FAILURE_TTL = 300


class DisplayNames:
    def __init__(self, client, clock: Callable[[], float] = time.monotonic):
        self._client = client
        self._clock = clock
        self._cache: dict[str, tuple[str | None, float]] = {}
        self._lock = threading.Lock()

    def __call__(self, user_id: str) -> str | None:
        now = self._clock()
        with self._lock:
            cached = self._cache.get(user_id)
        if cached and cached[1] > now:
            return cached[0]
        name = self._lookup(user_id)
        with self._lock:
            self._cache[user_id] = (name, now + (SUCCESS_TTL if name else FAILURE_TTL))
        return name

    def warm(self, user_ids: Iterable[str]) -> None:
        """Look every id up in the background so the first upload after a restart finds them cached."""
        threading.Thread(target=lambda: [self(user_id) for user_id in user_ids], daemon=True).start()

    def _lookup(self, user_id: str) -> str | None:
        try:
            user = self._client.users_info(user=user_id)["user"]
        except Exception as error:
            reason = getattr(getattr(error, "response", None), "data", {}).get("error", type(error).__name__)
            logging.getLogger(__name__).warning("display name lookup failed: %s", reason)
            return None
        profile = user.get("profile") or {}
        return (profile.get("display_name") or profile.get("real_name") or user.get("real_name") or "").strip() or None
