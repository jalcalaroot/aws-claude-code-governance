#!/usr/bin/env bash
# Add a second inference target to the gateway that sends the Anthropic Messages API to bedrock-runtime
# (https://bedrock-runtime.<region>.amazonaws.com/anthropic/v1/messages), signed with the gateway role.
# Needed for the models the account can use on bedrock-runtime but that bedrock-mantle does not serve.
# Idempotent: does nothing if a target named "bedrock-runtime" exists. Asks before creating it.
set -euo pipefail
cd "$(dirname "$0")/.."
source .env.local

# model IDs exactly as clients send them (inference profile IDs on the Messages route)
MODELS=("us.anthropic.claude-sonnet-4-6" "us.anthropic.claude-haiku-4-5-20251001-v1:0")

GW=$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='GatewayId'].OutputValue | [0]" --output text)
EXISTING=$(aws bedrock-agentcore-control list-gateway-targets --gateway-identifier "$GW" --region "$REGION" \
  --query "items[?name=='bedrock-runtime'].targetId | [0]" --output text)
if [[ -n "$EXISTING" && "$EXISTING" != "None" ]]; then echo "Target bedrock-runtime already exists ($EXISTING)"; exit 0; fi

MODELS_JSON=$(printf '%s\n' "${MODELS[@]}" | python3 -c 'import sys,json;print(json.dumps([{"model":l.strip()} for l in sys.stdin if l.strip()]))')
CONFIG=$(MODELS_JSON="$MODELS_JSON" REGION="$REGION" python3 -c 'import os,json
print(json.dumps({"inference":{"provider":{"endpoint":f"https://bedrock-runtime.{os.environ[\"REGION\"]}.amazonaws.com","operations":[{"path":"/v1/messages","providerPath":"/anthropic/v1/messages","models":json.loads(os.environ["MODELS_JSON"])}]}}}))')

echo "About to add target 'bedrock-runtime' to gateway $GW with models: ${MODELS[*]}"
read -r -p "Continue? [y/N] " ok
[[ "$ok" == "y" ]] || exit 1

aws bedrock-agentcore-control create-gateway-target --gateway-identifier "$GW" --region "$REGION" \
  --name bedrock-runtime --description "Anthropic Messages API on bedrock-runtime" \
  --target-configuration "$CONFIG" \
  --credential-provider-configurations '[{"credentialProviderType":"GATEWAY_IAM_ROLE"}]' \
  --query '[targetId,status]' --output text
