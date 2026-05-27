import os from "node:os";
import path from "node:path";
import { AUTOCOMPLETE_TIMEOUT_MS } from "./autocomplete.js";

export type ProviderKind = "gateway" | "openrouter";

export interface ServiceConfig {
  appSupportDir: string;
  databasePath: string;
  profilePath: string;
  logDir: string;
  sidecarLogPath: string;
  provider: ProviderKind;
  model: string;
  token: string;
  host: string;
  port: number;
  timeoutMs: number;
  maxOutputTokens: number;
  temperature: number;
  openRouterApiKey?: string;
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

function providerFromEnv(): ProviderKind {
  const raw = process.env.GHOSTCOMPLETE_PROVIDER?.trim().toLowerCase();
  if (raw === "gateway" || raw === "vercel" || raw === "ai-gateway") return "gateway";
  if (raw === "openrouter" || raw === "open-router") return "openrouter";
  return process.env.OPENROUTER_API_KEY ? "openrouter" : "gateway";
}

export function loadConfig(): ServiceConfig {
  const appSupportDir =
    process.env.GHOSTCOMPLETE_APP_SUPPORT ??
    path.join(os.homedir(), "Library", "Application Support", "GhostComplete");
  const logDir = process.env.GHOSTCOMPLETE_LOG_DIR ?? path.join(appSupportDir, "logs");
  const provider = providerFromEnv();

  return {
    appSupportDir,
    databasePath: process.env.GHOSTCOMPLETE_DB ?? path.join(appSupportDir, "learning.sqlite"),
    profilePath: process.env.GHOSTCOMPLETE_PROFILE ?? path.join(appSupportDir, "profile.json"),
    logDir,
    sidecarLogPath: path.join(logDir, "sidecar.jsonl"),
    provider,
    model: process.env.GHOSTCOMPLETE_MODEL ?? "google/gemini-2.0-flash-lite",
    token: process.env.GHOSTCOMPLETE_TOKEN ?? "",
    host: process.env.GHOSTCOMPLETE_HOST ?? "127.0.0.1",
    port: intFromEnv("GHOSTCOMPLETE_PORT", 50573),
    timeoutMs: intFromEnv("GHOSTCOMPLETE_TIMEOUT_MS", AUTOCOMPLETE_TIMEOUT_MS),
    maxOutputTokens: intFromEnv("GHOSTCOMPLETE_MAX_OUTPUT_TOKENS", 48),
    temperature: floatFromEnv("GHOSTCOMPLETE_TEMPERATURE", 0.2),
    openRouterApiKey: process.env.OPENROUTER_API_KEY,
    fakeCompletion: process.env.GHOSTCOMPLETE_FAKE_COMPLETION,
  };
}
