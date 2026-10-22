#!/usr/bin/env bash
# Read-only matrix of which Claude models this account can actually call, through both endpoints:
#   runtime = bedrock-runtime Converse (inference profile)   mantle = bedrock-mantle Messages API (what the gateway uses)
# Sends one 16-token request per model and endpoint (a few cents at most). Uses your current AWS credentials.
set -euo pipefail
cd "$(dirname "$0")/.."
source .env.local 2>/dev/null || true
REGION="${REGION:-us-east-1}"

# label | bedrock-runtime model/profile id | bedrock-mantle model id ("-" when Mantle does not list it)
MODELS=(
  "Haiku 4.5|us.anthropic.claude-haiku-4-5-20251001-v1:0|anthropic.claude-haiku-4-5"
  "Sonnet 4.5|us.anthropic.claude-sonnet-4-5-20250929-v1:0|-"
  "Sonnet 4.6|us.anthropic.claude-sonnet-4-6|-"
  "Sonnet 5|us.anthropic.claude-sonnet-5|anthropic.claude-sonnet-5"
  "Opus 4.5|us.anthropic.claude-opus-4-5-20251101-v1:0|-"
  "Opus 4.6|us.anthropic.claude-opus-4-6-v1|-"
  "Opus 4.7|us.anthropic.claude-opus-4-7|anthropic.claude-opus-4-7"
  "Opus 4.8|us.anthropic.claude-opus-4-8|anthropic.claude-opus-4-8"
  "Opus 5|us.anthropic.claude-opus-5|anthropic.claude-opus-5"
  "Opus 5.5|us.anthropic.claude-opus-5-5|anthropic.claude-opus-5-5"
  "Sonnet 5.5|us.anthropic.claude-sonnet-5-5|-"
  "Haiku 5.5|us.anthropic.claude-haiku-5-5|-"
  "Fable 5.1|us.anthropic.claude-fable-5-1|-"
  "Fable 5|us.anthropic.claude-fable-5|anthropic.claude-fable-5"
)

eval "$(aws configure export-credentials --format env)"
printf '| Model | bedrock-runtime | bedrock-mantle |\n|---|---|---|\n'
for entry in "${MODELS[@]}"; do
  IFS='|' read -r label rt mantle <<<"$entry"
  if aws bedrock-runtime converse --region "$REGION" --model-id "$rt" \
       --messages '[{"role":"user","content":[{"text":"Say hello."}]}]' \
       --inference-config maxTokens=16 >/dev/null 2>&1; then r="works"; else r="denied or unavailable"; fi
  if [[ "$mantle" == "-" ]]; then m="not listed"; else
    code=$(curl -s -o /dev/null -w '%{http_code}' -m 60 \
      --aws-sigv4 "aws:amz:${REGION}:bedrock-mantle" --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
      -H "x-amz-security-token: ${AWS_SESSION_TOKEN:-}" -H "anthropic-version: bedrock-2023-05-31" -H "content-type: application/json" \
      "https://bedrock-mantle.${REGION}.api.aws/anthropic/v1/messages" \
      -d "{\"model\":\"$mantle\",\"max_tokens\":16,\"messages\":[{\"role\":\"user\",\"content\":\"Say hello.\"}]}")
    if [[ "$code" == "200" ]]; then m="works"; else m="HTTP $code"; fi
  fi
  printf '| %s | %s | %s |\n' "$label" "$r" "$m"
done
