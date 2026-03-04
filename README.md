## 📚 Personal Memory RAG Blueprint

A privacy-first, self-hosted blueprint for building a RAG-enabled personal memory system.

This repository provides a lightweight, modular setup for managing photos, journal entries, and messages as structured, queryable life events. Using Immich, a local LLM + embeddings, vector & graph databases, and OpenClaw, it demonstrates how to combine semantic search and structured memory for complex queries like 
- “When was I last in Toronto?”
- “What were my son’s last illness symptoms?”

Designed as a reusable, hands-on blueprint — experiment, extend, and adapt your own private memory AI system entirely locally.

## Setup Instructions

1. **Install Ollama** — <https://ollama.com/download>
   - After installing, Ollama should be running. Test with `curl http://localhost:11434/api/tags` (won't have any models yet)

2. **Pull models**
   - Chat model (showing recommended model): `ollama pull qwen3.5:9b`
   - Embedding model (showing recommended model): `ollama pull nomic-embed-text`
   - IMPORTANT: If you choose a different model from default, update EMBED_MODEL and/or CHAT_MODEL in [rag/.env](rag/.env).
   - Check `curl http://localhost:11434/api/tags` again, `Content` should include a populated "models" array now.

3. **Configure OpenClaw to use Ollama** — edit `openclaw/config/openclaw.json`:

    NOTE: This must be done manually for Ollama, as opposed to using other LLM providers which are supported via [`openclaw onboard`](https://openclaw.im/docs/cli/onboard)

   - Set `agents.defaults.model.primary` to `"ollama/<model>:<version>"`, e.g. `"ollama/qwen3.5:9b"`
   - Add a `"models"` object (sibling to `"agents"`) like this (using defaults as shown):

     ```json
     "models": {
       "mode": "merge",
       "providers": {
         "ollama": {
           "baseUrl": "http://host.docker.internal:11434",
           "apiKey": "ollama-local",
           "api": "ollama",
           "models": [
             {
               "id": "qwen3.5:9b",
               "name": "qwen3.5:9b",
               "reasoning": false,
               "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
               "contextWindow": 16192,
               "maxTokens": 16192
             }
           ]
         }
       }
     }
     ```

   - Note: You may need to enlarge `contextWindow` — this can be model-dependent.

4. **Start the containers**
   - `cd openclaw && docker compose up -d` from root
   - `cd qdrant && docker compose up -d` from root
     - [Qdrant dashboard](http://localhost:6333/dashboard) — running at `http://host.docker.internal:6333`

5. **Set up the RAG service**
   - Run `rag/setup.sh`
   - Follow the "Next steps" printed out
   - Verify at `http://localhost:18790/health`
