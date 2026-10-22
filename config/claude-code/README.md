# Claude Code configuration

| File | Install at | Purpose |
|---|---|---|
| `settings.json` | `~/.claude/settings.json` (merge the `env` block) | Points Claude Code at the gateway. Values taken from the AWS sample. |
| `managed-settings.json` | `/etc/claude-code/managed-settings.json` (Linux, root-owned) | Machine policy: blocks `bypassPermissions` and `auto` modes, denies secrets and AWS commands. The user cannot override it. |

The token is not stored here. Export it per session with `source scripts/claude-token.sh` (sets `ANTHROPIC_AUTH_TOKEN`).

Notes:

- Deny rules on Bash match the command text, not the program: they are a first barrier, not a security boundary. The real boundary is that the user holds no AWS credentials (and, in phase 5, an SCP).
- `allowManagedPermissionRulesOnly` makes this file the only source of permission rules.
- Docs: [managed settings](https://code.claude.com/docs/en/managed-settings), [permissions](https://code.claude.com/docs/en/permissions).
