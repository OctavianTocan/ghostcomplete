import { createHash } from "node:crypto";
import { MAX_SUGGESTION_CHARS } from "./autocomplete.js";

export function hashText(text: string): string {
  return createHash("sha256").update(text, "utf8").digest("hex");
}

export function hashContext(context: string): string {
  return hashText(context);
}

export function sanitizeContinuation(context: string, raw: string): string {
  let text = raw.replace(/\r/g, "").trimEnd();
  text = text.replace(/^["'`]+|["'`]+$/g, "");
  text = text.replace(/^\s*(?:continuation(?:\s+only)?|completion|output|answer)\s*:\s*/i, "");
  text = text.split("\n\n")[0] ?? "";

  const trimmedLeft = text.trimStart();
  const contextTail = context.slice(-500);

  if (trimmedLeft.startsWith(contextTail)) {
    text = trimmedLeft.slice(contextTail.length);
  } else if (trimmedLeft.startsWith(context)) {
    text = trimmedLeft.slice(context.length);
  }

  const normalizedContext = context.replace(/\s+/g, " ").trim().toLowerCase();
  const normalizedText = text.replace(/\s+/g, " ").trim().toLowerCase();
  if (!normalizedText || normalizedText === normalizedContext) {
    return "";
  }

  if (normalizedText.length < 2 || /^[\p{P}\p{S}]+$/u.test(normalizedText)) {
    return "";
  }

  if (normalizedContext.endsWith(normalizedText)) {
    return "";
  }

  return text.slice(0, MAX_SUGGESTION_CHARS);
}
