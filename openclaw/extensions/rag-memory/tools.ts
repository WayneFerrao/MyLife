/**
 * Tool implementations for the RAG memory plugin.
 *
 * Registers three agent tools (save_note, search_notes, delete_note) that
 * call the RAG service over HTTP. Each tool handles its own errors and
 * returns structured text responses.
 */

import type { OpenClawPluginApi } from "openclaw/plugin-sdk";
import type { RagMemoryConfig } from "./config.js";

/** Timeout for HTTP requests to the RAG service (ms). */
const REQUEST_TIMEOUT_MS = 30_000;

/**
 * Makes an authenticated HTTP request to the RAG service.
 *
 * @param cfg - Plugin configuration containing the RAG URL and API key.
 * @param path - The endpoint path (e.g. "/ingest", "/query").
 * @param init - Additional fetch options (method, body, etc.).
 * @returns The fetch Response object.
 */
async function ragFetch(
  cfg: RagMemoryConfig,
  path: string,
  init: RequestInit = {},
): Promise<Response> {
  const url = `${cfg.ragUrl}${path}`;
  return fetch(url, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      "X-Api-Key": cfg.ragApiKey,
      ...(init.headers as Record<string, string> | undefined),
    },
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });
}

/**
 * Registers all RAG memory tools with the OpenClaw plugin API.
 *
 * @param api - The OpenClaw plugin API used to register tools.
 * @param cfg - Parsed plugin configuration with RAG service URL and API key.
 */
export function registerTools(
  api: OpenClawPluginApi,
  cfg: RagMemoryConfig,
): void {
  // ── save_note ─────────────────────────────────────────────────────

  api.registerTool({
    name: "save_note",
    label: "Save Note",
    description:
      "Store a personal note into memory. The service automatically extracts " +
      "metadata (topic, people, locations, dates, mood, tags) for better retrieval later.",
    parameters: {
      type: "object",
      properties: {
        text: {
          type: "string",
          description:
            "The note text to store. Include dates, people, and locations for better retrieval.",
        },
      },
      required: ["text"],
    },
    async execute(_toolCallId, params) {
      const text = params.text as string;

      try {
        const resp = await ragFetch(cfg, "/ingest", {
          method: "POST",
          body: JSON.stringify({ text }),
        });

        if (!resp.ok) {
          const detail = await resp.text();
          return {
            content: [
              { type: "text", text: `Failed to save note (${resp.status}): ${detail}` },
            ],
          };
        }

        const data = (await resp.json()) as { id: string; metadata: Record<string, unknown> };
        const meta = data.metadata;
        const summary = [
          `Note saved (id: ${data.id}).`,
          meta.topic ? `Topic: ${meta.topic}` : null,
          Array.isArray(meta.tags) && meta.tags.length > 0
            ? `Tags: ${meta.tags.join(", ")}`
            : null,
        ]
          .filter(Boolean)
          .join(" ");

        return { content: [{ type: "text", text: summary }] };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Memory service unavailable: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    },
  });

  // ── search_notes ──────────────────────────────────────────────────

  api.registerTool({
    name: "search_notes",
    label: "Search Notes",
    description:
      "Search personal memory with a natural language question. " +
      "Returns matching notes ranked by relevance with metadata.",
    parameters: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "Natural language search question.",
        },
        limit: {
          type: "number",
          description: "Maximum number of results to return (default: 5).",
          minimum: 1,
          maximum: 20,
        },
      },
      required: ["query"],
    },
    async execute(_toolCallId, params) {
      const query = params.query as string;
      const limit = (params.limit as number | undefined) ?? 5;

      try {
        const resp = await ragFetch(cfg, "/query", {
          method: "POST",
          body: JSON.stringify({ text: query, limit }),
        });

        if (!resp.ok) {
          const detail = await resp.text();
          return {
            content: [
              { type: "text", text: `Search failed (${resp.status}): ${detail}` },
            ],
          };
        }

        const data = (await resp.json()) as {
          results: Array<{
            id: string;
            text: string;
            metadata: Record<string, unknown>;
            score: number;
          }>;
        };

        if (data.results.length === 0) {
          return {
            content: [{ type: "text", text: "No matching notes found." }],
          };
        }

        const formatted = data.results
          .map((r, i) => {
            const meta = r.metadata;
            const parts = [
              `[${i + 1}] (id: ${r.id}, score: ${r.score.toFixed(2)})`,
              r.text,
            ];
            if (meta.topic) parts.push(`  Topic: ${meta.topic}`);
            if (Array.isArray(meta.dates_mentioned) && meta.dates_mentioned.length > 0) {
              parts.push(`  Dates: ${meta.dates_mentioned.join(", ")}`);
            }
            return parts.join("\n");
          })
          .join("\n\n");

        return {
          content: [{ type: "text", text: formatted }],
          details: { count: data.results.length },
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Memory service unavailable: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    },
  });

  // ── delete_note ───────────────────────────────────────────────────

  api.registerTool({
    name: "delete_note",
    label: "Delete Note",
    description:
      "Delete a specific note from memory by its ID. " +
      "Use search_notes first to find the ID of the note to delete.",
    parameters: {
      type: "object",
      properties: {
        note_id: {
          type: "string",
          description: "UUID of the note to delete (from search_notes results).",
        },
      },
      required: ["note_id"],
    },
    async execute(_toolCallId, params) {
      const noteId = params.note_id as string;

      try {
        const resp = await ragFetch(cfg, `/notes/${encodeURIComponent(noteId)}`, {
          method: "DELETE",
        });

        if (!resp.ok) {
          const detail = await resp.text();
          return {
            content: [
              { type: "text", text: `Failed to delete note (${resp.status}): ${detail}` },
            ],
          };
        }

        return {
          content: [{ type: "text", text: `Note ${noteId} deleted.` }],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Memory service unavailable: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    },
  });
}
