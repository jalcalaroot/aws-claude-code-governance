# Network access to the gateway

## Public or private?

**Both are possible; today it is public.** The gateway data-plane endpoint is `https://<gateway-id>.gateway.bedrock-agentcore.<region>.amazonaws.com`, reachable from the internet. It is protected in layers: AWS WAF at the edge ([phase 7](phases.md)), then the JWT authorizer (no token: 401), then the interceptors (model entitlement, budget, guardrail).

AgentCore Gateway also supports **private access** through an AWS PrivateLink interface endpoint, service name `com.amazonaws.<region>.bedrock-agentcore.gateway` ([interface VPC endpoints](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/vpc-interface-endpoints.html), [AWS blog](https://aws.amazon.com/blogs/machine-learning/secure-ingress-connectivity-to-amazon-bedrock-agentcore-gateway-using-interface-vpc-endpoints)):

- With private DNS enabled, the gateway's standard URL resolves to private IPs inside the VPC, so clients need no change.
- It covers the **data plane** only; control-plane calls (creating gateways, targets) use their own endpoint. Authentication flows (the identity provider) and the gateway's calls to its targets still need internet connectivity.
- The endpoint policy can limit the endpoint to one gateway (`bedrock-agentcore:InvokeGateway` on its ARN). Because this gateway authenticates with OAuth tokens and not SigV4, the policy's `Principal` must be `*`; the security group on the endpoint can restrict the source.
- **Not found in the pages read:** a setting that disables the public endpoint. A private-only design should be checked in the console or with AWS before relying on it.

## Which fits this solution

| Users | Path |
|---|---|
| Developers on laptops and in containers (today) | Public endpoint, with WAF, JWT and interceptors |
| Workloads or workstations inside a VPC | PrivateLink endpoint; traffic stays on the AWS network |
| A requirement that nothing is reachable from the internet | Needs the PrivateLink design plus confirmation that the public endpoint can be closed; not available in the documentation reviewed |

Both paths pass through the same authorizer and interceptors. The AWS WAF web ACL is associated with the gateway; whether it also evaluates requests that arrive through the VPC endpoint is not stated in the pages read.
