# Review — #323 souls step 4b, side projects on the corkboard

**Verdict: request_changes** (branch `work/323-souls-step-4b-side-projects-on-the-c` @ 3755f0b).

Read: the full diff against origin/main (8 files), the parent spec §B and plan S0–S3, `Server.Generator.run/1`, `Server.Office.Writer.write/2`, `Server.Soul.voice/1`, `Server.ModelCli` (timeout), the four earlier kind-check migrations. CHECKS: `mise run check` green on 3755f0b; no `bench_contrast` row (the diff touches neither `profiles.ex` nor `soul.ex`, so none is owed).

What is right: S1/S2/S3 match the spec. The counter is the standing thread's rows (`side_state/2` counts in the query, not a cached field); `post_side_project/4` is `suggest/4`'s shape, stored delivered; `switchboard`/`needs` exclude the new kind everywhere `suggestion`/`margin` are excluded (I grepped: no fifth site). The Writer→Generator deviation is correct, not a deviation: the plan's parenthetical "counts against generator_daily_cap through Server.Generator" was false of `Writer.write/2`, which calls `ModelCli` directly; spec §B names `Server.Generator`. The migration is the margin migration's pattern, `down` deleting the rows first. The `@allowed` addition in `soul_callers_test.exs` is the right door: reading "The side project" shapes a note, never a work decision.

## Findings

**1. Spec §B says the note is "in voice"; the prompt carries no voice.** `side_note/4` hands the model `@side_voice` + the section + the counter + the previous note. `@side_voice` says "in their own voice" but gives the model nothing to go on, so it invents one. Banter does this with `Server.Soul.voice(b.name)` (corkboard.ex may now call it). Fix, one line in `side_note/4`:

```
-        section <> "\nThis is number #{n}; continue it, do not repeat. Previous: " <> last_side_note(ws, name)
+        section <>
+        "\nHOW #{name} TALKS: " <> (Server.Soul.voice(name) || "(nothing on file)") <>
+        "\nThis is number #{n}; continue it, do not repeat. Previous: " <> last_side_note(ws, name)
```
Test: give the fixture's `daneri.md` a `## Quirks\ncounts syllables\n` section and assert the captured prompt `=~ "counts syllables"`.

**2. `@side_every_s 60` is under the model timeout (120 s): a slow call double-posts and skews the counter.** The comment says "a slow model never fans out", but the poll only gates on `side_at`. Poll at t=0 starts `side_write`; the model takes 90 s; poll at t=60 starts another; both read `side_state` with yesterday's `last`, both compute the same `n`, both post → two "number 3" messages the same day, and `side_state` then counts 4. The banter writer avoids this because `@every_s 480 > 120`. Fix: `@side_every_s 480` (one seat per poll still gives every seat its daily note within hours), or hold an in-flight flag per workspace in state until the `{:pinned, …}` cast lands. The tests are unaffected either way (their first poll fires at `side_at: 0`).

**3. Docs out of sync in the same change.** `server/AGENTS.md` (the `Server.Soul` paragraph, "…by `Server.Office.Banter` on every line and by `Profiles.instantiate/2` at spawn, and by nothing else") must now name the corkboard's side projects (it already omits the diary; fix both while there). The test name in `soul_callers_test.exs` still reads "called only from banter, profiles and the diary" while its comment was updated.

## Not findings, noted
- `post_side_project/4` skips `Server.Recall.embed_on_write/1` that `suggest/4` runs. Chatter, not knowledge; `search_history` is FTS and finds it anyway. Fine as is.
- Operator gate: this change carries a **migration** (`20261026170000_message_side_project`, widens the message kind check). Said here so the gate sees it.
