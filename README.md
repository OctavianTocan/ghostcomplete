# GhostComplete

Native macOS inline autocomplete with a local Bun/TypeScript AI sidecar.

GhostComplete watches the focused editable field through macOS Accessibility, asks a localhost-only AI sidecar for a short continuation, renders it as ghost text near the caret, and inserts it when you press Tab. Esc dismisses the suggestion.

The app is split intentionally:

- `mac/` owns macOS permissions, focus tracking, overlay rendering, Tab/Esc handling, and insertion.
- `ai-service/` owns Vercel AI SDK calls, prompt construction, local learning, and provider config. It runs on Bun and builds to a bundled sidecar executable for the app.
- `shared/` documents the localhost protocol used between the two processes.
- `scripts/` contains local development, build, install, permissions, and smoke-test helpers.

The original Python prototype remains in `ghostcomplete.py` as reference material.

## Requirements

- macOS 14+
- Xcode command line tools with Swift
- Bun 1.3+
- A Vercel AI Gateway key in `AI_GATEWAY_API_KEY`

## Quick Start

```sh
cp .env.example .env
# edit .env and set AI_GATEWAY_API_KEY
bun run try
```

`bun run try` builds the Bun sidecar, builds and ad-hoc signs the macOS app, installs it to `/Applications/GhostComplete.app`, stores `AI_GATEWAY_API_KEY` from `.env` in Keychain, and launches the app.

Grant Accessibility and Input Monitoring permissions when macOS prompts, then type in a supported text field. Tab accepts the ghost suggestion and Esc dismisses it.

For development:

```sh
bun run dev
```

## Configuration

Runtime files live in:

```text
~/Library/Application Support/GhostComplete
```

Scripts source environment variables from `.env` automatically. `.env` is gitignored; use `.env.example` as the template.

The sidecar reads:

- `AI_GATEWAY_API_KEY` for Vercel AI Gateway auth.
- `GHOSTCOMPLETE_MODEL` for the AI Gateway model string. Default: `openai/gpt-4o-mini`.
- `GHOSTCOMPLETE_PORT` for development. Production launch uses the bundled Bun sidecar.

The Swift app reads the key from Keychain first. Seed it with `scripts/set-api-key`, or run `scripts/install-local` after setting `AI_GATEWAY_API_KEY` in `.env`. If the key is not in Keychain but `AI_GATEWAY_API_KEY` exists in the app environment, the app stores it in Keychain and passes it to the sidecar at launch.

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
bun run smoke          # smoke-test the local sidecar
bun run reset-perms    # reset macOS TCC permissions for the app
bun run reset-data     # reset permissions and delete learned data
```

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
