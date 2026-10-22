#!/usr/bin/env bash
# Create the end users, their Cognito groups and per-user budget caps. Phase 1.
# GATEWAY_USERS in .env.local: "<user>:<group>:<email>:<daily USD>:<monthly USD> ..."
set -euo pipefail
cd "$(dirname "$0")/.."
source .env.local

POOL_ID=$(aws cloudformation describe-stack-resource --region "$REGION" --stack-name "$STACK" \
  --logical-resource-id UserPool --query StackResourceDetail.PhysicalResourceId --output text)
[[ -n "$POOL_ID" && "$POOL_ID" != "None" ]] || { echo "Could not find the user pool of stack $STACK"; exit 1; }
TABLE=$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='SpendTableName'].OutputValue | [0]" --output text)
echo "User pool: $POOL_ID, spend table: $TABLE"

for entry in $GATEWAY_USERS; do
  IFS=: read -r user group email daily monthly <<<"$entry"
  echo "== $user ($group) daily \$$daily monthly \$$monthly"

  aws cognito-idp create-group --region "$REGION" --user-pool-id "$POOL_ID" \
    --group-name "$group" >/dev/null 2>&1 || echo "Group $group already exists"

  aws cognito-idp admin-create-user --region "$REGION" --user-pool-id "$POOL_ID" \
    --username "$user" \
    --user-attributes Name=email,Value="$email" Name=email_verified,Value=true \
    >/dev/null 2>&1 || echo "User $user already exists"

  aws cognito-idp admin-add-user-to-group --region "$REGION" --user-pool-id "$POOL_ID" \
    --username "$user" --group-name "$group"

  # per-user caps override the stack defaults (row schema of the sample's spend table)
  aws dynamodb update-item --region "$REGION" --table-name "$TABLE" \
    --key "{\"pk\":{\"S\":\"USER#$user\"}}" \
    --update-expression "SET daily_cap_usd = :d, monthly_cap_usd = :m" \
    --expression-attribute-values "{\":d\":{\"N\":\"$daily\"},\":m\":{\"N\":\"$monthly\"}}"
done
echo "Done. Each user received a temporary password by email."
