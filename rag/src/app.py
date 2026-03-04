"""RAG Service — Personal memory API for OpenClaw.

Provides endpoints to store, search, and delete personal notes backed by
Qdrant vector search and Ollama embeddings.
"""

import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone

import httpx
from fastapi import Depends, FastAPI, HTTPException

from .models import (
    HealthResponse,
    IngestRequest,
    IngestResponse,
    QueryRequest,
    QueryResponse,
    QueryResult,
)
from .services import (
    ALLOW_SEED,
    COLLECTION,
    OLLAMA_URL,
    QDRANT_URL,
    SEED_NOTES,
    build_qdrant_filter,
    embed,
    ensure_collection,
    extract_metadata,
    extract_query_filters,
    http,
    log,
    verify_api_key,
)


# ── App lifecycle ───────────────────────────────────────────────────


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage app startup and shutdown.

    Startup: creates the Qdrant collection if it doesn't exist.
    Shutdown: closes the shared httpx async client.

    Args:
        app: The FastAPI application instance.
    """
    try:
        await ensure_collection()
    except Exception as e:
        log.warning("Could not create collection on startup: %s", e)
    yield
    await http.aclose()


app = FastAPI(title="RAG Service", lifespan=lifespan)


@app.exception_handler(httpx.ConnectError)
async def handle_connect_error(request, exc):
    """Handle connection failures to upstream services.

    Args:
        request: The incoming HTTP request.
        exc: The httpx.ConnectError that was raised.

    Raises:
        HTTPException: 503 with a message identifying which service is down.
    """
    target = "Ollama" if "11434" in str(exc) else "Qdrant" if "6333" in str(exc) else "dependency"
    raise HTTPException(status_code=503, detail=f"{target} is unavailable")

@app.exception_handler(httpx.TimeoutException)
async def handle_timeout(request, exc):
    """Handle upstream request timeouts.

    Args:
        request: The incoming HTTP request.
        exc: The httpx.TimeoutException that was raised.

    Raises:
        HTTPException: 504 Gateway Timeout.
    """
    raise HTTPException(status_code=504, detail="Upstream request timed out")

# ── Endpoints ───────────────────────────────────────────────────────

@app.get("/health", response_model=HealthResponse)
async def health():
    """Check connectivity to Ollama and Qdrant. No auth required.

    Returns:
        HealthResponse: status ("ok" or "degraded"), ollama (bool), qdrant (bool).
    """
    ollama_ok = qdrant_ok = False
    try:
        r = await http.get(f"{OLLAMA_URL}/api/tags")
        ollama_ok = r.status_code == 200
    except Exception:
        pass
    try:
        r = await http.get(f"{QDRANT_URL}/collections")
        qdrant_ok = r.status_code == 200
    except Exception:
        pass
    status = "ok" if (ollama_ok and qdrant_ok) else "degraded"
    return HealthResponse(status=status, ollama=ollama_ok, qdrant=qdrant_ok)


@app.post("/ingest", response_model=IngestResponse, dependencies=[Depends(verify_api_key)])
async def ingest(req: IngestRequest):
    """Store a note: extract metadata via LLM, embed, and save to Qdrant.

    If metadata extraction fails (e.g., Ollama timeout), the note is still
    stored with fallback metadata {"topic": "unknown", "tags": []}.

    Args:
        req: IngestRequest with the note text.

    Returns:
        IngestResponse: the UUID of the stored point and its extracted metadata.

    Raises:
        httpx.HTTPStatusError: If Qdrant upsert fails.
    """
    try:
        metadata = await extract_metadata(req.text)
    except Exception:
        log.warning("Metadata extraction failed, using fallback")
        metadata = {"topic": "unknown", "tags": []}

    vector = await embed(req.text, prefix="search_document")
    point_id = str(uuid.uuid4())
    payload = {
        "text": req.text,
        "metadata": metadata,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    resp = await http.put(
        f"{QDRANT_URL}/collections/{COLLECTION}/points?wait=true",
        json={"points": [{"id": point_id, "vector": vector, "payload": payload}]},
    )
    resp.raise_for_status()
    return IngestResponse(id=point_id, metadata=metadata)


@app.post("/query", response_model=QueryResponse, dependencies=[Depends(verify_api_key)])
async def query(req: QueryRequest):
    """Search stored notes using semantic similarity plus structured filters.

    1. Extracts filter hints (people, locations, tags, time preference)
       from the query via the chat model.
    2. Embeds the query with the "search_query" prefix.
    3. Searches Qdrant with the vector *and* any payload filters (OR logic),
       so results matching mentioned entities are prioritised.
    4. Re-sorts by created_at when the query implies a time preference
       (e.g. "last", "most recent", "first").

    Falls back to pure vector similarity if filter extraction fails.

    Args:
        req: QueryRequest with the search text and optional limit.

    Returns:
        QueryResponse: list of QueryResult objects ordered by relevance.

    Raises:
        httpx.HTTPStatusError: If Qdrant query fails.
    """
    # Extract structured filters from the query (best-effort).
    try:
        filters = await extract_query_filters(req.text)
        log.info("Query filters: %s", filters)
    except Exception:
        log.warning("Query filter extraction failed, using pure vector search")
        filters = {}

    vector = await embed(req.text, prefix="search_query")

    qdrant_body: dict = {"query": vector, "with_payload": True, "limit": req.limit}
    qdrant_filter = build_qdrant_filter(filters)
    if qdrant_filter:
        qdrant_body["filter"] = qdrant_filter

    resp = await http.post(
        f"{QDRANT_URL}/collections/{COLLECTION}/points/query",
        json=qdrant_body,
    )
    resp.raise_for_status()
    points = resp.json().get("points", [])

    results = [
        QueryResult(
            id=p["id"],
            text=p["payload"]["text"],
            metadata=p["payload"].get("metadata", {}),
            score=p["score"],
        )
        for p in points
    ]

    # Re-sort by time when the query implies recency/chronology.
    time_sort = filters.get("time_sort", "relevance")
    if time_sort != "relevance" and results:
        results.sort(
            key=lambda r: r.metadata.get("dates_mentioned", [""])[0] if r.metadata.get("dates_mentioned") else "",
            reverse=(time_sort == "newest_first"),
        )

    return QueryResponse(results=results)


@app.delete("/notes/{point_id}", dependencies=[Depends(verify_api_key)])
async def delete_note(point_id: str):
    """Delete a specific note from Qdrant by its point ID.

    Args:
        point_id: The UUID of the Qdrant point to delete.

    Returns:
        dict: {"deleted": point_id} on success.

    Raises:
        httpx.HTTPStatusError: If Qdrant delete fails.
    """
    resp = await http.post(
        f"{QDRANT_URL}/collections/{COLLECTION}/points/delete?wait=true",
        json={"points": [point_id]},
    )
    resp.raise_for_status()
    return {"deleted": point_id}


@app.post("/seed", dependencies=[Depends(verify_api_key)])
async def seed():
    """Load test data into Qdrant for verifying retrieval quality.

    Ingests ~10 diverse notes covering health, travel, family, work,
    hobbies, and finance. Each note goes through the full ingest pipeline
    (metadata extraction + embedding).

    Gated behind ALLOW_SEED=true env var to prevent accidental use.

    Returns:
        dict: {"seeded": count, "notes": [{"id": str, "topic": str}, ...]}.

    Raises:
        HTTPException: 403 if ALLOW_SEED is not true.
    """
    if not ALLOW_SEED:
        raise HTTPException(status_code=403, detail="Seeding is disabled. Set ALLOW_SEED=true in .env")

    results = []
    for note in SEED_NOTES:
        try:
            metadata = await extract_metadata(note)
        except Exception:
            metadata = {"topic": "unknown", "tags": []}
        vector = await embed(note, prefix="search_document")
        point_id = str(uuid.uuid4())
        payload = {
            "text": note,
            "metadata": metadata,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
        await http.put(
            f"{QDRANT_URL}/collections/{COLLECTION}/points?wait=true",
            json={"points": [{"id": point_id, "vector": vector, "payload": payload}]},
        )
        results.append({"id": point_id, "topic": metadata.get("topic", "unknown")})
        log.info("Seeded: %s", metadata.get("topic", "unknown"))

    return {"seeded": len(results), "notes": results}
