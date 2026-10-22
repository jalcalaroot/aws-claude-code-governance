#!/usr/bin/env bash
# Read-only: applied vs default quota for the Claude models (bedrock-mantle endpoint and the
# bedrock-runtime cross-region/global tokens per minute), plus the state of any increase request. An applied value of 0 is why Mantle answers "not available for this account".
set -euo pipefail
cd "$(dirname "$0")/.."
source .env.local 2>/dev/null || true
REGION="${REGION:-us-east-1}"

printf '| Quota | Applied | Default |\n|---|---|---|\n'
aws service-quotas list-service-quotas --service-code bedrock --region "$REGION" --max-items 1000 \
  --query "Quotas[?contains(QuotaName,'Claude') && (contains(QuotaName,'bedrock-mantle') || contains(QuotaName,'Cross-region model inference tokens per minute'))].[QuotaCode,QuotaName,Value]" --output text |
while IFS=$'\t' read -r code name value; do
  default=$(aws service-quotas get-aws-default-service-quota --service-code bedrock --quota-code "$code" \
    --region "$REGION" --query Quota.Value --output text 2>/dev/null || echo "n/a")
  printf '| %s | %s | %s |\n' "${name#\[bedrock-mantle endpoint\] }" "$value" "$default"
done | sort

echo
echo "Increase requests:"
aws service-quotas list-requested-service-quota-change-history --service-code bedrock --region "$REGION" \
  --query "RequestedQuotas[?contains(QuotaName,'Claude')].[QuotaName,DesiredValue,Status,Created]" --output text |
  sed 's/\[bedrock-mantle endpoint\] //' | sort
