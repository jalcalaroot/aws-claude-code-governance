# Phases

Each phase builds on the previous one. Tick items as they are done and add evidence to `evidence/`.

## Phase 1 — Baseline: deploy the AWS sample as-is

Status 2026-10-21: stack deployed (template without reserved concurrency, ADR-010), users created, token obtained from the end-user container. The model call is blocked by account-level Mantle access ([model-availability.md](model-availability.md)).

Goal: Claude Code works through AgentCore Gateway and spend is recorded per user.

- [ ] Clone the sample at the pinned commit into `upstream/` (gitignored): `scripts/fetch-upstream.sh`
- [ ] Read the sample's `cloudformation/standalone.yaml`, interceptor code and `auth-helper/README.md`
- [ ] Copy `.env.example` to `.env.local` and fill region, stack name, CFN bucket, Cognito domain prefix
- [ ] Deploy with `ProvisionedConcurrency=0`, `DailyBudgetUsd=2`, `MonthlyBudgetUsd=10`: `scripts/deploy-baseline.sh`
- [ ] Create the two end users, their groups and caps (`finanzas-user` / `finanzas-builders`, `platform-user` / `platform-engineers`): `scripts/create-users.sh`
- [ ] First sign-in with the auth helper, then `source scripts/claude-token.sh`
- [ ] Copy `config/claude-code/settings.json` to `~/.claude/settings.json` (fill the gateway URL)
- [ ] Run a short Claude Code session and verify: interceptor logs, DynamoDB spend row, CloudWatch `AgentCore/InferenceUsage` metrics
- [x] Run one container per user and sign in as described in the README (End users)
- [ ] Run `scripts/verify-gateway.sh` as each user and record the results
- [ ] Record token lifetime (24 h access, 30 d refresh) and what happens when it expires mid-session

## Phase 2 — Model allowlist per group

Goal: `finanzas-builders` can only use Haiku.

- [ ] Confirm where `cognito:groups` and the request `model` appear in the REQUEST interceptor payload
- [x] Payload shape confirmed (decisions.md, open question 1)
- [x] Extension wired by `scripts/build_interceptor.py` (hook before the budget lookup); allowlist from `MODEL_ALLOWLIST_JSON`
- [ ] Unit and end-to-end tests pass: `pytest interceptor/tests` (after `fetch-upstream.sh`)
- [ ] Set `MODEL_ALLOWLIST_JSON` in `.env.local`, then `scripts/publish-interceptor.sh`
- [ ] Test: Haiku works, Sonnet returns 403 with a clear error code (`MODEL_NOT_ALLOWED`)

## Phase 3 — Guardrail on the prompt

Goal: prompt injection and PII are blocked before the model.

- [ ] Create the guardrail from `policies/guardrail.json`: `scripts/create-guardrail.sh`
- [x] Grant the interceptor role `bedrock:ApplyGuardrail` on that guardrail only: `scripts/grant-guardrail.sh` (creates an IAM policy: owner runs it)
- [ ] Publish with the guardrail env vars: `scripts/publish-interceptor.sh` (hook runs after the budget check; Lambda timeout raised to 10 s)
- [x] Scanned content decided: last user turn without `<system-reminder>`, tail kept
- [ ] Measure added latency and `ApplyGuardrail` cost per request
- [ ] Test: a direct injection prompt returns 403 (`GUARDRAIL_BLOCKED`); a normal prompt passes
- [ ] Document the indirect-injection gap (instructions hidden in files or tool results)
- [ ] Investigate whether output can be filtered given streaming (open question 4)

## Phase 4 — Claude Code local policy

Goal: the agent cannot be switched to unsafe modes or read secrets.

- [ ] Install `config/claude-code/managed-settings.json` at `/etc/claude-code/managed-settings.json` (Linux, needs sudo)
- [ ] Verify with `/status` and `/permissions` inside Claude Code
- [ ] Test: `claude --dangerously-skip-permissions` is refused; reading `.env` is denied; `aws ... delete-*` is denied

## Phase 5 (deferred) — Make the gateway mandatory

**Not applicable for now:** the SCP route needs AWS Organizations, and this account is standalone (decided 2026-10-20). `policies/scp-deny-direct-bedrock.json` stays as a reference for a future organization.

Single-account substitute, if the bypass question matters later: attach an IAM deny (or permissions boundary) for `bedrock:Invoke*`, `Converse*` and the `bedrock-mantle` actions to the people or roles that should only use the gateway. It controls **identities in this account only**; it does not stop a user who can edit their own policies.

- [ ] (later) Decide between IAM deny/boundary and a real SCP once an organization exists
- [ ] (later) Test T9: a direct `invoke-model` / Mantle call as a restricted identity is denied

## Phase 6 (optional) — Terraform port

- [ ] Port the stack to Terraform (check AWS provider support for AgentCore Gateway resources first)
- [ ] Document the results and findings in the README
- [ ] Destroy everything: `scripts/cleanup.sh`

## Phase 7 — AWS WAF in front of the gateway

Status 2026-10-22: **deployed** (`infra/waf.yaml`, `scripts/deploy-waf.sh`); evidence in [evidence/2026-10-22-waf.md](../evidence/2026-10-22-waf.md).

Goal: filter abusive or malformed traffic before it reaches the authorizer, the interceptors and Bedrock, and add a volumetric guard that the interceptors do not provide.

Facts from the documentation ([announcement](https://aws.amazon.com/about-aws/whats-new/2026/06/aws-waf-amazon-bedrock-agentcore/), [Protecting your gateway with AWS WAF](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-waf.html)):

- One **regional** web ACL per gateway, in the same Region; CloudFront (global) web ACLs are not supported; one ACL can serve several gateways. The gateway must be `READY`.
- Association: `aws wafv2 associate-web-acl --web-acl-arn <acl> --resource-arn <gateway arn>` (the template does it with `AWS::WAFv2::WebACLAssociation`); disassociate before deleting the gateway.
- Permissions needed by the person associating: `wafv2:AssociateWebACL`, `DisassociateWebACL`, `GetWebACLForResource`, `ListResourcesForWebACL` and the matching `bedrock-agentcore:Gateway*WebACL` actions.
- Failure mode: `FAIL_CLOSE` by default (kept). A blocked request on an HTTP or inference target returns HTTP 403. Metrics `WafBlocks`, `WafFailOpens`, `WafFailCloses` in `AWS/Bedrock-AgentCore`. Limit: 100 web ACL associations per account.

What was built:

- [x] Web ACL `<stack>-waf` with four rules: per-IP rate limit (2,000 requests per 5 minutes), AWS IP reputation list, AWS known-bad-inputs, AWS common rule set (its `SizeRestrictions_BODY` rule overridden to COUNT, see below)
- [x] Everything started in COUNT mode; the known-bad-inputs group counted a log4j-style payload (`Log4JRCE_BODY`) and the common set counted Claude Code's own requests (`SizeRestrictions_BODY`: prompts routinely exceed 8 KB)
- [x] Enforced: rate limit, IP reputation and known-bad-inputs (`scripts/deploy-waf.sh true false`); the same payload then returns 403 `Request blocked by WAF`, normal requests and Claude Code still work
- [x] Logging to CloudWatch Logs with `authorization`, `cookie` and `x-api-key` redacted
- [x] Alarms on `WafFailCloses`, `WafFailOpens` and a `WafBlocks` spike (no notification action yet)
- [ ] Review the counted requests of the common rule set over normal use (code in prompts can trigger the XSS or file-inclusion rules) and then enforce it: `scripts/deploy-waf.sh true true` (the size rule stays in COUNT)
- [ ] Attach an SNS topic to the alarms
- [ ] Decide whether to restrict by source IP (IP set) once the users' networks are known
- [ ] Check the WAF pricing page against the real bill after a month (the estimate is about 9 USD per month for the four rules plus 0.60 USD per million requests and log ingestion)
