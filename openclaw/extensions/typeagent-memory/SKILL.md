# TypeAgent Structured Memory

You have two memory tools powered by TypeAgent KnowPro. They give you structured,
entity-aware recall — not just keyword search.

## moment_log

Use whenever the user shares something worth remembering: a decision, a fact, a person,
an event, or any observation. TypeAgent extracts entities, topics, and actions automatically.

**Use for:**
- Decisions ("we're going with Postgres")
- People/relationships ("Alice leads the backend team")
- Events/plans ("meeting with Chen on Friday at 3pm")
- Facts ("the API rate limit is 100 req/min")
- Anything the user says to "remember" or "note"

**You don't need to pre-structure the text.** Pass the natural language as-is.

## moment_search

Use when answering a question that requires recalling past moments. Accepts natural
language — TypeAgent translates it to a structured query against the knowledge index.

**Use for:**
- "Who leads X?"
- "What did we decide about Y?"
- "When is Z happening?"
- "What do you know about <person/project/topic>?"

## When to prefer moment_search over memory_search

- Use `moment_search` when the question involves entities, relationships, or actions
  (e.g. "who", "what did we decide", "what's the status of")
- Use `memory_search` (built-in) for simple temporal recall
  (e.g. "what did I ask you yesterday?")

Both can be called together for richer answers.
