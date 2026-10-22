#!/usr/bin/env bash
# Deploy the AWS WAF web ACL and associate it with the gateway (phase 7). Idempotent.
# Usage: scripts/deploy-waf.sh [enforce-other] [enforce-common]    (each "true" or "false", default false)
# Starts in COUNT mode: review the counted requests before enforcing (docs/phases.md).
set -euo pipefail
cd "$(dirname "$0")/.."
source .env.local

OTHER="${1:-false}"; COMMON="${2:-false}"
GW=$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='GatewayId'].OutputValue | [0]" --output text)

echo "About to deploy stack '${STACK}-waf' in $REGION for gateway $GW (enforce other rules: $OTHER, enforce common rules: $COMMON)."
echo "It needs the wafv2 and bedrock-agentcore WebACL permissions; a web ACL with 4 rules costs roughly 9 USD/month plus 0.60 USD per million requests and log ingestion."
read -r -p "Continue? [y/N] " ok
[[ "$ok" == "y" ]] || exit 1

aws cloudformation deploy --region "$REGION" --stack-name "${STACK}-waf" \
  --template-file infra/waf.yaml --no-fail-on-empty-changeset \
  --parameter-overrides GatewayId="$GW" EnforceOtherRules="$OTHER" EnforceCommonRules="$COMMON"

aws wafv2 get-web-acl-for-resource --region "$REGION" \
  --resource-arn "arn:aws:bedrock-agentcore:${REGION}:$(aws sts get-caller-identity --query Account --output text):gateway/${GW}" \
  --query 'WebACL.Name' --output text
