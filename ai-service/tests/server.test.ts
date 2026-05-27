import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "bun:test";
import { FakeCompletionEngine } from "../src/ai.js";
import type { ServiceConfig } from "../src/config.js";
import { createServer } from "../src/server.js";
import { LearningStore } from "../src/storage.js";

const tmpDirs: string[] = [];

function makeConfig(): ServiceConfig {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "ghostcomplete-test-"));
  tmpDirs.push(dir);
  return {
    appSupportDir: dir,
    databasePath: path.join(dir, "learning.sqlite"),
    profilePath: path.join(dir, "profile.json"),
    logDir: path.join(dir, "logs"),
    sidecarLogPath: path.join(dir, "logs", "sidecar.jsonl"),
    model: "test/model",
    token: "test-token",
    host: "127.0.0.1",
    port: 0,
    timeoutMs: 1000,
    maxOutputTokens: 24,
    temperature: 0.1,
  };
}

afterEach(() => {
  for (const dir of tmpDirs.splice(0)) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

describe("sidecar server", () => {
  it("returns deterministic completions from a fake engine", async () => {
    const config = makeConfig();
    const store = new LearningStore(config.databasePath);
    const server = createServer(config, new FakeCompletionEngine(" done"), store);

    try {
      const response = await fetch(`http://127.0.0.1:${server.port}/complete`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: "Bearer test-token",
        },
        body: JSON.stringify({
          requestId: "abc",
          context: "Nearly",
          app: { bundleId: "com.apple.TextEdit", name: "TextEdit" },
        }),
      });

      expect(response.status).toBe(200);
      await expect(response.json()).resolves.toMatchObject({ requestId: "abc", completion: " done" });
    } finally {
      server.stop();
      store.close();
    }
  });

  it("rejects missing tokens", async () => {
    const config = makeConfig();
    const store = new LearningStore(config.databasePath);
    const server = createServer(config, new FakeCompletionEngine(" done"), store);

    try {
      const response = await fetch(`http://127.0.0.1:${server.port}/complete`, { method: "POST" });
      expect(response.status).toBe(401);
    } finally {
      server.stop();
      store.close();
    }
  });
});
