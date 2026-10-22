#!/usr/bin/env bash
# Clone the AWS sample into upstream/ (gitignored) at the pinned commit. Phase 1.
# The patch in scripts/build_interceptor.py is written against this commit;
# bump UPSTREAM_SHA only after re-running the tests.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=https://github.com/aws-samples/sample-agentcore-gateway-usage-interceptor.git
UPSTREAM_SHA=d79bd57f6d5461b81f862630961b72c49967a4f9

if [[ ! -d upstream/.git ]]; then
  echo "Cloning $REPO into upstream/"
  git clone "$REPO" upstream
fi
git -C upstream fetch --quiet origin
git -C upstream checkout --quiet "$UPSTREAM_SHA"
echo "Upstream pinned at commit: $(git -C upstream rev-parse --short HEAD)"
