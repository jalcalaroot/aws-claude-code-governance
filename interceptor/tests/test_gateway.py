import base64
import json

from extensions import gateway

HAIKU = "anthropic.claude-haiku-4-5"
SONNET = "anthropic.claude-sonnet-5"


def jwt(claims):
    enc = lambda d: base64.urlsafe_b64encode(json.dumps(d).encode()).rstrip(b"=").decode()
    return f"{enc({'alg': 'none'})}.{enc(claims)}.sig"


def headers(groups=("finanzas-builders",)):
    return {"authorization": "Bearer " + jwt({"username": "finanzas-user", "cognito:groups": list(groups)})}


def b64(model, text="hi"):
    body = {"model": model, "messages": [{"role": "user", "content": text}]}
    return base64.b64encode(json.dumps(body).encode()).decode()


def status_and_code(resp):
    r = resp["http"]["transformedGatewayResponse"]
    return r["statusCode"], json.loads(base64.b64decode(r["body"]))["error"]["code"]


class Guard:
    def __init__(self, action="NONE", raises=False):
        self.action, self.raises = action, raises

    def apply_guardrail(self, **_):
        if self.raises:
            raise RuntimeError("x")
        return {"action": self.action}


def test_claims_from_headers_handles_garbage():
    assert gateway.claims_from_headers(None) == {}
    assert gateway.claims_from_headers({"authorization": "Bearer abc"}) == {}
    assert gateway.claims_from_headers(headers())["cognito:groups"] == ["finanzas-builders"]


def test_model_check_disabled_without_env(monkeypatch):
    monkeypatch.delenv("MODEL_ALLOWLIST_JSON", raising=False)
    assert gateway.model_check(headers(), b64(SONNET)) is None


def test_model_check_allows_and_denies(monkeypatch):
    monkeypatch.setenv("MODEL_ALLOWLIST_JSON", json.dumps({"finanzas-builders": [HAIKU]}))
    assert gateway.model_check(headers(), b64(HAIKU)) is None
    assert gateway.model_check(headers(), b64("claude-haiku-4-5")) is None  # bare name normalizes
    assert status_and_code(gateway.model_check(headers(), b64(SONNET))) == (403, "MODEL_NOT_ALLOWED")


def test_model_check_denies_user_without_groups(monkeypatch):
    monkeypatch.setenv("MODEL_ALLOWLIST_JSON", json.dumps({"finanzas-builders": [HAIKU]}))
    assert status_and_code(gateway.model_check(headers(groups=()), b64(HAIKU)))[0] == 403


def test_model_check_fails_closed_on_bad_config(monkeypatch):
    monkeypatch.setenv("MODEL_ALLOWLIST_JSON", "not json")
    assert status_and_code(gateway.model_check(headers(), b64(HAIKU))) == (503, "ALLOWLIST_MISCONFIGURED")


def test_guardrail_check(monkeypatch):
    monkeypatch.delenv("GUARDRAIL_ID", raising=False)
    assert gateway.guardrail_check(b64(HAIKU), Guard("GUARDRAIL_INTERVENED")) is None
    monkeypatch.setenv("GUARDRAIL_ID", "gr-1")
    assert gateway.guardrail_check(b64(HAIKU), Guard()) is None
    assert status_and_code(gateway.guardrail_check(b64(HAIKU), Guard("GUARDRAIL_INTERVENED"))) == (403, "GUARDRAIL_BLOCKED")
    assert status_and_code(gateway.guardrail_check(b64(HAIKU), Guard(raises=True))) == (503, "GUARDRAIL_UNAVAILABLE")


def test_strip_metadata_removes_only_metadata():
    body = {"model": HAIKU, "metadata": {"user_id": "{\"device\":\"x\"}"}, "messages": [{"role": "user", "content": "hi"}]}
    out = gateway.strip_metadata(base64.b64encode(json.dumps(body).encode()).decode())
    new = json.loads(base64.b64decode(out["http"]["transformedGatewayRequest"]["body"]))
    assert "metadata" not in new and new["model"] == HAIKU and new["messages"] == body["messages"]


def test_strip_metadata_noop_without_metadata():
    assert gateway.strip_metadata(b64(HAIKU)) is None
    assert gateway.strip_metadata(None) is None
