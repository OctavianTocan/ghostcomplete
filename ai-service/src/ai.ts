import {
  gateway,
  streamText,
  type CallWarning,
  type FinishReason,
  type LanguageModel,
  type LanguageModelResponseMetadata,
  type LanguageModelUsage,
  type ProviderMetadata,
} from "ai";
import { performance } from "node:perf_hooks";
import type { ServiceConfig } from "./config.js";
import type { PromptParts } from "./prompt.js";
import { sanitizeContinuation } from "./privacy.js";

export interface StreamStats {
  chunkCount: number;
  firstChunkLatencyMs?: number;
  streamLatencyMs: number;
  rawCompletionLength: number;
}

export interface CompletionResult {
  completion: string;
  usage?: LanguageModelUsage;
  totalUsage?: LanguageModelUsage;
  finishReason?: FinishReason;
  warnings?: CallWarning[];
  response?: LanguageModelResponseMetadata;
  providerMetadata?: ProviderMetadata;
  stream: StreamStats;
}

export interface CompletionEngine {
  complete(context: string, prompt: PromptParts, signal?: AbortSignal): Promise<CompletionResult>;
}

function timeoutSignal(timeoutMs: number, signal?: AbortSignal): AbortSignal {
  const timeout = AbortSignal.timeout(timeoutMs);
  if (!signal) return timeout;
  return AbortSignal.any([signal, timeout]);
}

export class FakeCompletionEngine implements CompletionEngine {
  constructor(private readonly completion: string) {}

  async complete(context: string): Promise<CompletionResult> {
    const completion = sanitizeContinuation(context, this.completion);
    return {
      completion,
      usage: {
        inputTokens: undefined,
        outputTokens: undefined,
        totalTokens: undefined,
      },
      finishReason: "stop",
      stream: {
        chunkCount: completion ? 1 : 0,
        firstChunkLatencyMs: 0,
        streamLatencyMs: 0,
        rawCompletionLength: this.completion.length,
      },
    };
  }
}

export class VercelAICompletionEngine implements CompletionEngine {
  constructor(private readonly config: ServiceConfig) {}

  async complete(context: string, prompt: PromptParts, signal?: AbortSignal): Promise<CompletionResult> {
    const startedAt = performance.now();
    const result = streamText({
      model: gateway(this.config.model),
      system: prompt.system,
      prompt: prompt.prompt,
      temperature: this.config.temperature,
      maxOutputTokens: this.config.maxOutputTokens,
      stopSequences: ["\n\n", "```", "</"],
      maxRetries: 0,
      abortSignal: timeoutSignal(this.config.timeoutMs, signal),
    });

    return collectStreamResult(context, result, startedAt);
  }
}

export class ModelCompletionEngine implements CompletionEngine {
  constructor(
    private readonly model: LanguageModel,
    private readonly config: Pick<ServiceConfig, "temperature" | "maxOutputTokens" | "timeoutMs">,
  ) {}

  async complete(context: string, prompt: PromptParts, signal?: AbortSignal): Promise<CompletionResult> {
    const startedAt = performance.now();
    const result = streamText({
      model: this.model,
      system: prompt.system,
      prompt: prompt.prompt,
      temperature: this.config.temperature,
      maxOutputTokens: this.config.maxOutputTokens,
      stopSequences: ["\n\n", "```", "</"],
      maxRetries: 0,
      abortSignal: timeoutSignal(this.config.timeoutMs, signal),
    });
    return collectStreamResult(context, result, startedAt);
  }
}

async function collectStreamResult(
  context: string,
  result: ReturnType<typeof streamText>,
  startedAt: number,
): Promise<CompletionResult> {
  let rawCompletion = "";
  let chunkCount = 0;
  let firstChunkLatencyMs: number | undefined;

  for await (const chunk of result.textStream) {
    if (firstChunkLatencyMs === undefined) {
      firstChunkLatencyMs = Math.round(performance.now() - startedAt);
    }
    chunkCount += 1;
    rawCompletion += chunk;
  }

  const [usage, totalUsage, finishReason, warnings, response, providerMetadata] = await Promise.all([
    optional(result.usage),
    optional(result.totalUsage),
    optional(result.finishReason),
    optional(result.warnings),
    optional(result.response),
    optional(result.providerMetadata),
  ]);

  return {
    completion: sanitizeContinuation(context, rawCompletion),
    usage,
    totalUsage,
    finishReason,
    warnings,
    response: response ? omitResponseMessages(response) : undefined,
    providerMetadata,
    stream: {
      chunkCount,
      firstChunkLatencyMs,
      streamLatencyMs: Math.round(performance.now() - startedAt),
      rawCompletionLength: rawCompletion.length,
    },
  };
}

async function optional<T>(promise: Promise<T>): Promise<T | undefined> {
  try {
    return await promise;
  } catch {
    return undefined;
  }
}

function omitResponseMessages(
  response: Awaited<ReturnType<typeof streamText>["response"]>,
): LanguageModelResponseMetadata {
  return {
    id: response.id,
    timestamp: response.timestamp,
    modelId: response.modelId,
    headers: response.headers,
  };
}
