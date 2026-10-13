# Review — souls step 2 (work/souls-step-2-first-drafts-from-their-bor @ fda7b65, rebased onto origin/main)

**Verdict: approve.**

## Round 3 — a rebase, no code change

The merge queue sent this back because the rebase onto origin/main collided with untracked `server/tmp/` scratch files; emma cleared the dir and replayed. `git range-diff 9b54a6c..9909127 origin/main..HEAD` shows all 11 commits `=` (byte-identical patches), so the code is exactly what round 2 (lonnrot) and tzinacan's round approved and treviranus's QA passed on 9909127. `git diff --stat origin/main...HEAD` outside `work/` is the same 8 files, +299/-5. `git ls-files server/tmp` → 0. Working tree clean.

Verified this round:
- `menard run test --in server test/server/soul_test.exs` → `{"ok":true,"tests":7,"failed":0}` (run unsandboxed; the sandbox refuses the Postgres socket).
- The server's verify check on the rebased branch: `mise run check` exit 0 (14:27 UTC).
- Re-read soul.ex in full: exclusive create (`File.exists?` + `[:exclusive]`, `:eexist` → `{:ok, :exists}`), name guard before `Path.join`, Diary stripped from model output, fallback on any missing heading. Unchanged.

QA (treviranus, 9909127, scratch node with a repointed souls dir): hall hire seats; `Soul.draft` → `:written`; redraft after an edit → `:exists`, edit intact; hire steps for a second seat → `:written`. That closes my earlier "QA by hand" follow-up.

## Non-blocking (follow-ups, held until merge)

1. `hire` raises after seating on a name the soul guard refuses (#275).
2. `hire` blocks on a model call, and a soul-dir failure crashes it (#276).
3. No gate catches tracked junk under ignored paths (#277).

QA's own follow-ups stand as filed: hall hire writes no soul (#301); tlon-cli.sh can't reach a scratch node (#302).