## Personal Memory RAG Blueprint

A privacy-first, self-hosted blueprint for building a RAG-enabled personal memory system.

This repository provides a lightweight, modular setup for managing personal journal entries and messages as structured, queryable life events. Using a local LLM + embeddings, a vector database, and OpenClaw, it combines semantic search and structured memory for complex queries like
- "When was I last in Toronto?"
- "What were my son's last illness symptoms?"

Optionally includes Immich for self-hosted photo and video management.

Designed as a reusable, hands-on blueprint — experiment, extend, and adapt your own private memory AI system entirely locally.

## Quick Start

### 1. Install Ollama and pull models

Install from <https://ollama.com/download>, then:

```bash
ollama pull nomic-embed-text    # embedding model
ollama pull qwen3.5:9b          # chat model (or any model you prefer)
```

> **Using a different model?** Update `EMBED_MODEL` and `CHAT_MODEL` in `rag/.env` after setup.
> If you change the embedding model, also update `VECTOR_DIM` to match its output dimensions
> (nomic-embed-text=768, mxbai-embed-large=1024, all-minilm=384).

### 2. Run setup

```bash
make setup    # or: bash setup.sh
```

The setup script will:
- Create the shared Docker network
- Check that Ollama is running and models are pulled
- Generate API keys for RAG and Qdrant
- Configure OpenClaw (interactive — choose auto or wizard mode)
- Ask whether to enable optional services (Immich, Docker-based Ollama)

### 3. Start services

```bash
make up       # or: docker compose up -d
```

This starts the core stack: **Qdrant** → **RAG** → **OpenClaw**, in dependency order.
Optional services (Immich, Ollama Docker) only start if you enabled them during setup.

### 4. Verify

```bash
make health
```

| Service  | URL                                    |
|----------|----------------------------------------|
| OpenClaw | http://localhost:18789                  |
| RAG      | http://localhost:18790/health           |
| Qdrant   | http://localhost:6333/dashboard         |

## Common Operations

| Command                  | What it does                                            |
|--------------------------|---------------------------------------------------------|
| `make up`                | Start services (profiles from `.env`)                   |
| `make down`              | Stop all services                                       |
| `make rebuild-rag`       | Rebuild RAG image and restart (after code changes)      |
| `make restart-openclaw`  | Recreate OpenClaw (picks up .env/config changes)        |
| `make logs-rag`          | Tail RAG service logs                                   |
| `make logs-openclaw`     | Tail OpenClaw logs                                      |
| `make health`            | Check health of all endpoints                           |
| `make status`            | Show container status                                   |
| `make backup`            | Snapshot Qdrant data (timestamped tarball)              |
| `make restore FILE=...`  | Restore Qdrant data from a backup tarball               |
| `make reset-vectors`     | Delete Qdrant collection (recreated on next RAG start)  |
| `make help`              | Show all available targets                              |

## Architecture

```
User (WhatsApp / Web UI)
  │
  ▼
OpenClaw Gateway (:18789)
  │  rag-memory plugin calls RAG API
  ▼
RAG Service (:18790)
  ├── Ollama (:11434) — embedding + metadata extraction
  └── Qdrant (:6333)  — vector storage + search
```

OpenClaw talks to RAG via the shared Docker network. RAG reaches Ollama via `host.docker.internal`
(Ollama runs natively, not in Docker). Qdrant is on the same Docker network as RAG.

## Model Configuration

The system is model-agnostic. Change models by editing `rag/.env`:

| Variable       | Default            | Purpose                                        |
|----------------|--------------------|-------------------------------------------------|
| `EMBED_MODEL`  | `nomic-embed-text` | Ollama model for vector embeddings              |
| `CHAT_MODEL`   | `qwen3.5:9b`      | Ollama model for metadata extraction            |
| `VECTOR_DIM`   | `768`              | Must match embedding model output dimensions    |
| `EMBED_PREFIX`  | `true`             | Task prefixes (required for nomic, disable for others) |

OpenClaw's chat model is configured separately in `openclaw/.env` (`OLLAMA_MODEL`).

### Recommended models

| Use case    | Model               | Size  | Notes                           |
|-------------|---------------------|-------|---------------------------------|
| Lightweight | `llama3.2`          | 3B    | Fast, lower quality             |
| Balanced    | `qwen3.5:9b`        | 9B    | Good quality/speed tradeoff     |
| Advanced    | `qwen3:14b`         | 14B   | Higher quality, more VRAM       |
| Reasoning   | `deepseek-r1:32b`   | 32B   | Chain-of-thought reasoning      |

## Project Structure

```
├── docker-compose.yml      # Root orchestration (start here)
├── Makefile                # Common workflow shortcuts
├── setup.sh                # First-time setup script
├── .env                    # Profiles + Qdrant API key (generated)
│
├── rag/                    # RAG service (Python FastAPI)
│   ├── Dockerfile
│   ├── src/                # App source code
│   └── .env                # RAG config (models, keys)
│
├── openclaw/               # AI agent gateway
│   ├── config/             # Agent configuration
│   ├── extensions/         # Plugins (rag-memory)
│   └── .env                # Provider keys, gateway token
│
├── qdrant/                 # Vector database
│   └── qdrant_data/        # Persistent storage
│
├── immich/                 # Photo & video management (optional)
│   └── .env                # Immich config
│
└── ollama/                 # Ollama Docker config (optional)
    └── models/             # Downloaded models
```

## Backup & Restore

### Create a backup

```bash
make backup
```

Creates a timestamped tarball in `backups/` (e.g., `backups/qdrant-20260306-143000.tar.gz`).

### Restore from backup

```bash
make down
rm -rf qdrant/qdrant_data
tar -xzf backups/qdrant-YYYYMMDD-HHMMSS.tar.gz -C qdrant/
make up
```

### Changing embedding models

If you switch to a different embedding model (e.g., from `nomic-embed-text` to `mxbai-embed-large`),
the vector dimensions will no longer match the existing collection. To handle this:

1. Back up your data: `make backup`
2. Update `EMBED_MODEL`, `VECTOR_DIM`, and `EMBED_PREFIX` in `rag/.env`
3. Delete the old collection: `make reset-vectors`
4. Restart RAG: `make rebuild-rag`
5. Re-ingest your notes (the old vectors are incompatible with the new model)

## Platform Support

Tested on **macOS**, **Linux**, and **Windows (WSL2)**.

Requirements:
- Docker 20.10+ and Docker Compose v2
- `bash`, `curl`, `openssl`, `make` (all pre-installed on macOS and most Linux/WSL distros)

**Windows users**: Run everything inside WSL2, not PowerShell/CMD. Install Docker Desktop
with the WSL2 backend enabled.

Ollama runs natively on the host. Containers reach it via `host.docker.internal`, which is
resolved automatically on all platforms through Docker's `host-gateway` mapping.

## Security

- **Qdrant**: Protected by API key (generated during setup). Dashboard prompts for the key.
- **RAG**: Protected by `X-Api-Key` header (shared between RAG and OpenClaw).
- **OpenClaw**: Protected by gateway token.
- **Immich**: Username/password login.
- All API keys are generated automatically by `setup.sh` and stored in `.env` files (gitignored).

## Per-Service Documentation

Each service has its own README with detailed configuration:
- [OpenClaw](openclaw/README.md) — agent setup, model providers, WhatsApp
- [RAG](rag/README.md) — API endpoints, environment variables
- [Ollama](ollama/README.md) — native vs Docker, hardware requirements
- [Immich](immich/README.md) — photo & video management setup
