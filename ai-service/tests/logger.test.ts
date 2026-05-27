import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, expect, it } from "bun:test";
import { JsonlTraceLogger } from "../src/logger.js";

describe("jsonl trace logger", () => {
  it("writes structured one-line JSON records", () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "ghostcomplete-logs-"));
    const logPath = path.join(dir, "sidecar.jsonl");

    try {
      const logger = new JsonlTraceLogger(logPath);
      logger.info("test_event", { requestId: "abc", latencyMs: 42, ok: true });

      const lines = fs.readFileSync(logPath, "utf8").trim().split("\n").map((line) => JSON.parse(line));
      expect(lines.length).toBe(2);
      expect(lines[1]).toMatchObject({
        level: "info",
        component: "sidecar",
        event: "test_event",
        requestId: "abc",
        latencyMs: 42,
        ok: true,
      });
      expect(typeof lines[1].ts).toBe("string");
      expect(typeof lines[1].pid).toBe("number");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });
});
