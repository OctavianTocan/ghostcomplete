import { describe, expect, it } from "bun:test";
import { MAX_SUGGESTION_CHARS } from "../src/autocomplete.js";
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

  it("truncates suggestions to the autocomplete cap", () => {
    const result = sanitizeContinuation("I want to", " ".repeat(1) + "x".repeat(MAX_SUGGESTION_CHARS + 20));
    expect(result).toHaveLength(MAX_SUGGESTION_CHARS);
  });
});
