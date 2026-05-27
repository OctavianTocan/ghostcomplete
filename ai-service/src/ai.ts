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

export interface MetadataFailure {
  field: string;
  message: string;
}

export interface CompletionResult {
  completion: string;
  usage?: LanguageModelUsage;
  totalUsage?: LanguageModelUsage;
  finishReason?: FinishReason;
  warnings?: CallWarning[];
  response?: LanguageModelResponseMetadata;
  providerMetadata?: ProviderMetadata;
  metadataFailures: MetadataFailure[];
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
      metadataFailures: [],
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

  const metadata = await collectMetadata(result);
  const response = metadata.values.response as Awaited<ReturnType<typeof streamText>["response"]> | undefined;

  return {
    completion: sanitizeContinuation(context, rawCompletion),
    usage: metadata.values.usage as LanguageModelUsage | undefined,
    totalUsage: metadata.values.totalUsage as LanguageModelUsage | undefined,
    finishReason: metadata.values.finishReason as FinishReason | undefined,
    warnings: metadata.values.warnings as CallWarning[] | undefined,
    response: response ? omitResponseMessages(response) : undefined,
    providerMetadata: metadata.values.providerMetadata as ProviderMetadata | undefined,
    metadataFailures: metadata.failures,
    stream: {
      chunkCount,
      firstChunkLatencyMs,
      streamLatencyMs: Math.round(performance.now() - startedAt),
      rawCompletionLength: rawCompletion.length,
    },
  };
}

type MetadataField = "usage" | "totalUsage" | "finishReason" | "warnings" | "response" | "providerMetadata";

async function collectMetadata(result: ReturnType<typeof streamText>): Promise<{
  values: Partial<Record<MetadataField, unknown>>;
  failures: MetadataFailure[];
}> {
  const fields: Array<[MetadataField, Promise<unknown>]> = [
    ["usage", Promise.resolve(result.usage)],
    ["totalUsage", Promise.resolve(result.totalUsage)],
    ["finishReason", Promise.resolve(result.finishReason)],
    ["warnings", Promise.resolve(result.warnings)],
    ["response", Promise.resolve(result.response)],
    ["providerMetadata", Promise.resolve(result.providerMetadata)],
  ];

  const settled: Array<
    { field: MetadataField; value: unknown } | { field: MetadataField; failure: string }
  > = await Promise.all(
    fields.map(async ([field, promise]) => {
      try {
        return { field, value: await promise };
      } catch (error) {
        return { field, failure: errorMessage(error) };
      }
    }),
  );

  const values: Partial<Record<MetadataField, unknown>> = {};
  const failures: MetadataFailure[] = [];
  for (const entry of settled) {
    if ("value" in entry) {
      values[entry.field] = entry.value;
    } else {
      failures.push({ field: entry.field, message: entry.failure });
    }
  }

  return { values, failures };
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
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
