# Security Policy

This repository is a reference implementation (AWS) of Claude Code access to Amazon Bedrock through an AgentCore Gateway. There are no supported version branches: only `main` is maintained.

## Reporting a vulnerability

If you find a security issue (a permissive default, a leaked credential in the history, a way around the budget, the model allowlist, the guardrail or the WAF) please report it privately with [GitHub's private vulnerability reporting](../../security/advisories/new) instead of opening a public issue.

## What this repository does not contain

No account IDs, gateway or Cognito identifiers, domain prefixes, e-mail addresses, passwords or tokens. Deployment values live in `.env.local` (git-ignored) and in the stack outputs of the account. Secret scanning and push protection are enabled, gitleaks runs on every push and pull request, and `pre-commit` runs it locally.

## Scope

- The code, scripts, container and CloudFormation template in this repository.

Out of scope: vulnerabilities in the AWS services, in the AWS sample this builds on, or in Claude Code: please report those to their maintainers.
