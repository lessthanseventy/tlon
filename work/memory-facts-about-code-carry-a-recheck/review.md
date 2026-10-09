# Review — facts about code carry a recheck (#88)

**Verdict: request_changes.** One real bug (batch starvation); two smaller probe-precision items. I read the diff only; I did not run the suite.

## 1. Sweep batch starves (must fix) — `maintain/sweep.ex` `sweep_fact_rechecks`
Ordering is "least recently checked first, never-checked first". But `Recheck.run` records **nothing** for prose, ref-less facts, facts with no project repo, or facts inside the 24h window. Those facts keep `c.at == nil`, so they sort first on every sweep, forever. Once ≥25 live thread-bound facts are prose (the common case), the same 25 lowest-id prose facts fill the batch each run, and no code-naming fact beyond them is ever rechecked.

Failure scenario: 30 prose facts with lower ids, then a fact `Server.Gone ...`. Every `Sweep.run/1` takes the 25 prose ones, skips them, and the gone-symbol fact is never checked.

Fix options (pick the simplest):
- Filter in SQL to facts that can produce a verdict: pre-select by the same patterns (`f.text ~ 'Server\.|server/|mise run'` etc.) — duplicates `CodeRefs` rules, so drift risk; or
- Have `Recheck.run` record a `skipped`-style touch the sweep orders on (new event kind, so the batch rotates); or
- Fetch candidates in a stream and stop once 25 *non-skipped* results have been produced (keeps `CodeRefs` the single source of rules). Probably least code.

Add a test: 26+ prose facts plus one code fact; assert the code fact gets checked.

## 2. Probe prefix false-passes (should fix) — `recall/probe.ex`
`grep -F "defmodule Server.A"` matches `defmodule Server.AB`; `"def go"` matches `def gone`/`defp`-less names like `def good`. A renamed symbol whose old name is a prefix of a surviving one records `check_passed`, boosting a stale fact. Anchor: module `"defmodule " <> name <> " do"`, function `"def " <> name <> "("` plus the zero-arity `"def " <> name <> ","`/` do`/newline cases — or use `-E` with `\b`. Add misses-test for prefix cases.

## 3. Minor
- `:function` ref drops the module (`Server.Foo.run/1` → `"run"`), so it passes if *any* `def run` exists on main. Weak signal; either probe the module too or say so in the CodeRefs moduledoc.
- `sweep_fact_rechecks` `rescue _ -> :ok` hides probe/DB errors silently; at least `Logger.warning` with the fact id.

Tests otherwise cover the stated behaviours (pass/fail/strength, 24h skip, batch cap, forgotten). Docs updated in the moduledoc.
