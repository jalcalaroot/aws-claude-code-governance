from extensions.model_allowlist import check_model, load_allowlist

HAIKU = "anthropic.claude-haiku-4-5"
SONNET = "anthropic.claude-sonnet-5"

ALLOWLIST = load_allowlist(
    '{"finanzas-builders": ["%s"], "platform": ["%s", "%s"], "*": []}' % (HAIKU, HAIKU, SONNET)
)


def finanzas():
    return {"username": "finanzas-user", "cognito:groups": ["finanzas-builders"]}


def test_haiku_allowed_for_finanzas():
    assert check_model(finanzas(), {"model": HAIKU}, ALLOWLIST).allowed


def test_sonnet_denied_for_finanzas():
    decision = check_model(finanzas(), {"model": SONNET}, ALLOWLIST)
    assert not decision.allowed
    assert decision.error_code == "MODEL_NOT_ALLOWED"


def test_union_of_groups():
    claims = {"cognito:groups": ["finanzas-builders", "platform"]}
    assert check_model(claims, {"model": SONNET}, ALLOWLIST).allowed


def test_no_groups_denied_by_default():
    assert not check_model({"username": "x"}, {"model": HAIKU}, ALLOWLIST).allowed


def test_missing_model_denied():
    assert not check_model(finanzas(), {}, ALLOWLIST).allowed


def test_single_string_group_claim():
    claims = {"cognito:groups": "finanzas-builders"}
    assert check_model(claims, {"model": HAIKU}, ALLOWLIST).allowed


def test_bare_model_name_is_normalized():
    assert check_model(finanzas(), {"model": "claude-haiku-4-5"}, ALLOWLIST).allowed
    assert check_model(finanzas(), {"model": "bedrock/anthropic.claude-haiku-4-5"}, ALLOWLIST).allowed
