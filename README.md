# GhostComplete

Native macOS inline autocomplete with a local Bun/TypeScript AI sidecar.

GhostComplete watches the focused editable field through macOS Accessibility, asks a localhost-only AI sidecar for a short continuation, renders it as ghost text near the caret, and inserts one ghost word each time you press Tab. Esc dismisses the suggestion.

The app is split intentionally:

- `mac/` owns macOS permissions, focus tracking, overlay rendering, Tab/Esc handling, and insertion.
- `ai-service/` owns Vercel AI SDK streaming calls, prompt construction, local learning, provider config, and Gateway/OpenRouter verification. It runs on Bun and builds to a bundled sidecar executable for the app.
- `shared/` documents the localhost protocol used between the two processes.
- `scripts/` contains local development, build, install, permissions, and smoke-test helpers.

## Requirements

- macOS 14+
- Xcode command line tools with Swift
- Bun 1.3+
- An OpenRouter key in `OPENROUTER_API_KEY`, or a Vercel AI Gateway key in `AI_GATEWAY_API_KEY`

## Quick Start

```sh
cp .env.example .env.local
# edit .env.local and set OPENROUTER_API_KEY
bun run try
```

`bun run try` builds the Bun sidecar, builds the macOS app, signs it with the first available local code-signing identity, installs it to `/Applications/GhostComplete.app`, asks the signed app to store `OPENROUTER_API_KEY` and/or `AI_GATEWAY_API_KEY` from `.env.local` or `.env` in Keychain, and launches the app. If no signing identity exists, it falls back to ad-hoc signing and macOS may require permissions again after each rebuild.

Grant Accessibility and Input Monitoring permissions when macOS prompts, then type in a supported text field. Tab accepts one ghost word at a time and Esc dismisses the suggestion.

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

- `GHOSTCOMPLETE_PROVIDER` to choose `openrouter` or `gateway`. If unset, GhostComplete uses OpenRouter when `OPENROUTER_API_KEY` is present, otherwise Gateway.
- `OPENROUTER_API_KEY` for OpenRouter auth.
- `AI_GATEWAY_API_KEY` for Vercel AI Gateway auth.
- `GHOSTCOMPLETE_MODEL` for the selected provider's model string. Default: `google/gemini-2.0-flash-lite`.
- `GHOSTCOMPLETE_TIMEOUT_MS` for the autocomplete model timeout. Default: `4000`.
- `GHOSTCOMPLETE_PORT` for development. Production launch uses the bundled Bun sidecar.
- `GHOSTCOMPLETE_LOG_DIR` to override the default JSONL trace directory.

The Swift app uses provider keys from its launch environment first and also stores those values in GhostComplete's app-owned Keychain item. Finder launches usually do not inherit your shell environment, so the app falls back to Keychain and passes the selected provider key to the sidecar at launch.

Seed Keychain with `bun run set-key`, or run `bun run install:local` after setting `OPENROUTER_API_KEY` or `AI_GATEWAY_API_KEY` in `.env.local`. Both commands use the signed GhostComplete app to write the Keychain item; they do not call the macOS `security` CLI to edit Keychain access lists.

Autocomplete UI preferences live in:

```text
~/Library/Application Support/GhostComplete/preferences.json
```

You can tune provider, model, debounce timing, ghost text reveal animation, reveal speed, and overlay X/Y nudges from the menu bar item under `Show Status, Logs, and Settings`. Saving the provider or model restarts only the local sidecar, not the whole app.

## AI Providers

The sidecar uses Vercel AI SDK `streamText` through OpenRouter or Vercel AI Gateway and then returns the final continuation to the Swift app over the local JSON protocol. Stream traces include provider, model, chunk count, first-token latency, stream latency, finish reason, provider response metadata, warnings, and token usage.

Autocomplete requests are trailing-debounced on the Mac side. GhostComplete defaults to 120 ms of idle typing, uses a shorter boundary-key delay for spaces and punctuation, skips prefixes shorter than 3 visible characters, sends at most the last 4000 characters before the caret, suppresses unchanged duplicate contexts, and cancels in-flight requests when newer typing arrives. Suggestions are capped at 80 characters.

Accepted text is incremental: if the overlay shows multiple words, each Tab press inserts only the next word and leaves the remaining ghost text visible.

Timeouts and cancellations are soft failures: the sidecar returns an empty completion and the app shows no overlay. Provider access and rate-limit errors are still logged and surfaced in status so they are diagnosable.

Overlay anchoring is driven by Accessibility caret bounds. For browser, Electron, and terminal-style fields, GhostComplete derives the caret from the previous character's bounds when zero-length caret bounds are unreliable. If the app does not expose usable caret bounds, GhostComplete estimates the caret within the focused element before falling back to the element bounds. Overlay traces record the anchor source and unclamped/clamped coordinates so bad placement can be diagnosed without logging raw typed text.

OpenRouter is the default local recommendation because Gateway free-tier accounts can rate-limit autocomplete quickly. Set `GHOSTCOMPLETE_PROVIDER=openrouter` and an OpenRouter model such as `google/gemini-2.0-flash-lite`, or change the provider and model from the Settings tab in the status window.

`openai/gpt-5.4` works only when your provider account has access to that model. On free-tier Gateway accounts it can fail with a restricted-model error, so the local default uses `google/gemini-2.0-flash-lite`.

Gateway free-tier accounts can still return rate-limit errors on otherwise valid models. When that happens GhostComplete backs off instead of spamming requests, the status window shows `Last completion: Rate limited`, and `sidecar.jsonl` records the Gateway error without raw typed text.

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
bun run set-key        # store OPENROUTER_API_KEY or AI_GATEWAY_API_KEY from .env or prompt in Keychain
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

Use the menu bar item `Show Status, Logs, and Settings` to browse human-readable app logs, sidecar logs, tuning controls, provider/model settings, profile facts, curated snippets, and recent accepted suggestions. The in-app log view hides low-value no-focus heartbeat noise and collapses repeated equivalent lines; the raw JSONL files remain unchanged. The Logs and Learning tabs both include Copy buttons for sharing diagnostics. From the terminal, use:

```sh
bun run logs
bun run logs:tail
```

The trace stream includes app launch, permission checks, sidecar launch, debounce suppression, duplicate-context suppression, request cancellation, request lifecycle, focus-snapshot skip reasons, stale responses, stream chunk counts, first-token latency, completion latency, AI SDK token usage, finish reasons, response metadata, overlay anchor source and coordinates, insertion strategy, accepted suggestions, validation failures, model access errors, Gateway rate limits, soft model timeouts, and sidecar shutdown. Raw typed context is not logged; trace records use lengths and SHA-256 hashes for text-bearing fields.

## Permissions And Keychain Prompts

GhostComplete shows a status window on launch with Accessibility, Input Monitoring, sidecar state, last completion state, and the exact bundle/path/signing requirement macOS is evaluating. If System Settings shows GhostComplete enabled but the app still reports `Not trusted by macOS` or `Event tap blocked`, remove all GhostComplete rows from Accessibility and Input Monitoring, add `/Applications/GhostComplete.app` again, then click `Retry Checks`. A full restart is not usually needed after granting permission.

Accessibility and Input Monitoring prompts are macOS privacy permissions for reading focused text fields and intercepting Tab/Esc. They are managed in System Settings.

Keychain prompts are different: they appear when the Finder-launched app reads `OPENROUTER_API_KEY` or `AI_GATEWAY_API_KEY` from the login Keychain. `bun run install:local` and `bun run set-key` seed the secret by running `/Applications/GhostComplete.app/Contents/MacOS/GhostComplete --store-api-key-and-exit`, so the signed app creates or updates its own Keychain item. If macOS still shows a GhostComplete Keychain dialog, choose `Always Allow`; `Allow` is one-time and can reappear on the next launch. A dialog that says `security wants to use the "login" keychain` is from another CLI process, not GhostComplete.

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
