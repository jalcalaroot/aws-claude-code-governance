# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-22

First public release.

### Added
- AgentCore Gateway in front of Amazon Bedrock for Claude Code, built on the AWS sample `sample-agentcore-gateway-usage-interceptor` (pinned to a commit), with Cognito sign-in (PKCE and password/SRP).
- **REQUEST interceptor extensions**: model allowlist per Cognito group (one model per seat), `ApplyGuardrail` on the prompt, and removal of Claude Code's `metadata.user_id` for the bedrock-runtime route; packaged by `scripts/build_interceptor.py` without forking the sample.
- **Per-user budgets** (daily and monthly) backed by the sample's DynamoDB spend ledger, and a price table (`config/price-table.json`).
- **Second inference target** on `bedrock-runtime` (Messages API) so models the account can use are served when the Mantle quotas are at 0.
- **AWS WAF** web ACL (`infra/waf.yaml`): per-IP rate limit, IP reputation list, known-bad-inputs and common rule sets, logging with credentials redacted, alarms.
- **End-user containers** (`containers/Dockerfile`, `scripts/run-user.sh`) with Claude Code and no AWS credentials; password read from a read-only file.
- Scripts to deploy, create users, verify the gateway, check model access and quotas, and clean up; 26 tests, CI, gitleaks, Dependabot and a security policy.
- Documentation: architecture decisions, risks, model availability, SCP vs Guardrails, network access, and the evidence of each verification (`evidence/`).

### Verified
Authentication, per-seat model entitlement, per-user budgets (including a block with real spend), the guardrail (7 of 7 attacks blocked, 7 of 8 normal prompts passed), the WAF (known-bad-input payload blocked), and Claude Code answering through the gateway from two containers at the same time. See [docs/verification.md](docs/verification.md).

### Known limits
- Sonnet 5 and Opus 5.5 through Mantle wait for Service Quotas increases.
- The guardrail does not scan tool results, and prompts that dictate the exact answer can be flagged.
- The WAF common rule set only counts until its counted requests are reviewed.
- SCP policies are references: they could not be tested without AWS Organizations.

Details in [docs/risks.md](docs/risks.md).
