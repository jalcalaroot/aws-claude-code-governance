#!/usr/bin/env bash
# Destroy everything, including what the sample retains (DeletionPolicy: Retain):
# KMS key, spend table and the (versioned) rollover archive bucket. Phase 6.
set -euo pipefail
cd "$(dirname "$0")/.."
source .env.local

out() { aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue | [0]" --output text; }
res() { aws cloudformation describe-stack-resource --region "$REGION" --stack-name "$STACK" \
  --logical-resource-id "$1" --query StackResourceDetail.PhysicalResourceId --output text; }

# Read the physical IDs BEFORE the stack disappears.
KEY_ARN=$(out InterceptorDataKeyArn)
SPEND_TABLE=$(out SpendTableName)
ARCHIVE_BUCKET=$(res RolloverArchiveBucket)

echo "About to delete: stack '$STACK', table '$SPEND_TABLE', KMS key '$KEY_ARN' (7-day window), bucket '$ARCHIVE_BUCKET' (all versions), guardrail '${GUARDRAIL_ID:-none}'."
read -r -p "This cannot be undone. Type the stack name to confirm: " ok
[[ "$ok" == "$STACK" ]] || exit 1

aws cloudformation delete-stack --region "$REGION" --stack-name "$STACK"
aws cloudformation wait stack-delete-complete --region "$REGION" --stack-name "$STACK"

aws dynamodb delete-table --region "$REGION" --table-name "$SPEND_TABLE" || echo "table not deleted"
if [[ -n "$ARCHIVE_BUCKET" && "$ARCHIVE_BUCKET" != "None" ]]; then
  # versioned bucket: remove every version and delete marker, then the bucket
  python3 - "$ARCHIVE_BUCKET" "$REGION" <<'PY' || echo "bucket not deleted"
import sys, boto3
b = boto3.resource("s3", region_name=sys.argv[2]).Bucket(sys.argv[1])
b.object_versions.delete()
b.delete()
PY
fi
# the key encrypts the bucket: schedule its deletion after the bucket is gone
aws kms schedule-key-deletion --region "$REGION" --key-id "$KEY_ARN" --pending-window-in-days 7 || echo "key not scheduled"
if [[ -n "${GUARDRAIL_ID:-}" ]]; then
  aws bedrock delete-guardrail --region "$REGION" --guardrail-identifier "$GUARDRAIL_ID" || echo "guardrail not deleted"
fi
echo "Cleanup finished. Check the 'not deleted' lines above, if any."
