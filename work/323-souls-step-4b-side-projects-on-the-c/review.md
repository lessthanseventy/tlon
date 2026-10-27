# Review — #323 souls step 4b, side projects on the corkboard (round 4)

**Verdict: approve** (branch `work/323-souls-step-4b-side-projects-on-the-c` @ c8c80a2).

Read: my round-3 review.md, then the delta `git diff cbc7ba8..c8c80a2 -- . ':!work/323-…'` (4 files: `server/AGENTS.md`, `corkboard.ex`, `corkboard_test.exs`, `soul_callers_test.exs`). CHECKS: `mise run check` exit 0 on this head (server, adapters, office all green); `bench_contrast` unmeasurable (`server/AGENTS.md` is read by a seat, never loaded by the bench) — not a regression, not a finding.

## The three findings, each verified fixed

**1. Voice in the prompt.** `corkboard.ex:311-313` now reads
```
"\nHOW #{name} TALKS: " <> (Server.Soul.voice(name) || "(nothing on file)") <>
```
`Server.Soul.voice/1` is `String.t() | nil` (soul.ex:195), so the `||` is the right guard. New test `the prompt carries the seat's voice` writes a `## Quirks\ncounts syllables` section and asserts the captured prompt `=~ ~r/counts syllables.{0,300}This is number 1/s`; builder says it went red first.

**2. Poll spacing.** `corkboard.ex:33` → `@side_every_s 480`, past the 120 s model timeout; the comment at :171 now states the constraint, not the history. Hold path unchanged (`side_hold` set on `:failed`, 3600 s).

**3. Docs.** `server/AGENTS.md:152-153` names banter, profiles, the diary and the corkboard's side projects; `soul_callers_test.exs:9` name matches its `@allowed`.

## For the operator gate
This change carries a **migration** (`20261026170000_message_side_project`, widens the `messages.kind` check to admit "side project"). A limit on the risk grade; the gate is the operator's, not mine.

## Not findings, noted
- `post_side_project/4` skips `Server.Recall.embed_on_write/1`. Fine for a sticky note.
- No follow-ups left open.
