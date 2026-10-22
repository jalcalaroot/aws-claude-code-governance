# CLAUDE.md

Context for Claude Code working in this repository. Read this first, then `docs/phases.md`.

## What this project is

A solution that puts Amazon Bedrock **AgentCore Gateway** in front of Bedrock so a **Claude Code** user reaches the model only through the gateway, with identity, per-user budgets, a per-group model allowlist and Bedrock Guardrails enforced on every request. AWS only, no Azure.

The baseline is the AWS sample `aws-samples/sample-agentcore-gateway-usage-interceptor` (CloudFormation, MIT-0). We **extend** its REQUEST interceptor by patching its inline Lambda at build time (ADR-005); we do not rewrite or fork the sample. It is pinned to a commit (ADR-006).

## Current phase

Phases 1 to 3 and 7 (AWS WAF, infra/waf.yaml) deployed; verified end to end on 2026-10-22 through a second inference target on bedrock-runtime (Haiku 4.5, Sonnet 4.6); Mantle quota increases for Sonnet 5 and Opus 5.5 still pending (docs/model-access-request.md). Phase 4 (managed settings) not applied; phase 5 deferred.

## Hard constraints

- **One interceptor per type.** A gateway accepts at most one REQUEST and one RESPONSE interceptor. Budget check, model allowlist and guardrail must live in the same REQUEST Lambda.
- **Interceptors must be idempotent.** The gateway may retry them. Never double-count spend.
- **Never log request bodies, prompts or headers.** They contain company code and, with `passRequestHeaders`, bearer tokens.
- **The gateway user holds no AWS credentials.** Only a Cognito token for the gateway.
- **Cost discipline:** Haiku only, `ProvisionedConcurrency=0`, low budgets, destroy after each session unless told otherwise.
- **No secrets in the repo.** Stack outputs, tokens and account IDs go in `.env.local` (gitignored).
- **Ask before** any `aws cloudformation deploy`, `delete-stack`, IAM policy change, or anything else that creates permissions.
- **No AWS Organizations** in this account: no SCPs. Phase 5 is deferred.

## Key facts (verified against official docs, Oct 2026)

- Through an AgentCore Gateway inference target, Bedrock records the **gateway's IAM role** as caller; on the Mantle endpoint, IAM principal attribution, request metadata and application inference profiles are not supported. Per-user identity therefore comes only from the interceptors.
- Claude Code has no command-based bearer token helper for this gateway: export `ANTHROPIC_AUTH_TOKEN` from `auth-helper/oidc-token.py` (sample) before each session, and set `ANTHROPIC_BASE_URL` in `~/.claude/settings.json` (without the `/v1` suffix). See `config/claude-code/settings.json`.
- Interceptors only receive request headers if `passRequestHeaders` is true.
- Cognito access tokens carry `username` (not `email`) and `cognito:groups`.
- Bedrock Guardrails filters **content**; SCPs/IAM control **actions**. Different jobs.

## Open questions

Answered from the sample's template: see `docs/decisions.md` ("Answers to the open questions"). Still open: streaming output filtering (4, untested) and the exact Mantle actions for the SCP (5, test in phase 5).

## Code layout

- `interceptor/extensions/` — `model_allowlist.py`, `guardrail.py` (pure functions) and `gateway.py` (glue to the sample's event/response shape). No AWS calls at import time; testable with `pytest` and no network.
- `scripts/build_interceptor.py` builds the patched package; `scripts/publish-interceptor.sh` deploys it (needs approval).
- `config/claude-code/` — `managed-settings.json` (machine policy) and `settings.json` (user connection template).
- `policies/` — SCP JSON and guardrail definition.
- `scripts/` — bash, `set -euo pipefail`, read config from `.env.local`.

## Conventions

- Python 3.12, `boto3`, type hints, `pytest`. Run `pytest interceptor/tests` before every commit.
- Bash scripts are idempotent and print what they are about to do.
- Every success criterion in `docs/verification.md` gets evidence in `evidence/` (command, output, screenshot) when it passes.
- Commit messages: `phase-N: <what>`.
- When a decision is made or a question answered, update `docs/decisions.md` and this file.

## How to work a phase

1. Read the phase checklist in `docs/phases.md`.
2. Read the relevant upstream code or doc page before writing anything.
3. Propose the change, wait for approval on anything that deploys.
4. Implement, test, collect evidence, tick the checklist, update "Current phase".
