import { performance } from "node:perf_hooks";
import type { CompletionEngine, CompletionResult } from "./ai.js";
import type { ServiceConfig } from "./config.js";
import { noopLogger, type TraceLogger } from "./logger.js";
import { ensureProfile } from "./profile.js";
import { buildPrompt } from "./prompt.js";
import { hashContext, hashText } from "./privacy.js";
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

export function createServer(
  config: ServiceConfig,
  engine: CompletionEngine,
  store: LearningStore,
  logger: TraceLogger = noopLogger,
): Bun.Server<unknown> {
  if (!isLoopbackHost(config.host)) {
    throw new Error("GhostComplete sidecar must bind to a loopback host");
  }

  logger.info("server_starting", {
    host: config.host,
    requestedPort: config.port,
    provider: config.provider,
    model: config.model,
    databasePath: config.databasePath,
    profilePath: config.profilePath,
    fakeCompletion: config.fakeCompletion !== undefined,
  });

  const server = Bun.serve({
    hostname: config.host,
    port: config.port,
    async fetch(req) {
      const url = new URL(req.url);
      const requestStarted = performance.now();
      let requestId: string | undefined;

      logger.debug("http_request_started", {
        method: req.method,
        path: url.pathname,
        hasAuthorization: req.headers.has("authorization"),
      });

      if (req.method === "GET" && url.pathname === "/health") {
        logger.debug("health_check", { latencyMs: Math.round(performance.now() - requestStarted) });
        return json({ ok: true, provider: config.provider, model: config.model });
      }

      if (!isAuthorized(req, config.token)) {
        logger.warn("http_request_unauthorized", {
          method: req.method,
          path: url.pathname,
          latencyMs: Math.round(performance.now() - requestStarted),
        });
        return json({ error: "unauthorized" }, 401);
      }

      try {
        if (req.method === "POST" && url.pathname === "/complete") {
          const body = await readBody(req);
          const completeRequest = parseCompleteRequest(body);
          requestId = completeRequest.requestId;
          const contextHash = hashContext(completeRequest.context);
          const profile = ensureProfile(config.profilePath);
          const examples = store.getExamples(completeRequest.app);
          const prompt = buildPrompt(completeRequest, profile, examples);

          logger.info("completion_request_received", {
            requestId,
            appBundleId: completeRequest.app.bundleId,
            appName: completeRequest.app.name,
            contextLength: completeRequest.context.length,
            contextHash,
            ...(config.rawTextLogging ? {
              context: completeRequest.context,
              contextSuffix: completeRequest.context.slice(-500),
              promptSystem: prompt.system,
              promptUser: prompt.prompt,
            } : {}),
            hasSelection: completeRequest.selection !== undefined,
            selectionLocation: completeRequest.selection?.location ?? null,
            selectionLength: completeRequest.selection?.length ?? null,
            examplesCount: examples.length,
          });

          store.recordCompletionRequest(completeRequest.requestId, contextHash, completeRequest.app);
          const result = await engine.complete(completeRequest.context, prompt, req.signal);
          const completion = result.completion;
          const latencyMs = Math.round(performance.now() - requestStarted);

          if (result.metadataFailures.length > 0) {
            logger.warn("ai_metadata_unavailable", {
              requestId,
              failureCount: result.metadataFailures.length,
              failures: result.metadataFailures,
            });
          }

          logger.info("completion_request_succeeded", {
            requestId,
            provider: config.provider,
            model: config.model,
            latencyMs,
            completionLength: completion.length,
            completionHash: hashText(completion),
            ...(config.rawTextLogging ? { completion } : {}),
            ...completionTraceFields(result),
          });

          return json({
            requestId: completeRequest.requestId,
            completion,
            model: config.model,
            latencyMs,
          });
        }

        if (req.method === "POST" && url.pathname === "/learn") {
          const body = await readBody(req);
          const learnRequest = parseLearnRequest(body);
          requestId = learnRequest.requestId;
          logger.info("learn_event_received", {
            requestId,
            eventType: learnRequest.event,
            appBundleId: learnRequest.app.bundleId,
            appName: learnRequest.app.name,
            contextHash: learnRequest.contextHash,
            suggestionLength: learnRequest.suggestion.length,
            suggestionHash: hashText(learnRequest.suggestion),
          });
          store.recordLearnEvent(learnRequest);
          logger.info("learn_event_recorded", {
            requestId,
            eventType: learnRequest.event,
            latencyMs: Math.round(performance.now() - requestStarted),
          });
          return json({ ok: true });
        }

        logger.warn("http_request_not_found", {
          method: req.method,
          path: url.pathname,
          latencyMs: Math.round(performance.now() - requestStarted),
        });
        return json({ error: "not_found" }, 404);
      } catch (error) {
        if (error instanceof ValidationError) {
          logger.warn("request_validation_failed", {
            path: url.pathname,
            requestId: requestId ?? null,
            message: error.message,
            latencyMs: Math.round(performance.now() - requestStarted),
          });
          return json({ error: "bad_request", message: error.message }, 400);
        }

        const classified = classifyRequestError(error);
        if (classified.softEmpty) {
          const latencyMs = Math.round(performance.now() - requestStarted);
          logger.warn("completion_request_soft_empty", {
            path: url.pathname,
            requestId: requestId ?? null,
            code: classified.code,
            message: classified.message,
            latencyMs,
          });
          return json({
            requestId: requestId ?? "",
            completion: "",
            model: config.model,
            latencyMs,
          });
        }
        logger.error("request_failed", {
          path: url.pathname,
          requestId: requestId ?? null,
          code: classified.code,
          message: classified.message,
          latencyMs: Math.round(performance.now() - requestStarted),
        });
        return json({ error: classified.code, message: classified.message }, classified.status);
      }
    }
  });

  logger.info("server_listening", {
    host: config.host,
    port: server.port,
    provider: config.provider,
    model: config.model,
  });

  return server;
}

function classifyRequestError(error: unknown): { code: string; status: number; message: string; softEmpty: boolean } {
  const message = error instanceof Error ? error.message : String(error);
  const name = error instanceof Error ? error.name : "";
  const lower = message.toLowerCase();

  if (name === "TimeoutError" || lower.includes("timeout") || lower.includes("timed out")) {
    return { code: "timeout", status: 200, message, softEmpty: true };
  }
  if (name === "AbortError" || lower.includes("abort") || lower.includes("cancelled") || lower.includes("canceled")) {
    return { code: "cancelled", status: 200, message, softEmpty: true };
  }
  if (lower.includes("rate-limit") || lower.includes("rate limit") || lower.includes("rate_limited")) {
    return { code: "rate_limited", status: 429, message, softEmpty: false };
  }
  if (
    lower.includes("restricted model") ||
    lower.includes("access to this model") ||
    lower.includes("model access")
  ) {
    return { code: "model_access_denied", status: 403, message, softEmpty: false };
  }

  return { code: "sidecar_error", status: 500, message, softEmpty: false };
}

function completionTraceFields(result: CompletionResult): Record<string, unknown> {
  return {
    streamChunkCount: result.stream.chunkCount,
    streamFirstChunkLatencyMs: result.stream.firstChunkLatencyMs ?? null,
    streamLatencyMs: result.stream.streamLatencyMs,
    rawCompletionLength: result.stream.rawCompletionLength,
    finishReason: result.finishReason ?? null,
    usage: result.usage ?? null,
    totalUsage: result.totalUsage ?? null,
    metadataFailureCount: result.metadataFailures.length,
    warningsCount: result.warnings?.length ?? 0,
    warnings: result.warnings?.map((warning) => ({
      type: warning.type,
      message: "message" in warning ? warning.message : undefined,
    })) ?? [],
    response: result.response ? {
      id: result.response.id,
      modelId: result.response.modelId,
      timestamp: result.response.timestamp.toISOString(),
      headersCount: result.response.headers ? Object.keys(result.response.headers).length : 0,
    } : null,
    providerMetadataKeys: result.providerMetadata ? Object.keys(result.providerMetadata) : [],
  };
}
