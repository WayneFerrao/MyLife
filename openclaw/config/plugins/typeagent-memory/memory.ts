/**
 * Lazy-loading wrapper around TypeAgent's ConversationMemory.
 *
 * TypeAgent packages are resolved from file: deps in package.json pointing to
 * typeagent/ (shallow-cloned by setup.sh, gitignored). Re-run setup.sh if this
 * import fails.
 *
 * Dynamic import is used so the plugin loads even when TypeAgent isn't ready yet;
 * tool calls will fail with a clear error rather than crashing the gateway at startup.
 */

import { mkdir } from "node:fs/promises";
import type { TypeAgentMemoryConfig } from "./config.js";

// Per-dataDir cache so we don't reload on every tool call.
const cache = new Map<string, ConversationMemoryInstance>();

type ConversationMemoryModule = {
  ConversationMemory: {
    new (nameTag?: string): ConversationMemoryInstance;
    readFromFile(
      dirPath: string,
      baseFileName: string,
    ): Promise<ConversationMemoryInstance>;
  };
  ConversationMessage: {
    new (text: string): ConversationMessageInstance;
  };
};

type ConversationMemoryInstance = {
  addMessage(
    message: ConversationMessageInstance,
    extractKnowledge?: boolean,
    retainKnowledge?: boolean,
  ): Promise<unknown>;
  getAnswerFromLanguage(
    question: string,
    searchOptions?: unknown,
    langSearchFilter?: unknown,
    progress?: unknown,
    answerContextOptions?: unknown,
  ): Promise<{ success: boolean; data?: AnswerPair[]; message?: string }>;
  searchWithLanguage(
    searchText: string,
    options?: unknown,
  ): Promise<{ success: boolean; data?: unknown[]; message?: string }>;
  writeToFile(dirPath: string, baseFileName: string): Promise<void>;
};

type ConversationMessageInstance = {
  timestamp?: string;
};

type AnswerPair = [searchResult: unknown, answerResp: AnswerResponse];
type AnswerResponse =
  | { type: "Answered"; answer?: string }
  | { type: "NoAnswer"; whyNoAnswer?: string };

async function loadModule(): Promise<ConversationMemoryModule> {
  try {
    const mod = await import("conversation-memory");
    return mod as ConversationMemoryModule;
  } catch (err) {
    throw new Error(
      "TypeAgent conversation-memory package not found. " +
        "Re-run setup.sh — it will clone TypeAgent and install plugin deps.",
      { cause: err },
    );
  }
}

export async function getMemory(
  cfg: TypeAgentMemoryConfig,
): Promise<ConversationMemoryInstance> {
  const { dataDir } = cfg;

  // Set env vars that TypeAgent's aiclient reads from the environment.
  process.env.OPENAI_API_KEY = cfg.openaiApiKey;
  process.env.OPENAI_MODEL = cfg.openaiModel;
  if (cfg.openaiBaseUrl) {
    process.env.OPENAI_ENDPOINT = cfg.openaiBaseUrl;
  }

  if (cache.has(dataDir)) {
    return cache.get(dataDir)!;
  }

  await mkdir(dataDir, { recursive: true });

  const { ConversationMemory } = await loadModule();

  let memory: ConversationMemoryInstance;
  try {
    memory = await ConversationMemory.readFromFile(dataDir, "moments");
  } catch {
    // No persisted state yet — start fresh.
    memory = new ConversationMemory("moments");
  }

  cache.set(dataDir, memory);
  return memory;
}

export async function persistMemory(
  cfg: TypeAgentMemoryConfig,
  memory: ConversationMemoryInstance,
): Promise<void> {
  await memory.writeToFile(cfg.dataDir, "moments");
}

export async function createMessage(
  text: string,
  timestamp?: string,
): Promise<ConversationMessageInstance> {
  const { ConversationMessage } = await loadModule();
  const msg = new ConversationMessage(text);
  if (timestamp) {
    msg.timestamp = timestamp;
  }
  return msg;
}

export type { AnswerPair, AnswerResponse, ConversationMemoryInstance };
