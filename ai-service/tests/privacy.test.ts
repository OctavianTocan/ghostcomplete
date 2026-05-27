import { describe, expect, it } from "bun:test";
import { hashContext, sanitizeContinuation } from "../src/privacy.js";

describe("privacy helpers", () => {
  it("hashes context deterministically", () => {
    expect(hashContext("hello")).toHaveLength(64);
    expect(hashContext("hello")).toBe(hashContext("hello"));
  });

  it("strips repeated input from model output", () => {
    expect(sanitizeContinuation("I want to", "I want to finish this")).toBe(" finish this");
  });

  it("rejects pure repeats", () => {
    expect(sanitizeContinuation("I want to", "I want to")).toBe("");
  });

  it("strips provider labels", () => {
    expect(sanitizeContinuation("I want to", "Continuation only: finish this")).toBe("finish this");
  });

  it("rejects single characters and standalone punctuation", () => {
    expect(sanitizeContinuation("I want to", ".")).toBe("");
    expect(sanitizeContinuation("I want to", "a")).toBe("");
  });
});
