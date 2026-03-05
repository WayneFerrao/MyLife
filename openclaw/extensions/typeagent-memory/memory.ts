/**
 * Proxy layer that delegates all ConversationMemory operations to a Worker
 * thread running typeagent-bridge.mjs.
 *
 * jiti's VM context (used to load TypeScript plugins in openclaw) does not
 * support dynamic import() — not even via new Function(). Worker threads run
 * in a fresh native Node.js context where ESM import("conversation-memory")
 * works normally.
 */

import { Worker } from "node:worker_threads";
import { join } from "node:path";
import type { TypeAgentMemoryConfig } from "./config.js";

// jiti compiles TypeScript to CJS, so __dirname is available at runtime.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
declare const __dirname: string;

const bridgePath = join(__dirname, "typeagent-bridge.mjs");

// Lazy singleton worker — created on first use.
let worker: Worker | null = null;
let nextId = 0;
const pending = new Map<number, { resolve: (v: unknown) => void; reject: (e: Error) => void }>();

function getWorker(): Worker {
  if (worker) return worker;

  worker = new Worker(bridgePath);

  worker.on("message", ({ id, result, error }: { id: number; result: unknown; error?: { message: string; stack?: string } }) => {
    const p = pending.get(id);
    if (!p) return;
    pending.delete(id);
    if (error) {
      const err = new Error(error.message);
      if (error.stack) err.stack = error.stack;
      p.reject(err);
    } else {
      p.resolve(result);
    }
  });

  worker.on("error", (err: Error) => {
    // Reject all pending calls if the worker crashes.
    for (const p of pending.values()) p.reject(err);
    pending.clear();
    worker = null;
  });

  worker.on("exit", () => {
    worker = null;
  });

  return worker;
}

function workerCall(op: string, args: Record<string, unknown>): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const id = nextId++;
    pending.set(id, { resolve, reject });
    getWorker().postMessage({ id, op, args });
  });
}

// ---- Types mirrored from the old memory.ts so tools.ts compiles unchanged ----

type AnswerResponse =
  | { type: "Answered"; answer?: string }
  | { type: "NoAnswer"; whyNoAnswer?: string };

type AnswerPair = [searchResult: unknown, answerResp: AnswerResponse];

type ConversationMemoryInstance = {
  addMessage(
    message: ConversationMessageDescriptor,
    extractKnowledge?: boolean,
    retainKnowledge?: boolean,
  ): Promise<unknown>;
  getAnswerFromLanguage(
    question: string,
  ): Promise<{ success: boolean; data?: AnswerPair[]; message?: string }>;
  writeToFile(dirPath: string, baseFileName: string): Promise<void>;
};

// Plain descriptor — the worker creates the real ConversationMessage.
type ConversationMessageDescriptor = {
  __isDescriptor: true;
  text: string;
  timestamp?: string;
};

/**
 * Proxy object that forwards calls to the worker thread.
 */
class MemoryProxy implements ConversationMemoryInstance {
  constructor(
    private readonly dataDir: string,
    private readonly env: Record<string, string>,
  ) {}

  async addMessage(
    message: ConversationMessageDescriptor,
    extractKnowledge = true,
    retainKnowledge = false,
  ): Promise<unknown> {
    return workerCall("addMessage", {
      dataDir: this.dataDir,
      env: this.env,
      text: message.text,
      timestamp: message.timestamp,
      extractKnowledge,
      retainKnowledge,
    });
  }

  async getAnswerFromLanguage(
    question: string,
  ): Promise<{ success: boolean; data?: AnswerPair[]; message?: string }> {
    return workerCall("getAnswerFromLanguage", {
      dataDir: this.dataDir,
      env: this.env,
      question,
    }) as Promise<{ success: boolean; data?: AnswerPair[]; message?: string }>;
  }

  async writeToFile(dirPath: string, _baseFileName: string): Promise<void> {
    await workerCall("writeToFile", { dataDir: dirPath, env: this.env });
  }
}

// Per-dataDir cache of MemoryProxy instances.
const cache = new Map<string, MemoryProxy>();

export async function getMemory(cfg: TypeAgentMemoryConfig): Promise<ConversationMemoryInstance> {
  const { dataDir } = cfg;
  if (cache.has(dataDir)) return cache.get(dataDir)!;

  const env: Record<string, string> = {
    openaiApiKey: cfg.openaiApiKey,
    openaiModel: cfg.openaiModel,
  };
  if (cfg.openaiBaseUrl) env.openaiBaseUrl = cfg.openaiBaseUrl;

  // Send init op so the worker pre-loads ConversationMemory and creates the instance.
  await workerCall("init", { dataDir, env });

  const proxy = new MemoryProxy(dataDir, env);
  cache.set(dataDir, proxy);
  return proxy;
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
): Promise<ConversationMessageDescriptor> {
  return { __isDescriptor: true as const, text, timestamp };
}

export type { AnswerPair, AnswerResponse, ConversationMemoryInstance };
