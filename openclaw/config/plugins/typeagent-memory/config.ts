import { homedir } from "node:os";
import { join } from "node:path";

export const DEFAULT_MODEL = "gpt-4o";
export const DEFAULT_DATA_DIR = join(homedir(), ".openclaw", "typeagent-memory");

export type TypeAgentMemoryConfig = {
  openaiApiKey: string;
  openaiModel: string;
  openaiBaseUrl?: string;
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
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new Error("typeagent-memory config required");
    }
    const cfg = value as Record<string, unknown>;
    assertAllowedKeys(
      cfg,
      ["openaiApiKey", "openaiModel", "openaiBaseUrl", "dataDir"],
      "typeagent-memory config",
    );

    if (typeof cfg.openaiApiKey !== "string" || !cfg.openaiApiKey) {
      throw new Error("openaiApiKey is required");
    }

    return {
      openaiApiKey: resolveEnvVars(cfg.openaiApiKey),
      openaiModel:
        typeof cfg.openaiModel === "string" ? cfg.openaiModel : DEFAULT_MODEL,
      openaiBaseUrl:
        typeof cfg.openaiBaseUrl === "string"
          ? resolveEnvVars(cfg.openaiBaseUrl)
          : undefined,
      dataDir:
        typeof cfg.dataDir === "string" ? cfg.dataDir : DEFAULT_DATA_DIR,
    };
  },
};
