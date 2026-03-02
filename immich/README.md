# Immich — Photo & Video Management

Self-hosted photo and video management server used as the media ingestion layer for this project. Immich handles uploading, organizing, and storing personal photos and videos that will later be indexed and queried by the RAG pipeline.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/)

## Setup

1. Create your `.env` file from the example:

   ```sh
   cp .env-example .env
   ```

2. Set a strong password for `DB_PASSWORD` in `.env`. Use only `A-Za-z0-9` characters.

3. Start the services:

   ```sh
   docker compose up -d
   ```

4. Open the web UI at [http://localhost:2283](http://localhost:2283) and create your admin account.

## Services

Running docker-compose up will start the following services.

| Service                  | Description                                      |
| ------------------------ | ------------------------------------------------ |
| **immich-server**        | Core API and web UI (port 2283)                  |
| **immich-machine-learning** | ML models for smart search, face detection, etc. |
| **redis**                | Cache and job queue (Valkey)                      |
| **database**             | PostgreSQL with vector extensions (pgvectors)    |

## Storage

| Path        | Purpose                          | Configured via      |
| ----------- | -------------------------------- | -------------------- |
| `./library` | Uploaded photos and videos       | `UPLOAD_LOCATION`    |
| `./postgres`| PostgreSQL data files            | `DB_DATA_LOCATION`   |

Both directories are created automatically on first run and excluded from version control via `.gitignore`.

## Common Commands

```sh
# Start services
docker compose up -d

# Stop services
docker compose down

# View logs
docker compose logs -f

# View logs for a specific service
docker compose logs -f immich-server

# Pull latest images and restart
docker compose pull && docker compose up -d
```

## Uploading Photos

- **Web UI** — Drag and drop at [http://localhost:2283](http://localhost:2283)
- **Mobile app** — Download the [Immich mobile app](https://immich.app/download) and point it at your server's IP on port 2283
- **CLI** — Use the [Immich CLI](https://docs.immich.app/docs/features/command-line-interface) for bulk uploads

## Further Reading

- [Immich documentation](https://docs.immich.app)
- [Environment variables reference](https://docs.immich.app/install/environment-variables)
- [Hardware-accelerated transcoding](https://docs.immich.app/features/ml-hardware-acceleration)