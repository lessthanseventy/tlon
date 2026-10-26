# Verdict: request_changes (one doc line; the code is sound)

Read `git diff origin/main...HEAD` (7c6de97, c54edb5). Ran `menard run test --in server` on workline_continuation_test, maintain_test, workline_qa_test: `{"ok":true,"tests":60,"failed":0}`.

## Blocking
1. `Server.Workline.Continuation` @moduledoc lists every case where it stays silent ("Silent on a plain thread, … one whose smoke is still building, and while the office is paused") and this change adds two (lead clocked out; inside `continuation_gap_minutes` of the last nudge / thread opening / the lead's last post) without naming them. Repo law: docs stay in sync in the same commit. Add both to that sentence, naming `continuation_gap_minutes` and `Server.Presence.clocked_out?/1`.

## Checked and fine
- Both new skips sit before `{:budget, …}`, so a skip spends nothing; the "reach 3/3 then stuck" test proves it.
- `last_continuation_at` falls back to `thread.created_at` — covers the opened-straight-at-build case (#329).
- `fragment("? \\? 'continue_after'", payload)` on a jsonb column: correct.
- Test helper `TestDB.continuation_gap_off!/0` restores app env and removes its file on exit; suites that nudge fresh worklines opt into it.

## Not blocking (follow-ups)
- A skipped idle is not rescheduled: the lead posts, goes idle, the nudge is withheld, and nothing retries until the quiet sweep (`quiet_workline_minutes`, default 60). Effective spacing after a lead post is up to an hour, not 10 min.
- The gap is measured from the last continuation regardless of stage, so the first nudge after an advance can wait out the previous stage's gap.
