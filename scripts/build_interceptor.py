#!/usr/bin/env python3
"""Build the patched REQUEST interceptor package (phases 2-3).

The AWS sample ships its Lambda code inline in the CloudFormation template
(``ZipFile: |``), so extra modules cannot be imported from it. This script:

1. extracts the REQUEST function's inline code from the upstream template,
2. inserts two hooks at fixed anchors (aborts if an anchor is missing or
   duplicated, e.g. after an upstream change),
3. zips ``index.py`` + ``extensions/`` into ``build/request-interceptor.zip``.

Usage: python3 scripts/build_interceptor.py [--template upstream/cloudformation/standalone.yaml]
"""

from __future__ import annotations

import argparse
import re
import sys
import textwrap
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCE = "  RequestInterceptorFunction:\n"

IMPORT_ANCHOR = "import boto3\n\nddb = boto3.client(\"dynamodb\")\n"
IMPORT_PATCH = (
    "import boto3\n\n"
    "from extensions import gateway as _ext\n\n"
    "ddb = boto3.client(\"dynamodb\")\n"
    "_bedrock_rt = boto3.client(\"bedrock-runtime\")\n"
)

MODEL_ANCHOR = "    daily_spend, daily_cap, monthly_spend, monthly_cap = _lookup_state(user)\n"
MODEL_PATCH = (
    "    if ENFORCE and not _is_catalog:\n"
    "        _denied = _ext.model_check(headers, req.get(\"body\"))\n"
    "        if _denied:\n"
    "            log(\"budget_check\", level=\"warn\", request_id=req_id, path=path,\n"
    "                user=user, team=team, outcome=\"block_model_not_allowed\")\n"
    "            return _denied\n\n"
)

GUARD_ANCHOR = (
    "    log(\"budget_check\",\n"
    "        outcome=(\"allow_over_budget\" if limit_hit else \"allow\"),\n"
)
GUARD_PATCH = (
    "    if ENFORCE and not limit_hit and not _is_catalog:\n"
    "        _denied = _ext.guardrail_check(req.get(\"body\"), _bedrock_rt)\n"
    "        if _denied:\n"
    "            log(\"budget_check\", level=\"warn\", request_id=req_id, path=path,\n"
    "                user=user, team=team, outcome=\"block_guardrail\")\n"
    "            return _denied\n\n"
)


TAIL_ANCHOR = (
    "        limit_hit=limit_hit,\n"
    "        **log_common)\n"
    "    return _passthrough()\n"
)
# Claude Code's metadata.user_id is rejected by the bedrock-runtime Messages route: strip it.
TAIL_PATCH = (
    "        limit_hit=limit_hit,\n"
    "        **log_common)\n"
    "    if not _is_catalog:\n"
    "        _cleaned = _ext.strip_metadata(req.get(\"body\"))\n"
    "        if _cleaned:\n"
    "            return _cleaned\n"
    "    return _passthrough()\n"
)


def extract_inline_code(template: str) -> str:
    start = template.index(RESOURCE)
    block = template[start + len(RESOURCE):]
    nxt = re.search(r"^  [A-Za-z]+:\n", block, re.MULTILINE)
    block = block[: nxt.start()] if nxt else block
    marker = "        ZipFile: |\n"
    code = block[block.index(marker) + len(marker):]
    return textwrap.dedent(code)


def replace_once(code: str, anchor: str, new: str, before: bool) -> str:
    # the template is indented inside the handler; match on stripped anchors
    pattern = re.compile(r"^([ ]*)" + re.escape(anchor.lstrip()), re.MULTILINE)
    found = pattern.findall(code)
    if len(found) != 1:
        sys.exit(f"anchor found {len(found)} times (expected 1): {anchor.strip()[:60]!r}")
    indent = found[0]
    indented = textwrap.indent(new, indent[: len(indent) - 4] if len(indent) >= 4 else "")
    if before:
        return pattern.sub(lambda m: indented + m.group(0), code, count=1)
    return pattern.sub(lambda m: m.group(0) + indented, code, count=1)


def patch(code: str) -> str:
    if code.count(IMPORT_ANCHOR) != 1:
        sys.exit("import block not found exactly once (upstream changed?)")
    code = code.replace(IMPORT_ANCHOR, IMPORT_PATCH, 1)
    code = replace_once(code, MODEL_ANCHOR, MODEL_PATCH, before=True)
    code = replace_once(code, GUARD_ANCHOR, GUARD_PATCH, before=True)
    if code.count(TAIL_ANCHOR) != 1:
        sys.exit("tail anchor not found exactly once (upstream changed?)")
    code = code.replace(TAIL_ANCHOR, TAIL_PATCH, 1)
    return code


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--template", default=str(ROOT / "upstream/cloudformation/standalone.yaml"))
    parser.add_argument("--out", default=str(ROOT / "build/request-interceptor.zip"))
    args = parser.parse_args()

    template = Path(args.template).read_text()
    code = patch(extract_inline_code(template))
    compile(code, "index.py", "exec")  # syntax check

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    (out.parent / "index.py").write_text(code)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("index.py", code)
        for path in sorted((ROOT / "interceptor/extensions").glob("*.py")):
            zf.write(path, f"extensions/{path.name}")
    print(f"built {out} ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
