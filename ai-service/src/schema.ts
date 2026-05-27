import type { AppContext, CompleteRequest, LearnRequest, SelectionRange } from "./types.js";

const MAX_CONTEXT_CHARS = 2000;
const MAX_SUGGESTION_CHARS = 2000;

export class ValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ValidationError";
  }
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readString(value: unknown, name: string, minLength = 1, maxLength = Number.MAX_SAFE_INTEGER): string {
  if (typeof value !== "string") {
    throw new ValidationError(`${name} must be a string`);
  }
  if (value.trim().length < minLength) {
    throw new ValidationError(`${name} is required`);
  }
  if (value.length > maxLength) {
    throw new ValidationError(`${name} is too long`);
  }
  return value;
}

function readApp(value: unknown): AppContext {
  if (!isObject(value)) {
    throw new ValidationError("app must be an object");
  }
  return {
    bundleId: readString(value.bundleId, "app.bundleId"),
    name: readString(value.name, "app.name"),
  };
}

function readSelection(value: unknown): SelectionRange | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (!isObject(value)) {
    throw new ValidationError("selection must be an object");
  }
  if (!Number.isInteger(value.location) || Number(value.location) < 0) {
    throw new ValidationError("selection.location must be a non-negative integer");
  }
  if (!Number.isInteger(value.length) || Number(value.length) < 0) {
    throw new ValidationError("selection.length must be a non-negative integer");
  }
  return {
    location: Number(value.location),
    length: Number(value.length),
  };
}

export function parseCompleteRequest(value: unknown): CompleteRequest {
  if (!isObject(value)) {
    throw new ValidationError("request body must be an object");
  }
  return {
    requestId: readString(value.requestId, "requestId"),
    context: readString(value.context, "context", 1, MAX_CONTEXT_CHARS),
    app: readApp(value.app),
    selection: readSelection(value.selection),
  };
}

export function parseLearnRequest(value: unknown): LearnRequest {
  if (!isObject(value)) {
    throw new ValidationError("request body must be an object");
  }
  const event = readString(value.event, "event") as LearnRequest["event"];
  if (!["accepted", "rejected", "curated"].includes(event)) {
    throw new ValidationError("event must be accepted, rejected, or curated");
  }
  return {
    requestId: readString(value.requestId, "requestId"),
    event,
    contextHash: readString(value.contextHash, "contextHash", 16),
    suggestion: readString(value.suggestion, "suggestion", 0, MAX_SUGGESTION_CHARS),
    app: readApp(value.app),
  };
}
