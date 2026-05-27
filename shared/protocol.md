# GhostComplete Local Protocol

The Swift app launches the sidecar on localhost and passes a per-session bearer token in `GHOSTCOMPLETE_TOKEN`.

## Auth

Every mutating or AI endpoint requires:

```http
Authorization: Bearer <GHOSTCOMPLETE_TOKEN>
```

The sidecar rejects requests from non-loopback addresses.

## POST /complete

Request:

```json
{
  "requestId": "uuid-or-monotonic-id",
  "context": "trailing text before the caret",
  "app": {
    "bundleId": "com.apple.TextEdit",
    "name": "TextEdit"
  },
  "selection": {
    "location": 120,
    "length": 0
  }
}
```

Response:

```json
{
  "requestId": "same-id",
  "completion": " short continuation",
  "model": "openai/gpt-5.4",
  "latencyMs": 420
}
```

Validation rules:

- `context` is required and capped at 2,000 characters.
- `requestId` is required so Swift can ignore stale responses.
- The sidecar returns only the continuation, never the repeated prompt prefix.

## POST /learn

Request:

```json
{
  "requestId": "uuid-or-monotonic-id",
  "event": "accepted",
  "contextHash": "sha256-context-hash",
  "suggestion": " accepted continuation",
  "app": {
    "bundleId": "com.apple.TextEdit",
    "name": "TextEdit"
  }
}
```

Response:

```json
{
  "ok": true
}
```

Only accepted suggestions and user-curated snippets are persisted by default. Raw typed context is not stored.

## GET /health

Returns sidecar status without exposing typed text:

```json
{
  "ok": true,
  "model": "openai/gpt-5.4"
}
```
