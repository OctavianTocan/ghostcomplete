# Changelog

All notable changes to GhostComplete will be documented in this file.

## 0.1.0 - 2026-05-27

- Added native macOS menu-bar app with Accessibility focus tracking, global Tab/Esc handling, ghost text overlay, and synthetic insertion with pasteboard fallback.
- Added local Bun/TypeScript AI sidecar using Vercel AI SDK and Vercel AI Gateway.
- Added localhost-only authenticated `/complete`, `/learn`, and `/health` sidecar endpoints.
- Added local privacy-first learning store with SQLite, accepted/curated examples, profile JSON, and no default raw typing persistence.
- Added Bun build/test/dev scripts, local installer, permission reset helper, Keychain API key seeding, and sidecar smoke test.
- Added Swift and Bun unit/integration tests for skip rules, debounce behavior, insertion strategy, schema validation, prompts, privacy helpers, AI wrapper, and sidecar HTTP behavior.
