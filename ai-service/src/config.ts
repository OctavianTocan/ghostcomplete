import os from "node:os";
import path from "node:path";

export interface ServiceConfig {
  appSupportDir: string;
  databasePath: string;
  profilePath: string;
  model: string;
  token: string;
  host: string;
  port: number;
  timeoutMs: number;
  maxOutputTokens: number;
  temperature: number;
  fakeCompletion?: string;
}

function intFromEnv(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) return fallback;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function floatFromEnv(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) return fallback;
  const parsed = Number.parseFloat(raw);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function loadConfig(): ServiceConfig {
  const appSupportDir =
    process.env.GHOSTCOMPLETE_APP_SUPPORT ??
    path.join(os.homedir(), "Library", "Application Support", "GhostComplete");

  return {
    appSupportDir,
    databasePath: process.env.GHOSTCOMPLETE_DB ?? path.join(appSupportDir, "learning.sqlite"),
    profilePath: process.env.GHOSTCOMPLETE_PROFILE ?? path.join(appSupportDir, "profile.json"),
    model: process.env.GHOSTCOMPLETE_MODEL ?? "openai/gpt-4o-mini",
    token: process.env.GHOSTCOMPLETE_TOKEN ?? "",
    host: process.env.GHOSTCOMPLETE_HOST ?? "127.0.0.1",
    port: intFromEnv("GHOSTCOMPLETE_PORT", 50573),
    timeoutMs: intFromEnv("GHOSTCOMPLETE_TIMEOUT_MS", 3500),
    maxOutputTokens: intFromEnv("GHOSTCOMPLETE_MAX_OUTPUT_TOKENS", 48),
    temperature: floatFromEnv("GHOSTCOMPLETE_TEMPERATURE", 0.2),
    fakeCompletion: process.env.GHOSTCOMPLETE_FAKE_COMPLETION,
  };
}
