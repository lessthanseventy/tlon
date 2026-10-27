# Review — #323 souls step 4b, side projects on the corkboard (round 2)

**Verdict: request_changes** (branch `work/323-souls-step-4b-side-projects-on-the-c` @ ef93578).

Read: my round-1 review.md (9f59048), the delta since it (`git diff 9f59048..ef93578 -- . ':!work/323-…'`: corkboard.ex +9/−2, corkboard_test.exs +21), and the full corkboard diff against origin/main again. CHECKS: `mise run check` green on ef93578 (2220 server tests, 0 failed); no `bench_contrast` row, none owed (neither `profiles.ex` nor `soul.ex` changed).

**What round 2 did:** the follow-up only. `side_hold` (one hour after a `:failed` cast) is correct: `side_note(...) || :failed` makes `find_value` stop at the first due seat either way, so one call per poll holds; the `:failed` clause sits before the generic `{:pinned, ws, note}` clause; the test goes red without the hold (second poll after `rewind` would make a second call). A cap-hit or banter-off also returns nil → an hour's hold, which is fine for a daily cap. No new findings in the delta.

**What round 2 did not do:** the three blocking findings in review.md. The builder's note (msg 14695) says "the review's one follow-up is fixed"; the follow-up was the non-blocking item. The blocking ones were in the committed review.md, and each is still exactly as written. I checked each against ef93578:

## Findings (carried from round 1, all still open)

**1. Spec §B: the note is "in voice"; the prompt carries no voice.** `grep Soul.voice server/lib/server/office/corkboard.ex` → nothing; line 299 reads only the section. `@side_voice` says "in their own voice" with nothing to go on, so the model invents one. `Server.Soul.voice/1` exists (`soul.ex:196`, returns `String.t() | nil`) and corkboard.ex is now in `@allowed`, so it may call it. Fix, in `side_note/4`:

```
-        section <> "\nThis is number #{n}; continue it, do not repeat. Previous: " <> last_side_note(ws, name)
+        section <>
+        "\nHOW #{name} TALKS: " <> (Server.Soul.voice(name) || "(nothing on file)") <>
+        "\nThis is number #{n}; continue it, do not repeat. Previous: " <> last_side_note(ws, name)
```
Test: give the fixture's `daneri.md` a `## Quirks\ncounts syllables\n` section and assert the captured prompt `=~ "counts syllables"`.

**2. `@side_every_s 60` (corkboard.ex:33) is under the model timeout (`model_cli.ex:59`, 120 s): a slow *successful* call double-posts and skews the counter.** The hold only engages on failure; the poll still gates only on `side_at`. Poll at t=0 starts `side_write`; the model takes 90 s; poll at t=60 starts another; both read `side_state` with yesterday's `last`, both compute the same `n`, both post → two "number 3" messages the same day, and `side_state` then counts 4 for good. The banter writer avoids this because `@every_s 480 > 120`. Fix: `@side_every_s 480` (one seat per poll still gives every seat its daily note within hours), or an in-flight flag per workspace in state cleared by the `{:pinned, …}` cast. The tests are unaffected either way (their first poll fires at `side_at: 0`).

**3. Docs out of sync in the same change.** `server/AGENTS.md:151-152` still reads: read "by `Server.Office.Banter` on every line and by `Profiles.instantiate/2` at spawn, and by nothing else" — now false twice over (corkboard side projects; it already omitted the diary). The test name at `soul_callers_test.exs:9` still says "called only from banter, profiles and the diary" while the comment above it and `@allowed` were updated. Fix both lines.

## Not findings, noted
- `post_side_project/4` skips `Server.Recall.embed_on_write/1`. Chatter, not knowledge; fine.
- Operator gate: this change carries a **migration** (`20261026170000_message_side_project`, widens the message kind check). Said again so the gate sees it.
- Process: the thread showed only the follow-ups post (msg 14688), not the findings, and the builder fixed what the thread showed. Filed as a ticket so the next request_changes doesn't lose a round the same way.
