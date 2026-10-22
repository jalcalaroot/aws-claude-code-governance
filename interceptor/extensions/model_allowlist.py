"""Per-group model allowlist for the AgentCore Gateway REQUEST interceptor.

Pure functions: no AWS calls, safe to import in tests. The sample's REQUEST
handler decodes the JWT and parses the request body; it then calls
``check_model`` and returns a 403 if the result is not allowed.

Configuration comes from the ``MODEL_ALLOWLIST_JSON`` environment variable,
a JSON object mapping a Cognito group to the model IDs it may use, plus an
optional "*" entry for users in no listed group:

    {"finanzas-builders": ["anthropic.claude-haiku-4-5"], "*": []}

Deny by default: a user whose groups grant nothing is refused.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from typing import Any, Iterable, Mapping

GROUPS_CLAIM = "cognito:groups"
DEFAULT_KEY = "*"
ERROR_CODE = "MODEL_NOT_ALLOWED"


@dataclass(frozen=True)
class Decision:
    allowed: bool
    error_code: str | None = None
    message: str | None = None


def normalize_model(model: Any) -> str | None:
    """Same normalization as the AWS sample's REQUEST/RESPONSE Lambdas.

    Strips a ``target/`` prefix and adds the provider prefix on bare names, so
    the allowlist is compared against the ID the sample prices and logs.
    """
    if not isinstance(model, str) or not model:
        return None
    if "/" in model:
        model = model.split("/", 1)[1]
    if "." not in model:
        if model.startswith("gpt-") or model.startswith("o"):
            model = f"openai.{model}"
        elif model.startswith("claude"):
            model = f"anthropic.{model}"
    return model


def load_allowlist(raw: str | None = None) -> dict[str, set[str]]:
    """Parse the allowlist from JSON (defaults to the env var)."""
    raw = raw if raw is not None else os.environ.get("MODEL_ALLOWLIST_JSON", "{}")
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise ValueError("MODEL_ALLOWLIST_JSON must be a JSON object")
    return {
        str(group): {normalize_model(str(m)) or str(m) for m in models}
        for group, models in data.items()
    }


def groups_from_claims(claims: Mapping[str, Any]) -> list[str]:
    """Cognito puts groups in a list; tolerate a single string or absence."""
    value = claims.get(GROUPS_CLAIM)
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    return [str(g) for g in value]


def allowed_models(groups: Iterable[str], allowlist: Mapping[str, set[str]]) -> set[str]:
    """Union of models granted by every group the user belongs to."""
    granted: set[str] = set()
    matched = False
    for group in groups:
        if group in allowlist:
            granted |= allowlist[group]
            matched = True
    if not matched:
        granted |= allowlist.get(DEFAULT_KEY, set())
    return granted


def check_model(
    claims: Mapping[str, Any],
    body: Mapping[str, Any],
    allowlist: Mapping[str, set[str]],
) -> Decision:
    """Allow the request only if its model is granted to one of the user's groups."""
    model = normalize_model(body.get("model"))
    if model is None:
        return Decision(False, ERROR_CODE, "Request has no model")
    granted = allowed_models(groups_from_claims(claims), allowlist)
    if model in granted:
        return Decision(True)
    return Decision(False, ERROR_CODE, f"Model '{model}' is not allowed for your group")
