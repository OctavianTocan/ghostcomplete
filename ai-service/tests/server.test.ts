import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "bun:test";
import { FakeCompletionEngine } from "../src/ai.js";
import type { CompletionEngine } from "../src/ai.js";
import type { ServiceConfig } from "../src/config.js";
import type { TraceLogger } from "../src/logger.js";
import { createServer } from "../src/server.js";
import { LearningStore } from "../src/storage.js";

const tmpDirs: string[] = [];

async function freeLoopbackPort(): Promise<number> {
  return await new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (!address || typeof address === "string") {
        server.close(() => reject(new Error("Could not allocate a test port")));
        return;
      }
      server.close(() => resolve(address.port));
    });
  });
}

async function makeConfig(): Promise<ServiceConfig> {
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
    port: await freeLoopbackPort(),
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
    const config = await makeConfig();
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
    const config = await makeConfig();
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

  it("logs AI SDK stream metadata and token usage", async () => {
    const config = await makeConfig();
    const store = new LearningStore(config.databasePath);
    const events: Array<{ event: string; fields: Record<string, unknown> }> = [];
    const logger: TraceLogger = {
      debug: (event, fields = {}) => events.push({ event, fields }),
      info: (event, fields = {}) => events.push({ event, fields }),
      warn: (event, fields = {}) => events.push({ event, fields }),
      error: (event, fields = {}) => events.push({ event, fields }),
    };
    const engine: CompletionEngine = {
      complete: async () => ({
        completion: " done",
        usage: { inputTokens: 3, outputTokens: 2, totalTokens: 5 },
        totalUsage: { inputTokens: 3, outputTokens: 2, totalTokens: 5 },
        finishReason: "stop",
        response: {
          id: "response-1",
          timestamp: new Date("2026-05-27T00:00:00.000Z"),
          modelId: "test/model",
        },
        metadataFailures: [],
        stream: {
          chunkCount: 2,
          firstChunkLatencyMs: 12,
          streamLatencyMs: 20,
          rawCompletionLength: 5,
        },
      }),
    };
    const server = createServer(config, engine, store, logger);

    try {
      const response = await fetch(`http://127.0.0.1:${server.port}/complete`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: "Bearer test-token",
        },
        body: JSON.stringify({
          requestId: "usage-test",
          context: "Nearly",
          app: { bundleId: "com.apple.TextEdit", name: "TextEdit" },
        }),
      });

      expect(response.status).toBe(200);
      const event = events.find((entry) => entry.event === "completion_request_succeeded");
      expect(event?.fields).toMatchObject({
        requestId: "usage-test",
        streamChunkCount: 2,
        streamFirstChunkLatencyMs: 12,
        streamLatencyMs: 20,
        finishReason: "stop",
        usage: { inputTokens: 3, outputTokens: 2, totalTokens: 5 },
        totalUsage: { inputTokens: 3, outputTokens: 2, totalTokens: 5 },
        metadataFailureCount: 0,
      });
    } finally {
      server.stop();
      store.close();
    }
  });

  it("logs AI SDK metadata collection failures without failing completions", async () => {
    const config = await makeConfig();
    const store = new LearningStore(config.databasePath);
    const events: Array<{ event: string; fields: Record<string, unknown> }> = [];
    const logger: TraceLogger = {
      debug: (event, fields = {}) => events.push({ event, fields }),
      info: (event, fields = {}) => events.push({ event, fields }),
      warn: (event, fields = {}) => events.push({ event, fields }),
      error: (event, fields = {}) => events.push({ event, fields }),
    };
    const engine: CompletionEngine = {
      complete: async () => ({
        completion: " done",
        metadataFailures: [{ field: "usage", message: "usage unavailable" }],
        stream: {
          chunkCount: 1,
          streamLatencyMs: 20,
          rawCompletionLength: 5,
        },
      }),
    };
    const server = createServer(config, engine, store, logger);

    try {
      const response = await fetch(`http://127.0.0.1:${server.port}/complete`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: "Bearer test-token",
        },
        body: JSON.stringify({
          requestId: "metadata-test",
          context: "Nearly",
          app: { bundleId: "com.apple.TextEdit", name: "TextEdit" },
        }),
      });

      expect(response.status).toBe(200);
      const metadataEvent = events.find((entry) => entry.event === "ai_metadata_unavailable");
      expect(metadataEvent?.fields).toMatchObject({
        requestId: "metadata-test",
        failureCount: 1,
        failures: [{ field: "usage", message: "usage unavailable" }],
      });
      const successEvent = events.find((entry) => entry.event === "completion_request_succeeded");
      expect(successEvent?.fields).toMatchObject({ metadataFailureCount: 1 });
    } finally {
      server.stop();
      store.close();
    }
  });

  it("classifies Gateway rate limits for the app", async () => {
    const config = await makeConfig();
    const store = new LearningStore(config.databasePath);
    const engine: CompletionEngine = {
      complete: async () => {
        throw new Error("AI stream failed: Free tier requests on this model are rate-limited.");
      },
    };
    const server = createServer(config, engine, store);

    try {
      const response = await fetch(`http://127.0.0.1:${server.port}/complete`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: "Bearer test-token",
        },
        body: JSON.stringify({
          requestId: "rate-limit-test",
          context: "Nearly finished",
          app: { bundleId: "com.apple.TextEdit", name: "TextEdit" },
        }),
      });

      expect(response.status).toBe(429);
      const body = await response.json() as { error: string; message: string };
      expect(body.error).toBe("rate_limited");
      expect(body.message).toContain("rate-limited");
    } finally {
      server.stop();
      store.close();
    }
  });
});
