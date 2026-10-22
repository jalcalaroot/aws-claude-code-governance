"""Extensions plugged into the AWS sample's REQUEST interceptor.

``scripts/build_interceptor.py`` patches the sample's handler to call, in order:

1. ``gateway.model_check``     per-group model allowlist (cheap, no network),
                                 right before the sample's budget lookup
2. the sample's budget check   unchanged
3. ``gateway.guardrail_check`` ``ApplyGuardrail`` on the prompt (network call,
                                 costs per request), only if the budget allowed

Denials are HTTP responses in the same shape as the sample's ``BUDGET_EXCEEDED``.
"""
