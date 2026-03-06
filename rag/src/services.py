"""Business logic for the RAG service: embedding, metadata extraction, and Qdrant operations."""

import json
import logging
import os
from datetime import date

import httpx
from fastapi import Header, HTTPException

from . import chat
from . import embed as embed_mod

# ── Config ──────────────────────────────────────────────────────────

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://host.docker.internal:11434")
QDRANT_URL = os.environ.get("QDRANT_URL", "http://host.docker.internal:6333")
# Optional — when set, all Qdrant HTTP requests include the api-key header.
# Matches the service.api_key value configured in Qdrant's production.yaml.
QDRANT_API_KEY = os.environ.get("QDRANT_API_KEY", "")
EMBED_MODEL = embed_mod.EMBED_MODEL
CHAT_MODEL = chat.CHAT_MODEL
COLLECTION = os.environ.get("COLLECTION_NAME", "notes")
API_KEY = os.environ["RAG_API_KEY"]  # required — fail fast if missing
ALLOW_SEED = os.environ.get("ALLOW_SEED", "false").lower() == "true"
# Each embedding model outputs vectors of a specific dimension. This must
# match the model set in EMBED_MODEL. Common values:
#   nomic-embed-text=768, mxbai-embed-large=1024, all-minilm=384,
#   text-embedding-3-small=1536
VECTOR_DIM = int(os.environ.get("VECTOR_DIM", "768"))
SCORE_THRESHOLD = float(os.environ.get("SCORE_THRESHOLD", "0.3"))  # drop results below this cosine similarity
# Timeout for upstream HTTP calls (Ollama, Qdrant). First requests may be slow
# while Ollama loads a model into memory.
HTTP_TIMEOUT = float(os.environ.get("HTTP_TIMEOUT", "60"))

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("rag")

http = httpx.AsyncClient(timeout=HTTP_TIMEOUT)

# JSON schema passed to Ollama's `format` parameter to force structured metadata output.
METADATA_SCHEMA = {
    "type": "object",
    "properties": {
        "topic": {"type": "string"},
        "people": {"type": "array", "items": {"type": "string"}},
        "locations": {"type": "array", "items": {"type": "string"}},
        "dates_mentioned": {"type": "array", "items": {"type": "string"}}, # if no dates are mentioned, include the current date so you know when smth happened
        "mood": {"type": "string"},
        "tags": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["topic", "tags"],
}

QUERY_FILTER_SCHEMA = {
    "type": "object",
    "properties": {
        "topic": {"type": "string"},
        "people": {"type": "array", "items": {"type": "string"}},
        "locations": {"type": "array", "items": {"type": "string"}},
        "tags": {"type": "array", "items": {"type": "string"}},
        "time_sort": {
            "type": "string",
            "enum": ["newest_first", "oldest_first", "relevance"],
        },
    },
    "required": ["topic", "people", "locations", "tags", "time_sort"],
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


# ── Embedding helper ───────────────────────────────────────────────


async def embed(text: str, prefix: str = "search_document") -> list[float]:
    """Generate a vector embedding via the configured provider (Ollama or cloud).

    Dimension validation is intentionally omitted here — Qdrant enforces
    dimension constraints at insert time, and the startup check in
    ensure_collection() gives an actionable warning if VECTOR_DIM is wrong.

    Args:
        text: The text to embed.
        prefix: Task prefix for nomic-embed-text style models.

    Returns:
        A list of floats representing the embedding vector.
    """
    return await embed_mod.generate(http, text, prefix=prefix)


async def extract_metadata(text: str) -> dict:
    """Extract structured metadata from a note using the configured chat provider.

    Args:
        text: The note text to extract metadata from.

    Returns:
        A dict with keys: topic (str), people (list[str]), locations (list[str]),
        dates_mentioned (list[str]), mood (str | None), tags (list[str]).

    Raises:
        httpx.HTTPStatusError: If the chat provider returns a non-2xx response.
        json.JSONDecodeError: If the LLM output isn't valid JSON.
    """
    system = (
        f"Today's date is {date.today().isoformat()}. "
        "Extract metadata from this note. Return JSON with: "
        "topic (single lowercase category like 'travel', 'health', 'work', 'family', 'food', 'finance'), "
        "people (list of lowercase names or relationships like 'son', 'sarah'), "
        "locations (list of lowercase place names like 'toronto', 'miami'), "
        "dates_mentioned (list of ISO dates like '2026-02-10' — "
        "resolve relative references like 'yesterday', 'last week' to actual dates using today's date; "
        "if no date is mentioned at all, use today's date), "
        "mood (lowercase string or null), "
        "tags (list of short lowercase keyword strings). "
        "All string values must be lowercase. "
        "Only include fields where you find relevant information."
    )
    content = await chat.complete(http, system, text, schema=METADATA_SCHEMA)
    raw = json.loads(content)
    return normalize_metadata(raw)


def normalize_metadata(meta: dict) -> dict:
    """Lowercase all filterable string fields so Qdrant exact-match works
    regardless of LLM casing inconsistencies."""
    out = dict(meta)
    if "topic" in out and isinstance(out["topic"], str):
        out["topic"] = out["topic"].lower()
    for key in ("people", "locations", "tags"):
        if key in out and isinstance(out[key], list):
            out[key] = [v.lower() for v in out[key] if isinstance(v, str)]
    if "mood" in out and isinstance(out["mood"], str):
        out["mood"] = out["mood"].lower()
    return out


async def validate_ollama_model(model: str, label: str) -> bool:
    """Check if a model is available in Ollama. Logs actionable errors if not.

    Args:
        model: The model name to check (e.g., "nomic-embed-text").
        label: Human-readable label for log messages (e.g., "embedding").

    Returns:
        True if the model is available, False otherwise.
    """
    try:
        resp = await http.get(f"{OLLAMA_URL}/api/tags")
        if resp.status_code != 200:
            log.warning("Cannot reach Ollama at %s to verify %s model", OLLAMA_URL, label)
            return False
        models = [m["name"] for m in resp.json().get("models", [])]
        model_base = model.split(":")[0]
        found = any(model in m or model_base in m for m in models)
        if not found:
            log.error(
                "%s model '%s' is not available in Ollama. "
                "Pull it with: ollama pull %s\n"
                "  Available models: %s",
                label.capitalize(), model, model,
                ", ".join(models) if models else "(none)",
            )
        else:
            log.info("[ok] %s model '%s' available in Ollama", label, model)
        return found
    except Exception as e:
        log.warning("Cannot reach Ollama at %s: %s", OLLAMA_URL, e)
        return False


# ── Qdrant helpers ──────────────────────────────────────────────────


def qdrant_headers() -> dict[str, str]:
    """Return headers for Qdrant HTTP requests, including the API key if configured."""
    if QDRANT_API_KEY:
        return {"api-key": QDRANT_API_KEY}
    return {}


async def ensure_collection():
    """Create the Qdrant collection if it doesn't already exist.

    Configures cosine similarity vectors with dimension matching VECTOR_DIM.
    If the collection exists but has a different dimension, logs an error
    with remediation instructions.

    Raises:
        httpx.HTTPStatusError: If Qdrant returns a non-2xx response on creation.
    """
    resp = await http.get(
        f"{QDRANT_URL}/collections/{COLLECTION}", headers=qdrant_headers()
    )
    if resp.status_code == 200:
        existing_dim = (
            resp.json()
            .get("result", {})
            .get("config", {})
            .get("params", {})
            .get("vectors", {})
            .get("size")
        )
        if existing_dim and existing_dim != VECTOR_DIM:
            log.error(
                "VECTOR_DIM mismatch: collection '%s' has dimension %d but "
                "VECTOR_DIM is set to %d. Delete the collection and restart, "
                "or update VECTOR_DIM to match.\n"
                "  Delete: curl -X DELETE %s/collections/%s",
                COLLECTION, existing_dim, VECTOR_DIM, QDRANT_URL, COLLECTION,
            )
        return
    resp = await http.put(
        f"{QDRANT_URL}/collections/{COLLECTION}",
        json={"vectors": {"size": VECTOR_DIM, "distance": "Cosine"}},
        headers=qdrant_headers(),
    )
    resp.raise_for_status()
    log.info("Created Qdrant collection '%s' (dim=%d)", COLLECTION, VECTOR_DIM)


async def extract_query_filters(text: str) -> dict:
    """Extract structured filter hints from a search query using the configured chat provider.

    Identifies people, locations, and tags mentioned in the query so Qdrant
    payload filters can narrow results before vector ranking.  Also determines
    whether results should be sorted by time rather than pure relevance.

    Args:
        text: The natural-language search query.

    Returns:
        A dict with keys: people, locations, tags (all list[str]) and
        time_sort ("newest_first", "oldest_first", or "relevance").
    """
    system = (
        "Extract search filters from this query. Return JSON with: "
        "topic (single lowercase category like 'travel', 'health', 'work', 'family', 'food', 'finance' — empty string if unclear), "
        "people (list of person names or relationships like 'son', 'mom'), "
        "locations (list of place names), "
        "tags (list of short topic keywords that would help find relevant notes), "
        "time_sort ('newest_first' if the query asks about recent/last events, "
        "'oldest_first' if it asks about earliest/first events, "
        "'relevance' otherwise). "
        "Return empty lists if no specific filters are found. "
        "All string values must be lowercase."
    )
    content = await chat.complete(http, system, text, schema=QUERY_FILTER_SCHEMA)
    log.debug("Query filter raw response: %s", content[:500])
    return json.loads(content)


def build_qdrant_filter(filters: dict) -> dict | None:
    """Convert extracted query filters into a Qdrant filter clause.

    Builds ``should`` conditions (OR logic) so results matching *any*
    extracted entity are included.  Returns None when no meaningful
    filters were extracted, letting the query fall back to pure vector
    similarity.

    Args:
        filters: Output of :func:`extract_query_filters`.

    Returns:
        A Qdrant filter dict with a ``should`` clause, or None if no
        conditions were generated.
    """
    conditions = []
    topic = filters.get("topic", "")
    if topic:
        conditions.append({"key": "metadata.topic", "match": {"value": topic.lower()}})
    for person in filters.get("people", []):
        conditions.append({"key": "metadata.people", "match": {"value": person.lower()}})
    for location in filters.get("locations", []):
        conditions.append({"key": "metadata.locations", "match": {"value": location.lower()}})
    for tag in filters.get("tags", []):
        conditions.append({"key": "metadata.tags", "match": {"value": tag.lower()}})
    if not conditions:
        return None
    return {"should": conditions}
