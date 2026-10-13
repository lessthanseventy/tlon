# Review — souls step 2 (work/souls-step-2-first-drafts-from-their-bor @ 1e61ebd)

**Verdict: approve.**

## Round 4 — a re-run of the pipeline, no code change

This round exists because the merge queue lost the landing (untracked `server/tmp/` collided with the rebase); ireneo advanced build with pr.md already on the branch, the server's verify passed, and it came back to review.

- `git diff 1e61ebd..HEAD -- . ':!work/…'` is empty: not one line of code differs from what round 3 (lonnrot), tzinacan's round and treviranus's QA (9909127) approved.
- The server's verify on this branch: `mise run check` exit 0 (16:06 UTC, recorded against this workline's verify).
- `git ls-files server/tmp` → 0; working tree clean.
- origin/main has moved 26 commits past the branch base (8a6a168 → 883e290), including its own `server/tmp/` gitignore (aed53c8). `git merge-tree --write-tree origin/main HEAD` merges clean: the branch's `.gitignore` hunk is byte-identical to main's, so the landing rebase should not conflict this time.

Round 3's reading of soul.ex stands (exclusive create, `:eexist` → `{:ok, :exists}`, name guard before `Path.join`, Diary stripped from model output, fallback on a missing heading).

## Non-blocking (follow-ups, held until merge)

1. `hire` raises after seating on a name the soul guard refuses (#275).
2. `hire` blocks on a model call, and a soul-dir failure crashes it (#276).
3. No gate catches tracked junk under ignored paths (#277).

QA's own follow-ups stand as filed: hall hire writes no soul (#301); tlon-cli.sh can't reach a scratch node (#302).