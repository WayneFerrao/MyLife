import { Type } from "@sinclair/typebox";
import type { OpenClawPluginApi } from "openclaw/plugin-sdk";
import type { TypeAgentMemoryConfig } from "./config.js";
import { getMemory, persistMemory, createMessage } from "./memory.js";

export function registerTools(
  api: OpenClawPluginApi,
  cfg: TypeAgentMemoryConfig,
): void {
  // --- moment_log ---
  // Takes a moment/observation and indexes it into the TypeAgent structured store.
  // KnowPro uses GPT-4o to extract entities, topics, and actions automatically.
  api.registerTool({
    name: "moment_log",
    label: "Log Moment",
    description:
      "Store a moment, observation, or piece of information into structured memory. " +
      "TypeAgent automatically extracts entities, topics, and actions — no formatting needed.",
    parameters: Type.Object({
      text: Type.String({
        description: "The moment or observation to store.",
      }),
      timestamp: Type.Optional(
        Type.String({
          description: "ISO 8601 timestamp (defaults to now).",
        }),
      ),
    }),
    async execute(_toolCallId, params) {
      const text = params.text as string;
      const timestamp = params.timestamp as string | undefined;

      const memory = await getMemory(cfg);
      const msg = await createMessage(text, timestamp ?? new Date().toISOString());

      // extractKnowledge=true triggers GPT-4o entity/topic/action extraction.
      await memory.addMessage(msg, true, false);
      await persistMemory(cfg, memory);

      return {
        content: [{ type: "text", text: "Moment stored and indexed." }],
      };
    },
  });

  // --- moment_search ---
  // Answers a natural language question by querying the KnowPro inverted index.
  api.registerTool({
    name: "moment_search",
    label: "Search Moments",
    description:
      "Search structured memory with a natural language question. " +
      "Returns answers grounded in previously logged moments, with entity and topic awareness.",
    parameters: Type.Object({
      question: Type.String({
        description: "Natural language question to answer from memory.",
      }),
      limit: Type.Optional(
        Type.Number({
          description: "Maximum number of answers to return (default: 5).",
          minimum: 1,
          maximum: 20,
        }),
      ),
    }),
    async execute(_toolCallId, params) {
      const question = params.question as string;
      const limit = (params.limit as number | undefined) ?? 5;

      const memory = await getMemory(cfg);
      const result = await memory.getAnswerFromLanguage(question);

      if (!result.success) {
        return {
          content: [
            {
              type: "text",
              text: `Search failed: ${result.message ?? "unknown error"}`,
            },
          ],
        };
      }

      const pairs = result.data ?? [];
      if (pairs.length === 0) {
        return {
          content: [{ type: "text", text: "No relevant moments found." }],
        };
      }

      const answers = pairs
        .slice(0, limit)
        .map(([, answerResp]) => {
          if (answerResp.type === "Answered") {
            return answerResp.answer ?? "(empty answer)";
          }
          return `(No direct answer: ${answerResp.whyNoAnswer ?? "unknown"})`;
        })
        .join("\n\n---\n\n");

      return {
        content: [{ type: "text", text: answers }],
        details: { count: Math.min(pairs.length, limit) },
      };
    },
  });
}
