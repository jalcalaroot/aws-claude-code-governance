# Model availability

Which Claude models the account can call, and what that means for the gateway. Measured on **2026-10-21** with `scripts/check-model-access.sh` (one 16-token request per model and endpoint). Re-run it before relying on any model.

| Model | bedrock-runtime | bedrock-mantle |
|---|---|---|
| Haiku 4.5 | works | HTTP 403 |
| Sonnet 4.5 | works | not listed |
| Sonnet 4.6 | works | not listed |
| Sonnet 5 | denied or unavailable | HTTP 403 |
| Opus 4.5 | works | not listed |
| Opus 4.6 | works | not listed |
| Opus 4.7 | denied or unavailable | HTTP 403 |
| Opus 4.8 | denied or unavailable | HTTP 403 |
| Opus 5 | denied or unavailable | HTTP 403 |
| Opus 5.5 | denied or unavailable | HTTP 403 |
| Sonnet 5.5 | denied or unavailable | not listed |
| Haiku 5.5 | denied or unavailable | not listed |
| Fable 5.1 | denied or unavailable | not listed |
| Fable 5 | denied or unavailable | HTTP 403 |

Sonnet 5.5, Haiku 5.5 and Fable 5.1 are not in the gateway's Mantle catalog, so even with their quotas approved they can be used on `bedrock-runtime` but not routed through the gateway until AWS adds them to Mantle. Check the catalog again before adding them to a group.

`bedrock-runtime` is the classic Bedrock endpoint (Converse, InvokeModel). `bedrock-mantle` is the Messages-API endpoint that the gateway's inference target calls. The gateway's model catalog (`GET /v1/models`) lists only these Claude models, all under `bedrock-mantle/`: Fable 5, Haiku 4.5, Opus 4.7, Opus 4.8, Opus 5, Opus 5.5, Sonnet 5.

## What this means

- **No model is reachable through the gateway yet.** The models the account can use on `bedrock-runtime` (Haiku 4.5, Sonnet 4.5 and 4.6, Opus 4.5 and 4.6) are not on Mantle, except Haiku 4.5, which Mantle refuses for this account. The ones Mantle lists are refused with `permission_error: <model> is not available for this account`.
- **Root cause: the applied Service Quotas for these models are 0**, not IAM or agreements. The same refusal comes back when calling Mantle directly with administrator credentials (SigV4), so it is not the gateway role, and `get-foundation-model-availability` reports `AUTHORIZED`/`AVAILABLE` for models that are refused. Details and the increase requests filed on 2026-10-21 are in [model-access-request.md](model-access-request.md).
- **The documentation says so.** [Request access to models](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html): some models require additional account-level access that activation steps do not grant, and a request that still gets `AccessDeniedException` after completing them should go to AWS Sales. The Anthropic first-time-use form does not apply to `bedrock-mantle`.

## Checks already done

| Check | Result |
|---|---|
| Anthropic use-case form (`get-use-case-for-model-access`) | Submitted |
| Agreement offers (`list-foundation-model-agreement-offers`) | None to accept for the refused models |
| `get-foundation-model-availability` | Reports available for several refused models |
| AWS Support API | Not available (no Premium Support plan), so a case cannot be opened from the CLI |

## Routes forward

1. **Quota increases for Sonnet 5 and Opus 5.5 on Mantle, filed 2026-10-21 and pending** ([model-access-request.md](model-access-request.md)); escalate to Support or Sales if they stall.
2. **Test the rest of the pipeline with a model Mantle does serve to this account**, for example an open-weight model that needs no Marketplace subscription (`openai.gpt-oss-20b`; it is in the price table). It would exercise the gateway, the interceptors, the spend ledger and the metrics end to end. Not tried yet; it needs that model added to a group's allowlist.
3. **A second inference target for `bedrock-runtime`.** The official docs state that `bedrock-runtime` also serves the Anthropic Messages API (`https://bedrock-runtime.{region}.amazonaws.com/anthropic/v1/messages`, model in the body, SigV4 or a Bedrock API key) and that both endpoints use the same inference engine ([Inference endpoints](https://docs.aws.amazon.com/bedrock/latest/userguide/endpoints.html), [Messages API](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-messages-api.html)). The models this account can use (Haiku 4.5, Sonnet 4.5 and 4.6, Opus 4.5 and 4.6) are **runtime-only** per [Endpoint availability](https://docs.aws.amazon.com/bedrock/latest/userguide/models-endpoint-availability.html). A provider-based inference target (`endpoint`, `operations[].path`/`providerPath`, `modelMapping`) pointing at `bedrock-runtime` is therefore plausible. **Done and verified on 2026-10-22** (`scripts/add-runtime-target.sh`, [ADR-013](decisions.md)): the gateway signs with its own role (`GATEWAY_IAM_ROLE`, no IAM change needed) and clients send inference profile IDs. On the Messages route this account can use Haiku 4.5 (`us.anthropic.claude-haiku-4-5-20251001-v1:0`) and Sonnet 4.6 (`us.anthropic.claude-sonnet-4-6`); Opus 4.5 and 4.6 work with Converse but answer "model doesn't exist or doesn't support this API" on this route. An earlier version of this note said it was unlikely because the model goes in the URL; that applies to InvokeModel, not to the Messages route.

Route 3 is what serves requests today. Routes 1 and 2 remain useful for Sonnet 5 and Opus 5.5 and the newer models, which need the Mantle quotas.
