#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

OPENCLAW_SKILL_DIR="../openclaw/workspace/skills/memory"
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

# ── 2. Install OpenClaw skill ───────────────────────────────────────

echo
echo "[+] Installing memory skill into OpenClaw workspace..."
mkdir -p "$OPENCLAW_SKILL_DIR"

sed "s|{{RAG_API_KEY}}|${RAG_API_KEY}|g" SKILL.md.template \
    > "$OPENCLAW_SKILL_DIR/SKILL.md"

echo "[ok] Skill installed at $OPENCLAW_SKILL_DIR/SKILL.md"

# ── 3. Summary ──────────────────────────────────────────────────────

echo
echo "=== Setup Complete ==="
echo
echo "Next steps:"
echo "  1. Build and start the RAG service:"
echo "       docker compose up -d --build"
echo
echo "  2. Restart OpenClaw to pick up the new skill:"
echo "       cd ../openclaw && docker compose restart"
echo
echo "  3. Verify the service is healthy:"
echo "       curl http://localhost:18790/health"
echo
echo "  4. Verify OpenClaw can reach the RAG service:"
echo "       docker exec openclaw-gateway curl -sf http://rag:18790/health"
echo "       (should return {\"status\":\"ok\",...})"
echo
echo "  5. (Optional) Seed test data"
echo "       Manually set ALLOW_SEED=true in .env"
echo "       docker compose down; docker compose up -d --force-recreate"
echo "       curl -X POST http://localhost:18790/seed -H 'X-Api-Key: $RAG_API_KEY'"
echo
