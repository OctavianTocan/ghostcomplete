import path from "node:path";
import { fileURLToPath } from "node:url";
import { gateway, streamText } from "ai";
import { config as loadDotenv } from "dotenv";

const thisDir = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(thisDir, "../..");
loadDotenv({ path: path.join(rootDir, ".env"), quiet: true });
loadDotenv({ path: path.join(rootDir, ".env.local"), override: true, quiet: true });

const model = process.env.GHOSTCOMPLETE_MODEL ?? "openai/gpt-5.4";
const prompt = process.argv.slice(2).join(" ") || "Write one short sentence confirming AI Gateway streaming works.";

const result = streamText({
  model: gateway(model),
  prompt,
});

for await (const chunk of result.textStream) {
  process.stdout.write(chunk);
}
process.stdout.write("\n");

const [usage, totalUsage, finishReason, response, warnings] = await Promise.all([
  result.usage,
  result.totalUsage,
  result.finishReason,
  result.response,
  result.warnings,
]);

console.log(JSON.stringify({
  event: "gateway_check_finished",
  model,
  finishReason,
  usage,
  totalUsage,
  response: {
    id: response.id,
    modelId: response.modelId,
    timestamp: response.timestamp.toISOString(),
  },
  warnings: warnings ?? [],
}, null, 2));
