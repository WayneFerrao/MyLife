# Ollama — Local Model Server

Shared local model server for running LLMs on your own hardware. Ollama provides a simple API for pulling, managing, and serving open-weight models. Other services in this project (like OpenClaw) connect to Ollama to use local models instead of — or alongside — cloud provider APIs.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/)

## Setup

1. Create your `.env` file from the example:

   ```sh
   cp .env-example .env
   ```

2. Start the service:

   ```sh
   docker compose up -d
   ```

3. Pull a model:

   ```sh
   docker compose exec ollama ollama pull llama3.2
   ```

4. Verify the model is available:

   ```sh
   curl http://localhost:11434/api/tags
   ```

## Recommended Models

| Model | Size | Use Case |
| ----- | ---- | -------- |
| `llama3.2` | 3B | Lightweight general-purpose, fast on most hardware |
| `llama3.2:1b` | 1B | Minimal footprint for testing and low-resource machines |
| `qwen3:14b` | 14B | Strong balance of quality and performance |
| `deepseek-r1:32b` | 32B | Best reasoning capability, requires 24+ GB VRAM |

Choose a model based on available hardware. See the [hardware requirements](#hardware-notes) section below.

## Storage

| Path | Purpose | Configured via |
| ---- | ------- | -------------- |
| `./models` | Downloaded model weights and metadata | Volume mount in docker-compose.yml |

The `models/` directory is created automatically on first run and excluded from version control via `.gitignore`. Model files can be several gigabytes each.

## Common Commands

```sh
# Start the service
docker compose up -d

# Stop the service
docker compose down

# View logs
docker compose logs -f

# Pull a model
docker compose exec ollama ollama pull <model-name>

# List downloaded models
docker compose exec ollama ollama list

# Remove a model
docker compose exec ollama ollama rm <model-name>

# Test a model directly
docker compose exec ollama ollama run <model-name> "Hello, world"
```

## Connecting Other Services

Other Docker services in this project reach Ollama at `http://host.docker.internal:11434` (Docker Desktop on macOS/Windows) or via `extra_hosts` mapping on Linux. See the OpenClaw README for specific connection instructions.

## Hardware Notes

Ollama runs on CPU by default. For faster inference, a dedicated GPU is recommended.

| VRAM | Models |
| ---- | ------ |
| No GPU (CPU only) | 1B-3B models at usable speed |
| 8 GB | Most 7B models in common quantizations |
| 16-24 GB | 14B-32B models comfortably |
| 48+ GB | Large models with large context windows |

### GPU Support

For GPU acceleration with Docker, you need the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html). Once installed, add the following to `docker-compose.yml` under the `ollama` service:

```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: all
          capabilities: [gpu]
```

Apple Silicon (M1/M2/M3/M4) Macs use the Metal GPU automatically — no extra configuration needed when running Ollama natively. When running inside Docker on macOS, Ollama will use CPU only since Docker containers cannot access Metal.

## Further Reading

- [Ollama documentation](https://ollama.com)
- [Ollama model library](https://ollama.com/library)
- [Ollama Docker image](https://hub.docker.com/r/ollama/ollama)
- [Ollama GitHub repository](https://github.com/ollama/ollama)
