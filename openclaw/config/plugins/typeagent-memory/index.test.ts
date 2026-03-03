/**
 * typeagent-memory plugin tests
 *
 * TypeAgent packages are mocked so these run without building TypeAgent.
 * Live tests (requiring a real OPENAI_API_KEY + TypeAgent installed) are
 * skipped unless OPENCLAW_LIVE_TEST=1.
 */

import { describe, test, expect, beforeEach, vi } from "vitest";

const liveEnabled = Boolean(process.env.OPENAI_API_KEY) && process.env.OPENCLAW_LIVE_TEST === "1";
const describeLive = liveEnabled ? describe : describe.skip;

// ── Helpers ──────────────────────────────────────────────────────────────────

// oxlint-disable-next-line typescript/no-explicit-any
function makeMockApi(pluginConfig: Record<string, unknown>): any {
  // oxlint-disable-next-line typescript/no-explicit-any
  const registeredTools: any[] = [];
  return {
    id: "typeagent-memory",
    name: "TypeAgent Memory",
    source: "test",
    config: {},
    pluginConfig,
    runtime: {},
    logger: {
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
      debug: vi.fn(),
    },
    // oxlint-disable-next-line typescript/no-explicit-any
    registerTool: (tool: any) => {
      registeredTools.push(tool);
    },
    registerCli: vi.fn(),
    registerService: vi.fn(),
    on: vi.fn(),
    resolvePath: (p: string) => p,
    _registeredTools: registeredTools,
  };
}

const VALID_CONFIG = {
  openaiApiKey: "sk-test-key",
  openaiModel: "gpt-4o",
  dataDir: "/tmp/typeagent-test",
};

// ── Plugin metadata ───────────────────────────────────────────────────────────

describe("typeagent-memory plugin", () => {
  test("has correct id, kind, and name", async () => {
    const { default: plugin } = await import("./index.js");
    expect(plugin.id).toBe("typeagent-memory");
    expect(plugin.kind).toBe("memory");
    expect(plugin.name).toBe("TypeAgent Memory");
    // oxlint-disable-next-line typescript/unbound-method
    expect(plugin.register).toBeInstanceOf(Function);
  });
});

// ── Config schema ─────────────────────────────────────────────────────────────

describe("config schema", () => {
  test("parses a valid config", async () => {
    const { typeAgentMemoryConfigSchema } = await import("./config.js");
    const result = typeAgentMemoryConfigSchema.parse(VALID_CONFIG);
    expect(result.openaiApiKey).toBe("sk-test-key");
    expect(result.openaiModel).toBe("gpt-4o");
    expect(result.dataDir).toBe("/tmp/typeagent-test");
  });

  test("defaults model to gpt-4o when omitted", async () => {
    const { typeAgentMemoryConfigSchema, DEFAULT_MODEL } = await import("./config.js");
    const result = typeAgentMemoryConfigSchema.parse({ openaiApiKey: "sk-x" });
    expect(result.openaiModel).toBe(DEFAULT_MODEL);
  });

  test("defaults dataDir when omitted", async () => {
    const { typeAgentMemoryConfigSchema, DEFAULT_DATA_DIR } = await import("./config.js");
    const result = typeAgentMemoryConfigSchema.parse({ openaiApiKey: "sk-x" });
    expect(result.dataDir).toBe(DEFAULT_DATA_DIR);
  });

  test("resolves ${ENV_VAR} in openaiApiKey", async () => {
    const { typeAgentMemoryConfigSchema } = await import("./config.js");
    process.env.TEST_TYPEAGENT_KEY = "sk-from-env";
    const result = typeAgentMemoryConfigSchema.parse({ openaiApiKey: "${TEST_TYPEAGENT_KEY}" });
    expect(result.openaiApiKey).toBe("sk-from-env");
    delete process.env.TEST_TYPEAGENT_KEY;
  });

  test("throws when openaiApiKey is missing", async () => {
    const { typeAgentMemoryConfigSchema } = await import("./config.js");
    expect(() => typeAgentMemoryConfigSchema.parse({})).toThrow("openaiApiKey is required");
  });

  test("throws when config is not an object", async () => {
    const { typeAgentMemoryConfigSchema } = await import("./config.js");
    expect(() => typeAgentMemoryConfigSchema.parse(null)).toThrow("typeagent-memory config required");
    expect(() => typeAgentMemoryConfigSchema.parse("string")).toThrow();
  });

  test("throws on unknown keys", async () => {
    const { typeAgentMemoryConfigSchema } = await import("./config.js");
    expect(() =>
      typeAgentMemoryConfigSchema.parse({ openaiApiKey: "sk-x", unknownField: true }),
    ).toThrow("unknown keys");
  });
});

// ── Tool registration ─────────────────────────────────────────────────────────

describe("tool registration", () => {
  test("registers moment_log and moment_search tools", async () => {
    vi.resetModules();
    // Mock conversation-memory so plugin.register() doesn't fail at import time
    vi.doMock("conversation-memory", () => ({
      ConversationMemory: class {
        static async readFromFile() { return new this(); }
        async addMessage() {}
        async writeToFile() {}
        async getAnswerFromLanguage() { return { success: true, data: [] }; }
        async searchWithLanguage() { return { success: true, data: [] }; }
      },
      ConversationMessage: class {
        constructor(public text: string) {}
      },
    }));

    try {
      const { default: plugin } = await import("./index.js");
      const api = makeMockApi(VALID_CONFIG);
      // oxlint-disable-next-line typescript/no-explicit-any
      plugin.register(api as any);

      const names = api._registeredTools.map((t: any) => t.name);
      expect(names).toContain("moment_log");
      expect(names).toContain("moment_search");
    } finally {
      vi.doUnmock("conversation-memory");
      vi.resetModules();
    }
  });

  test("moment_log tool has required parameters", async () => {
    vi.resetModules();
    vi.doMock("conversation-memory", () => ({
      ConversationMemory: class {
        static async readFromFile() { return new this(); }
        async addMessage() {}
        async writeToFile() {}
      },
      ConversationMessage: class {},
    }));

    try {
      const { default: plugin } = await import("./index.js");
      const api = makeMockApi(VALID_CONFIG);
      // oxlint-disable-next-line typescript/no-explicit-any
      plugin.register(api as any);

      const logTool = api._registeredTools.find((t: any) => t.name === "moment_log");
      expect(logTool).toBeDefined();
      expect(logTool.parameters.properties).toHaveProperty("text");
      expect(logTool.parameters.properties).toHaveProperty("timestamp");
      expect(logTool.parameters.required).toContain("text");
    } finally {
      vi.doUnmock("conversation-memory");
      vi.resetModules();
    }
  });

  test("moment_search tool has required parameters", async () => {
    vi.resetModules();
    vi.doMock("conversation-memory", () => ({
      ConversationMemory: class {
        static async readFromFile() { return new this(); }
        async addMessage() {}
        async writeToFile() {}
      },
      ConversationMessage: class {},
    }));

    try {
      const { default: plugin } = await import("./index.js");
      const api = makeMockApi(VALID_CONFIG);
      // oxlint-disable-next-line typescript/no-explicit-any
      plugin.register(api as any);

      const searchTool = api._registeredTools.find((t: any) => t.name === "moment_search");
      expect(searchTool).toBeDefined();
      expect(searchTool.parameters.properties).toHaveProperty("question");
      expect(searchTool.parameters.required).toContain("question");
    } finally {
      vi.doUnmock("conversation-memory");
      vi.resetModules();
    }
  });
});

// ── Tool execution ────────────────────────────────────────────────────────────

describe("moment_log execution", () => {
  beforeEach(() => {
    vi.resetModules();
  });

  test("calls addMessage and writeToFile", async () => {
    const addMessage = vi.fn(async () => undefined);
    const writeToFile = vi.fn(async () => undefined);

    vi.doMock("conversation-memory", () => ({
      ConversationMemory: class {
        static async readFromFile() { return new this(); }
        addMessage = addMessage;
        writeToFile = writeToFile;
      },
      ConversationMessage: class {
        timestamp?: string;
        constructor(public text: string) {}
      },
    }));

    try {
      const { default: plugin } = await import("./index.js");
      const api = makeMockApi(VALID_CONFIG);
      // oxlint-disable-next-line typescript/no-explicit-any
      plugin.register(api as any);

      const logTool = api._registeredTools.find((t: any) => t.name === "moment_log");
      const result = await logTool.execute("call-1", { text: "I prefer dark mode" });

      expect(addMessage).toHaveBeenCalledOnce();
      // extractKnowledge should be true
      expect(addMessage).toHaveBeenCalledWith(expect.anything(), true, false);
      expect(writeToFile).toHaveBeenCalledOnce();
      expect(result.content[0].text).toBe("Moment stored and indexed.");
    } finally {
      vi.doUnmock("conversation-memory");
      vi.resetModules();
    }
  });
});

describe("moment_search execution", () => {
  beforeEach(() => {
    vi.resetModules();
  });

  test("returns answer text on success", async () => {
    vi.doMock("conversation-memory", () => ({
      ConversationMemory: class {
        static async readFromFile() { return new this(); }
        async addMessage() {}
        async writeToFile() {}
        async getAnswerFromLanguage() {
          return {
            success: true,
            data: [[{}, { type: "Answered", answer: "Dark mode is preferred." }]],
          };
        }
      },
      ConversationMessage: class {},
    }));

    try {
      const { default: plugin } = await import("./index.js");
      const api = makeMockApi(VALID_CONFIG);
      // oxlint-disable-next-line typescript/no-explicit-any
      plugin.register(api as any);

      const searchTool = api._registeredTools.find((t: any) => t.name === "moment_search");
      const result = await searchTool.execute("call-2", { question: "What display mode?" });

      expect(result.content[0].text).toBe("Dark mode is preferred.");
    } finally {
      vi.doUnmock("conversation-memory");
      vi.resetModules();
    }
  });

  test("returns no-results message when data is empty", async () => {
    vi.doMock("conversation-memory", () => ({
      ConversationMemory: class {
        static async readFromFile() { return new this(); }
        async addMessage() {}
        async writeToFile() {}
        async getAnswerFromLanguage() { return { success: true, data: [] }; }
      },
      ConversationMessage: class {},
    }));

    try {
      const { default: plugin } = await import("./index.js");
      const api = makeMockApi(VALID_CONFIG);
      // oxlint-disable-next-line typescript/no-explicit-any
      plugin.register(api as any);

      const searchTool = api._registeredTools.find((t: any) => t.name === "moment_search");
      const result = await searchTool.execute("call-3", { question: "Unknown thing?" });

      expect(result.content[0].text).toBe("No relevant moments found.");
    } finally {
      vi.doUnmock("conversation-memory");
      vi.resetModules();
    }
  });

  test("returns error message when search fails", async () => {
    vi.doMock("conversation-memory", () => ({
      ConversationMemory: class {
        static async readFromFile() { return new this(); }
        async addMessage() {}
        async writeToFile() {}
        async getAnswerFromLanguage() {
          return { success: false, message: "index corrupted" };
        }
      },
      ConversationMessage: class {},
    }));

    try {
      const { default: plugin } = await import("./index.js");
      const api = makeMockApi(VALID_CONFIG);
      // oxlint-disable-next-line typescript/no-explicit-any
      plugin.register(api as any);

      const searchTool = api._registeredTools.find((t: any) => t.name === "moment_search");
      const result = await searchTool.execute("call-4", { question: "Anything?" });

      expect(result.content[0].text).toContain("Search failed");
      expect(result.content[0].text).toContain("index corrupted");
    } finally {
      vi.doUnmock("conversation-memory");
      vi.resetModules();
    }
  });

  test("respects limit parameter", async () => {
    vi.doMock("conversation-memory", () => ({
      ConversationMemory: class {
        static async readFromFile() { return new this(); }
        async addMessage() {}
        async writeToFile() {}
        async getAnswerFromLanguage() {
          return {
            success: true,
            data: [
              [{}, { type: "Answered", answer: "First" }],
              [{}, { type: "Answered", answer: "Second" }],
              [{}, { type: "Answered", answer: "Third" }],
            ],
          };
        }
      },
      ConversationMessage: class {},
    }));

    try {
      const { default: plugin } = await import("./index.js");
      const api = makeMockApi(VALID_CONFIG);
      // oxlint-disable-next-line typescript/no-explicit-any
      plugin.register(api as any);

      const searchTool = api._registeredTools.find((t: any) => t.name === "moment_search");
      const result = await searchTool.execute("call-5", { question: "anything", limit: 2 });

      // Only 2 answers should appear despite 3 being returned
      expect(result.content[0].text).toContain("First");
      expect(result.content[0].text).toContain("Second");
      expect(result.content[0].text).not.toContain("Third");
      expect(result.details.count).toBe(2);
    } finally {
      vi.doUnmock("conversation-memory");
      vi.resetModules();
    }
  });
});

// ── Live tests (skipped unless OPENCLAW_LIVE_TEST=1 + OPENAI_API_KEY set) ─────

describeLive("live: moment_log + moment_search round-trip", () => {
  test("stores a moment and retrieves it", async () => {
    const fs = await import("node:fs/promises");
    const os = await import("node:os");
    const path = await import("node:path");

    const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "typeagent-live-test-"));
    try {
      const { default: plugin } = await import("./index.js");
      const api = makeMockApi({
        openaiApiKey: process.env.OPENAI_API_KEY!,
        openaiModel: "gpt-4o",
        dataDir: tmpDir,
      });
      // oxlint-disable-next-line typescript/no-explicit-any
      plugin.register(api as any);

      const logTool = api._registeredTools.find((t: any) => t.name === "moment_log");
      const searchTool = api._registeredTools.find((t: any) => t.name === "moment_search");

      await logTool.execute("live-1", { text: "The wifi password is BlueSky2024" });
      const result = await searchTool.execute("live-2", { question: "What is the wifi password?" });

      expect(result.content[0].text.toLowerCase()).toContain("bluesky2024");
    } finally {
      await fs.rm(tmpDir, { recursive: true, force: true });
    }
  }, 30_000); // allow 30s for GPT-4o extraction
});
