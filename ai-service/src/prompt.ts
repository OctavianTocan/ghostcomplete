import type { CompleteRequest, LearnedExample, Profile } from "./types.js";

export interface PromptParts {
  system: string;
  prompt: string;
}

function bulletList(label: string, values: string[]): string {
  const clean = values.map((value) => value.trim()).filter(Boolean);
  if (clean.length === 0) return "";
  return `${label}:\n${clean.map((value) => `- ${value}`).join("\n")}`;
}

export function buildPrompt(request: CompleteRequest, profile: Profile, examples: LearnedExample[]): PromptParts {
  const profileSections = [
    profile.name ? `User name: ${profile.name}` : "",
    profile.role ? `Role: ${profile.role}` : "",
    profile.tone ? `Tone: ${profile.tone}` : "",
    bulletList("Projects", profile.projects),
    bulletList("Vocabulary", profile.vocabulary),
    bulletList("Languages", profile.languages),
    bulletList("People and organizations", profile.peopleOrgs),
    bulletList("Never say", profile.neverSay),
  ].filter(Boolean);

  const exampleSection =
    examples.length > 0
      ? `Recent accepted or curated examples:\n${examples
          .slice(0, 6)
          .map((example) => `- ${example.text}`)
          .join("\n")}`
      : "";

  return {
    system: [
      "You are GhostComplete, a private inline autocomplete engine.",
      "Return only the next characters the user would type after the provided context.",
      "Do not repeat any part of the input context.",
      "Do not add quotation marks, markdown, explanations, labels, greetings, or alternatives.",
      "Prefer 2 to 12 words of natural continuation text, or one short sentence.",
      "Start with a space if the next typed character would be a space.",
      "Do not return a single character or standalone punctuation; return an empty string if that is all you can infer.",
      "If unsure, return an empty string.",
      "Respect the user's profile and never-say preferences.",
    ].join(" "),
    prompt: [
      profileSections.length > 0 ? `User profile:\n${profileSections.join("\n")}` : "",
      exampleSection,
      `Active app: ${request.app.name} (${request.app.bundleId})`,
      "Typed context before caret:",
      request.context,
      "Continuation only:",
    ]
      .filter(Boolean)
      .join("\n\n"),
  };
}
