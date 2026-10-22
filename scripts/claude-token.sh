#!/usr/bin/env bash
# Usage: source scripts/claude-token.sh <profile> [--srp <cognito user>]
# Exports a gateway token for Claude Code (works on a laptop).
# Needs .env.local with REGION and STACK, and scripts/fetch-upstream.sh run once.
# <profile> keeps one token cache per user (e.g. finanzas, platform).
# --srp signs in with the user's password (prompt) instead of the browser flow: needs
# `pip install --user -r requirements-client.txt`; nothing is cached, the token lasts 24 hours.
#
# Headless shells: the helper prints a sign-in URL and waits on
# 127.0.0.1:8400. Open the URL in your own browser, sign in, copy the final
# (failing) http://localhost:8400/callback?... URL from the address bar and run
#   curl -s 'http://localhost:8400/callback?...'
# in a second terminal. See README, "End users".
_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_profile="${1:?usage: source scripts/claude-token.sh <profile>}"
source "$_root/.env.local"

_out() { aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue | [0]" --output text; }

export AGENTCORE_OIDC_DISCOVERY_URL=$(_out DiscoveryUrl)
export AGENTCORE_OIDC_CLIENT_ID=$(_out ClientId)
export AGENTCORE_OIDC_CACHE_PATH="$HOME/.config/agentcore-gateway/${_profile}.json"
export ANTHROPIC_BASE_URL=$(_out InferenceBaseUrl | sed 's#/v1$##')

if [[ "${2:-}" == "--srp" ]]; then
  export ANTHROPIC_AUTH_TOKEN=$(python3 "$_root/scripts/get-token-srp.py" "${3:?usage: ... <profile> --srp <cognito user>}")
else
  export ANTHROPIC_AUTH_TOKEN=$(python3 "$_root/upstream/auth-helper/oidc-token.py")
fi
echo "profile '${_profile}': token exported (${#ANTHROPIC_AUTH_TOKEN} chars), base URL ${ANTHROPIC_BASE_URL}"
