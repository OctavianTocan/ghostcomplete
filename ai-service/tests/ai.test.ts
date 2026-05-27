import { describe, expect, it } from "bun:test";
import { MockLanguageModelV2 } from "ai/test";
import { ModelCompletionEngine } from "../src/ai.js";

describe("AI SDK wrapper", () => {
  it("uses a fake AI SDK model for deterministic completions", async () => {
    const engine = new ModelCompletionEngine(
      new MockLanguageModelV2({
        doGenerate: async () => ({
          content: [{ type: "text", text: " finish this sentence" }],
          finishReason: "stop",
          usage: {
            inputTokens: 1,
            outputTokens: 4,
            totalTokens: 5,
          },
          warnings: [],
        }),
      }),
      { temperature: 0.2, maxOutputTokens: 24, timeoutMs: 1000 },
    );

    const text = await engine.complete("Please", {
      system: "Return continuation only.",
      prompt: "Please",
    });

    expect(text).toBe(" finish this sentence");
  });
});
