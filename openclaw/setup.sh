#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

REPO_ROOT="$(cd .. && pwd)"

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

# ── Prompt for OpenAI API key (required for TypeAgent memory plugin) ──────────
if grep -q '<your-openai-api-key>' .env || ! grep -qE '^OPENAI_API_KEY=.+' .env; then
  echo ""
  read -r -p "Enter your OpenAI API key (required for TypeAgent memory plugin, sk-...): " OPENAI_KEY
  if [ -n "$OPENAI_KEY" ]; then
    if grep -q '<your-openai-api-key>' .env; then
      if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|OPENAI_API_KEY=<your-openai-api-key>|OPENAI_API_KEY=$OPENAI_KEY|" .env
      else
        sed -i "s|OPENAI_API_KEY=<your-openai-api-key>|OPENAI_API_KEY=$OPENAI_KEY|" .env
      fi
    else
      echo "OPENAI_API_KEY=$OPENAI_KEY" >> .env
    fi
    echo "OpenAI API key saved to .env"
  else
    echo "Skipped — TypeAgent memory plugin will not work until OPENAI_API_KEY is set in .env"
  fi
  echo ""
fi

# ── Clone TypeAgent and install plugin deps ───────────────────────────────────
TYPEAGENT_DIR="$REPO_ROOT/typeagent/ts"
PLUGIN_DIR="./config/plugins/typeagent-memory"

if [ -d "$PLUGIN_DIR" ]; then
  echo "Setting up TypeAgent memory plugin..."

  # Shallow-clone TypeAgent if not already present (ignored by git, never committed)
  if [ ! -d "$REPO_ROOT/typeagent/.git" ]; then
    echo "Cloning TypeAgent (shallow)..."
    git clone --depth=1 https://github.com/microsoft/TypeAgent.git "$REPO_ROOT/typeagent"
    echo "TypeAgent cloned."
  else
    echo "TypeAgent already cloned."
  fi

  # Build TypeAgent packages if not already built
  if [ ! -d "$TYPEAGENT_DIR/packages/knowPro/dist" ] || \
     [ ! -d "$TYPEAGENT_DIR/packages/memory/conversation/dist" ]; then
    echo "Building TypeAgent (this takes a few minutes on first run)..."
    if ! command -v pnpm &>/dev/null; then
      echo "Error: pnpm is required to build TypeAgent. Install it with: npm install -g pnpm"
      exit 1
    fi
    (cd "$TYPEAGENT_DIR" && pnpm install --frozen-lockfile && pnpm build)
    echo "TypeAgent built."
  else
    echo "TypeAgent already built."
  fi

  # Install plugin npm deps (copies TypeAgent packages into node_modules)
  if [ ! -d "$PLUGIN_DIR/node_modules/conversation-memory" ]; then
    echo "Installing plugin dependencies..."
    (cd "$PLUGIN_DIR" && npm install --omit=dev)
    echo "Plugin dependencies installed."
  else
    echo "Plugin dependencies already installed."
  fi
fi

# ── Run onboarding wizard ────────────────────────────────────────────────────
echo "Starting onboarding wizard..."
echo "Follow the interactive prompts to configure your agent."
echo ""
docker compose run --rm --entrypoint "node dist/index.js onboard" openclaw-gateway

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
