import { FakeCompletionEngine, VercelAICompletionEngine } from "./ai.js";
import { loadConfig } from "./config.js";
import { createServer } from "./server.js";
import { LearningStore } from "./storage.js";

const config = loadConfig();
const store = new LearningStore(config.databasePath);
const engine = config.fakeCompletion
  ? new FakeCompletionEngine(config.fakeCompletion)
  : new VercelAICompletionEngine(config);

const server = createServer(config, engine, store);

process.on("SIGTERM", () => {
  server.stop();
  store.close();
});

process.on("SIGINT", () => {
  server.stop();
  store.close();
  process.exit(0);
});

console.log(JSON.stringify({ event: "ready", port: server.port, model: config.model }));
