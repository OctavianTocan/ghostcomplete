import { describe, expect, it } from "bun:test";
import { MAX_PREFIX_CHARS } from "../src/autocomplete.js";
import { parseCompleteRequest, parseLearnRequest } from "../src/schema.js";

describe("schema validation", () => {
  it("accepts a valid complete request", () => {
    const parsed = parseCompleteRequest({
      requestId: "1",
      context: "Please finish this",
      app: { bundleId: "com.apple.TextEdit", name: "TextEdit" },
      selection: { location: 18, length: 0 },
    });

    expect(parsed.app.name).toBe("TextEdit");
  });

  it("rejects missing context", () => {
    expect(() =>
      parseCompleteRequest({
        requestId: "1",
        app: { bundleId: "com.apple.TextEdit", name: "TextEdit" },
      }),
    ).toThrow(/context/);
  });

  it("accepts autocomplete prefixes up to the configured cap", () => {
    const parsed = parseCompleteRequest({
      requestId: "1",
      context: "a".repeat(MAX_PREFIX_CHARS),
      app: { bundleId: "com.apple.TextEdit", name: "TextEdit" },
    });

    expect(parsed.context).toHaveLength(MAX_PREFIX_CHARS);
  });

  it("rejects autocomplete prefixes over the configured cap", () => {
    expect(() =>
      parseCompleteRequest({
        requestId: "1",
        context: "a".repeat(MAX_PREFIX_CHARS + 1),
        app: { bundleId: "com.apple.TextEdit", name: "TextEdit" },
      }),
    ).toThrow(/context is too long/);
  });

  it("accepts learn events without raw context", () => {
    const parsed = parseLearnRequest({
      requestId: "1",
      event: "accepted",
      contextHash: "0123456789abcdef",
      suggestion: " next words",
      app: { bundleId: "com.apple.TextEdit", name: "TextEdit" },
    });

    expect(parsed.event).toBe("accepted");
  });
});
