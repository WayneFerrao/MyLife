"""Business logic for the RAG service: embedding, metadata extraction, and Qdrant operations."""

import json
import logging
import os

import httpx
from fastapi import Header, HTTPException

# ── Config ──────────────────────────────────────────────────────────

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://host.docker.internal:11434")
QDRANT_URL = os.environ.get("QDRANT_URL", "http://host.docker.internal:6333")
EMBED_MODEL = os.environ.get("EMBED_MODEL", "nomic-embed-text")
CHAT_MODEL = os.environ.get("CHAT_MODEL", "qwen3.5:9b")
COLLECTION = os.environ.get("COLLECTION_NAME", "notes")
API_KEY = os.environ["RAG_API_KEY"]  # required — fail fast if missing
ALLOW_SEED = os.environ.get("ALLOW_SEED", "false").lower() == "true"
VECTOR_DIM = 768  # nomic-embed-text output dimensions

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("rag")

http = httpx.AsyncClient(timeout=30.0)

# JSON schema passed to Ollama's `format` parameter to force structured metadata output.
METADATA_SCHEMA = {
    "type": "object",
    "properties": {
        "topic": {"type": "string"},
        "people": {"type": "array", "items": {"type": "string"}},
        "locations": {"type": "array", "items": {"type": "string"}},
        "dates_mentioned": {"type": "array", "items": {"type": "string"}},
        "mood": {"type": "string"},
        "tags": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["topic", "tags"],
}

SEED_NOTES = [
    "On February 10, 2026, my son came down with a cold and fever. He stayed home from school for three days.",
    "Visited my parents in Toronto on January 15, 2026. Mom made her famous biryani for dinner.",
    "Had a dentist appointment on February 28, 2026. No cavities, but need to floss more.",
    "Booked round-trip flights to Miami for March 20-25, 2026. Got a great deal on Delta.",
    "Started a new sourdough bread recipe on February 5, 2026. The starter took about a week to get going.",
    "Had a one-on-one with my manager Sarah on February 20, 2026. Discussed promotion timeline and Q2 goals.",
    "My daughter's piano recital was on February 14, 2026. She played Moonlight Sonata beautifully.",
    "Replaced the water heater on January 28, 2026. Cost $1,200 for the tank plus installation.",
    "Went hiking at Mount Rainier with Jake and Lisa on February 8, 2026. Trail was muddy but views were amazing.",
    "Started reading 'Project Hail Mary' by Andy Weir on February 1, 2026. Finished it in four days, couldn't put it down.",
]


# ── Auth ────────────────────────────────────────────────────────────


async def verify_api_key(x_api_key: str = Header(...)):
    """Validate the X-Api-Key header against the configured secret.

    Used as a FastAPI dependency on all mutating endpoints.

    Args:
        x_api_key: The API key from the request's X-Api-Key header.

    Raises:
        HTTPException: 401 if the key doesn't match RAG_API_KEY.
    """
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")


# ── Ollama helpers ──────────────────────────────────────────────────


async def embed(text: str, prefix: str = "search_document") -> list[float]:
    """Generate a vector embedding for the given text via Ollama.

    nomic-embed-text requires task prefixes for optimal retrieval quality:
    - "search_document" when storing notes (ingestion)
    - "search_query" when searching (retrieval)

    Args:
        text: The text to embed.
        prefix: Task prefix for nomic-embed-text. Defaults to "search_document".

    Returns:
        A list of 768 floats representing the embedding vector.

    Raises:
        httpx.HTTPStatusError: If Ollama returns a non-2xx response.
    """
    resp = await http.post(
        f"{OLLAMA_URL}/api/embed",
        json={"model": EMBED_MODEL, "input": f"{prefix}: {text}"},
    )
    resp.raise_for_status()
    return resp.json()["embeddings"][0]


async def extract_metadata(text: str) -> dict:
    """Extract structured metadata from a note using the chat model.

    Sends the note to Ollama with a JSON schema constraint so the LLM
    returns structured fields.

    Args:
        text: The note text to extract metadata from.

    Returns:
        A dict with keys: topic (str), people (list[str]), locations (list[str]),
        dates_mentioned (list[str]), mood (str | None), tags (list[str]).

    Raises:
        httpx.HTTPStatusError: If Ollama returns a non-2xx response.
        json.JSONDecodeError: If the LLM output isn't valid JSON.
    """
    resp = await http.post(
        f"{OLLAMA_URL}/api/chat",
        json={
            "model": CHAT_MODEL,
            "messages": [
                {
                    "role": "system",
                    "content": (
                        "Extract metadata from this note. Return JSON with: "
                        "topic (string), people (list of strings), locations (list of strings), "
                        "dates_mentioned (list of strings), mood (string or null), "
                        "tags (list of short keyword strings). "
                        "Only include fields where you find relevant information."
                    ),
                },
                {"role": "user", "content": text},
            ],
            "format": METADATA_SCHEMA,
            "stream": False,
            "options": {"temperature": 0},
        },
    )
    resp.raise_for_status()
    return json.loads(resp.json()["message"]["content"])


# ── Qdrant helpers ──────────────────────────────────────────────────


async def ensure_collection():
    """Create the Qdrant collection if it doesn't already exist.

    Configures 768-dimension cosine similarity vectors to match
    nomic-embed-text output. Called on app startup.

    Raises:
        httpx.HTTPStatusError: If Qdrant returns a non-2xx response on creation.
    """
    resp = await http.get(f"{QDRANT_URL}/collections/{COLLECTION}")
    if resp.status_code == 200:
        return
    resp = await http.put(
        f"{QDRANT_URL}/collections/{COLLECTION}",
        json={"vectors": {"size": VECTOR_DIM, "distance": "Cosine"}},
    )
    resp.raise_for_status()
    log.info("Created Qdrant collection '%s'", COLLECTION)
