import type { OpenClawPluginApi } from "openclaw/plugin-sdk";
import { typeAgentMemoryConfigSchema } from "./config.js";
import { registerTools } from "./tools.js";

const plugin = {
  id: "typeagent-memory",
  name: "TypeAgent Memory",
  description:
    "Structured memory via TypeAgent KnowPro: logs moments and answers questions " +
    "using GPT-4o entity/topic/action extraction backed by a local SQLite index.",
  kind: "memory" as const,
  configSchema: typeAgentMemoryConfigSchema,

  register(api: OpenClawPluginApi) {
    const cfg = typeAgentMemoryConfigSchema.parse(api.pluginConfig);
    registerTools(api, cfg);
  },
};

export default plugin;
