#!/usr/bin/env bash
# Run an end-user container (a clean Linux box with Claude Code and NO AWS credentials).
# Usage: scripts/run-user.sh <finanzas|platform> [verify | claude ... | command ...]
#   no command   interactive shell, already signed in, `claude` ready to use
#   verify       scripts/verify-gateway.sh against the gateway (allowed model, other seat's model, injection)
# The gateway address and the Cognito pool/client are read from the stack with YOUR credentials on the
# host; only those non-secret values reach the container. The password comes from, in this order:
#   1. the file ~/.config/aws-claude-code-governance/<seat>.pass (mode 600), mounted read-only into the
#      container (it never appears in an environment variable or in `docker inspect`)
#   2. the variable GATEWAY_PASSWORD   3. a prompt on the terminal.
set -euo pipefail
cd "$(dirname "$0")/.."
source .env.local

SEAT="${1:?usage: run-user.sh <finanzas|platform> [verify | command ...]}"; shift || true
case "$SEAT" in
  finanzas) GATEWAY_USER=finanzas-user; SEAT_MODEL=us.anthropic.claude-haiku-4-5-20251001-v1:0; OTHER_MODEL=us.anthropic.claude-sonnet-4-6 ;;
  platform) GATEWAY_USER=platform-user; SEAT_MODEL=us.anthropic.claude-sonnet-4-6; OTHER_MODEL=us.anthropic.claude-haiku-4-5-20251001-v1:0 ;;
  *) echo "unknown seat: $SEAT" >&2; exit 2 ;;
esac

out() { aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue | [0]" --output text; }
BASE_URL=$(out InferenceBaseUrl | sed 's#/v1$##')

docker build -q -t agentcore-enduser -f containers/Dockerfile . >/dev/null

if [[ "${1:-}" == "verify" ]]; then set -- /home/enduser/gateway/verify-gateway.sh "$SEAT_MODEL" "$OTHER_MODEL"; fi
[[ $# -gt 0 ]] || set -- bash

TTY=(); [[ -t 0 ]] && TTY=(-t)
PASS_FILE="${GATEWAY_PASSWORD_FILE:-$HOME/.config/aws-claude-code-governance/$SEAT.pass}"
PASS_ARGS=()
if [[ -z "${GATEWAY_PASSWORD:-}" && -r "$PASS_FILE" ]]; then
  PASS_ARGS=(-v "$PASS_FILE:/run/gateway_password:ro" -e GATEWAY_PASSWORD_FILE=/run/gateway_password)
fi
docker run --rm -i "${TTY[@]}" --name "agentcore-user-$SEAT" \
  -e GATEWAY_BASE_URL="$BASE_URL" -e AGENTCORE_OIDC_DISCOVERY_URL="$(out DiscoveryUrl)" \
  -e AGENTCORE_OIDC_CLIENT_ID="$(out ClientId)" -e GATEWAY_USER="$GATEWAY_USER" -e SEAT_MODEL="$SEAT_MODEL" \
  ${GATEWAY_PASSWORD:+-e GATEWAY_PASSWORD} "${PASS_ARGS[@]}" \
  agentcore-enduser "$@"
