# Changelog

All notable changes to GhostComplete will be documented in this file.

## 0.1.0 - 2026-05-27

- Added native macOS menu-bar app with Accessibility focus tracking, global Tab/Esc handling, ghost text overlay, and synthetic insertion with pasteboard fallback.
- Added local Bun/TypeScript AI sidecar using Vercel AI SDK and Vercel AI Gateway.
- Switched AI generation to Vercel AI SDK `streamText`, with traces for stream latency, finish reason, provider metadata, warnings, and token usage.
- Removed the old Python prototype and PyObjC dependency file from the active repository.
- Added a launch status window with Accessibility, Input Monitoring, and sidecar state plus settings shortcuts.
- Improved permission diagnostics with exact bundle path/signing requirement display, bounded Input Monitoring retries, and manual retry controls.
- Changed local app signing to prefer an available stable code-signing identity before falling back to ad-hoc signing.
- Added localhost-only authenticated `/complete`, `/learn`, and `/health` sidecar endpoints.
- Added structured JSONL tracing for the macOS app and Bun sidecar under `~/Library/Application Support/GhostComplete/logs`.
- Added explicit sidecar trace events when AI SDK metadata or token-usage promises are unavailable.
- Added installer handling for running app updates: local install now quits GhostComplete before replacing `/Applications/GhostComplete.app`, and `bun run try` relaunches the fresh build.
- Added `bun run logs` and `bun run logs:tail` for quick local diagnostics.
- Added local privacy-first learning store with SQLite, accepted/curated examples, profile JSON, and no default raw typing persistence.
- Added Bun build/test/dev scripts, local installer, permission reset helper, Keychain API key seeding, and sidecar smoke test.
- Added root-level Bun scripts for one-command local install, launch, smoke testing, and reset workflows.
- Added Swift and Bun unit/integration tests for skip rules, debounce behavior, insertion strategy, schema validation, prompts, privacy helpers, AI wrapper, and sidecar HTTP behavior.
- Fixed Finder-launched app completions by persisting non-secret sidecar model settings from `.env.local` and passing them to the bundled sidecar.
- Changed the default Gateway model to `google/gemini-2.0-flash-lite` because the previous `openai/gpt-5.4` default is restricted on free-tier Gateway accounts.
- Changed the status window so launch health can auto-dismiss while manually opened status stays visible.
- Added last-completion diagnostics, overlay coordinate traces, Gateway rate-limit classification, and filtering for one-character or punctuation-only suggestions.
- Changed autocomplete requests to use a trailing debounce, 3-character prefix gate, 4000-character prefix cap, duplicate-context suppression, cancellable in-flight requests, 80-character suggestion cap, and soft empty completions for timeout/cancel.
- Improved overlay anchoring for browser, Electron, and terminal-style fields by deriving the caret from previous-character AX bounds, estimating a caret inside the focused element when caret bounds are unavailable, keeping element fallback bounds separate, and logging unclamped/clamped overlay coordinates without per-key noise.
- Fixed canceled AI streams being logged as successful empty completions with unavailable metadata; cancellation now produces the intended soft-empty trace.
- Changed the default autocomplete idle debounce from 300 ms to 120 ms, with a shorter delay after spaces and punctuation so completions feel ready when typing stops.
- Changed Tab acceptance to insert only the next ghost word at a time while keeping the remaining suggestion visible.
- Added local ghost-text reveal animation plus user-tunable debounce, animation speed, and overlay X/Y nudge preferences.
- Added a tabbed status panel with embedded app/sidecar JSONL log browsing, settings controls, learned words, profile facts, and recent accepted suggestions.
- Added OpenRouter as a first-class Vercel AI SDK provider, with `GHOSTCOMPLETE_PROVIDER=openrouter`, `OPENROUTER_API_KEY`, and Keychain seeding alongside AI Gateway.
- Added provider and model controls to the Settings tab; saving either one persists sidecar runtime settings and restarts the local sidecar.
- Changed the Logs tab to render JSONL traces as human-readable diagnostics, hide low-value no-focus heartbeat chatter, collapse repeated lines, and added Copy buttons to Logs and Learning.
- Cleaned the Learning tab so it shows profile vocabulary, curated snippets, accepted suggestions, and real learning events instead of noisy request events or guessed word counts.
