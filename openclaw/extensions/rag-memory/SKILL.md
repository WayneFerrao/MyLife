---
name: memory
description: Store and retrieve personal notes, journal entries, and life events using vector memory
---

# Memory — Personal Knowledge Store

You have three memory tools backed by a vector search service. Use them to save and recall information across conversations.

## When to SAVE (`save_note`)

- User shares personal information, events, experiences, or decisions
- User says "remember this", "save this", or tells you about something worth recalling
- Trips, health events, milestones, work updates, purchases, appointments

Write rich, descriptive notes. Include dates, people, and locations naturally for better retrieval later.

## When to SEARCH (`search_notes`)

- User asks "when was the last time...", "what did I say about...", "do you remember..."
- Any question that needs personal historical context
- Phrase search queries as natural questions for best results

Use the results as context to give a natural answer. Don't dump raw results.

## When to DELETE (`delete_note`)

- User says "delete that note about...", "remove the one about...", "forget that..."
- For corrections: search for the old note, delete it, then save the corrected version
- Always search first to find the note ID before deleting

## When to SKIP

- Casual chat, greetings, general knowledge questions
- Ephemeral info not worth storing
- When in doubt, don't store

## Tips

- Never store passwords, API keys, financial account numbers, or other secrets
- If the service is unavailable, tell the user and suggest trying again shortly
