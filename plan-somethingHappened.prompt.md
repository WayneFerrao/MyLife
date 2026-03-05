# Plan: Reconfigure OpenClaw as "Something Happened" Memory System

Strip OpenClaw's generic personal assistant workspace files down to a single-purpose moment-capture system. Agent is named Bonsai (🪴), kind but terse. Phase 1 rewrites the workspace markdown to classify messages as StoreMoment or RecallDetails (acknowledge-only). Phase 2 wires those intents to the existing RAG service via an OpenClaw skill.

---

### Phase 1 — Intent Classification via System Prompts

All steps are independent (parallel-safe) except the restart at the end.

0. **Backup current workspace** — copy all markdown files in `openclaw/workspace` to a safe location: `C:\src\MyLife\.bak.workspace`

1. **Rewrite SOUL.md** — Replace entirely with Bonsai persona: name is Bonsai, starts every message with 🪴, kind but terse, objective-focused, not conversational.

2. **Update IDENTITY.md** — Name: Bonsai, Emoji: 🪴, Creature: "Meticulous Librarian", Vibe: "kind, terse, focused"

3. **Rewrite AGENTS.md** — Replace entirely. Define two intents:
   - **StoreMoment** — User describes something that happened. Triggers: natural language event description, or explicit `/m` prefix. Response: `"🪴 Moment noted: [brief summary]"`
   - **RecallDetails** — User asks about past moments. Triggers: "when did", "what happened", "do you remember", or `/r` prefix. Response: `"🪴 Searching moments for: [rephrased query]"`
   - Anything else: gentle redirect to the system's purpose
   - Remove all heartbeat, group chat, memory file, reaction, and safety boilerplate

4. **Clear USER.md** — Minimal stub

5. **Clear MEMORY.md** — Fresh start (old personal assistant memories about Mark/Brittany are irrelevant)

6. **Clear TOOLS.md** — Stub pointing to skills/

7. **Clear HEARTBEAT.md** — Empty, agent is reactive only

8. **Delete contents of BOOTSTRAP.md** — Agent already bootstrapped; no onboarding flow

9. **Restart OpenClaw** — `docker compose restart` in `openclaw/`

**Verification (Phase 1):**

- Send `"I had sushi with Kyle yesterday"` → StoreMoment acknowledgment
- Send `"/m went for a run"` → StoreMoment acknowledgment
- Send `"When did I last eat sushi?"` → RecallDetails acknowledgment
- Send `"/r running"` → RecallDetails acknowledgment
- Send `"What's the weather?"` → gentle redirect
- All responses start with 🪴

---

### Phase 2 — Wire Intents to RAG Service

_Depends on Phase 1 + RAG service running._

1. **Install the RAG skill** — Run `bash rag/setup.sh` (generates API key, creates `openclaw/workspace/skills/memory/SKILL.md` from `rag/SKILL.md.template`). On Windows, manually create the skill file and substitute the `RAG_API_KEY`.

2. **Adapt the skill for "Something Happened"** — Adjust the "When to Use" section of the installed SKILL.md to match StoreMoment/RecallDetails language. Keep API call instructions intact (`web_fetch` to `http://host.docker.internal:18790`):
   - StoreMoment → `POST /ingest` — existing endpoint, no code changes
   - RecallDetails → `POST /query` — existing endpoint, no code changes

3. **Update AGENTS.md** — Change Phase 1 "acknowledge-only" to "use the memory skill." StoreMoment confirms stored metadata; RecallDetails synthesizes query results into a natural answer.

4. **Restart OpenClaw** — pick up new skill

**Verification (Phase 2):**

- `curl http://localhost:18790/health` → `{"status":"ok"}`
- Send `"Had coffee with Sarah at the park"` → moment stored, agent confirms topic/tags
- Send `"When did I last see Sarah?"` → agent queries RAG, returns result with date/context

---

### Decisions

- **Intent detection: hybrid.** Natural language inference (reliable with only 2 intents) + optional `/m` and `/r` explicit triggers. Both produce the same result.
- **No RAG code changes.** `/ingest` = StoreMoment, `/query` = RecallDetails — fits perfectly.
- **No `openclaw.json` changes.** Model config, plugins, channels all stay as-is. Only workspace content changes.
- **MEMORY.md cleared.** Old personal assistant context is irrelevant to the new system.
- **Heartbeats stay configured but idle.** Empty HEARTBEAT.md means polls return HEARTBEAT_OK with no work.

### Future Features (out of scope)

1. **Delete/correct moments** — find via `/r`, then "delete that" or correct → delete + re-ingest
2. **Date-range browsing** — "What happened this week?" (needs Qdrant payload filtering)
3. **Rich moments** — photos, voice notes, location pins (extends `IngestRequest`)
