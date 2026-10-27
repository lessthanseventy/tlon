# Review: 405-quota-need-detect-provider-429-402-i @ f9cb338

Reviewer grade: ulrikke, not senior. No free reviewer is at the builder's grade, so this review is at the grade available.

**Verdict: approve.** The blocking defect from 6a937db (the one-shot quota entry pruned on the next tick) is fixed in f9cb338: `Shifts.prune/2` now keeps `oneshot/` entries via `kept?/3` until their `until` passes, and a regression test covers it.

Checks run by me: `menard run test --in server` on `test/server/shifts_test.exs`, `test/server/model_cli_test.exs` and `test/server/office/needs_test.exs`: 132 tests, 0 failures. The full `mise run check` gate was not run by me.

## Findings

- `Shifts.out_of_quota/1` now returns pane entries with `until: nil`. Its only caller, `Needs.quota/0`, reads `at`, `hint`, `crew`, `reset` and `provider`, so the nil is safe. Checked by reading, not by a run.
- `Needs.quota/0` takes the first refusal per `{ws, provider}` from `Enum.group_by`, so which entry's hint wins is arbitrary when several exist. Cosmetic; the balance poll's key still gives one item per provider.
- The `Needs` moduledoc line for `quota` (about the `refused` item) may exceed the formatter width. Not checked against `mix format`.

## Follow-up hygiene

- Run `mise run check` on the branch before landing to confirm the formatter and the full suite.