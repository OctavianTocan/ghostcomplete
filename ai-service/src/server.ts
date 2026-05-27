import { performance } from "node:perf_hooks";
import type { CompletionEngine } from "./ai.js";
import type { ServiceConfig } from "./config.js";
import { ensureProfile } from "./profile.js";
import { buildPrompt } from "./prompt.js";
import { hashContext } from "./privacy.js";
import { parseCompleteRequest, parseLearnRequest, ValidationError } from "./schema.js";
import { LearningStore } from "./storage.js";

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status });
}

async function readBody(req: Request): Promise<unknown> {
  const raw = await req.text();
  if (raw.length > 64 * 1024) {
    throw new ValidationError("request body too large");
  }
  try {
    return raw ? JSON.parse(raw) : {};
  } catch {
    throw new ValidationError("request body must be valid JSON");
  }
}

function isLoopbackHost(host: string): boolean {
  return host === "127.0.0.1" || host === "::1" || host === "localhost";
}

function isAuthorized(req: Request, token: string): boolean {
  if (!token) return false;
  return req.headers.get("authorization") === `Bearer ${token}`;
}

export function createServer(config: ServiceConfig, engine: CompletionEngine, store: LearningStore): Bun.Server<unknown> {
  if (!isLoopbackHost(config.host)) {
    throw new Error("GhostComplete sidecar must bind to a loopback host");
  }

  return Bun.serve({
    hostname: config.host,
    port: config.port,
    async fetch(req) {
      const url = new URL(req.url);

      if (req.method === "GET" && url.pathname === "/health") {
        return json({ ok: true, model: config.model });
      }

      if (!isAuthorized(req, config.token)) {
        return json({ error: "unauthorized" }, 401);
      }

      try {
        if (req.method === "POST" && url.pathname === "/complete") {
          const body = await readBody(req);
          const completeRequest = parseCompleteRequest(body);
          const contextHash = hashContext(completeRequest.context);
          const profile = ensureProfile(config.profilePath);
          const examples = store.getExamples(completeRequest.app);
          const prompt = buildPrompt(completeRequest, profile, examples);
          const start = performance.now();
          store.recordCompletionRequest(completeRequest.requestId, contextHash, completeRequest.app);
          const completion = await engine.complete(completeRequest.context, prompt);

          return json({
            requestId: completeRequest.requestId,
            completion,
            model: config.model,
            latencyMs: Math.round(performance.now() - start),
          });
        }

        if (req.method === "POST" && url.pathname === "/learn") {
          const body = await readBody(req);
          const learnRequest = parseLearnRequest(body);
          store.recordLearnEvent(learnRequest);
          return json({ ok: true });
        }

        return json({ error: "not_found" }, 404);
      } catch (error) {
        if (error instanceof ValidationError) {
          return json({ error: "bad_request", message: error.message }, 400);
        }

        const code = error instanceof Error && error.name === "AbortError" ? "timeout" : "sidecar_error";
        return json({ error: code }, code === "timeout" ? 504 : 500);
      }
    }
  });
}
