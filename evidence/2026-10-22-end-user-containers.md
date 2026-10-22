# End-user containers, 2026-10-22

Two containers built from `containers/Dockerfile` (Amazon Linux 2023, non-root user, Claude Code from the official installer) and started with `scripts/run-user.sh`. No AWS credentials inside (the entrypoint prints the count of `AWS_*` variables: 0). No account or resource identifiers are recorded here.

| Seat | Sign-in (SRP) | `verify` | Claude Code |
|---|---|---|---|
| finanzas (Haiku 4.5) | token for `finanzas-user` | 200; 403 `MODEL_NOT_ALLOWED`; 403 `GUARDRAIL_BLOCKED` | Wrote a `reverse_string` function with a docstring |
| platform (Sonnet 4.6) | token for `platform-user` | 200; 403 `MODEL_NOT_ALLOWED`; 403 `GUARDRAIL_BLOCKED` | Wrote the same function with type hints |

Both containers ran Claude Code **at the same time**; the spend rows moved independently: `finanzas-user` +0.042 USD (cap 1 USD) and `platform-user` +0.119 USD (cap 2 USD).

First attempt, same containers: both Claude Code runs were refused with 403 `Request blocked by the organization's AI guardrail` because the prompt ended in "Reply with only the code" (see risks 4h). The same request without that sentence passed.
