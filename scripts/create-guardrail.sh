#!/usr/bin/env bash
# Create the input guardrail and publish version 1. Phase 3.
set -euo pipefail
cd "$(dirname "$0")/.."
source .env.local

GR_ID=$(aws bedrock create-guardrail --region "$REGION" \
  --cli-input-json file://policies/guardrail.json --query guardrailId --output text)
GR_VERSION=$(aws bedrock create-guardrail-version --region "$REGION" \
  --guardrail-identifier "$GR_ID" --query version --output text)

echo "GUARDRAIL_ID=$GR_ID" >> .env.local
echo "GUARDRAIL_VERSION=$GR_VERSION" >> .env.local
echo "Guardrail $GR_ID version $GR_VERSION created and saved to .env.local"
