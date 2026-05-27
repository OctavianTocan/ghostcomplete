import fs from "node:fs";
import path from "node:path";
import type { Profile } from "./types.js";

export const defaultProfile: Profile = {
  name: "",
  role: "",
  projects: [],
  vocabulary: [],
  tone: "",
  languages: ["en"],
  peopleOrgs: [],
  neverSay: [],
};

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is string => typeof item === "string" && item.trim().length > 0);
}

export function normalizeProfile(value: unknown): Profile {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return defaultProfile;
  }
  const record = value as Record<string, unknown>;
  return {
    name: typeof record.name === "string" ? record.name : "",
    role: typeof record.role === "string" ? record.role : "",
    projects: stringArray(record.projects),
    vocabulary: stringArray(record.vocabulary),
    tone: typeof record.tone === "string" ? record.tone : "",
    languages: stringArray(record.languages).length > 0 ? stringArray(record.languages) : ["en"],
    peopleOrgs: stringArray(record.peopleOrgs),
    neverSay: stringArray(record.neverSay),
  };
}

export function ensureProfile(profilePath: string): Profile {
  fs.mkdirSync(path.dirname(profilePath), { recursive: true });
  if (!fs.existsSync(profilePath)) {
    fs.writeFileSync(profilePath, JSON.stringify(defaultProfile, null, 2) + "\n", { mode: 0o600 });
    return defaultProfile;
  }

  const raw = fs.readFileSync(profilePath, "utf8");
  return normalizeProfile(JSON.parse(raw));
}
