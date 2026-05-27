import { FakeCompletionEngine, OpenRouterCompletionEngine, VercelAICompletionEngine } from "./ai.js";
import { loadConfig } from "./config.js";
import { JsonlTraceLogger } from "./logger.js";
import { createServer } from "./server.js";
import { LearningStore } from "./storage.js";

const config = loadConfig();
const logger = new JsonlTraceLogger(config.sidecarLogPath);

logger.info("sidecar_boot", {
  appSupportDir: config.appSupportDir,
  databasePath: config.databasePath,
  profilePath: config.profilePath,
  logPath: config.sidecarLogPath,
  provider: config.provider,
  model: config.model,
  host: config.host,
  port: config.port,
  hasGatewayKey: Boolean(process.env.AI_GATEWAY_API_KEY),
  hasOpenRouterKey: Boolean(process.env.OPENROUTER_API_KEY),
  fakeCompletion: config.fakeCompletion !== undefined,
});

const store = new LearningStore(config.databasePath);
const engine = config.fakeCompletion
  ? new FakeCompletionEngine(config.fakeCompletion)
  : config.provider === "openrouter"
    ? new OpenRouterCompletionEngine(config)
  : new VercelAICompletionEngine(config);

const server = createServer(config, engine, store, logger);

process.on("SIGTERM", () => {
  logger.info("sidecar_sigterm");
  server.stop();
  store.close();
});

process.on("SIGINT", () => {
  logger.info("sidecar_sigint");
  server.stop();
  store.close();
  process.exit(0);
});

logger.info("sidecar_ready", { port: server.port, provider: config.provider, model: config.model });
console.log(JSON.stringify({ event: "ready", port: server.port, provider: config.provider, model: config.model }));
