#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# ── Preflight checks ────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  echo "Error: Docker is not installed. See https://docs.docker.com/get-docker/"
  exit 1
fi

if ! docker compose version &>/dev/null; then
  echo "Error: Docker Compose is not installed. See https://docs.docker.com/compose/install/"
  exit 1
fi

# ── Create .env from example if it doesn't exist ────────────────────────────
if [ ! -f .env ]; then
  cp .env-example .env
  echo "Created .env from .env-example"
fi

# ── Generate gateway token if still using the placeholder ────────────────────
if grep -q '<your-gateway-token>' .env; then
  TOKEN=$(openssl rand -hex 32)
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/<your-gateway-token>/$TOKEN/" .env
  else
    sed -i "s/<your-gateway-token>/$TOKEN/" .env
  fi
  echo "Generated gateway token"
else
  TOKEN=$(grep '^OPENCLAW_GATEWAY_TOKEN=' .env | cut -d'=' -f2)
  echo "Using existing gateway token from .env"
fi

# ── Prompt for API key if still using the placeholder ────────────────────────
if grep -q '<your-anthropic-api-key>' .env; then
  echo ""
  echo "No model provider API key configured in .env."
  echo "Edit .env and add at least one API key before starting the gateway."
  echo "See the Model Providers section in README.md for options."
  echo ""
fi

# ── Set Ollama keep-alive to prevent GPU discovery timeouts on reload ────────
# Without this, Ollama unloads the model after 5 minutes of inactivity, and
# reloading can fail GPU discovery on Windows, causing CPU fallback or 500s.
if [ -z "${OLLAMA_KEEP_ALIVE:-}" ]; then
  echo "Setting OLLAMA_KEEP_ALIVE=-1 (keep models loaded permanently)"
  export OLLAMA_KEEP_ALIVE=-1
  echo ""
  echo "NOTE: To persist this across reboots, add to your shell profile:"
  echo "  export OLLAMA_KEEP_ALIVE=-1"
  echo ""
fi

# ── Run onboarding wizard ────────────────────────────────────────────────────
echo "Starting onboarding wizard..."
echo "Follow the interactive prompts to configure your agent."
echo ""
docker compose run --rm --entrypoint "node dist/index.js onboard" openclaw-gateway

# ── Install "Something Happened" workspace templates ─────────────────────────
TEMPLATE_DIR="./workspace-templates"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-./workspace}"
if [ -d "$TEMPLATE_DIR" ]; then
  echo ""
  echo "[+] Installing workspace templates (Something Happened)..."
  cp "$TEMPLATE_DIR"/*.md "$WORKSPACE_DIR/"
  echo "[ok] Workspace files installed from $TEMPLATE_DIR"
fi

# ── Install moments skill (requires RAG_API_KEY from ../rag/.env) ────────────
SKILL_TEMPLATE="$TEMPLATE_DIR/skills/memory/SKILL.md.template"
SKILL_DIR="$WORKSPACE_DIR/skills/memory"
if [ -f "$SKILL_TEMPLATE" ]; then
  RAG_ENV="../rag/.env"
  if [ -f "$RAG_ENV" ]; then
    RAG_API_KEY=$(grep '^RAG_API_KEY=' "$RAG_ENV" | cut -d= -f2)
    if [ -n "$RAG_API_KEY" ] && [ "$RAG_API_KEY" != "<your-rag-api-key>" ]; then
      mkdir -p "$SKILL_DIR"
      sed "s|{{RAG_API_KEY}}|${RAG_API_KEY}|g" "$SKILL_TEMPLATE" > "$SKILL_DIR/SKILL.md"
      echo "[ok] Moments skill installed with API key from ../rag/.env"
    else
      echo "[!] RAG_API_KEY not set in ../rag/.env — run rag/setup.sh first"
    fi
  else
    echo "[!] ../rag/.env not found — run rag/setup.sh first to generate API key"
  fi
fi

# ── Patch config for Docker environment ──────────────────────────────────────
CONFIG_FILE="./config/openclaw.json"
if [ -f "$CONFIG_FILE" ]; then
  # The onboarding wizard generates config assuming a native install.
  # Docker requires the gateway to bind to a non-loopback address for port
  # forwarding, which in turn requires explicit CORS origins for the web UI.
  NEEDS_PATCH=false

  if grep -q '"bind": "loopback"' "$CONFIG_FILE"; then
    NEEDS_PATCH=true
  fi

  if ! grep -q '"allowedOrigins"' "$CONFIG_FILE"; then
    NEEDS_PATCH=true
  fi

  if [ "$NEEDS_PATCH" = true ]; then
    # Use python3 (available on macOS and most Linux) to patch JSON reliably
    python3 -c "
import json, sys
with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)
gw = config.setdefault('gateway', {})
gw['bind'] = 'lan'
gw.setdefault('controlUi', {})['allowedOrigins'] = ['http://localhost:18789']
with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')
"
    echo "Patched config for Docker (bind: lan, allowedOrigins: localhost:18789)"
  fi
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  Setup complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo ""
echo "  1. Start the gateway:"
echo "     docker compose up -d"
echo ""
echo "  2. Open the web UI:"
echo "     http://localhost:18789"
echo ""
echo "  3. When prompted, paste your gateway token and click Connect:"
echo "     $TOKEN"
echo ""
echo "  4. Approve devices (browser + local machine):"
echo ""
echo "     Before the dashboard works and before you can run 'openclaw devices list'"
echo "     locally, you must first approve both the browser and your local machine"
echo "     using the long docker compose exec command."
echo ""
echo "     a) List pending device requests:"
echo "        docker compose exec openclaw-gateway node dist/index.js devices list"
echo ""
echo "     b) Approve the browser device:"
echo "        docker compose exec openclaw-gateway node dist/index.js devices approve <browser-requestId>"
echo ""
echo "     c) Approve your local machine (the device that runs 'openclaw devices list'):"
echo "        docker compose exec openclaw-gateway node dist/index.js devices approve <local-machine-requestId>"
echo ""
echo "     Once both devices are approved, the dashboard will be fully functional"
echo "     and you can use the local CLI shorthand instead:"
echo "        openclaw devices list"
echo "        openclaw devices approve <requestId>"
echo ""
