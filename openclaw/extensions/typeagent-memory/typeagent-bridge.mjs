/**
 * Worker thread that loads TypeAgent's ESM packages in a native Node.js context,
 * bypassing jiti's VM which doesn't support dynamic import().
 *
 * All ConversationMemory state lives here; the main thread communicates via postMessage.
 */
import { parentPort } from "node:worker_threads";
import { mkdir } from "node:fs/promises";

let ConversationMemory, ConversationMessage;

async function ensureLoaded() {
  if (ConversationMemory) return;
  const mod = await import("conversation-memory");
  ConversationMemory = mod.ConversationMemory;
  ConversationMessage = mod.ConversationMessage;
}

// One ConversationMemory instance per dataDir
const cache = new Map();

async function getOrInit(dataDir) {
  if (cache.has(dataDir)) return cache.get(dataDir);
  await mkdir(dataDir, { recursive: true });
  let memory;
  try {
    memory = await ConversationMemory.readFromFile(dataDir, "moments");
  } catch {}
  if (!memory) memory = new ConversationMemory("moments");
  cache.set(dataDir, memory);
  return memory;
}

parentPort.on("message", async ({ id, op, args }) => {
  let result, error;
  try {
    // Apply env vars before any TypeAgent call so aiclient picks them up
    if (args.env) {
      const { openaiApiKey, openaiModel, openaiBaseUrl } = args.env;
      if (openaiApiKey) process.env.OPENAI_API_KEY = openaiApiKey;
      if (openaiModel) process.env.OPENAI_MODEL = openaiModel;
      if (openaiBaseUrl) process.env.OPENAI_ENDPOINT = openaiBaseUrl;
    }

    await ensureLoaded();

    switch (op) {
      case "init": {
        await getOrInit(args.dataDir);
        result = true;
        break;
      }
      case "addMessage": {
        const memory = await getOrInit(args.dataDir);
        const msg = new ConversationMessage(args.text);
        if (args.timestamp) msg.timestamp = args.timestamp;
        await memory.addMessage(
          msg,
          args.extractKnowledge ?? true,
          args.retainKnowledge ?? false,
        );
        result = true;
        break;
      }
      case "getAnswerFromLanguage": {
        const memory = await getOrInit(args.dataDir);
        const answer = await memory.getAnswerFromLanguage(args.question);
        // Serialize only what tools.ts uses — searchResult is opaque and not serializable
        result = {
          success: answer.success,
          message: answer.message,
          data: answer.data?.map(([, answerResp]) => [null, answerResp]),
        };
        break;
      }
      case "writeToFile": {
        const memory = cache.get(args.dataDir);
        if (memory) await memory.writeToFile(args.dataDir, "moments");
        result = true;
        break;
      }
      default:
        throw new Error(`Unknown op: ${op}`);
    }
  } catch (err) {
    error = { message: String(err?.message ?? err), stack: err?.stack };
  }
  parentPort.postMessage({ id, result, error });
});
