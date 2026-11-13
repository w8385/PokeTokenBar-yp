"""Slack message value types shared by the command handler and the trade service."""

from dataclasses import dataclass


@dataclass(frozen=True)
class DirectMessage:
    user_id: str
    text: str
    blocks: list[dict] | None = None
