# Policies

| File | What | When |
|---|---|---|
| `guardrail.json` | Bedrock guardrail input for `aws bedrock create-guardrail --cli-input-json`: prompt-attack filter and PII blocking on input | Phase 3 |
| `scp-require-guardrail.json` | **Reference, untested.** SCP that denies `InvokeModel*` when the call carries no guardrail (`bedrock:GuardrailIdentifier` is absent), except for the gateway role, which calls the model after its own guardrail check. Needs AWS Organizations | Phase 5 (deferred) |
| `scp-deny-direct-bedrock.json` | **Reference only, not used.** SCP that denies direct Bedrock inference except for the gateway role (and a break-glass role). Needs AWS Organizations, which this account lacks | Phase 5 (deferred) |

## SCP caveats — verify before attaching

- **Mantle endpoint actions:** the gateway role in the sample uses `bedrock-mantle:CallWithBearerToken`, `CreateInference`, `GetInference` and `ListModels`, so the SCP denies the first three as well as `bedrock:Invoke*`/`Converse*`. Verify in phase 5 that a privileged user is really blocked on both paths (test T9), and check the [Service Authorization Reference](https://docs.aws.amazon.com/service-authorization/latest/reference/reference.html) for further actions.
- Replace the role placeholders with the real names from the stack outputs.
- Attach only to a **sandbox OU**, never to the management account or production.
- SCPs control **actions** on AWS. Guardrails filter **content**. They do not replace each other.

## Guardrail caveats

- `PROMPT_ATTACK` applies to input only.
- Verify the PII entity types against the current [Guardrails documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails.html) before creating it.
