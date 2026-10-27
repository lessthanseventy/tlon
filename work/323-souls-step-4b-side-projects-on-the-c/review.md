# Review — #323 souls step 4b, side projects on the corkboard (round 3)

**Verdict: request_changes** (branch `work/323-souls-step-4b-side-projects-on-the-c` @ b3bda66).

Read: my round-2 review.md, and the delta since it: `git diff b3bda66..work/323-… -- . ':!work/323-…'` is **empty**. HEAD is still b3bda66, my own round-2 verdict commit. The builder advanced build → verify (msg 14741: "Build artifact was committed … Nothing further owed") without a code change. CHECKS: `mise run check` green on this head again (same code); no `bench_contrast` row, none owed.

Re-verified on b3bda66, the witness statements:
- `grep -n "Soul.voice" server/lib/server/office/corkboard.ex` → nothing; line 299 reads only the section.
- `corkboard.ex:33` → `@side_every_s 60`.
- `server/AGENTS.md:152-153` → "by `Server.Office.Banter` on every line and by `Profiles.instantiate/2` at spawn, and by nothing else"; `soul_callers_test.exs:9` → "called only from banter, profiles and the diary".

## Findings (carried from rounds 1 and 2, all still open, all blocking)

**1. Spec §B: the note is "in voice"; the prompt carries no voice.** `@side_voice` says "in their own voice" with nothing to go on, so the model invents one. `Server.Soul.voice/1` exists and corkboard.ex is in `@allowed`. Fix, in `side_note/4`:

```
-        section <> "\nThis is number #{n}; continue it, do not repeat. Previous: " <> last_side_note(ws, name)
+        section <>
+        "\nHOW #{name} TALKS: " <> (Server.Soul.voice(name) || "(nothing on file)") <>
+        "\nThis is number #{n}; continue it, do not repeat. Previous: " <> last_side_note(ws, name)
```
Test: give the fixture's `daneri.md` a `## Quirks\ncounts syllables\n` section and assert the captured prompt `=~ "counts syllables"`.

**2. `@side_every_s 60` (corkboard.ex:33) is under the model timeout (`model_cli.ex`, 120 s): a slow successful call double-posts and skews the counter for good.** The hold engages only on failure; the poll gates only on `side_at`. Poll at t=0 starts a 90 s call; poll at t=60 starts another; both compute the same `n`, both post. Fix: `@side_every_s 480` (the banter writer's margin), or an in-flight flag per workspace in state, cleared by the `{:pinned, …}` cast. Existing tests are unaffected (`side_at: 0`).

**3. Docs out of sync in the same change.** `server/AGENTS.md:152-153` must name the corkboard's side projects (and the diary, already missing). `soul_callers_test.exs:9`'s test name must match its updated `@allowed`.

## Not findings, noted
- `post_side_project/4` skips `Server.Recall.embed_on_write/1`. Fine.
- Operator gate: this change carries a **migration** (`20261026170000_message_side_project`). Said again for the gate.
- Process: this is the second round lost to the findings not reaching the builder; the review.md is in the worktree, and the thread shows only follow-ups. I am posting the three findings on the thread directly this round, @emma.
