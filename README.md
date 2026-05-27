# GhostComplete

Native macOS inline autocomplete with a local Bun/TypeScript AI sidecar.

GhostComplete watches the focused editable field through macOS Accessibility, asks a localhost-only AI sidecar for a short continuation, renders it as ghost text near the caret, and inserts it when you press Tab. Esc dismisses the suggestion.

The app is split intentionally:

- `mac/` owns macOS permissions, focus tracking, overlay rendering, Tab/Esc handling, and insertion.
- `ai-service/` owns Vercel AI SDK streaming calls, prompt construction, local learning, Gateway verification, and provider config. It runs on Bun and builds to a bundled sidecar executable for the app.
- `shared/` documents the localhost protocol used between the two processes.
- `scripts/` contains local development, build, install, permissions, and smoke-test helpers.

## Requirements

- macOS 14+
- Xcode command line tools with Swift
- Bun 1.3+
- A Vercel AI Gateway key in `AI_GATEWAY_API_KEY`

## Quick Start

```sh
cp .env.example .env.local
# edit .env.local and set AI_GATEWAY_API_KEY
bun run try
```

`bun run try` builds the Bun sidecar, builds the macOS app, signs it with the first available local code-signing identity, installs it to `/Applications/GhostComplete.app`, stores `AI_GATEWAY_API_KEY` from `.env.local` or `.env` in Keychain, grants the installed app access to that Keychain item, and launches the app. If no signing identity exists, it falls back to ad-hoc signing and macOS may require permissions again after each rebuild.

Grant Accessibility and Input Monitoring permissions when macOS prompts, then type in a supported text field. Tab accepts the ghost suggestion and Esc dismisses it.

If GhostComplete is already running, the installer quits it before replacing `/Applications/GhostComplete.app`. `bun run try` then relaunches the fresh build. `bun run install:local` leaves it stopped after the replacement, so launch it manually when you are ready.

For development:

```sh
bun run dev
```

## Configuration

Runtime files live in:

```text
~/Library/Application Support/GhostComplete
```

Scripts source environment variables from `.env` and `.env.local` automatically, with `.env.local` taking precedence. Both files are gitignored; use `.env.example` as the template.

The sidecar reads:

- `AI_GATEWAY_API_KEY` for Vercel AI Gateway auth.
- `GHOSTCOMPLETE_MODEL` for the AI Gateway model string. Default: `openai/gpt-5.4`.
- `GHOSTCOMPLETE_PORT` for development. Production launch uses the bundled Bun sidecar.
- `GHOSTCOMPLETE_LOG_DIR` to override the default JSONL trace directory.

The Swift app uses `AI_GATEWAY_API_KEY` from its launch environment first, which keeps `bun run try` and other local dev launches from touching Keychain. Finder launches usually do not inherit your shell environment, so the app falls back to Keychain and passes the key to the sidecar at launch.

Seed Keychain with `bun run set-key`, or run `bun run install:local` after setting `AI_GATEWAY_API_KEY` in `.env.local`. When `/Applications/GhostComplete.app` exists, both commands attach the installed app executable as the trusted client for the Keychain item.

## AI Gateway

The sidecar uses Vercel AI SDK `streamText` through AI Gateway and then returns the final continuation to the Swift app over the local JSON protocol. Stream traces include chunk count, first-token latency, stream latency, finish reason, provider response metadata, warnings, and token usage.

To verify Gateway independently:

```sh
bun run gateway:check
```

## Build And Install

```sh
bun run install:local
```

The installed app is ad-hoc signed as `/Applications/GhostComplete.app` with bundle ID `dev.octavian.GhostComplete`.

Useful local commands:

```sh
bun run setup          # install sidecar dependencies
bun run set-key        # store AI_GATEWAY_API_KEY from .env or prompt in Keychain
bun run try            # install and launch the app
bun run install:local  # install without launching
bun run gateway:check  # run a Vercel AI Gateway streamText check with tsx
bun run logs           # print JSONL trace file paths
bun run logs:tail      # follow app and sidecar JSONL traces
bun run smoke          # smoke-test the local sidecar
bun run reset-perms    # reset macOS TCC permissions for the app
bun run reset-data     # reset permissions and delete learned data
```

## Logs And Traces

GhostComplete writes structured JSONL traces to:

```text
~/Library/Application Support/GhostComplete/logs/app.jsonl
~/Library/Application Support/GhostComplete/logs/sidecar.jsonl
```

Use:

```sh
bun run logs
bun run logs:tail
```

The trace stream includes app launch, permission checks, sidecar launch, request lifecycle, stale responses, stream chunk counts, first-token latency, completion latency, AI SDK token usage, finish reasons, response metadata, insertion strategy, accepted suggestions, validation failures, model timeouts, and sidecar shutdown. Raw typed context is not logged; trace records use lengths and SHA-256 hashes for text-bearing fields.

## Permissions And Keychain Prompts

GhostComplete shows a status window on launch with Accessibility, Input Monitoring, sidecar state, and the exact bundle/path/signing requirement macOS is evaluating. If System Settings shows GhostComplete enabled but the app still reports `Not trusted by macOS` or `Event tap blocked`, remove all GhostComplete rows from Accessibility and Input Monitoring, add `/Applications/GhostComplete.app` again, then click `Retry Checks`. A full restart is not usually needed after granting permission.

Accessibility and Input Monitoring prompts are macOS privacy permissions for reading focused text fields and intercepting Tab/Esc. They are managed in System Settings.

Keychain prompts are different: they appear when the Finder-launched app reads `AI_GATEWAY_API_KEY` from the login Keychain. `bun run install:local` and `bun run set-key` attach `/Applications/GhostComplete.app/Contents/MacOS/GhostComplete` as the trusted app for that secret. If macOS still shows a Keychain dialog, choose `Always Allow`; `Allow` is one-time and can reappear on the next launch.

## Testing

```sh
bun run test
bun run smoke
```

## Privacy

Raw typing context is sent only to the local sidecar and then to the configured AI model for completion. It is not persisted by GhostComplete. Local learning stores accepted suggestions, user-curated snippets, profile facts, and event metadata. Rejections store hashes and reason codes, not raw text.

Use the menu item `Delete Learned Data` or run:

```sh
scripts/reset-permissions --delete-data
```

to remove local profile and learning artifacts.

## Status

GhostComplete targets local Mac use, not App Store distribution. It is early local-first software; expect app-specific AX behavior to need hardening across more editors and browsers.
