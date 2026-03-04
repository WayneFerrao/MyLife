import { homedir } from "node:os";
import { join } from "node:path";

export const DEFAULT_MODEL = "llama3.2";
export const DEFAULT_ENDPOINT = "http://host.docker.internal:11434/v1/chat/completions";
export const DEFAULT_API_KEY = "ollama";
export const DEFAULT_DATA_DIR = join(homedir(), ".openclaw", "typeagent-memory");

export type TypeAgentMemoryConfig = {
  openaiApiKey: string;
  openaiModel: string;
  openaiBaseUrl: string;
  dataDir: string;
};

function resolveEnvVars(value: string): string {
  return value.replace(/\$\{([^}]+)\}/g, (_, name) => {
    const v = process.env[name];
    if (!v) throw new Error(`Environment variable ${name} is not set`);
    return v;
  });
}

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

export const typeAgentMemoryConfigSchema = {
  parse(value: unknown): TypeAgentMemoryConfig {
    const cfg =
      value && typeof value === "object" && !Array.isArray(value)
        ? (value as Record<string, unknown>)
        : {};
    assertAllowedKeys(
      cfg,
      ["openaiApiKey", "openaiModel", "openaiBaseUrl", "dataDir"],
      "typeagent-memory config",
    );

    return {
      openaiApiKey:
        typeof cfg.openaiApiKey === "string" && cfg.openaiApiKey
          ? resolveEnvVars(cfg.openaiApiKey)
          : DEFAULT_API_KEY,
      openaiModel:
        typeof cfg.openaiModel === "string" ? cfg.openaiModel : DEFAULT_MODEL,
      openaiBaseUrl:
        typeof cfg.openaiBaseUrl === "string"
          ? resolveEnvVars(cfg.openaiBaseUrl)
          : DEFAULT_ENDPOINT,
      dataDir:
        typeof cfg.dataDir === "string" ? cfg.dataDir : DEFAULT_DATA_DIR,
    };
  },
};
