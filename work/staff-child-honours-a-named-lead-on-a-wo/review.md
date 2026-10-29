# Review: staff_child honours a named lead on a workline (#551)

**Verdict: request_changes.** The fix for the ticket is right and small, and the two new tests pass here (`menard run test --in server test/server/mcp/server_test.exs:1242` → 2 tests, 0 failed; the server's full `mise run check` row is green, no `bench_contrast` row). One path inside the new `staff_opened/2` regresses a documented rule and leaves a workline unled; it sits in the change's own lines, so it goes back rather than to a follow-up.

Read: commit 2db899e against origin/main 57b66b2 (coordination.ex, workline.ex, server_test.exs, pr.md), plus `restaff/2`, `hand_to/4`, `assign_lead/2`, `workline_changeset/1`.

## 1. A named lead the bench cannot replace is now dropped on the floor (blocking)

`lead_for/2`'s doc, still on the branch, says: *"a workline staffing left without a lead, takes the pick as asked"* — and the old code did that (`is_nil(current) -> {:ok, wanted, :as_asked}`). The new branch:

```elixir
why when is_binary(why) ->
  staffed = restaff(thread)
  lead = Server.Channel.thread_lead(staffed.id)
  post_brief(staffed, "→ #{lead} leads, not #{wanted}: #{why} (one coworker, one workline)")
  staffed
```

`workline_changeset/1` sets no `agent_id`, so the thread is born unled. When `wanted` is the wrong kind and the bench has nobody of the stage's kind, `restaff/2` hits `of_kind == []` → `restaff_miss` → returns the thread unled, quietly (only the reviewer kind posts). Then `lead` is nil, the line posted reads `→  leads, not yu: …`, the stage brief goes to nobody, and `staff_child` answers `"lead" => nil`.

Concrete case: a workspace whose bench is builders only (the new test's own "Named" workspace is one), manager calls `staff_child(lead: "hronir", workline: "spec")`. On main hronir gets the spec, as asked. On the branch an orphan workline opens with no lead.

Fix, in `staff_opened/2`: when staffing finds nobody, the pick stands, as the doc says.

```elixir
why when is_binary(why) ->
  staffed = restaff(thread)

  case Server.Channel.thread_lead(staffed.id) do
    nil ->
      # nobody of the stage's kind to give way to: the pick stands, as asked
      hand_to(thread, @staff_by_stage[thread.stage] || "lead", wanted)

    lead ->
      post_brief(staffed, "→ #{lead} leads, not #{wanted}: #{why} (one coworker, one workline)")
      staffed
  end
```

Red test first, beside the two new ones: builders-only bench, `staff_child(lead: "hronir", workline: "spec")` → `lead == "hronir"`, `thread_lead == "hronir"`, exactly one leads-line.

## 2. What is right

- One pick, one `hand_to`, one leads-line, one seat on the free path: `open/1` pops `:lead`, `staff_opened` hands straight to the name; `staff/2` for worklines no longer assigns. Matches the tech lead's plan.
- The busy and wrong-kind rule lives once, in `unfit/2`, shared by `lead_for/2` and `staff_opened/2`; `lead_for`'s existing tests (workline_test 748–774) still cover it.
- `bench_all` (off-shift counts as on the bench for a named pick) kept, as documented.
- The no-name path: `picked/2` → `suggest_lead` → a name, handed directly; a busy suggestion falls to `unfit` → `restaff` → the hire path. One pick there too.
- Plain threads untouched. pr.md says what changed and how it was checked.

Non-blocking findings are in the follow-ups.
