# OpenClaw — Personal AI Assistant

Self-hosted AI assistant that connects to messaging platforms (WhatsApp, Telegram, Slack, Discord, and more). OpenClaw acts as the conversational interface for this project, enabling natural-language queries against the RAG pipeline from any messaging app.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/)
- Ollama installed natively on your machine (see [Local Models (Ollama)](#local-models-ollama))
- Optionally, a cloud API key (Anthropic, OpenAI, etc.) if you prefer cloud models

## Setup

Run the setup script from the `openclaw/` directory:

```sh
./setup.sh
```

The script will ask you to choose a setup method:

### Method 1: Auto (Recommended)

Configures everything non-interactively from `.env` defaults. No manual JSON editing required.

1. Generates a gateway token
2. Prompts for your WhatsApp phone number (or skip to configure later)
3. Writes `config/openclaw.json` automatically using the OpenClaw CLI
4. Starts the gateway and shows the WhatsApp QR code in the terminal (if a number was provided)

After setup, follow the printed next steps to approve devices and you're done.

### Method 2: Wizard

Runs OpenClaw's built-in interactive onboarding CLI, then patches the generated config for Docker. Use this if you want to manually walk through provider selection, model choice, and channel configuration step by step.

1. Runs the interactive onboarding CLI to configure your agent
2. Automatically patches the generated config for Docker (`gateway.bind: lan`, `controlUi.allowedOrigins`)

## Local Models (Ollama)

Ollama must be installed and running **natively on your Mac** — do not use the Docker version of Ollama. Running natively gives OpenClaw access to Metal GPU acceleration (Apple Silicon), which Docker cannot access.

```sh
brew install ollama
brew services start ollama
```

Then pull your preferred model:

```sh
ollama pull qwen3.5:9b
```

The default model is `qwen3.5:9b`, configured via `OLLAMA_MODEL` in `.env`. OpenClaw connects to Ollama at `http://host.docker.internal:11434` — no additional configuration needed. The setup script handles registering the model in `openclaw.json` automatically.

See [`../ollama/README.md`](../ollama/README.md) for model recommendations and hardware notes.

## Model Providers

OpenClaw supports cloud APIs, local Ollama models, or both at the same time. Configure providers in `.env`.

### Cloud Providers

Add the API key for your provider. These are optional if you are using Ollama.

| Provider | Environment Variable | Sign Up |
| -------- | -------------------- | ------- |
| Anthropic (Claude) | `ANTHROPIC_API_KEY` | [console.anthropic.com](https://console.anthropic.com) |
| OpenAI (GPT) | `OPENAI_API_KEY` | [platform.openai.com](https://platform.openai.com) |
| Google (Gemini) | `GEMINI_API_KEY` | [aistudio.google.com](https://aistudio.google.com) |
| OpenRouter | `OPENROUTER_API_KEY` | [openrouter.ai](https://openrouter.ai) |

## Architecture

Running `docker compose up -d` starts a single container: **openclaw-gateway**. It handles everything:

- **Agent runtime** — Executes your AI agent, routing prompts to the configured model provider and running tools on your behalf.
- **WebSocket server** — Central communication hub for all messaging channels and companion apps.
- **Web UI** — Browser-based chat interface on port `18789`.
- **CLI** — Full OpenClaw CLI for administration. See [Running CLI Commands](#running-cli-commands).

## Storage

| Path          | Purpose                                      | Configured via           |
| ------------- | -------------------------------------------- | ------------------------ |
| `./config`    | Agent configuration, memory, and credentials | `OPENCLAW_CONFIG_DIR`    |
| `./workspace` | Agent workspace data                         | `OPENCLAW_WORKSPACE_DIR` |

Both directories are created automatically on first run and excluded from version control via `.gitignore`.

## Running CLI Commands

OpenClaw is installed inside the Docker container, not on your host machine. Run CLI commands via `docker compose exec`:

```sh
docker compose exec openclaw-gateway node dist/index.js <command>
```

### Shorter alternative: install the CLI locally

Install [Node.js](https://nodejs.org/) (v22+) and the OpenClaw CLI globally:

```sh
npm install -g openclaw
```

Then commands become simply `openclaw <command>`. The local CLI connects to the same running gateway container.

## Common Commands

```sh
# Start the gateway
docker compose up -d

# Stop the gateway
docker compose down

# View logs
docker compose logs -f

# List pending device pairing requests
docker compose exec openclaw-gateway node dist/index.js devices list

# Approve a device
docker compose exec openclaw-gateway node dist/index.js devices approve <requestId>

# Connect WhatsApp (show QR code in terminal)
docker compose exec openclaw-gateway node dist/index.js channels login --channel whatsapp --verbose

# Run diagnostics
docker compose exec openclaw-gateway node dist/index.js doctor

# Re-run onboarding (resets agent config)
docker compose run --rm --entrypoint "node dist/index.js onboard" openclaw-gateway

# Pull latest image and restart
docker compose pull && docker compose up -d
```

## Security

The gateway binds to `127.0.0.1` only and is not exposed to the public network. For remote access, use an SSH tunnel:

```sh
ssh -L 18789:127.0.0.1:18789 user@your-server
```

## Connecting Messaging Channels

Connect messaging platforms by running:

```sh
docker compose exec openclaw-gateway node dist/index.js channels login --channel <name>
```

Replace `<name>` with `whatsapp`, `telegram`, `discord`, `slack`, or any other supported channel. See the [OpenClaw channel docs](https://docs.openclaw.ai/channels) for platform-specific setup guides.

## Further Reading

- [OpenClaw documentation](https://docs.openclaw.ai)
- [Docker installation guide](https://docs.openclaw.ai/install/docker)
- [OpenClaw GitHub repository](https://github.com/openclaw/openclaw)

## FAQ

### Can I edit `openclaw.json` directly?

Yes. The config file lives at `config/openclaw.json` and is standard JSON. The setup script writes it automatically via the OpenClaw CLI, but you can hand-edit it if you need to make changes outside of what the CLI exposes. Restart the gateway after any manual edits:

```sh
docker compose restart
```

### Can I add Ollama models after setup?

Yes. Pull the model natively with `ollama pull <model>`, then update `OLLAMA_MODEL` in `.env` and re-run the relevant config set command (or edit `openclaw.json` directly):

```sh
docker compose exec openclaw-gateway node dist/index.js config set agents.defaults.model.primary "ollama/<model>"
docker compose restart
```
