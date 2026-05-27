import { describe, expect, it } from "bun:test";
import { MockLanguageModelV2, simulateReadableStream } from "ai/test";
import { ModelCompletionEngine } from "../src/ai.js";

describe("AI SDK wrapper", () => {
  it("uses a fake AI SDK model for deterministic completions", async () => {
    const engine = new ModelCompletionEngine(
      new MockLanguageModelV2({
        doStream: async () => ({
          stream: simulateReadableStream({
            chunks: [
              { type: "text-start", id: "text-1" },
              { type: "text-delta", id: "text-1", delta: " finish" },
              { type: "text-delta", id: "text-1", delta: " this sentence" },
              { type: "text-end", id: "text-1" },
              {
                type: "response-metadata",
                id: "response-1",
                timestamp: new Date("2026-05-27T00:00:00.000Z"),
                modelId: "mock-model",
              },
              {
                type: "finish",
                finishReason: "stop",
                usage: {
                  inputTokens: 1,
                  outputTokens: 4,
                  totalTokens: 5,
                },
              },
            ],
          }),
        }),
      }),
      { temperature: 0.2, maxOutputTokens: 24, timeoutMs: 1000 },
    );

    const result = await engine.complete("Please", {
      system: "Return continuation only.",
      prompt: "Please",
    });

    expect(result.completion).toBe(" finish this sentence");
    expect(result.stream.chunkCount).toBe(2);
    expect(result.usage).toEqual({ inputTokens: 1, outputTokens: 4, totalTokens: 5 });
    expect(result.finishReason).toBe("stop");
    expect(result.response?.modelId).toBe("mock-model");
    expect(result.metadataFailures).toEqual([]);
  });
});
