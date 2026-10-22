#!/usr/bin/env bash
# Signs the user in to the gateway (password, SRP), writes the Claude Code settings for the seat and
# runs the given command with ANTHROPIC_AUTH_TOKEN set. The container has no AWS credentials.
set -euo pipefail

: "${GATEWAY_BASE_URL:?}" "${AGENTCORE_OIDC_DISCOVERY_URL:?}" "${AGENTCORE_OIDC_CLIENT_ID:?}"
: "${GATEWAY_USER:?}" "${SEAT_MODEL:?}"
export AGENTCORE_OIDC_DISCOVERY_URL AGENTCORE_OIDC_CLIENT_ID

mkdir -p "$HOME/.claude"
python3 - <<'PY'
import json, os, pathlib
model = os.environ["SEAT_MODEL"]
settings = {
    "env": {
        "ANTHROPIC_BASE_URL": os.environ["GATEWAY_BASE_URL"],
        "ANTHROPIC_MODEL": model,
        "ANTHROPIC_SMALL_FAST_MODEL": model,   # internal requests must use an allowed model too
        "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1",
        "DISABLE_AUTOUPDATER": "1",   # the version is pinned in the image
    },
}
pathlib.Path.home().joinpath(".claude", "settings.json").write_text(json.dumps(settings, indent=2) + "\n")
PY

export ANTHROPIC_BASE_URL="$GATEWAY_BASE_URL"
ANTHROPIC_AUTH_TOKEN=$(python3 "$HOME/gateway/get-token-srp.py" "$GATEWAY_USER")
export ANTHROPIC_AUTH_TOKEN
unset GATEWAY_PASSWORD GATEWAY_PASSWORD_FILE
echo "signed in as $GATEWAY_USER; seat model $SEAT_MODEL; AWS credentials in this container: $(env | grep -c '^AWS_' || true)" >&2
exec "$@"
