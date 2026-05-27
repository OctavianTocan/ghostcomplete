import { createHash } from "node:crypto";

export function hashContext(context: string): string {
  return createHash("sha256").update(context, "utf8").digest("hex");
}

export function sanitizeContinuation(context: string, raw: string): string {
  let text = raw.replace(/\r/g, "").trimEnd();
  text = text.replace(/^["'`]+|["'`]+$/g, "");
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

  if (normalizedContext.endsWith(normalizedText)) {
    return "";
  }

  return text.slice(0, 280);
}
