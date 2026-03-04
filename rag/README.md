# RAG Service — Personal Memory for OpenClaw

A lightweight FastAPI service that gives your OpenClaw agent persistent memory. Store personal notes via chat, retrieve them later with semantic search.

## How It Works

```
WhatsApp → OpenClaw agent → decides: note / query / general chat
  ├─ NOTE:  calls /ingest → extracts metadata → embeds → stores in Qdrant
  ├─ QUERY: calls /query  → embeds question → searches Qdrant → returns context
  └─ GENERAL: agent responds directly, RAG not involved
```

The agent learns when and how to use the service through a **skill** (`SKILL.md.template`).

## Prerequisites

- **Ollama** running with models pulled:
  - `nomic-embed-text` (embeddings)
  - `qwen3.5:9b` (metadata extraction — or whichever chat model you use)
- **Qdrant** running (see `../qdrant/`)
- **OpenClaw** running (see `../openclaw/`)

## Setup

```bash
cd rag
bash setup.sh              # generates .env, installs skill into OpenClaw
docker compose up -d --build
cd ../openclaw && docker compose restart   # pick up new skill
```

Verify:
```bash
curl http://localhost:18790/health
# {"status":"ok","ollama":true,"qdrant":true}
```

## API Endpoints

All mutating endpoints require `X-Api-Key` header.

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/health` | No | Dependency health check |
| POST | `/ingest` | Yes | Store a note (extracts metadata, embeds, saves to Qdrant) |
| POST | `/query` | Yes | Semantic search over stored notes |
| DELETE | `/notes/{id}` | Yes | Delete a specific note by ID |
| POST | `/seed` | Yes | Load test data (requires `ALLOW_SEED=true`) |

### Ingest

```bash
curl -X POST http://localhost:18790/ingest \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: YOUR_KEY" \
  -d '{"text": "My son was sick on March 3 with a cold and fever."}'
```

### Query

```bash
curl -X POST http://localhost:18790/query \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: YOUR_KEY" \
  -d '{"text": "When was my son last sick?", "limit": 5}'
```

### Delete

```bash
curl -X DELETE http://localhost:18790/notes/POINT_ID \
  -H "X-Api-Key: YOUR_KEY"
```

## Seeding Test Data

To verify retrieval quality before using real data:

1. Set `ALLOW_SEED=true` in `.env`
2. Restart: `docker compose restart`
3. Seed: `curl -X POST http://localhost:18790/seed -H "X-Api-Key: YOUR_KEY"`
4. Test queries:
   ```bash
   curl -X POST http://localhost:18790/query \
     -H "Content-Type: application/json" \
     -H "X-Api-Key: YOUR_KEY" \
     -d '{"text": "When was I last sick?"}'
   ```
5. Set `ALLOW_SEED=false` in `.env` and restart when done

## Environment Variables

See `.env-example` for all options. Key variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `RAG_API_KEY` | (required) | Shared secret for auth |
| `OLLAMA_URL` | `http://host.docker.internal:11434` | Ollama API endpoint |
| `QDRANT_URL` | `http://host.docker.internal:6333` | Qdrant API endpoint |
| `EMBED_MODEL` | `nomic-embed-text` | Ollama embedding model |
| `CHAT_MODEL` | `qwen3.5:9b` | Ollama chat model for metadata |
| `COLLECTION_NAME` | `notes` | Qdrant collection name |
| `ALLOW_SEED` | `false` | Enable /seed endpoint |

## Security

- API key required on all mutating endpoints
- Port bound to `127.0.0.1` only (not network-accessible)
- Input validation via Pydantic (max lengths enforced)
- No secrets logged
- Skill template uses placeholder — real key only in gitignored files
