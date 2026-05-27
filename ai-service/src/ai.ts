import { generateText, gateway, type LanguageModel } from "ai";
import type { ServiceConfig } from "./config.js";
import type { PromptParts } from "./prompt.js";
import { sanitizeContinuation } from "./privacy.js";

export interface CompletionEngine {
  complete(context: string, prompt: PromptParts, signal?: AbortSignal): Promise<string>;
}

function timeoutSignal(timeoutMs: number, signal?: AbortSignal): AbortSignal {
  const timeout = AbortSignal.timeout(timeoutMs);
  if (!signal) return timeout;
  return AbortSignal.any([signal, timeout]);
}

export class FakeCompletionEngine implements CompletionEngine {
  constructor(private readonly completion: string) {}

  async complete(context: string): Promise<string> {
    return sanitizeContinuation(context, this.completion);
  }
}

export class VercelAICompletionEngine implements CompletionEngine {
  constructor(private readonly config: ServiceConfig) {}

  async complete(context: string, prompt: PromptParts, signal?: AbortSignal): Promise<string> {
    const { text } = await generateText({
      model: gateway(this.config.model),
      system: prompt.system,
      prompt: prompt.prompt,
      temperature: this.config.temperature,
      maxOutputTokens: this.config.maxOutputTokens,
      stopSequences: ["\n\n", "```", "</"],
      maxRetries: 0,
      abortSignal: timeoutSignal(this.config.timeoutMs, signal),
    });

    return sanitizeContinuation(context, text);
  }
}

export class ModelCompletionEngine implements CompletionEngine {
  constructor(
    private readonly model: LanguageModel,
    private readonly config: Pick<ServiceConfig, "temperature" | "maxOutputTokens" | "timeoutMs">,
  ) {}

  async complete(context: string, prompt: PromptParts, signal?: AbortSignal): Promise<string> {
    const { text } = await generateText({
      model: this.model,
      system: prompt.system,
      prompt: prompt.prompt,
      temperature: this.config.temperature,
      maxOutputTokens: this.config.maxOutputTokens,
      stopSequences: ["\n\n", "```", "</"],
      maxRetries: 0,
      abortSignal: timeoutSignal(this.config.timeoutMs, signal),
    });
    return sanitizeContinuation(context, text);
  }
}
