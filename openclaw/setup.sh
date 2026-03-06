#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

SHARED_NETWORK="mylife-shared"

# ── Preflight checks ────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  echo "Error: Docker is not installed. See https://docs.docker.com/get-docker/"
  exit 1
fi

if ! docker compose version &>/dev/null; then
  echo "Error: Docker Compose is not installed. See https://docs.docker.com/compose/install/"
  exit 1
fi

# ── Verify Ollama is reachable from inside Docker ────────────────────────────
OLLAMA_CHECK_URL="${OLLAMA_BASE_URL:-http://host.docker.internal:11434}"
if ! docker run --rm --add-host=host.docker.internal:host-gateway curlimages/curl -sf "$OLLAMA_CHECK_URL/api/version" &>/dev/null; then
  echo "Error: Ollama is not reachable at $OLLAMA_CHECK_URL"
  echo "Make sure Ollama is installed and running. See https://ollama.com/download"
  exit 1
fi

# ── Ensure shared Docker network exists ──────────────────────────────────────
if docker network inspect "$SHARED_NETWORK" &>/dev/null; then
  echo "Docker network '$SHARED_NETWORK' already exists"
else
  echo "Creating Docker network '$SHARED_NETWORK'..."
  docker network create "$SHARED_NETWORK"
  echo "Created Docker network '$SHARED_NETWORK'"
fi

# ── Onboarding mode ──────────────────────────────────────────────────────────
echo ""
echo "Setup mode:"
echo "  1) Auto   — apply defaults and configure non-interactively (recommended)"
echo "  2) Wizard — run the interactive CLI onboarding wizard"
echo ""
printf "Choice [1]: "
read -r SETUP_MODE
SETUP_MODE=${SETUP_MODE:-1}

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
  TOKEN=$(grep '^OPENCLAW_GATEWAY_TOKEN=' .env | cut -d'=' -f2 | tr -d '\r')
  echo "Using existing gateway token from .env"
fi

if [ "$SETUP_MODE" = "1" ]; then
  # ── Prompt for API key if still using the placeholder ──────────────────────
  if grep -q '<your-anthropic-api-key>' .env; then
    echo ""
    echo "No model provider API key configured in .env."
    echo "Edit .env and add at least one API key before starting the gateway."
    echo "See the Model Providers section in README.md for options."
    echo ""
  fi
  # ── Configure openclaw.json via OpenClaw CLI ───────────────────────────────
  CONFIG_FILE="./config/openclaw.json"

  OLLAMA_BASE_URL=$(grep -E '^OLLAMA_BASE_URL=' .env 2>/dev/null | cut -d'=' -f2- | tr -d '"\r')
  OLLAMA_BASE_URL=${OLLAMA_BASE_URL:-http://host.docker.internal:11434}
  OLLAMA_API_KEY=$(grep -E '^OLLAMA_API_KEY=' .env 2>/dev/null | cut -d'=' -f2- | tr -d '"\r')
  OLLAMA_API_KEY=${OLLAMA_API_KEY:-ollama-local}
  OLLAMA_MODEL=$(grep -E '^OLLAMA_MODEL=' .env 2>/dev/null | cut -d'=' -f2- | tr -d '"\r')
  OLLAMA_MODEL=${OLLAMA_MODEL:-qwen3.5:9b}

  WHATSAPP_ALLOW_FROM=$(grep -E '^WHATSAPP_ALLOW_FROM=' .env 2>/dev/null | cut -d'=' -f2- | tr -d '"\r')
  # Clear placeholder value so we can treat empty/unset uniformly
  if [ "$WHATSAPP_ALLOW_FROM" = "<your-phone-number>" ]; then
    WHATSAPP_ALLOW_FROM=""
  fi

  # ── Prompt for WhatsApp phone number if not set ────────────────────────────
  if [ -z "$WHATSAPP_ALLOW_FROM" ]; then
    echo ""
    printf "WhatsApp phone number in E.164 format (e.g. +12065551234), or press Enter to skip: "
    read -r WHATSAPP_ALLOW_FROM
    if [ -n "$WHATSAPP_ALLOW_FROM" ]; then
      # Validate E.164 format to avoid unexpected characters breaking quoting
      if ! [[ "$WHATSAPP_ALLOW_FROM" =~ ^\+[0-9]{6,15}$ ]]; then
        echo "Invalid WhatsApp phone number. Expected E.164 format like +12065551234. Skipping."
        WHATSAPP_ALLOW_FROM=""
      fi
    fi
    if [ -n "$WHATSAPP_ALLOW_FROM" ]; then
      if grep -q '^WHATSAPP_ALLOW_FROM=' .env; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
          sed -i '' "s|WHATSAPP_ALLOW_FROM=.*|WHATSAPP_ALLOW_FROM=$WHATSAPP_ALLOW_FROM|" .env
        else
          sed -i "s|WHATSAPP_ALLOW_FROM=.*|WHATSAPP_ALLOW_FROM=$WHATSAPP_ALLOW_FROM|" .env
        fi
      else
        echo "WHATSAPP_ALLOW_FROM=$WHATSAPP_ALLOW_FROM" >> .env
      fi
      echo "Saved WhatsApp number to .env"
    else
      echo "Skipped — you can set it later via: openclaw config set channels.whatsapp.allowFrom '[\"...\"]'"
    fi
  fi

  # Bootstrap an empty config if none exists so the CLI has a file to work with
  if [ ! -f "$CONFIG_FILE" ]; then
    mkdir -p "$(dirname "$CONFIG_FILE")"
    echo '{}' > "$CONFIG_FILE"
    echo "Initialized empty config"
  fi

  # Build the Ollama model entry as a JSON string
  OLLAMA_MODEL_JSON=$(printf '[{"id":"%s","name":"%s","reasoning":false,"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":131072,"maxTokens":8192}]' \
    "$OLLAMA_MODEL" "$OLLAMA_MODEL")

  # Build optional WhatsApp allowFrom config line
  # WHATSAPP_ALLOW_FROM is validated to E.164 format (+[0-9]{6,15}) above,
  # so it is safe to interpolate into the container shell script.
  WHATSAPP_CFG=""
  if [ -n "$WHATSAPP_ALLOW_FROM" ]; then
    WHATSAPP_CFG="cfg channels.whatsapp.enabled      true
    cfg channels.whatsapp.allowFrom '[\"$WHATSAPP_ALLOW_FROM\"]'
    cfg channels.whatsapp.dmPolicy     allowlist"
  fi

  echo "Applying config via OpenClaw CLI..."
  docker compose run --rm --entrypoint sh openclaw-gateway -c "
    set -e
    cfg() {
      # Run config set, capture output and status so we don't lose failures in the pipeline
      set +e
      out=\$(node dist/index.js config set \"\$@\" 2>&1)
      status=\$?
      set -e
      printf '%s\n' \"\$out\" | grep -Ev '^🦞|^Config overwrite|Failed to discover Ollama' || true
      return \$status
    }

    # Required: gateway mode (blocks startup if unset), auth, and Docker networking
    cfg gateway.mode             local
    cfg gateway.auth.mode        token
    cfg gateway.auth.token       '$TOKEN'
    cfg gateway.bind             lan
    cfg gateway.controlUi.allowedOrigins '[\"http://localhost:18789\"]' || true

    # Ollama provider — set models array before models.mode to pass validation,
    # then set baseUrl last so it overrides any URL auto-discovered when api is set
    cfg models.providers.ollama.apiKey   '$OLLAMA_API_KEY'
    cfg models.providers.ollama.api      ollama
    cfg models.providers.ollama.models   '$OLLAMA_MODEL_JSON'
    cfg models.mode                      merge
    cfg models.providers.ollama.baseUrl  '$OLLAMA_BASE_URL'

    # Default model for agents
    cfg agents.defaults.model.primary  'ollama/$OLLAMA_MODEL'
    cfg agents.defaults.models         '{\"ollama/$OLLAMA_MODEL\":{}}' || true

    # WhatsApp channel — only enabled when a phone number is provided;
    # set allowFrom before dmPolicy to pass validation
    $WHATSAPP_CFG
  "
  echo "Config applied (model: $OLLAMA_MODEL)"

  # ── Start gateway and show WhatsApp QR if number was configured ──────────
  if [ -n "$WHATSAPP_ALLOW_FROM" ]; then
    echo ""
    echo "Starting gateway..."
    docker compose up -d

    echo "Waiting for gateway to be ready..."
    for i in $(seq 1 30); do
      if curl -sf http://127.0.0.1:18789/healthz >/dev/null 2>&1; then
        echo "Gateway ready."
        break
      fi
      sleep 1
    done

    echo ""
    echo "Scan the QR code below with WhatsApp to link your account:"
    echo ""
    docker compose exec openclaw-gateway node dist/index.js channels login --channel whatsapp --verbose
  fi
else
  # ── Wizard mode: run onboarding then patch config for Docker ──────────────
  CONFIG_FILE="./config/openclaw.json"
  if [ -f "$CONFIG_FILE" ]; then
    rm "$CONFIG_FILE"
    echo "Cleared existing config for fresh onboarding"
  fi
  echo "Starting onboarding wizard..."
  echo "Follow the interactive prompts to configure your agent."
  echo ""
  docker compose run --rm --entrypoint "node dist/index.js onboard" openclaw-gateway

  # Patch config for Docker: bind must be lan, controlUi needs allowedOrigins
  if [ -f "$CONFIG_FILE" ]; then
    docker compose run --rm --entrypoint sh openclaw-gateway -c "
      set -e
      cfg() {
        output=\$(node dist/index.js config set \"\$@\" 2>&1)
        status=\$?
        printf '%s\n' \"\$output\" | grep -Ev '^🦞|^Config overwrite' || true
        return \"\$status\"
      }
      cfg gateway.bind                         lan
      cfg gateway.controlUi.allowedOrigins     '[\"http://localhost:18789\"]' || true
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
echo "  1. (Re)start the gateway to apply config:"
echo "     docker compose restart  (if already running)"
echo "     docker compose up -d    (if not yet started)"
echo ""
echo "  2. Open the web UI and connect with your token:"
echo "     http://localhost:18789"
echo "     Token: $TOKEN"
echo ""
echo "  3. Approve devices (browser + local machine):"
echo ""
echo "     Via docker (always works):"
echo "        docker compose exec openclaw-gateway node dist/index.js devices list"
echo "        docker compose exec openclaw-gateway node dist/index.js devices approve <requestId>"
echo ""
echo "     Via local CLI (once paired):"
echo "        openclaw devices list"
echo "        openclaw devices approve <requestId>"
echo ""
if [ -n "${WHATSAPP_ALLOW_FROM:-}" ] && [ "${SETUP_MODE:-1}" = "1" ]; then
echo "  4. Link WhatsApp (if not already done above):"
echo "     docker compose exec openclaw-gateway node dist/index.js channels login --channel whatsapp --verbose"
echo ""
fi
