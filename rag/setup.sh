#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

OPENCLAW_ENV="../openclaw/.env"
SHARED_NETWORK="mylife-shared"

echo "=== RAG Service Setup ==="
echo

# ── 0. Ensure shared Docker network exists ────────────────────────

if docker network inspect "$SHARED_NETWORK" &>/dev/null; then
    echo "[ok] Docker network '$SHARED_NETWORK' already exists"
else
    echo "[+] Creating Docker network '$SHARED_NETWORK'..."
    docker network create "$SHARED_NETWORK"
    echo "[ok] Created Docker network '$SHARED_NETWORK'"
fi
echo

# ── 1. Create .env ──────────────────────────────────────────────────

if [ -f .env ]; then
    echo "[ok] .env already exists, skipping creation"
else
    echo "[+] Creating .env from .env-example..."
    cp .env-example .env

    # Generate a random API key
    RAG_API_KEY=$(openssl rand -hex 32)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|<your-rag-api-key>|${RAG_API_KEY}|" .env
    else
        sed -i "s|<your-rag-api-key>|${RAG_API_KEY}|" .env
    fi
    echo "[ok] Generated API key and saved to .env"
fi

# Read the API key from .env
RAG_API_KEY=$(grep '^RAG_API_KEY=' .env | cut -d= -f2)

if [ -z "$RAG_API_KEY" ] || [ "$RAG_API_KEY" = "<your-rag-api-key>" ]; then
    echo "[!] Error: RAG_API_KEY is not set in .env"
    exit 1
fi

# ── 2. Share API key with OpenClaw ────────────────────────────────

echo
if [ -f "$OPENCLAW_ENV" ]; then
    if grep -q '^RAG_API_KEY=' "$OPENCLAW_ENV" 2>/dev/null; then
        echo "[ok] RAG_API_KEY already in OpenClaw .env"
    else
        echo "[+] Adding RAG_API_KEY to OpenClaw .env..."
        echo "RAG_API_KEY=${RAG_API_KEY}" >> "$OPENCLAW_ENV"
        echo "[ok] RAG_API_KEY added to $OPENCLAW_ENV"
    fi
else
    echo "[!] Warning: OpenClaw .env not found at $OPENCLAW_ENV"
    echo "    You'll need to add RAG_API_KEY=${RAG_API_KEY} to it manually."
fi

# ── 3. Summary ──────────────────────────────────────────────────────

echo
echo "=== Setup Complete ==="
echo
echo "Next steps:"
echo "  1. Build and start the RAG service:"
echo "       docker compose up -d --build"
echo
echo "  2. Restart OpenClaw to pick up the plugin:"
echo "       cd ../openclaw && docker compose up -d --force-recreate"
echo
echo "  3. Verify the service is healthy:"
echo "       curl http://localhost:18790/health"
echo
echo "  4. Verify OpenClaw can reach the RAG service:"
echo "       docker exec <openclaw-container> curl -sf http://rag:18790/health"
echo "       (should return {\"status\":\"ok\",...})"
echo
echo "  5. (Optional) Seed test data"
echo "       Manually set ALLOW_SEED=true in .env"
echo "       docker compose down; docker compose up -d --force-recreate"
echo "       curl -X POST http://localhost:18790/seed -H 'X-Api-Key: $RAG_API_KEY'"
echo
