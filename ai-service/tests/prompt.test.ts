import { describe, expect, it } from "bun:test";
import { defaultProfile } from "../src/profile.js";
import { buildPrompt } from "../src/prompt.js";

describe("prompt construction", () => {
  it("enforces continuation-only behavior and includes profile examples", () => {
    const prompt = buildPrompt(
      {
        requestId: "1",
        context: "I think we should",
        app: { bundleId: "com.apple.TextEdit", name: "TextEdit" },
      },
      {
        ...defaultProfile,
        name: "Octavian",
        role: "builder",
        vocabulary: ["sidecar", "ghost text"],
        neverSay: ["just circling back"],
      },
      [{ text: " ship the smallest useful version first.", source: "accepted" }],
    );

    expect(prompt.system).toContain("Return only the next characters");
    expect(prompt.system).toContain("2 to 12 words");
    expect(prompt.system).toContain("Do not return a single character");
    expect(prompt.prompt).toContain("Octavian");
    expect(prompt.prompt).toContain("Never say");
    expect(prompt.prompt).toContain("ship the smallest useful version");
  });
});
