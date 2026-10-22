# SCP vs Bedrock Guardrails

They answer different questions and are meant to be used together. **Bedrock Guardrails** decide whether the *content* of a request is acceptable. A **service control policy (SCP)** decides whether a *principal* may call an AWS *API* at all. This solution tested the first and could not test the second: the account is not part of an AWS Organization, and SCPs need one ([ADR-008](decisions.md)).

| | Bedrock Guardrails | SCP |
|---|---|---|
| Controls | Prompt attacks, sensitive data (PII, keys, passwords), denied topics, words, grounding in prompts and answers | Which actions, resources, Regions and conditions the principals of member accounts may use: a ceiling on permissions |
| Reads the content? | Yes | No |
| Acts on | The text it is given (here: `ApplyGuardrail` from the REQUEST interceptor) | The IAM authorization of every AWS API call |
| Stops someone from calling Bedrock directly and skipping the gateway? | No: it only filters calls made through it | Yes: deny `bedrock:InvokeModel*` and `bedrock-mantle` actions to everyone except the gateway role |
| Can it require a guardrail? | n/a | Yes: with the condition key `bedrock:GuardrailIdentifier` an IAM policy or SCP can require a guardrail on `InvokeModel` calls ([AWS announcement](https://aws.amazon.com/about-aws/whats-new/2025/03/amazon-bedrock-guardrails-policy-based-enforcement-responsible-ai/), [least-privilege guide](https://aws.amazon.com/blogs/security/implementing-least-privilege-access-for-amazon-bedrock/)) |
| Needs | Nothing special | AWS Organizations |
| In this repository | **Deployed and tested** ([evidence](../evidence/2026-10-22-guardrails.md)) | Reference policies, **not tested** (`policies/`) |

## What an SCP would add here

1. **Make the gateway the only path to the models** (phase 5): `policies/scp-deny-direct-bedrock.json` denies direct inference to everyone except the gateway role, which removes the bypass that the guardrail, the budgets and the model allowlist cannot prevent on their own.
2. **Force a guardrail on any direct call** that remains: `policies/scp-require-guardrail.json` denies `InvokeModel*` without `bedrock:GuardrailIdentifier`, with an exception for the gateway role (its calls follow its own `ApplyGuardrail` check).
3. **Protect the controls**: deny changes that would switch them off (deleting the guardrail, disassociating the web ACL, turning off logging) for everyone but an administrator role.
4. **Limit Regions and models** the account can use for Bedrock.

Limits of SCPs worth remembering: they never grant permissions, they do not apply to the management account, and they do not apply to service-linked roles.

## Without Organizations

An IAM deny policy or a permissions boundary on the people and roles that must go through the gateway does the first two jobs inside one account. It protects the identities you manage, not the account: someone who can edit their own policies can remove it.

## Not verified

- That `bedrock:GuardrailIdentifier` is evaluated for calls made through the Messages route of `bedrock-runtime` or through `bedrock-mantle` (the AWS pages found describe it for `InvokeModel` and `InvokeModelWithResponseStream`; Mantle does not support Guardrails according to the [endpoint comparison](https://docs.aws.amazon.com/bedrock/latest/userguide/endpoints.html)).
- Whether the condition key governs `ApplyGuardrail`, and whether an AWS Organizations policy type for Bedrock exists (one third-party article says so; not confirmed in AWS documentation).
- The SCP files themselves, because there is no organization to attach them to.
