#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

SHARED_NETWORK="mylife-shared"

echo "============================================"
echo "  MyLife — Setup"
echo "============================================"
echo ""

# ── Preflight ─────────────────────────────────────────────────────────

if ! command -v docker &>/dev/null; then
  echo "Error: Docker is not installed."
  echo "  Install: https://docs.docker.com/get-docker/"
  exit 1
fi

if ! docker compose version &>/dev/null; then
  echo "Error: Docker Compose (v2) is not installed."
  echo "  Install: https://docs.docker.com/compose/install/"
  exit 1
fi

# ── Step 1: Docker network ───────────────────────────────────────────

echo "── Step 1/5: Docker network ──"
if docker network inspect "$SHARED_NETWORK" &>/dev/null; then
  echo "[ok] Network '$SHARED_NETWORK' exists"
else
  docker network create "$SHARED_NETWORK"
  echo "[ok] Created network '$SHARED_NETWORK'"
fi
echo ""

# ── Step 2: Model providers ──────────────────────────────────────────

echo "── Step 2/5: Model providers ──"
echo ""

# -- Embedding provider --
echo "How will you run embedding models?"
echo "  1) Ollama (local — requires GPU or Apple Silicon)"
echo "  2) Cloud API (OpenAI, Gemini, Mistral, etc.)"
printf "Choice [1]: "
read -r EMBED_CHOICE
EMBED_CHOICE="${EMBED_CHOICE:-1}"

EMBED_PROVIDER="ollama"
EMBED_API_URL=""
EMBED_API_KEY=""
EMBED_CLOUD_MODEL=""
if [ "$EMBED_CHOICE" = "2" ]; then
  EMBED_PROVIDER="openai"
  printf "  API base URL (e.g., https://api.openai.com/v1): "
  read -r EMBED_API_URL
  printf "  API key: "
  read -r EMBED_API_KEY
  printf "  Model name (e.g., text-embedding-3-small): "
  read -r EMBED_CLOUD_MODEL
  echo "[ok] Embedding: cloud ($EMBED_CLOUD_MODEL)"
fi

echo ""

# -- Chat provider --
echo "How will you run the chat model (for metadata extraction)?"
echo "  1) Ollama (local — requires GPU or Apple Silicon)"
echo "  2) Cloud API (OpenAI-compatible: OpenAI, Gemini, Mistral, Groq)"
echo "  3) Anthropic (Claude)"
printf "Choice [1]: "
read -r CHAT_CHOICE
CHAT_CHOICE="${CHAT_CHOICE:-1}"

CHAT_PROVIDER="ollama"
CHAT_API_URL=""
CHAT_API_KEY=""
CHAT_CLOUD_MODEL=""
if [ "$CHAT_CHOICE" = "2" ]; then
  CHAT_PROVIDER="openai"
  printf "  API base URL (e.g., https://api.openai.com/v1): "
  read -r CHAT_API_URL
  printf "  API key: "
  read -r CHAT_API_KEY
  printf "  Model name (e.g., gpt-4o-mini): "
  read -r CHAT_CLOUD_MODEL
  echo "[ok] Chat: cloud OpenAI-compatible ($CHAT_CLOUD_MODEL)"
elif [ "$CHAT_CHOICE" = "3" ]; then
  CHAT_PROVIDER="anthropic"
  printf "  API key: "
  read -r CHAT_API_KEY
  printf "  Model name (e.g., claude-sonnet-4-5-20250514): "
  read -r CHAT_CLOUD_MODEL
  echo "[ok] Chat: Anthropic ($CHAT_CLOUD_MODEL)"
fi

echo ""

# -- Check Ollama if needed --
OLLAMA_OK=false
NEEDS_OLLAMA=false
[ "$EMBED_PROVIDER" = "ollama" ] && NEEDS_OLLAMA=true
[ "$CHAT_PROVIDER" = "ollama" ] && NEEDS_OLLAMA=true

if [ "$NEEDS_OLLAMA" = true ]; then
  if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
    OLLAMA_OK=true
    echo "[ok] Ollama is running"

    MODELS=$(curl -sf http://localhost:11434/api/tags 2>/dev/null \
      | python3 -c "import sys,json; print(' '.join(m['name'] for m in json.load(sys.stdin).get('models',[])))" 2>/dev/null \
      || echo "")

    if [ "$EMBED_PROVIDER" = "ollama" ]; then
      if echo "$MODELS" | grep -q "nomic-embed-text"; then
        echo "[ok] Embedding model 'nomic-embed-text' available"
      else
        echo "[!] Embedding model not found. Run: ollama pull nomic-embed-text"
      fi
    fi

    if [ -n "$MODELS" ]; then
      echo "    Available models: $MODELS"
    fi
  else
    echo "[!] Ollama is not reachable at localhost:11434"
    echo "    Install: https://ollama.com/download"
    echo "    Then pull models: ollama pull nomic-embed-text && ollama pull qwen3.5:9b"
  fi
else
  OLLAMA_OK=true  # not needed
  echo "[ok] Using cloud providers — Ollama not required"
fi
echo ""

# ── Step 3: RAG service ──────────────────────────────────────────────

echo "── Step 3/5: RAG service ──"
if [ -f rag/.env ]; then
  echo "[ok] rag/.env exists, skipping"
else
  (cd rag && bash setup.sh)
fi

# Write provider settings to rag/.env
if [ -f rag/.env ]; then
  _update_env() {
    local file="$1" key="$2" value="$3"
    if grep -q "^${key}=" "$file" 2>/dev/null; then
      if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|^${key}=.*|${key}=${value}|" "$file"
      else
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
      fi
    else
      echo "${key}=${value}" >> "$file"
    fi
  }

  _update_env rag/.env EMBED_PROVIDER "$EMBED_PROVIDER"
  if [ "$EMBED_PROVIDER" != "ollama" ]; then
    _update_env rag/.env EMBED_API_URL "$EMBED_API_URL"
    _update_env rag/.env EMBED_API_KEY "$EMBED_API_KEY"
    [ -n "$EMBED_CLOUD_MODEL" ] && _update_env rag/.env EMBED_MODEL "$EMBED_CLOUD_MODEL"
    # Cloud embedding dimensions differ — prompt user to set VECTOR_DIM
    echo "[!] Set VECTOR_DIM in rag/.env to match your cloud model's output dimensions"
    echo "    (e.g., text-embedding-3-small=1536, text-embedding-3-large=3072)"
  fi

  _update_env rag/.env CHAT_PROVIDER "$CHAT_PROVIDER"
  if [ "$CHAT_PROVIDER" != "ollama" ]; then
    [ -n "$CHAT_API_URL" ] && _update_env rag/.env CHAT_API_URL "$CHAT_API_URL"
    _update_env rag/.env CHAT_API_KEY "$CHAT_API_KEY"
    [ -n "$CHAT_CLOUD_MODEL" ] && _update_env rag/.env CHAT_MODEL "$CHAT_CLOUD_MODEL"
  fi

  echo "[ok] Provider settings written to rag/.env"
fi
echo ""

# ── Step 4: OpenClaw ─────────────────────────────────────────────────

echo "── Step 4/5: OpenClaw ──"
if [ -f openclaw/.env ] && [ -f openclaw/config/openclaw.json ]; then
  # Check if gateway.mode is configured (indicator of completed setup)
  if python3 -c "
import json, sys
with open('openclaw/config/openclaw.json') as f:
    cfg = json.load(f)
sys.exit(0 if cfg.get('gateway', {}).get('mode') else 1)
" 2>/dev/null; then
    echo "[ok] OpenClaw already configured, skipping"
  else
    echo "OpenClaw config incomplete. Running setup..."
    (cd openclaw && bash setup.sh)
  fi
else
  (cd openclaw && bash setup.sh)
fi
echo ""

# ── Step 5: Optional services + root .env ────────────────────────────

echo "── Step 5/5: Optional services ──"
PROFILES=""

# Ollama Docker container (for users without a native install)
if [ "$NEEDS_OLLAMA" = true ] && [ "$OLLAMA_OK" = false ]; then
  echo ""
  printf "Ollama isn't running natively. Run it in Docker instead? [y/N]: "
  read -r USE_OLLAMA_DOCKER
  if [ "${USE_OLLAMA_DOCKER:-n}" = "y" ] || [ "${USE_OLLAMA_DOCKER:-n}" = "Y" ]; then
    PROFILES="ollama"
    echo "[ok] Ollama Docker profile enabled"
  fi
fi

# Immich photo management
echo ""
printf "Enable Immich photo management? [y/N]: "
read -r USE_IMMICH
if [ "${USE_IMMICH:-n}" = "y" ] || [ "${USE_IMMICH:-n}" = "Y" ]; then
  if [ -n "$PROFILES" ]; then
    PROFILES="$PROFILES,immich"
  else
    PROFILES="immich"
  fi
  # Create immich .env if needed
  if [ ! -f immich/.env ]; then
    cp immich/.env-example immich/.env
    echo "[ok] Created immich/.env — edit it to set DB_PASSWORD before starting"
  fi
  echo "[ok] Immich profile enabled"
else
  echo "Skipped — enable later by adding 'immich' to COMPOSE_PROFILES in .env"
fi

# Generate Qdrant API key
QDRANT_API_KEY=""
if [ -f .env ] && grep -q '^QDRANT_API_KEY=' .env 2>/dev/null; then
  QDRANT_API_KEY=$(grep '^QDRANT_API_KEY=' .env | cut -d= -f2)
fi
if [ -z "$QDRANT_API_KEY" ]; then
  QDRANT_API_KEY=$(openssl rand -hex 32)
fi

# Write root .env
cat > .env <<EOF
# Generated by setup.sh — safe to edit
COMPOSE_PROFILES=$PROFILES
QDRANT_API_KEY=$QDRANT_API_KEY
EOF
echo ""
echo "[ok] Root .env written (profiles: ${PROFILES:-core only})"

# Share Qdrant API key with RAG service
if [ -f rag/.env ]; then
  if grep -q '^QDRANT_API_KEY=' rag/.env 2>/dev/null; then
    echo "[ok] QDRANT_API_KEY already in rag/.env"
  else
    echo "QDRANT_API_KEY=$QDRANT_API_KEY" >> rag/.env
    echo "[ok] Added QDRANT_API_KEY to rag/.env"
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────

echo ""
echo "============================================"
echo "  Setup complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo ""
echo "  1. Start services:"
echo "       make up"
echo "       (or: docker compose up -d)"
echo ""
echo "  2. Check health:"
echo "       make health"
echo ""
if [ "$NEEDS_OLLAMA" = true ] && [ "$OLLAMA_OK" = false ] && [ -z "$PROFILES" ]; then
  echo "  3. Install and start Ollama:"
  echo "       https://ollama.com/download"
  [ "$EMBED_PROVIDER" = "ollama" ] && echo "       ollama pull nomic-embed-text"
  [ "$CHAT_PROVIDER" = "ollama" ] && echo "       ollama pull qwen3.5:9b"
  echo ""
fi
echo "  Dashboards:"
echo "    OpenClaw: http://localhost:18789"
echo "    Qdrant:   http://localhost:6333/dashboard"
if echo "$PROFILES" | grep -q "immich"; then
  echo "    Immich:   http://localhost:2283"
fi
echo ""
if [ -n "$QDRANT_API_KEY" ]; then
  echo "  Qdrant API key (for dashboard login):"
  echo "    $QDRANT_API_KEY"
  echo ""
fi
