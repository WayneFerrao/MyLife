/**
 * Configuration schema and parsing for the RAG memory plugin.
 *
 * Reads plugin config from openclaw.json and falls back to environment
 * variables. Supports `${VAR_NAME}` interpolation in config values.
 */

/** Default URL for the RAG service on the shared Docker network. */
export const DEFAULT_RAG_URL = "http://rag:18790";

/** Resolved plugin configuration passed to tool implementations. */
export type RagMemoryConfig = {
  ragUrl: string;
  ragApiKey: string;
};

/**
 * Replaces `${VAR_NAME}` placeholders in a string with the corresponding
 * environment variable value. Throws if the variable is not set.
 *
 * @param value - The string potentially containing `${...}` placeholders.
 * @returns The string with all placeholders resolved.
 */
function resolveEnvVars(value: string): string {
  return value.replace(/\$\{([^}]+)\}/g, (_, name) => {
    const v = process.env[name];
    if (!v) throw new Error(`Environment variable ${name} is not set`);
    return v;
  });
}

/**
 * Validates that an object only contains expected keys. Throws with a
 * descriptive message if unknown keys are found (catches config typos).
 *
 * @param obj - The object to validate.
 * @param allowed - List of allowed key names.
 * @param label - Human-readable label for error messages.
 */
function assertAllowedKeys(
  obj: Record<string, unknown>,
  allowed: string[],
  label: string,
): void {
  const unknown = Object.keys(obj).filter((k) => !allowed.includes(k));
  if (unknown.length > 0) {
    throw new Error(`${label} has unknown keys: ${unknown.join(", ")}`);
  }
}

/**
 * Schema object that parses and validates the raw plugin config from
 * openclaw.json into a typed {@link RagMemoryConfig}.
 *
 * Resolution order for `ragApiKey`:
 * 1. `plugins.rag-memory.ragApiKey` in openclaw.json (supports `${RAG_API_KEY}`)
 * 2. `RAG_API_KEY` environment variable
 * 3. Throws if neither is set
 */
export const ragMemoryConfigSchema = {
  parse(value: unknown): RagMemoryConfig {
    const cfg =
      value && typeof value === "object" && !Array.isArray(value)
        ? (value as Record<string, unknown>)
        : {};
    assertAllowedKeys(cfg, ["ragUrl", "ragApiKey"], "rag-memory config");

    const ragApiKey =
      typeof cfg.ragApiKey === "string" && cfg.ragApiKey
        ? resolveEnvVars(cfg.ragApiKey)
        : process.env.RAG_API_KEY;

    if (!ragApiKey) {
      throw new Error(
        "rag-memory: ragApiKey is required. Set it in plugin config or RAG_API_KEY env var.",
      );
    }

    return {
      ragUrl:
        typeof cfg.ragUrl === "string" && cfg.ragUrl
          ? resolveEnvVars(cfg.ragUrl)
          : DEFAULT_RAG_URL,
      ragApiKey,
    };
  },
};
