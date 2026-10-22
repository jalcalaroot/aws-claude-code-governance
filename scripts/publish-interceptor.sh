#!/usr/bin/env bash
# Deploy the patched REQUEST interceptor (phases 2-3): upload the zip, set the
# env vars, publish a version and move the :live alias the gateway points at.
# Needs .env.local with MODEL_ALLOWLIST_JSON; GUARDRAIL_ID/VERSION after phase 3.
# NOTE: re-running `cloudformation deploy` restores the template's inline code;
# run this script again afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
source .env.local

FN="${STACK}-budget-check"
python3 scripts/build_interceptor.py

echo "About to update Lambda '$FN' in $REGION: new code, env MODEL_ALLOWLIST_JSON${GUARDRAIL_ID:+, GUARDRAIL_ID=$GUARDRAIL_ID}, then publish a version and move alias 'live'."
read -r -p "Continue? [y/N] " ok
[[ "$ok" == "y" ]] || exit 1

aws lambda update-function-code --region "$REGION" --function-name "$FN" \
  --zip-file fileb://build/request-interceptor.zip >/dev/null
aws lambda wait function-updated-v2 --region "$REGION" --function-name "$FN"

# merge env vars: keep the sample's, add ours
CURRENT=$(aws lambda get-function-configuration --region "$REGION" --function-name "$FN" \
  --query Environment.Variables --output json)
MERGED=$(MODEL_ALLOWLIST_JSON="${MODEL_ALLOWLIST_JSON:-}" GUARDRAIL_ID="${GUARDRAIL_ID:-}" \
  GUARDRAIL_VERSION="${GUARDRAIL_VERSION:-}" CURRENT="$CURRENT" python3 - <<'PY'
import json, os
env = json.loads(os.environ["CURRENT"])
for key in ("MODEL_ALLOWLIST_JSON", "GUARDRAIL_ID", "GUARDRAIL_VERSION"):
    if os.environ.get(key):
        env[key] = os.environ[key]
print(json.dumps({"Variables": env}))
PY
)
# timeout 5 s (sample) -> 10 s: ApplyGuardrail adds a network call. Measure it (risks.md #1).
aws lambda update-function-configuration --region "$REGION" --function-name "$FN" \
  --environment "$MERGED" --timeout 10 >/dev/null
aws lambda wait function-updated-v2 --region "$REGION" --function-name "$FN"

VERSION=$(aws lambda publish-version --region "$REGION" --function-name "$FN" --query Version --output text)
aws lambda update-alias --region "$REGION" --function-name "$FN" --name live --function-version "$VERSION" >/dev/null
echo "Alias 'live' of $FN now points at version $VERSION."

# The RESPONSE interceptor reads PRICE_TABLE from its own environment. A stack update changes the
# function's $LATEST, but the gateway calls the :live alias, so republish it as well.
RFN="${STACK}-usage-record"
aws lambda wait function-updated-v2 --region "$REGION" --function-name "$RFN"
RVERSION=$(aws lambda publish-version --region "$REGION" --function-name "$RFN" --query Version --output text)
aws lambda update-alias --region "$REGION" --function-name "$RFN" --name live --function-version "$RVERSION" >/dev/null
echo "Alias 'live' of $RFN now points at version $RVERSION."
