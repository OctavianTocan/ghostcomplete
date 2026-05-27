import fs from "node:fs";
import path from "node:path";

type LogLevel = "debug" | "info" | "warn" | "error";
type JsonValue = string | number | boolean | null | JsonValue[] | { [key: string]: JsonValue };
type LogFields = Record<string, unknown>;

export interface TraceLogger {
  debug(event: string, fields?: LogFields): void;
  info(event: string, fields?: LogFields): void;
  warn(event: string, fields?: LogFields): void;
  error(event: string, fields?: LogFields): void;
}

export const noopLogger: TraceLogger = {
  debug: () => {},
  info: () => {},
  warn: () => {},
  error: () => {},
};

export class JsonlTraceLogger implements TraceLogger {
  constructor(
    private readonly filePath: string,
    private readonly component = "sidecar",
  ) {
    this.ensureLogDirectory();
    this.info("logger_configured", { path: filePath });
  }

  debug(event: string, fields: LogFields = {}): void {
    this.write("debug", event, fields);
  }

  info(event: string, fields: LogFields = {}): void {
    this.write("info", event, fields);
  }

  warn(event: string, fields: LogFields = {}): void {
    this.write("warn", event, fields);
  }

  error(event: string, fields: LogFields = {}): void {
    this.write("error", event, fields);
  }

  private write(level: LogLevel, event: string, fields: LogFields): void {
    const payload = {
      ...sanitizeFields(fields),
      ts: new Date().toISOString(),
      level,
      component: this.component,
      event,
      pid: process.pid,
    };

    try {
      fs.appendFileSync(this.filePath, `${JSON.stringify(payload)}\n`, { encoding: "utf8" });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "trace_write_failed", message }));
    }
  }

  private ensureLogDirectory(): void {
    try {
      fs.mkdirSync(path.dirname(this.filePath), { recursive: true, mode: 0o700 });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "trace_directory_failed", message }));
    }
  }
}

function sanitizeFields(fields: LogFields): Record<string, JsonValue> {
  const sanitized: Record<string, JsonValue> = {};
  for (const [key, value] of Object.entries(fields)) {
    sanitized[key] = sanitizeValue(value);
  }
  return sanitized;
}

function sanitizeValue(value: unknown): JsonValue {
  if (value === null || value === undefined) return null;
  if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") return value;
  if (typeof value === "bigint") return value.toString();
  if (value instanceof Error) {
    return {
      name: value.name,
      message: value.message,
    };
  }
  if (Array.isArray(value)) {
    return value.map(sanitizeValue);
  }
  if (typeof value === "object") {
    const result: Record<string, JsonValue> = {};
    for (const [key, nested] of Object.entries(value)) {
      result[key] = sanitizeValue(nested);
    }
    return result;
  }
  return String(value);
}
