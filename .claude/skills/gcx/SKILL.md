---
name: gcx
description: Use GhostComplete's project-local CLI to verify sidecar health, provider/model settings, logs, and completion behavior through the same localhost HTTP surface the app uses.
---

# gcx

`gcx` is the GhostComplete end-to-end verifier CLI. It is for agents debugging this repo without relying on the macOS overlay UI.

## First Move

Run:

```sh
bun run gcx -- doctor --json
```

This checks the local app support directory, installed app bundle, runtime settings, preferences, and sidecar `/health`.

## Resource Map

| Resource | Commands | Purpose |
|---|---|---|
| `doctor` | `doctor` | Check config, installed app, preferences, selected provider/model, and sidecar health. |
| `settings` | `show`, `set provider`, `set model`, `set raw-logs` | Inspect or change the same local settings the app uses. |
| `api` | `METHOD PATH` | Call the running sidecar over localhost HTTP. |
| `verify` | `verify completions` | Start a disposable sidecar and call `/complete` with a fake completion by default. |

## Common Workflows

```sh
bun run gcx -- settings show --json
bun run gcx -- settings set provider openrouter
bun run gcx -- settings set model google/gemini-2.0-flash-lite-001
bun run gcx -- settings set raw-logs on
bun run gcx -- verify completions --fake --json
```

`verify completions` applies saved provider/model settings over `.env.local`, matching the installed app launch behavior.

Use `--live` on `verify completions` only when you intentionally want a real provider call.

## Output Modes

Structured commands support:

- default human output
- `--json`
- `--plain`

Data goes to stdout. Status, errors, and hints go to stderr.

## Exit Codes

| Code | Meaning |
|---:|---|
| 0 | success |
| 1 | local/config error |
| 2 | usage error |
| 4 | backend unreachable |
| 5 | API/provider error |
| 6 | verification failed |
