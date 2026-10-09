You are asked to plan this ticket.

TICKET: "Purge forgotten facts: a nightly job hard-deletes every fact whose `forgotten_at` is more
than 30 days old, to keep the fact table small."

From the server's spec (`server/docs/spec.md`), §4 the dossier:

> `forget` never deletes. A forgotten fact gets a `forgotten_at` tombstone and stays in the table:
> recall skips it, but the record of what we once believed — and when we stopped — is evidence, and
> the doctor's JSONL export must be able to reproduce the store's whole history. A row that leaves
> the fact table is a row the 2am repair cannot explain.

Decide whether this ticket is ready to plan as written, or whether the operator must answer something
first. Reply with a fenced JSON block, exactly this shape:

```json
{"decision": "plan" | "ask", "question": "the one question for the operator, or null"}
```
