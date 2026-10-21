## Verdict: APPROVE

#489 — `Smoke.start` refuses an empty `work/` ref. Reviewed the diff on `work/smoke-start-refuses-an-empty-work-ref-ni @ 9d16698` against the goal (nil slug + no ref refused; `@ref` rejects a trailing `/`).

### What I verified

**The nil-slug refusal.** `ref = ref || (thread.slug && "work/#{thread.slug}")` now yields `nil` when both are absent, and the new `is_nil(ref)` arm returns `{:error, "no ref: ..."}` before the regex ever sees `nil` (which would crash `Regex.match?/2`). Ordering is load-bearing and correct — nil is guarded first.

**The regex.** `@ref` went from `\A[A-Za-z0-9][A-Za-z0-9._/-]*\z` to `\A[A-Za-z0-9](?:[A-Za-z0-9._/-]*[A-Za-z0-9._-])?\z`. The trailing char class drops `/`, so the last character must be alnum, `.`, `_` or `-`. Checked every edge case in `elixir -e`:
- matches: `work/a-thing`, `w`, `x`, `a/b`, `a.`, `a.b.c`, `main`, `refs/heads/main`
- rejects: `work/`, `a./`, `work/a-thing/`, `--upload-pack=x`

Single-char refs still match (the optional group is `?`), so `ref: "x"` and the existing `--upload-pack=x` injection test are unaffected. `/` is still legal mid-ref.

**The empty-string slug corner.** If `thread.slug` were `""` (truthy in Elixir), `&& "work/#{slug}"` would yield `"work/"`, caught by the regex arm as "not a ref" rather than the nil arm. Still refused — just via the other branch. No thread is born with an empty-string slug in practice, and the test uses `nil`, so this is fine.

**Callers.** The only non-test caller is `Server.MCP.Tool.StartSmoke` (`server/lib/server/mcp/tools/smoke.ex:26`), which passes `params[:ref]` (nil when absent) and surfaces `{:error, why}` as `fail(frame, why)`. A nil-slug thread now reaches the QA seat as a clean "no ref: …" instead of a queued `work/`. No other call sites.

**Tests.** Both new tests are the right shape and go red before / green after (per pr.md's RED/GREEN record): nil slug + no ref → "no ref" and nothing enqueued; explicit `work/` → "not a ref" and nothing enqueued. `refute_enqueued` holds because both errors return before `Oban.insert`.

**Verify.** Green at 9d16698 (`mise run check` exit 0, 00:53). The earlier red was the two unrelated 60s timeouts (ProfilesTest :34, Bench.RolesTest :28) scharlach traced to box load — filed as #517, not this branch.

### Findings

None blocking. The change is minimal (5 lines of logic, 10 of test), surgical, and the regex is provably correct. No follow-ups.