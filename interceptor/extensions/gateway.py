"""Glue between the AWS sample's REQUEST handler and the extension checks.

The sample's handler (``RequestInterceptorFunction`` in standalone.yaml) works
with this event shape, verified against the template:

    event["http"]["gatewayRequest"] = {"path", "httpMethod", "headers", "body"}
    body    = base64-encoded JSON string
    claims  = payload of the Bearer token in the ``authorization`` header
              (the gateway already validated the JWT; this only decodes it)

A denial is a short-circuit response in the same shape as the sample's
``BUDGET_EXCEEDED``: ``http.transformedGatewayResponse`` with a base64 body.

No function here logs prompts, bodies or headers.
"""

from __future__ import annotations

import base64
import json
import logging
import os
from typing import Any, Mapping

from . import guardrail, model_allowlist

logger = logging.getLogger(__name__)

ERROR_CODE_CONFIG = "ALLOWLIST_MISCONFIGURED"
_ALLOWLIST_CACHE: dict[str, dict[str, set[str]]] = {}


def decode_body(b64_body: str | None) -> dict[str, Any] | None:
    """Request body as a dict, or None if absent or not a JSON object."""
    if not b64_body:
        return None
    try:
        data = json.loads(base64.b64decode(b64_body).decode("utf-8", errors="replace"))
    except Exception:
        return None
    return data if isinstance(data, dict) else None


def claims_from_headers(headers: Mapping[str, str] | None) -> dict[str, Any]:
    """Claims of the Bearer token; empty if absent or malformed."""
    auth = (headers or {}).get("authorization") or (headers or {}).get("Authorization") or ""
    if not auth.lower().startswith("bearer "):
        return {}
    parts = auth.split(" ", 1)[1].split(".")
    if len(parts) != 3:
        return {}
    try:
        payload = parts[1] + "=" * (-len(parts[1]) % 4)
        claims = json.loads(base64.urlsafe_b64decode(payload))
    except Exception:
        return {}
    return claims if isinstance(claims, dict) else {}


def strip_metadata(b64_body: str | None) -> dict[str, Any] | None:
    """Transformed request without the ``metadata`` field, or None when there is nothing to strip.

    Claude Code sends ``metadata.user_id`` on every request; the Messages route of ``bedrock-runtime``
    rejects it ("Request metadata contains a value that violates the regular expression"). The field is
    optional attribution data, so it is removed before the gateway forwards the request.
    """
    body = decode_body(b64_body)
    if body is None or "metadata" not in body:
        return None
    del body["metadata"]
    new_body = base64.b64encode(json.dumps(body, separators=(",", ":")).encode()).decode()
    return {"interceptorOutputVersion": "1.0", "http": {"transformedGatewayRequest": {"body": new_body}}}


def deny_response(status: int, code: str, message: str, **details: Any) -> dict[str, Any]:
    error: dict[str, Any] = {"type": "access_denied", "code": code, "message": message}
    if details:
        error["details"] = details
    body = json.dumps({"error": error})
    return {
        "interceptorOutputVersion": "1.0",
        "http": {
            "transformedGatewayResponse": {
                "statusCode": status,
                "headers": {"content-type": "application/json"},
                "body": base64.b64encode(body.encode()).decode(),
                "contentType": "application/json",
            }
        },
    }


def _allowlist() -> dict[str, set[str]]:
    raw = os.environ.get("MODEL_ALLOWLIST_JSON", "")
    if raw not in _ALLOWLIST_CACHE:
        _ALLOWLIST_CACHE[raw] = model_allowlist.load_allowlist(raw or "{}")
    return _ALLOWLIST_CACHE[raw]


def model_check(headers: Mapping[str, str] | None, b64_body: str | None) -> dict[str, Any] | None:
    """Denial response if the user's groups do not grant the requested model.

    Returns None to continue. Skipped when MODEL_ALLOWLIST_JSON is unset (the
    sample's global price-table allowlist still applies). Fail-closed when it
    is set but invalid.
    """
    if not os.environ.get("MODEL_ALLOWLIST_JSON"):
        return None
    body = decode_body(b64_body)
    if body is None:
        return None  # the sample already rejects unparseable bodies (MODEL_MISSING)
    try:
        allowlist = _allowlist()
    except Exception:
        logger.error("MODEL_ALLOWLIST_JSON is invalid")
        return deny_response(503, ERROR_CODE_CONFIG, "Model policy is misconfigured, request blocked")
    decision = model_allowlist.check_model(claims_from_headers(headers), body, allowlist)
    if decision.allowed:
        return None
    return deny_response(403, decision.error_code or model_allowlist.ERROR_CODE, decision.message or "")


def guardrail_check(b64_body: str | None, client: Any) -> dict[str, Any] | None:
    """Denial response if the guardrail intervenes. Skipped when GUARDRAIL_ID is unset."""
    if not os.environ.get("GUARDRAIL_ID"):
        return None
    body = decode_body(b64_body)
    if body is None:
        return None
    decision = guardrail.check_prompt(body, client)
    if decision.allowed:
        return None
    status = 503 if decision.error_code == guardrail.ERROR_CODE_UNAVAILABLE else 403
    return deny_response(status, decision.error_code or guardrail.ERROR_CODE, decision.message or "")
