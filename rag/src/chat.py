"""Chat completion providers for LLM-based metadata extraction.

Supports Ollama (local), any OpenAI-compatible API, and Anthropic's Messages
API.  Adding a new provider is one function + one PROVIDERS entry.
"""

import os
from collections.abc import Callable, Coroutine
from typing import Any

import httpx

# ── Config ────────────────────────────────────────────────────────────

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://host.docker.internal:11434")
CHAT_MODEL = os.environ.get("CHAT_MODEL", "qwen3.5:9b")
CHAT_PROVIDER = os.environ.get("CHAT_PROVIDER", "ollama")
CHAT_API_URL = os.environ.get("CHAT_API_URL", "")
CHAT_API_KEY = os.environ.get("CHAT_API_KEY", "")

# Type alias for provider callables
ProviderFn = Callable[
    [httpx.AsyncClient, str, str, dict | None],
    Coroutine[Any, Any, str],
]


# ── Provider implementations ─────────────────────────────────────────


async def _ollama(
    client: httpx.AsyncClient, system: str, user: str, schema: dict | None
) -> str:
    resp = await client.post(
        f"{OLLAMA_URL}/api/chat",
        json={
            "model": CHAT_MODEL,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "format": schema,
            "stream": False,
            "options": {"temperature": 0},
            "think": False,
        },
    )
    resp.raise_for_status()
    return resp.json()["message"]["content"]


async def _openai(
    client: httpx.AsyncClient, system: str, user: str, schema: dict | None
) -> str:
    if not CHAT_API_URL:
        raise ValueError("CHAT_API_URL must be set when CHAT_PROVIDER=openai")
    resp = await client.post(
        f"{CHAT_API_URL.rstrip('/')}/chat/completions",
        json={
            "model": CHAT_MODEL,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "temperature": 0,
            "response_format": {"type": "json_object"},
        },
        headers={
            "Authorization": f"Bearer {CHAT_API_KEY}",
            "Content-Type": "application/json",
        },
    )
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]["content"]


async def _anthropic(
    client: httpx.AsyncClient, system: str, user: str, schema: dict | None
) -> str:
    if not CHAT_API_KEY:
        raise ValueError("CHAT_API_KEY must be set when CHAT_PROVIDER=anthropic")
    api_url = CHAT_API_URL or "https://api.anthropic.com"
    resp = await client.post(
        f"{api_url.rstrip('/')}/v1/messages",
        json={
            "model": CHAT_MODEL,
            "max_tokens": 1024,
            "system": system,
            "messages": [{"role": "user", "content": user}],
            "temperature": 0,
        },
        headers={
            "x-api-key": CHAT_API_KEY,
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json",
        },
    )
    resp.raise_for_status()
    return resp.json()["content"][0]["text"]


# ── Registry ──────────────────────────────────────────────────────────

PROVIDERS: dict[str, ProviderFn] = {
    "ollama": _ollama,
    "openai": _openai,
    "anthropic": _anthropic,
}


# ── Public API ────────────────────────────────────────────────────────


async def complete(
    client: httpx.AsyncClient, system: str, user: str, schema: dict | None = None
) -> str:
    """Send a chat completion request to the configured provider.

    Args:
        client: Shared httpx async client.
        system: System prompt.
        user: User message.
        schema: Optional JSON schema — used as Ollama's ``format`` param;
            included as prompt instructions for cloud providers.

    Returns:
        Raw text content from the LLM.
    """
    provider_fn = PROVIDERS.get(CHAT_PROVIDER)
    if not provider_fn:
        raise ValueError(
            f"Unknown CHAT_PROVIDER '{CHAT_PROVIDER}'. "
            f"Supported: {', '.join(PROVIDERS)}"
        )
    return await provider_fn(client, system, user, schema)


def is_ollama() -> bool:
    """True when the chat provider is local Ollama."""
    return CHAT_PROVIDER == "ollama"
