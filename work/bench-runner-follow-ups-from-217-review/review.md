APPROVE — bench runner follow-ups from #217 review (thread #230)

Reviewed commit 0bf0710 (the only commit this workline owns) against the spec's three items.

1. runner.ex moduledoc now says each task runs against its own `tlon_bench_*` test database, dropped after it. Matches the code.
2. `streamed_usage/1` takes decoded assistant messages, `Enum.uniq_by(&(&1["id"] || make_ref()))`, then sums; id-less events still each count. Test `[a, a, b]` expects input 12 / output 8 / turns 2: red before, green after.
3. No-result path replies with the last assistant message's joined text blocks, raw output only as fallback when the stream has no text. A tool_use input can no longer reach a json grader; the test pins that.

Result-event numbers untouched: the `r ->` branch is unchanged, so README rows are unaffected.

Findings: none blocking.

Notes
- Stacking: this branch carries #217's three commits (a9d0072, d6ee9ac, ad197d2), not yet on origin/main. #217 must land first; do not merge this ahead of it. The README/results hunks in the full diff are #217's.
- Follow-up filed: streamed usage keeps the first event per message id; if stream-json's per-block events carry growing output_tokens, the last is the accurate one.