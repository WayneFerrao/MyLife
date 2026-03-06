"""Embedding providers — Ollama (local) and OpenAI-compatible (cloud).

Adding a new provider is one function + one PROVIDERS entry.
"""

import os
from collections.abc import Callable, Coroutine
from typing import Any

import httpx

# ── Config ────────────────────────────────────────────────────────────

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://host.docker.internal:11434")
EMBED_MODEL = os.environ.get("EMBED_MODEL", "nomic-embed-text")
EMBED_PROVIDER = os.environ.get("EMBED_PROVIDER", "ollama")
EMBED_API_URL = os.environ.get("EMBED_API_URL", "")
EMBED_API_KEY = os.environ.get("EMBED_API_KEY", "")
# nomic-embed-text requires task prefixes ("search_document:", "search_query:")
# for optimal retrieval. Most other models don't. Set to false for non-nomic models.
EMBED_PREFIX = os.environ.get("EMBED_PREFIX", "true").lower() == "true"

ProviderFn = Callable[
    [httpx.AsyncClient, str],
    Coroutine[Any, Any, list[float]],
]


# ── Provider implementations ─────────────────────────────────────────


async def _ollama(client: httpx.AsyncClient, text: str) -> list[float]:
    resp = await client.post(
        f"{OLLAMA_URL}/api/embed",
        json={"model": EMBED_MODEL, "input": text},
    )
    resp.raise_for_status()
    embeddings = resp.json().get("embeddings")
    if not embeddings or not embeddings[0]:
        raise ValueError(f"Ollama returned empty embeddings for model '{EMBED_MODEL}'")
    return embeddings[0]


async def _openai(client: httpx.AsyncClient, text: str) -> list[float]:
    if not EMBED_API_URL:
        raise ValueError("EMBED_API_URL must be set when EMBED_PROVIDER=openai")
    resp = await client.post(
        f"{EMBED_API_URL.rstrip('/')}/embeddings",
        json={"model": EMBED_MODEL, "input": text},
        headers={
            "Authorization": f"Bearer {EMBED_API_KEY}",
            "Content-Type": "application/json",
        },
    )
    resp.raise_for_status()
    data = resp.json().get("data")
    if not data or not data[0].get("embedding"):
        raise ValueError(f"Empty embedding response for model '{EMBED_MODEL}'")
    return data[0]["embedding"]


# ── Registry ──────────────────────────────────────────────────────────

PROVIDERS: dict[str, ProviderFn] = {
    "ollama": _ollama,
    "openai": _openai,
}


# ── Public API ────────────────────────────────────────────────────────


async def generate(
    client: httpx.AsyncClient, text: str, prefix: str = "search_document"
) -> list[float]:
    """Generate a vector embedding for the given text.

    Args:
        client: Shared httpx async client.
        text: The text to embed.
        prefix: Task prefix for nomic-embed-text style models. Ignored
            when EMBED_PREFIX is false.

    Returns:
        A list of floats representing the embedding vector.
    """
    input_text = f"{prefix}: {text}" if EMBED_PREFIX else text
    provider_fn = PROVIDERS.get(EMBED_PROVIDER)
    if not provider_fn:
        raise ValueError(
            f"Unknown EMBED_PROVIDER '{EMBED_PROVIDER}'. "
            f"Supported: {', '.join(PROVIDERS)}"
        )
    return await provider_fn(client, input_text)


def is_ollama() -> bool:
    """True when the embedding provider is local Ollama."""
    return EMBED_PROVIDER == "ollama"
