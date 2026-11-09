VERDICT: request_changes

Commit read: 2eebeec (needs: hold a parked review gate's Uqbar route while its grade job is live), one commit on work/a-parked-gate-wakes-uqbar-before-the-ris against origin/main 92deeca. Diff: server/lib/server/office/needs.ex, server/test/server/office/needs_test.exs, work/.../pr.md. CHECKS: `mise run check` green on 2eebeec (2812 passed); no bench_contrast row.

## Findings

1. **The hold is keyed by thread, not by the gate item.** In `routed/0`, `graded` maps `thread_id => {state, ended}` for the review gates under a standing approval, but the loop calls `hold(item, graded[item.thread_id])` for every item, and neither `hold/2` clause looks at the item's kind:

   ```
   defp hold(_item, {state, _}) when state in ~w(available scheduled executing retryable), do: :held
   defp hold(%{at: at} = item, {_, %DateTime{} = ended}), do: %{item | at: ...}
   ```

   A `question`, `ask`, `blocked` or `issue` raised on the workline's thread while its Grade job is live (a reviewer's `ask_operator`, say) is therefore also `held`: dropped from every group of `grouped/1`, so the operator's inbox and phone do not show it for the grade's duration; and once the job ends, its `at` is moved to the grade's end as well. The ticket and the tech lead's design hold the gate alone ("a review gate ... is held"). Fix, both clauses guarded on the gate:

   ```
   -  defp hold(_item, {state, _}) when state in ~w(available scheduled executing retryable), do: :held
   +  defp hold(%{kind: "gate", stage: "review"}, {state, _}) when state in ~w(available scheduled executing retryable),
   +    do: :held

   -  defp hold(%{at: at} = item, {_, %DateTime{} = ended}),
   +  defp hold(%{kind: "gate", stage: "review", at: at} = item, {_, %DateTime{} = ended}),
        do: %{item | at: Enum.max([at, DateTime.truncate(ended, :second)], DateTime)}
   ```

   Red first: under `auto_land_risk`, a review gate with a live Grade job and `Server.Attention.ask(thread_id, "daneri", "A or B?")` on the same thread; assert the question is in `Needs.grouped().phone` (today it is in no group) while the gate is still in none.

## Read and not a finding

- The `stage: "review"` filter keeps a thread that went to QA with a live grade (Grade is enqueued before `to_qa` in `Review`) out of the hold.
- `Map.new` over `order_by: j.id` keeps the newest Grade job per thread; a discarded grader (max_attempts 1) ends the hold through `discarded_at`, so a failed grade never holds a gate forever.
- The `at` bump cannot shadow a Uqbar verdict on the same park: a verdict row is written only after the hold ends, so it is newer than the bumped `at`; a verdict on an earlier park is meant to be ignored.
- With routing off, `grade_jobs` is not called and no Oban rows are read; with no review gate, no query.
- Two comment lines against ~40 of code; moduledoc's Routing paragraph updated; no ticket keys in code. pr.md names the ticket and the check.
