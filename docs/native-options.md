# What AWS offers natively for this

Checked on **2026-10-21** against the AgentCore Gateway documentation and AWS publications. Re-check before each phase: this area changes quickly.

## Native in AgentCore Gateway

| Capability | Status | Source |
|---|---|---|
| Inbound authentication (JWT / OAuth, IAM SigV4) | Native | [Core concepts](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-core-concepts.html) |
| Routing to inference targets by the `model` field | Native | same |
| Rate limits per caller, target or tool: requests, tokens per minute for inference targets, concurrent connections; callers grouped by JWT claim or IAM identity; a rate of 0 blocks a caller | Native, **fail-open by default** | [Add rate limits to a gateway](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-rate-limits.html) |
| Edge protection with AWS WAF: managed rule groups, rate-based and IP rules, one regional web ACL per gateway, `FAIL_CLOSE` by default | Native (deployed here, phase 7) | [Protecting your gateway with AWS WAF](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-waf.html) |
| Custom code before and after the target call (one REQUEST and one RESPONSE interceptor, Lambda only) | Native extension point | [Using interceptors with Gateway](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-interceptors.html) |

## Not native (no official feature found)

- **Per-user budgets in dollars, per day or per month**, and the spend ledger behind them.
- **Model entitlement per group** (which model each person may use).
- Prompt scanning with a guardrail in the gateway path (Bedrock Guardrails exist, but calling them from the gateway is custom code).

The rate limits are the closest native control, with differences that matter: they count tokens per minute, not dollars per day, they are not an entitlement, and by default they let traffic through when the limit service cannot decide. They are complementary: a per-user tokens-per-minute limit would be a cheap second guard against a runaway loop. Not configured yet.

No official AWS announcement of native per-user token budgets or model access control for AgentCore Gateway was found in the documentation or in "what's new" coverage.

## AWS-published patterns and alternatives

| Option | What it is | Fit |
|---|---|---|
| [aws-samples/sample-agentcore-gateway-usage-interceptor](https://github.com/aws-samples/sample-agentcore-gateway-usage-interceptor) | Per-user cost attribution and daily/monthly hard budgets with two interceptors | The baseline of this repository |
| [Claude apps gateway on AWS (AWS Builder Center)](https://builder.aws.com/content/3GBXL45hJbmHjUMe5QsgmnZb1RU/deploy-the-claude-apps-gateway-on-aws-claude-code-on-amazon-bedrock-with-sso-vpn-and-spend-caps) | Anthropic's gateway deployed on AWS, with SSO and per-user and per-group spend caps | Native spend limits; self-hosted |
| [sample-claude-code-amazon-bedrock-usage-governance-with-litellm](https://github.com/aws-samples/sample-claude-code-amazon-bedrock-usage-governance-with-litellm) | LiteLLM proxy with keys, budgets and rate limits | Built-in budgets; operated by you |
| [Guidance for Claude Code with Amazon Bedrock](https://github.com/aws-solutions-library-samples/guidance-for-claude-code-with-amazon-bedrock) | Authentication and per-user/per-team token quotas with warning and block modes | Its README shows Maintenance Mode |
| [Governing Amazon Bedrock Costs (AWS re:Post)](https://repost.aws/articles/AR5rBgrAyQStqFOiBYu88PDg/governing-amazon-bedrock-costs-team-and-user-level-tracking-budgets-and-hard-spend-controls-for-claude-code) | Tag-based AWS Budgets plus a Lambda that stops usage at the cap | Alerts alone do not stop spend |
| [What to Know Before Running Claude Code on Amazon Bedrock](https://builder.aws.com/content/3FaTYXWGVgHjO6glPCGxCWpdeyE/what-to-know-before-running-claude-code-and-cowork-on-amazon-bedrock) and [Bedrock Cost Attribution guide](https://builder.aws.com/content/3JSAQyX69JuBJZoHbThKlg7Y8jS/amazon-bedrock-cost-attribution-a-prescriptive-guide) | Guidance articles | Say Bedrock has no native per-user cap |

These were found through search and not all were opened in full: read the source before relying on a detail.

## Consequence for this design

Interceptors stay as the policy layer ([ADR-012](decisions.md)). Native rate limits are a candidate addition. Revisit this page when AWS publishes a managed budget feature, and compare with the alternatives above if the interceptor code becomes a maintenance burden.
