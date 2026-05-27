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
      "You are GhostComplete, a private ghost-text autocomplete engine inside the user's active text input.",
      "The user is in the middle of typing. Predict the most natural continuation of their text.",
      "Output only the continuation; never echo what the user already typed.",
      "Keep it short: 1 to 12 words.",
      "If the user's text already ends with a complete thought, return an empty string.",
      "If the user's text ends mid-word, complete that word naturally.",
      "Match the user's tone and language.",
      "Continue naturally. If there is no space after the user's last word, make sure your suggestion starts with a space.",
      "Start with a capital letter if it is the beginning of the sentence. Write normally.",
      "Do not add quotation marks, markdown, explanations, labels, greetings, or alternatives.",
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
