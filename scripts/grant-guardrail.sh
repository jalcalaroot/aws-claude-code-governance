#!/usr/bin/env bash
# Let the REQUEST interceptor role call ApplyGuardrail on THIS guardrail only. Phase 3.
# Creates an inline IAM policy: the account owner should review and run it.
set -euo pipefail
cd "$(dirname "$0")/.."
source .env.local

ROLE=$(aws cloudformation describe-stack-resource --region "$REGION" --stack-name "$STACK" \
  --logical-resource-id InterceptorRole --query StackResourceDetail.PhysicalResourceId --output text)
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
ARN="arn:aws:bedrock:${REGION}:${ACCOUNT}:guardrail/${GUARDRAIL_ID}"

echo "About to allow bedrock:ApplyGuardrail on ${ARN} for role ${ROLE}."
read -r -p "Continue? [y/N] " ok
[[ "$ok" == "y" ]] || exit 1

aws iam put-role-policy --role-name "$ROLE" --policy-name apply-guardrail \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"bedrock:ApplyGuardrail\",\"Resource\":\"${ARN}\"}]}"
echo "Done."
