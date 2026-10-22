# Model access request (Bedrock Mantle quotas)

## Root cause

The refusal `permission_error: <model> is not available for this account` on the `bedrock-mantle` endpoint comes from **quotas whose applied value is 0**, not from IAM, agreements or the use-case form. In Service Quotas (service `bedrock`) every `[bedrock-mantle endpoint]` quota for the Claude models is applied at 0 while the AWS default is above 0 (for example Claude Sonnet 5: 3,000,000 input and 300,000 output tokens per minute; Claude Opus 5.5: 20,000,000 and 2,000,000). The quotas are adjustable. The same pattern exists for the newest models on `bedrock-runtime` (for example "tokens per minute for Claude Opus 5" applied at 0), which is why Sonnet 5 and Opus 4.7 and later were refused on both endpoints.

`scripts/check-model-quotas.sh` prints applied vs default for all of them and the state of the increase requests.

## What was requested (2026-10-21)

Service Quotas rejects any desired value that is not above the default, so each request asks for the default plus one. Status when filed: `PENDING`, no Support case attached (the account has no Premium Support plan, so cases cannot be opened through the API).

| Model | Quota | Desired value |
|---|---|---|
| Claude Sonnet 5 | Input tokens per minute | 3,000,001 |
| Claude Sonnet 5 | Output tokens per minute | 300,001 |
| Claude Opus 5.5 | Input tokens per minute | 20,000,001 |
| Claude Opus 5.5 | Output tokens per minute | 2,000,001 |

These are the two models routed by the gateway (one per seat, [ADR-011](decisions.md)). A quota is a ceiling, not spend: what each person can spend is limited by the gateway budgets. The other Claude models on Mantle (Fable 5 and 5.1, Opus 4.7, 4.8 and 5) are at 0 as well and were not requested because the design does not route them. Haiku 4.5 has no Mantle quota in the list, so it is expected to stay unavailable through the gateway.

### Second batch: the 5.5 family (2026-10-21)

Also requested, to be able to use the whole 5.5 family. These are `bedrock-runtime` quotas (cross-region and global inference profiles); Sonnet 5.5 and Haiku 5.5 have no Mantle quota because Mantle does not list them. Opus 5.5 on Mantle was already in the first batch. All `PENDING` when filed, each at the default plus one.

| Model | Quota | Desired value |
|---|---|---|
| Claude Sonnet 5.5 | Cross-region tokens per minute | 6,000,001 |
| Claude Sonnet 5.5 | Global cross-region tokens per minute | 6,000,001 |
| Claude Haiku 5.5 | Cross-region tokens per minute | 10,000,001 |
| Claude Haiku 5.5 | Global cross-region tokens per minute | 10,000,001 |
| Claude Opus 5.5 | Cross-region tokens per minute | 30,000,001 |
| Claude Opus 5.5 | Global cross-region tokens per minute | 30,000,001 |

**Status shortly after filing:** the six requests of this batch moved to `CASE_OPENED`, meaning AWS opened a Support case for each on its own (no Premium Support plan needed); the first batch was still `PENDING`. Follow the cases from the Service Quotas console or the Support Center.

**Update 2026-10-22:** the six Support cases of this batch are `CASE_CLOSED` and the applied quotas are still 0 (no increase was applied), and `bedrock-runtime` still refuses the three 5.5 models. The closing reason is only visible in the Support Center or in the email AWS sends to the account owner (the Support API needs a Premium Support plan). The first batch (Sonnet 5 and Opus 5.5 on Mantle) is still `PENDING`.

Fable 5.1 (applied 0 on both endpoints) and the other models at 0 were not requested; ask for them the same way (`aws service-quotas request-service-quota-increase`, desired value above the default) if a seat needs them.

## Following up

```bash
scripts/check-model-quotas.sh      # applied value changes from 0 when approved; requests show their status
scripts/check-model-access.sh      # does the model answer on both endpoints now
```

If a request stays pending, is closed without an increase or is denied, open the request from the Service Quotas console (it gives the option to escalate to Support) or use the AWS Sales form named in [Request access to models](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html). Text to paste, filling the account details outside the repository:

> We deploy Claude Code for two internal users through an Amazon Bedrock AgentCore Gateway whose inference target uses the bedrock-mantle endpoint (us-east-1). Calls to anthropic.claude-sonnet-5 and anthropic.claude-opus-5-5 return `permission_error: ... is not available for this account`. The applied value of the matching `[bedrock-mantle endpoint]` quotas in Service Quotas is 0 (default 3,000,000 / 300,000 and 20,000,000 / 2,000,000 tokens per minute). We have submitted the Anthropic use-case details and are not part of an AWS Organization. Please enable these models for the account and apply the default quotas. Usage is capped per user by our own budgets (1 and 2 USD per day).

## After approval

1. Run both scripts above and update the table in [model-availability.md](model-availability.md).
2. Run `scripts/verify-gateway.sh` from each user session (README, End users) and record the first real responses and the spend rows in `evidence/`.
3. Check that the spend ledger and the metrics move, and that the budgets block a real overspend.
