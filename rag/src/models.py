"""Pydantic request/response models for the RAG service API."""

from pydantic import BaseModel, Field


class IngestRequest(BaseModel):
    """Request body for storing a new note.

    Attributes:
        text: The note text to store. Must be between 1 and 10,000 characters.
    """

    text: str = Field(..., min_length=1, max_length=10000, description="The note text to store")


class IngestResponse(BaseModel):
    """Response after successfully ingesting a note.

    Attributes:
        id: UUID of the stored Qdrant point. Use this for deletion.
        metadata: Extracted metadata dict with keys: topic, people, locations,
            dates_mentioned, mood, tags.
    """

    id: str
    metadata: dict


class QueryRequest(BaseModel):
    """Request body for searching stored notes.

    Attributes:
        text: Natural language search query. Must be between 1 and 2,000 characters.
        limit: Maximum number of results to return. Defaults to 5, range 1-20.
    """

    text: str = Field(..., min_length=1, max_length=2000, description="Natural language search query")
    limit: int = Field(default=5, ge=1, le=20, description="Max number of results to return")


class QueryResult(BaseModel):
    """A single matching note from a search.

    Attributes:
        id: UUID of the Qdrant point.
        text: The original note text.
        metadata: Extracted metadata dict (topic, people, locations, etc.).
        score: Cosine similarity score between 0 and 1. Higher is more relevant.
    """

    id: str
    text: str
    metadata: dict
    score: float


class QueryResponse(BaseModel):
    """Response containing matching notes from a search.

    Attributes:
        results: List of QueryResult objects ordered by relevance (highest score first).
    """

    results: list[QueryResult]


class HealthResponse(BaseModel):
    """Health check response showing dependency status.

    Attributes:
        status: "ok" if all dependencies are reachable, "degraded" otherwise.
        llm: True if the LLM provider (Ollama or cloud) is reachable.
        qdrant: True if Qdrant API is responding.
        embed_model_available: True if the configured embedding model is available.
            None if the provider is unreachable.
    """

    status: str
    llm: bool
    qdrant: bool
    embed_model_available: bool | None = None
