# Review — hall `W`: draft a hire's soul and pitch (#660) @ 0bec330

**Verdict: request_changes.** The code is correct and tested; what is wrong is the prose around it. Three comments and the moduledoc still describe a key `s` that the branch ships as `W`, and the new route is missing from the API's route list. Repo law says docs move in the same commit. Four lines; then approve.

## Verified

1. **`Soul.preview/2`** keeps `body/2`'s exact order (sample → model → template) and tags the source; `body/2` delegates to it, so `draft/2` and every hire write the same text as before. Nothing is written: `soul_test.exs` refutes `newhire.md` after a `:model` preview.
2. **`POST /api/workspaces/:id/hire/draft`** validates `name` through the same `name_ok/1` as `hire/2` (the 422 message is now one `@bad_name`). `archetype` is any string, but it only reaches the model prompt; `Persona.voice/2` falls through to a generic voice on an unknown archetype, no crash. 200 fallback, 200 model (stubbed CLI), 400, 404 and 422 all covered in `gateway_test.exs`; bench unchanged and no soul file after both drafts.
3. **Office:** `drawn` was already in `EDITABLE`, so `applyOverrides` lays the draft on and `pass` drops it unless locked — both covered by the two new `hall.test.ts` cases, including a `saveHall`/`loadHall` round trip. `hallDraw` drops the result if the candidate changed during the call. The render never calls the server (only the key does).
4. **Gate:** `mise run check` exit 0 on the branch (CHECKS 18:33, office 964 pass, server green). `bench_contrast` is unmeasurable (office/AGENTS.md is not loaded by the bench) — not a regression, no finding.
5. **Spec deviation, sanctioned:** the key is `W`, not `s`. `s` is `sort` in four scopes and `keys.test.ts` forbids two verbs on one key; the plan's task 3 said to pick a free letter in that case and say so. The builder said so (#21819, pr.md). The operator should know at the gate that the ticket's literal `s` is not what ships.

## Blocking

**B1. Comments name `s`; the key is `W`.** A reader of any of these goes looking for a key that doesn't exist.

```diff
--- a/office/kit/hall.ts
-/** `s`: the server's drawn soul and pitch, stored as the edits `e` would make, flagged drawn */
+/** `W`: the server's drawn soul and pitch, stored as the edits `e` would make, flagged drawn */
--- a/office/tui/data.ts
-/** `s` in the hall: a soul and pitch for a hire not yet made (nothing written server-side) */
+/** `W` in the hall: a soul and pitch for a hire not yet made (nothing written server-side) */
--- a/server/lib/server/mcp/operator_api.ex
-  # a soul and pitch for a hire not yet made: nothing written, nobody seated (the hall's `s`)
+  # a soul and pitch for a hire not yet made: nothing written, nobody seated (the hall's `W`)
```

**B2. The route is absent from the moduledoc's route list** (plan task 2 asked for it). After the `POST /api/workspaces/:id/coworkers` line:

```diff
+      POST   /api/workspaces/:id/hire/draft  {"name", "archetype", "grade"?, "specialty"?} → Soul.preview: {soul, pitch, source}; nothing written, nobody seated
```

## Non-blocking (follow_ups)

See the follow-ups posted after this verdict.
