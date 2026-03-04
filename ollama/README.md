# Ollama — Local Model Server

Shared local model server for running LLMs on your own hardware. Ollama provides a simple API for pulling, managing, and serving open-weight models. Other services in this project (like OpenClaw) connect to Ollama to use local models instead of — or alongside — cloud provider APIs.

## Install (Recommended: Native)

Running Ollama natively gives you the simplest CLI experience (`ollama pull`, `ollama run` — no prefix), direct GPU access (Metal on Apple Silicon, CUDA on Linux), and system-wide availability for editor integrations and other tools.

OpenClaw's `OLLAMA_BASE_URL=http://host.docker.internal:11434` reaches a native Ollama install the same way it reaches a Dockerized one — the port is identical, no config changes needed.

### macOS

```sh
brew install ollama
brew services start ollama
```

### Linux

```sh
curl -fsSL https://ollama.com/install.sh | sh
```

### Verify

```sh
ollama pull qwen3.5:9b
ollama list
curl http://localhost:11434/api/tags
```

## Docker Alternative

A `docker-compose.yml` is included if you prefer containerized deployment (e.g., on a shared server or for reproducibility). Note that on macOS, Docker cannot access Metal, so Ollama will run CPU-only inside a container.

```sh
   cp .env-example .env
   docker compose up -d
   docker compose exec ollama ollama pull qwen3.5:9b
```

See `.env-example` for available performance tuning options (flash attention, KV cache quantization).

## Recommended Models

| Model | Size | Use Case |
| ----- | ---- | -------- |
| `llama3.2` | 3B | Lightweight general-purpose, fast on most hardware but not the best quality |
| `llama3.2:1b` | 1B | Minimal footprint for testing and low-resource machines |
| `qwen3:14b` | 14B | Strong balance of quality and performance |
| `deepseek-r1:32b` | 32B | Best reasoning capability, requires 24+ GB VRAM |

For embeddings, consider `nomic-embed-text` or `mxbai-embed-large`.

Choose a model based on available hardware. See the [hardware notes](#hardware-notes) section below.

## Storage

When running natively, models are stored in `~/.ollama/models/`. When running via Docker, models are stored in `./models/` (mapped as a volume, excluded from version control via `.gitignore`).

## Common Commands

```sh
# Pull a model
ollama pull <model-name>

# List downloaded models
ollama list

# Remove a model
ollama rm <model-name>

# Test a model directly
ollama run <model-name> "Hello, world"

# Check service status (macOS)
brew services info ollama
```

## Connecting Other Services

Other Docker services in this project (like OpenClaw) reach Ollama at `http://host.docker.internal:11434` on macOS/Windows, or via `extra_hosts` mapping on Linux. This works the same whether Ollama is running natively or in Docker — the port is identical. See the OpenClaw README for specific connection instructions.

## Hardware Notes

Ollama runs on CPU by default. For faster inference, a dedicated GPU is recommended.

| VRAM | Models |
| ---- | ------ |
| No GPU (CPU only) | 1B-3B models at usable speed |
| 8 GB | Most 7B models in common quantizations |
| 16-24 GB | 14B-32B models comfortably |
| 48+ GB | Large models with large context windows |

### GPU Support

- **Apple Silicon (M1/M2/M3/M4):** Metal GPU is used automatically when running natively. Docker cannot access Metal — this is a key reason to prefer a native install on macOS.
- **NVIDIA (Linux):** Native installs detect CUDA automatically. For Docker, install the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) and add GPU reservations to `docker-compose.yml`.

## Further Reading

- [Ollama documentation](https://ollama.com)
- [Ollama model library](https://ollama.com/library)
- [Ollama Docker image](https://hub.docker.com/r/ollama/ollama)
- [Ollama GitHub repository](https://github.com/ollama/ollama)
