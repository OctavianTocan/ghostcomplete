export const MIN_PREFIX_CHARS = 3;
export const MAX_PREFIX_CHARS = 4000;
export const MAX_SUGGESTION_CHARS = 80;
export const AUTOCOMPLETE_TIMEOUT_MS = 4000;
export const AUTOCOMPLETE_REASONING = "minimal" as const;
export const AUTOCOMPLETE_STOP_SEQUENCES = ["\n\n", "```", "</"];
export const AUTOCOMPLETE_PROVIDER_OPTIONS = {
  openai: {
    reasoningEffort: AUTOCOMPLETE_REASONING,
  },
  groq: {
    reasoningEffort: AUTOCOMPLETE_REASONING,
  },
  google: {
    thinkingConfig: {
      thinkingBudget: 0,
    },
  },
  openrouter: {
    reasoning: {
      effort: "low",
    },
  },
};
