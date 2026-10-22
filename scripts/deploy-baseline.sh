#!/usr/bin/env bash
# Deploy the AWS sample stack with low-cost parameters. Phase 1.
# If the account's Lambda concurrency limit is below 1000 (new accounts: 10) the
# sample's reserved-concurrency settings cannot be created, so a copy of the
# template without them is deployed (scripts/prepare_template.py, ADR-010).
set -euo pipefail
cd "$(dirname "$0")/.."
source .env.local

LIMIT=$(aws lambda get-account-settings --region "$REGION" --query AccountLimit.ConcurrentExecutions --output text)
TEMPLATE=upstream/cloudformation/standalone.yaml
if (( LIMIT < 1000 )); then
  echo "Lambda concurrency limit is $LIMIT: deploying the template without reserved concurrency."
  python3 scripts/prepare_template.py
  TEMPLATE=build/standalone.yaml
fi

echo "About to deploy stack '$STACK' in $REGION (ProvisionedConcurrency=0, daily \$$DAILY_BUDGET_USD, monthly \$$MONTHLY_BUDGET_USD) from $TEMPLATE."
read -r -p "Continue? [y/N] " ok
[[ "$ok" == "y" ]] || exit 1

PRICE_TABLE=$(python3 -c 'import json;print(json.dumps(json.load(open("config/price-table.json")),separators=(",",":")))')

aws cloudformation deploy --region "$REGION" \
  --stack-name "$STACK" \
  --template-file "$TEMPLATE" \
  --s3-bucket "$CFN_BUCKET" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    DomainPrefix="$DOMAIN_PREFIX" \
    DailyBudgetUsd="$DAILY_BUDGET_USD" \
    MonthlyBudgetUsd="$MONTHLY_BUDGET_USD" \
    ProvisionedConcurrency=0 \
    PriceTableJson="$PRICE_TABLE" \
    RolloverTimezone=America/Argentina/Buenos_Aires

aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
  --query "Stacks[0].Outputs" --output table
