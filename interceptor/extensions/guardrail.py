"""Bedrock Guardrail check for the AgentCore Gateway REQUEST interceptor.

Scans the latest user turn of an Anthropic Messages request with the
``ApplyGuardrail`` API before the request reaches the model.

Known gap (documented in docs/decisions.md, ADR-004): tool results and file
contents are not scanned, so indirect prompt injection is not covered.

Fail-closed: if the guardrail call errors, the request is blocked.
Never log the scanned text.
"""

from __future__ import annotations

import logging
import os
import re
from dataclasses import dataclass
from typing import Any, Mapping, Protocol

logger = logging.getLogger(__name__)

ERROR_CODE = "GUARDRAIL_BLOCKED"
ERROR_CODE_UNAVAILABLE = "GUARDRAIL_UNAVAILABLE"
MAX_CHARS = 20_000  # keep cost and latency bounded per request

# Claude Code wraps CLAUDE.md, date and tool hints in <system-reminder> blocks
# inside the user message. They are not what the user typed: scanning them
# raises cost and false positives, and truncating from the head could cut the
# real prompt. They are removed, and if the text is still too long the END is
# kept (the user's own words come last).
_SYSTEM_REMINDER = re.compile(r"<system-reminder>.*?</system-reminder>", re.DOTALL)


class GuardrailClient(Protocol):
    def apply_guardrail(self, **kwargs: Any) -> Mapping[str, Any]: ...


@dataclass(frozen=True)
class Decision:
    allowed: bool
    error_code: str | None = None
    message: str | None = None


def latest_user_text(body: Mapping[str, Any]) -> str:
    """Text of the last user message, ignoring tool_result blocks."""
    messages = body.get("messages") or []
    for message in reversed(messages):
        if message.get("role") != "user":
            continue
        content = message.get("content")
        if isinstance(content, str):
            return _clean(content)
        parts = [
            block.get("text", "")
            for block in content or []
            if isinstance(block, Mapping) and block.get("type") == "text"
        ]
        text = _clean("\n".join(p for p in parts if p))
        if text:
            return text
    return ""


def _clean(text: str) -> str:
    text = _SYSTEM_REMINDER.sub("", text).strip()
    return text[-MAX_CHARS:]


def check_prompt(
    body: Mapping[str, Any],
    client: GuardrailClient,
    guardrail_id: str | None = None,
    guardrail_version: str | None = None,
) -> Decision:
    guardrail_id = guardrail_id or os.environ["GUARDRAIL_ID"]
    guardrail_version = guardrail_version or os.environ.get("GUARDRAIL_VERSION", "DRAFT")

    text = latest_user_text(body)
    if not text:
        return Decision(True)

    try:
        result = client.apply_guardrail(
            guardrailIdentifier=guardrail_id,
            guardrailVersion=guardrail_version,
            source="INPUT",
            content=[{"text": {"text": text}}],
        )
    except Exception as exc:  # fail closed
        logger.warning("guardrail call failed: %s", type(exc).__name__)
        return Decision(False, ERROR_CODE_UNAVAILABLE, "Guardrail unavailable, request blocked")

    if result.get("action") == "GUARDRAIL_INTERVENED":
        return Decision(False, ERROR_CODE, "Request blocked by the organization's AI guardrail")
    return Decision(True)
