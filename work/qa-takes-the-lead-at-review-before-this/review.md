VERDICT: approve

Reviewed fbc32c83467dfabf7aabb439bd75558f17961367 (one commit on origin/main 4460cc2): `server/lib/server/workline.ex` +3, `workline_qa_test.exs` +17, `pr.md`.

1. The fix is the right one line. `hand_to_qa` now refuses when `is_nil(since_review(thread, review)) and reviewed_before?(thread)`, the same predicate `this_round` already applies to the owed artifact (`owed_artifact` → `this_round`, workline.ex:2195). The advance path and the hand-off now agree: a re-entered review with no verdict this round gets `this_round`'s refusal ("review.md is the last round's — submit_review this round's verdict"), not a QA seat. First round (`reviewed_before?` false) is untouched, so the existing "approves in review.md and advances" hand-off still works.

2. The ticket's scenario is covered. Round 1 verdict → bounce → verify → review → advance with `review_line: "VERDICT: approve"` returns `{:error, {:artifact_missing, _}}`, lead stays the reviewer, no 🎭 QA post. The test bounces via `request_changes` rather than approve + send-back; the guard reads any prior verdict, so the coverage holds. That the test went red first is emma's claim in pr.md, not mine: the reviewer seat can't touch files.

3. Ran it: `menard run test --in server test/server/workline_qa_test.exs` → ok, 17 tests, 0 failures. The server's own `mise run check` on this head passed at 22:56Z (CHECKS, exit 0).

4. No other reader of review.md's first line seats anyone. `gate_summary` (workline.ex:768) shows it, but only at a gate, which `this_round` already keeps to a this-round verdict. `Publish` reads it after a verdict. A head that changes inside a round is `reviewed_current`'s bounce, so the sha-based shape the ticket suggested buys nothing extra here.

5. No `bench_contrast` row in CHECKS.

Nit, not a finding: the stale-round conjunction now lives in two places (`this_round`, `hand_to_qa`); fine at two, name it if a third appears.