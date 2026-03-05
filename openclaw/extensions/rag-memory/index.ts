/**
 * Entry point for the RAG memory plugin.
 *
 * Exports the plugin definition that OpenClaw loads at startup.
 * Parses configuration and delegates tool registration to tools.ts.
 */

import type { OpenClawPluginApi } from "openclaw/plugin-sdk";
import { ragMemoryConfigSchema } from "./config.js";
import { registerTools } from "./tools.js";

const plugin = {
  id: "rag-memory",
  name: "RAG Memory",
  description:
    "Store and retrieve personal notes via a RAG vector memory service " +
    "backed by Qdrant and Ollama.",

  /**
   * Called by OpenClaw when the plugin is loaded. Parses the plugin
   * config and registers all memory tools.
   *
   * @param api - The OpenClaw plugin API.
   */
  register(api: OpenClawPluginApi) {
    const cfg = ragMemoryConfigSchema.parse(api.pluginConfig);
    registerTools(api, cfg);
  },
};

export default plugin;
