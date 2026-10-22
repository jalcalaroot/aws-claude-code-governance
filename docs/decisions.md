# Architecture decisions

## ADR-001 — Use AgentCore Gateway (AWS-managed)

**Decision:** AgentCore Gateway with an inference target to Bedrock.

**Alternatives considered:**

| | AgentCore Gateway | LiteLLM (AWS guidance) | Custom gateway |
|---|---|---|---|
| Operated by | AWS | You (ECS or EKS) | You |
| Multiple providers | Yes | Yes, the broadest | What you build |
| Per-user budgets | With interceptors | Built-in | What you build |
| Guardrails | In the interceptor | Built-in for all providers | In your code |
| MCP tools on the same gateway | Yes | Not its focus | What you build |
| Operational effort | Low | Medium-high | High |

Also considered: Anthropic's Claude apps gateway (self-hosted, deepest Claude Code governance, per-group managed settings without MDM). Out of scope because this design uses the AWS-managed option.

**Why:** lowest operational load, and the same gateway can later front MCP tools.

**Trade-off:** per-user identity, budgets, model allowlist and guardrails are code we maintain in Lambda interceptors, not configuration.

## ADR-002 — Extend the AWS sample instead of building from scratch

**Decision:** Phase 1 deploys `aws-samples/sample-agentcore-gateway-usage-interceptor` unchanged; later phases extend its REQUEST interceptor.

**Why:** it already provides Cognito, the gateway, both interceptors, the DynamoDB ledger, rollover and a tested Claude Code wiring. Fastest path to a validated baseline.

**Trade-off:** CloudFormation instead of Terraform. A Terraform port is phase 6.

## ADR-003 — Identity provider: Cognito

**Decision:** Cognito user pool from the sample.

**Why:** AWS-only scope; Entra ID access is no longer available. The gateway's `CUSTOM_JWT` authorizer accepts any OIDC IdP, so switching later is a discovery URL and client ID change.

## ADR-004 — Guardrail scans the prompt in the REQUEST interceptor

**Decision:** call `ApplyGuardrail` with `source=INPUT` on the latest user turn, inside the REQUEST interceptor.

**Why:** only one REQUEST interceptor is allowed; scanning before the model call is where blocking is useful.

**Known gap:** indirect prompt injection arrives through tool results and file contents, which this does not scan. Output filtering is deferred because Claude Code streams responses.

## ADR-005 — Package the extensions by patching the sample's inline Lambda

**Context:** the sample ships the REQUEST Lambda inline in the template (`ZipFile: |`), so `import extensions` cannot work from the template itself.

**Decision:** `scripts/build_interceptor.py` extracts the inline code from the pinned upstream template, inserts two hooks at fixed anchors (aborts if an anchor is missing or duplicated), and zips it with `interceptor/extensions/`. `scripts/publish-interceptor.sh` uploads it with `update-function-code`, merges the env vars, publishes a version and moves the `live` alias (the gateway is attached to the alias). The upstream template is not modified.

**Why:** keeps the sample untouched and upgradable; the patch is 20 lines and covered by an end-to-end test that runs the patched handler with stubbed AWS clients (`interceptor/tests/test_patched_handler.py`).

**Trade-offs:** re-running `cloudformation deploy` restores the template's inline code (run the publish script again); the anchors break if upstream changes (hence ADR-006).

## ADR-006 — Pin the upstream sample to a commit

**Decision:** `scripts/fetch-upstream.sh` checks out `d79bd57f6d5461b81f862630961b72c49967a4f9` (aws-samples/sample-agentcore-gateway-usage-interceptor, last push 2026-08-06). Bump it only after re-running `pytest`.

## ADR-007 — Failure modes

| Check | On error | Why |
|---|---|---|
| Model allowlist (`MODEL_ALLOWLIST_JSON` set but invalid) | Fail closed: 503 `ALLOWLIST_MISCONFIGURED` | A broken policy must not become "allow all" |
| Model allowlist (variable unset) | Check skipped; the sample's global price-table allowlist still applies | Phase 1 works without extensions |
| Guardrail call fails | Fail closed: 503 `GUARDRAIL_UNAVAILABLE` | Proposed in ADR-004 |
| Budget lookup fails (sample behavior) | Fail open with default caps | Inherited; revisit if spend must be hard-capped |
| Identity stash fails (sample behavior) | Fail closed: 503 | Inherited; avoids misattributed spend |

Requests with no readable identity (`user == "unknown"`) return early in the sample, before our checks. The gateway's `CUSTOM_JWT` authorizer rejects tokenless requests first, so this is only reachable if the authorizer were misconfigured.

## Answers to the open questions (from the sample's template and architecture doc)

1. **Payload shape:** `event["http"]["gatewayRequest"]` = `{path, httpMethod, headers, body}`; `body` is base64 JSON; claims come from the Bearer token in `headers` (decoded, already validated by the gateway; requires `passRequestHeaders`, which the sample's wiring sets).
2. **Denial format:** `{"interceptorOutputVersion":"1.0","http":{"transformedGatewayResponse":{statusCode, headers, body(base64), contentType}}}`. The sample uses 403 (not 429) for budget because some clients retry 429.
3. **What to scan:** last user turn without `<system-reminder>` blocks, keeping the end if over 20,000 chars (see risks.md #1).
4. **Streaming:** the sample's architecture doc shows the RESPONSE interceptor receiving buffered SSE, so output filtering looks possible at a latency cost. **Not tested.**
5. **SCP actions:** the gateway role uses `bedrock-mantle:CallWithBearerToken|CreateInference|GetInference|ListModels` besides `bedrock:Invoke*`; the SCP now denies the first three too. Whether a direct user could call Mantle with those actions is **to be tested** in phase 5.
6. **Fail modes:** see ADR-007.

## ADR-008 — No SCP for now (2026-10-20)

**Decision:** phase 5 (SCP that forces traffic through the gateway) is deferred. The account is standalone, with no AWS Organizations, and SCPs cannot be used without one.

**Consequence:** the gateway is enforced only because the gateway user has no AWS credentials. For real developers an IAM deny or permissions boundary is the in-account substitute (weaker: it protects identities you manage, not the account).

## ADR-009 — Two end-user profiles (superseded by ADR-015)

Validate the gateway with two Cognito users in different groups (`finanzas-builders`, `platform-engineers`); originally planned from AWS CloudShell sessions.

## ADR-010 — Deploy without reserved concurrency on accounts with a low Lambda limit

**Context:** the sample reserves concurrency on four Lambdas (100, 100, 2 and 5). Lambda requires at least 10 unreserved executions, and a new account's total limit is 10, so the stack rolled back at creation.

**Decision:** when the account limit is below 1000, `scripts/deploy-baseline.sh` deploys `build/standalone.yaml`, the upstream template minus exactly those four settings (`scripts/prepare_template.py` aborts if the count differs). On an account with headroom the unmodified template is used.

**Trade-off:** the interceptors share the account's concurrency instead of being capped, so a traffic burst could throttle other functions in the account. Acceptable at this scale; raise the Service Quotas limit to restore the reservations.

**Side effect to know:** a rolled-back creation leaves the resources the sample retains (spend table, KMS key, archive bucket) behind, and the next attempt fails with a name conflict. They must be removed before retrying.

## ADR-011 — One model per seat, priced from `config/price-table.json`

**Decision:** each Cognito group maps to exactly one model, like a licence tier (`finanzas-builders`: Claude Sonnet 5; `platform-engineers`: Claude Opus 5.5), with per-user daily/monthly caps (1 and 2 USD daily). The price table is a file in the repo, passed as the `PriceTableJson` stack parameter.

**Why:** it reproduces what an enterprise licence gives (a model entitlement plus a spend limit per person) with the gateway's own controls, and the price table doubles as the routable-model list. The gateway natively offers rate limits (requests, tokens per minute, connections, by JWT claim) but not per-user dollar budgets or model-per-group entitlements, so those remain interceptor logic backed by the DynamoDB spend table.

**Verified 2026-10-21:** with spend injected in the table, `finanzas-user` is blocked at 1.00 of 1.00 USD, `platform-user` passes at 1.00 and is blocked at 2.00 of 2.00, and both pass again once spend is cleared. A request for the other seat's model returns 403 `MODEL_NOT_ALLOWED`.

## ADR-012 — Interceptors are the policy layer, not the whole solution

**Decision:** the gateway provides identity (JWT authorizer), routing to inference targets by `model`, and native rate limits (requests, tokens per minute and concurrent connections, groupable by JWT claim). Everything that is business policy runs in the two Lambda interceptors: the model entitlement per group, the per-user dollar budget and its spend ledger, and the guardrail call.

**Why:** the gateway has no per-user dollar budgets or model-per-group entitlements. Interceptors are the documented extension point: [Using interceptors with Gateway](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-interceptors.html) (REQUEST runs before the target call, RESPONSE after; at most one of each; Lambda only; `passRequestHeaders` needed to see the token; make them idempotent). The native rate limits ([Add rate limits to a gateway](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-rate-limits.html), fail-open by default; survey of native options and alternatives in [native-options.md](native-options.md)) are complementary and not used yet: a per-user tokens-per-minute limit would be a cheap second guard against runaway loops.

**Trade-off:** the policy is code we maintain (see [risks.md](risks.md)).

## ADR-013 — Second inference target on bedrock-runtime, and request clean-up

**Context:** the account's Mantle quotas for the Claude models are applied at 0, while the models it can use (Haiku 4.5, Sonnet 4.5 and 4.6, Opus 4.5 and 4.6) are served by `bedrock-runtime`, which the official docs say also offers the Anthropic Messages API ([endpoints](https://docs.aws.amazon.com/bedrock/latest/userguide/endpoints.html), [Messages API](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-messages-api.html)).

**Decision:** add a provider-based inference target `bedrock-runtime` (`scripts/add-runtime-target.sh`): endpoint `https://bedrock-runtime.<region>.amazonaws.com`, operation `/v1/messages` forwarded to `/anthropic/v1/messages`, `GATEWAY_IAM_ROLE` credentials, models as inference profile IDs. The seats map to Haiku 4.5 (`finanzas-builders`) and Sonnet 4.6 (`platform-engineers`). `config/price-table.json` carries both the request-side IDs and the response-side IDs, because the runtime route answers with `anthropic.claude-...` names.

**Request clean-up:** Claude Code sends `metadata.user_id` on every request and the runtime route rejects it (`400 Request metadata contains a value that violates the regular expression`). The REQUEST interceptor returns a `transformedGatewayRequest` without `metadata` (`strip_metadata` in `interceptor/extensions/gateway.py`, hooked by `build_interceptor.py`). The field is optional attribution data.

**Client header:** the runtime Messages route takes `anthropic-version: 2023-06-01`, which Claude Code sends by default; the earlier `ANTHROPIC_CUSTOM_HEADERS` override (`bedrock-2023-05-31`) was removed from the settings template.

**Trade-offs:** the Opus line is not available on this route for this account; Guardrails also exist on `bedrock-runtime`, but this design keeps calling `ApplyGuardrail` from the interceptor.

## ADR-014 — AWS WAF on the gateway, staged from COUNT to BLOCK

**Decision:** associate a regional web ACL with the gateway (`infra/waf.yaml`): per-IP rate limit, AWS IP reputation list, AWS known-bad-inputs and AWS common rule sets. Failure mode stays `FAIL_CLOSE`. Everything starts in COUNT; the rate limit, IP reputation and known-bad-inputs are enforced, the common rule set stays in COUNT until its counted requests are reviewed.

**Why staged:** the sampled requests showed what enforcing blindly would have done. The common set's `SizeRestrictions_BODY` rule flags every Claude Code request (prompts routinely exceed 8 KB), so that rule is overridden to COUNT permanently; other common rules (cross-site scripting, file inclusion) may react to code in prompts and need review first. The known-bad-inputs group did what was intended: it matched a log4j-style payload (`Log4JRCE_BODY`).

**Logging:** WAF logs go to CloudWatch Logs with the `authorization`, `cookie` and `x-api-key` headers redacted, so tokens never reach them.

**Trade-offs:** about 9 USD per month for the four rules plus per-request and log costs (estimate, check the bill); WAF returns `Request blocked by WAF` (403) with no error code, distinguishable from the interceptors' JSON error codes.

## ADR-015 — End users are two local containers with no AWS credentials

**Decision:** the two end-user profiles run as containers (`containers/Dockerfile`, `scripts/run-user.sh`): Amazon Linux 2023, a non-root user, Claude Code installed with the official native installer, a password sign-in (SRP) at start, and the Claude Code settings written for the seat. AWS CloudShell is not used.

**Why:** CloudShell is operated only from the console (no API, so it cannot be scripted or automated), carries the console user's AWS credentials (so it cannot show that end users hold none), has about 2 GiB of RAM, and needed a manual browser callback step. A container is reproducible, scriptable, runs both seats at the same time, and holds no AWS credentials, which is the property the design relies on.

**Trade-off:** the containers run on the administrator's workstation (they need Docker); the gateway is reached over the internet like any other client.

## Pending decisions

- Whether the budget lookup should fail closed (inherited behavior is fail open).
- Which in-account control replaces the SCP, if the bypass question is revisited (ADR-008).
