# OpenClaw — Personal AI Assistant

Self-hosted AI assistant that connects to messaging platforms (WhatsApp, Telegram, Slack, Discord, and more). OpenClaw acts as the conversational interface for this project, enabling natural-language queries against the RAG pipeline from any messaging app.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/)
- At least one model provider — either a cloud API key (Anthropic, OpenAI, etc.) or a locally running Ollama instance (see [Model Providers](#model-providers))

## Setup

1. Configure at least one model provider API key in `.env` (see [Model Providers](#model-providers)).

2. Run the setup script. It creates your `.env`, generates a gateway token, runs the onboarding wizard, and patches the config for Docker:

   ```sh
   ./setup.sh
   ```

3. Start the gateway:

   ```sh
   docker compose up -d
   ```

4. Open the web UI at [http://localhost:18789](http://localhost:18789).

5. When the UI prompts for a token, paste the gateway token printed by the setup script. This authenticates the browser's WebSocket connection to the gateway. You can find it again in your `.env` file under `OPENCLAW_GATEWAY_TOKEN`.

6. Approve the browser as a trusted device. The web UI will show a pairing prompt. In a separate terminal, run:

   ```sh
   docker compose exec openclaw-gateway node dist/index.js devices list
   docker compose exec openclaw-gateway node dist/index.js devices approve <requestId>
   ```

   Replace `<requestId>` with the ID shown in the devices list output.

## Architecture

Running `docker compose up -d` starts a single container: **openclaw-gateway**. It is the long-running core of OpenClaw and handles everything:

- **Agent runtime** — Executes your AI agent, routing prompts to the configured model provider (Anthropic, OpenAI, etc.) and running tools on your behalf.
- **WebSocket server** — Acts as the central communication hub. All messaging channels (WhatsApp, Telegram, Slack, etc.) and companion apps connect to the gateway over WebSocket to send and receive messages.
- **Web UI** — Serves a browser-based chat interface on port `18789` for interacting with your agent directly.
- **CLI** — The same container includes the full OpenClaw CLI for administration tasks (onboarding, channel management, diagnostics). See [Running CLI Commands](#running-cli-commands) for usage.

## Storage

| Path          | Purpose                                      | Configured via          |
| ------------- | ------------------------------------         | ----------------------- |
| `./config`    | Agent configuration, memory, and credentials | `OPENCLAW_CONFIG_DIR`   |
| `./workspace` | Agent workspace data                         | `OPENCLAW_WORKSPACE_DIR`|

Both directories are created automatically on first run and excluded from version control via `.gitignore`.

## Model Providers

OpenClaw supports cloud APIs, locally running models, or both at the same time. Configure providers by editing the `.env` file.

### Cloud Providers

Add the API key for your subscription. OpenClaw auto-discovers available models from each configured provider.

| Provider | Environment Variable | Sign Up |
| -------- | -------------------- | ------- |
| Anthropic (Claude) | `ANTHROPIC_API_KEY` | [console.anthropic.com](https://console.anthropic.com) |
| OpenAI (GPT) | `OPENAI_API_KEY` | [platform.openai.com](https://platform.openai.com) |
| Google (Gemini) | `GEMINI_API_KEY` | [aistudio.google.com](https://aistudio.google.com) |
| OpenRouter | `OPENROUTER_API_KEY` | [openrouter.ai](https://openrouter.ai) |

### Local Models (Ollama)

For users who prefer to keep all data on-device or want to avoid API costs, OpenClaw can connect to a local Ollama instance. This requires the `ollama/` service in this repo to be running.

1. Set up and start Ollama by following the instructions in [`../ollama/README.md`](../ollama/README.md).

2. Pull at least one model:

   ```sh
   cd ../ollama && docker compose exec ollama ollama pull qwen3.5:9b
   ```

3. Uncomment the Ollama lines in your `openclaw/.env`:

   ```env
   OLLAMA_API_KEY=ollama-local
   OLLAMA_BASE_URL=http://host.docker.internal:11434
   ```

4. Restart the gateway:

   ```sh
   docker compose restart openclaw-gateway
   ```

OpenClaw will discover all models available in your Ollama instance alongside any configured cloud providers.

## Running CLI Commands

OpenClaw is installed inside the Docker container, not on your host machine. To run CLI commands, execute them inside the running gateway container:

```sh
docker compose exec openclaw-gateway node dist/index.js <command>
```

For example, where the OpenClaw docs say `openclaw channels login --channel whatsapp`:

```sh
docker compose exec openclaw-gateway node dist/index.js channels login --channel whatsapp
```

### Shorter alternative: install the CLI locally

If you'd prefer to run `openclaw <command>` directly from your terminal, install [Node.js](https://nodejs.org/) (v22+) and the OpenClaw CLI globally:

```sh
npm install -g openclaw
```

Then commands become simply:

```sh
openclaw channels login --channel whatsapp
openclaw devices list
openclaw doctor
```

The local CLI connects to the same running gateway container — it reads the config from `./config/` and authenticates with the same gateway token. Both approaches work; the Docker method just avoids needing Node.js on the host.

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

# Connect a messaging channel (e.g. WhatsApp)
docker compose exec openclaw-gateway node dist/index.js channels login --channel whatsapp

# Run diagnostics
docker compose exec openclaw-gateway node dist/index.js doctor

# Re-run onboarding (resets agent config)
docker compose run --rm --entrypoint "node dist/index.js onboard" openclaw-gateway

# Pull latest image and restart
docker compose pull && docker compose up -d
```

## Security

The gateway binds to `127.0.0.1` only and is not exposed to the public network. For remote access, use an SSH tunnel rather than opening the port directly:

```sh
ssh -L 18789:127.0.0.1:18789 user@your-server
```

## Connecting Messaging Channels

After onboarding, connect messaging platforms by running:

```sh
docker compose exec openclaw-gateway node dist/index.js channels login --channel <name>
```

Replace `<name>` with `whatsapp`, `telegram`, `discord`, `slack`, or any other supported channel. Follow the interactive prompts to link the platform. See the [OpenClaw channel docs](https://docs.openclaw.ai/channels) for platform-specific setup guides.

## Further Reading

- [OpenClaw documentation](https://docs.openclaw.ai)
- [Docker installation guide](https://docs.openclaw.ai/install/docker)
- [OpenClaw GitHub repository](https://github.com/openclaw/openclaw)
