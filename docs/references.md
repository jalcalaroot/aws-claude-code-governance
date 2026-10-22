# References

## Baseline

- [AWS sample: per-user cost attribution and budgets on AgentCore Gateway](https://github.com/aws-samples/sample-agentcore-gateway-usage-interceptor) and its [auth helper for Claude Code](https://github.com/aws-samples/sample-agentcore-gateway-usage-interceptor/blob/main/auth-helper/README.md)

## AgentCore Gateway

- [Core concepts and inference targets](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-core-concepts.html)
- [Interceptors](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-interceptors.html)
- [Interceptor payload types](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-interceptors-types.html)
- [Interceptor examples](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-interceptors-examples.html)

- [Add rate limits to a gateway](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-rate-limits.html) and the [AWS blog on rate limits for AI traffic](https://aws.amazon.com/blogs/machine-learning/configure-rate-limits-for-ai-traffic-on-agentcore-gateway/)
- [Using interceptors with Gateway](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-interceptors.html) (overview, security best practices, permissions, types, configuration, examples)

## Alternatives and native options

See [native-options.md](native-options.md) for the survey of what AWS offers natively and the published alternatives.

- [AWS WAF protection for AgentCore Gateway (announcement)](https://aws.amazon.com/about-aws/whats-new/2026/06/aws-waf-amazon-bedrock-agentcore/) and [Protecting your gateway with AWS WAF](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-waf.html)

- [Interface VPC endpoints for AgentCore](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/vpc-interface-endpoints.html) and the [AWS blog on private ingress to the gateway](https://aws.amazon.com/blogs/machine-learning/secure-ingress-connectivity-to-amazon-bedrock-agentcore-gateway-using-interface-vpc-endpoints)

## Bedrock

- [Request access to models](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html): auto-enablement, Marketplace permissions, account-level access, agreement APIs


- [Guardrails](https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails.html)
- [Track usage and costs](https://docs.aws.amazon.com/bedrock/latest/userguide/cost-management.html), including attribution behind an LLM gateway

## Claude Code

- [Advanced setup and installation](https://code.claude.com/docs/en/setup): native installer, channels, system requirements

- [Managed settings](https://code.claude.com/docs/en/managed-settings)
- [Permissions](https://code.claude.com/docs/en/permissions)
- [LLM gateways](https://code.claude.com/docs/en/llm-gateway)
- [Manage costs](https://code.claude.com/docs/en/costs)

## Alternatives (not used)

- [Guidance for Multi-Provider Generative AI Gateway on AWS (LiteLLM)](https://docs.aws.amazon.com/solutions/multi-provider-generative-ai-gateway-on-aws/)
- [Custom gateway with Bedrock Guardrails (AWS blog)](https://aws.amazon.com/blogs/machine-learning/safeguard-generative-ai-applications-with-amazon-bedrock-guardrails/)
- [Claude apps gateway (Anthropic)](https://code.claude.com/docs/en/claude-apps-gateway)
