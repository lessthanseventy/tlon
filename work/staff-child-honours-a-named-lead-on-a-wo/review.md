# Review — staff-child-honours-a-named-lead-on-a-wo (head 7859fe8)

**Verdict: request_changes.** One confirmed regression against the rule the removed `lead_for/2` doc promised; four-line fix plus one test. Everything else stands as approved before.

## 1. An unfit pick on a bench without the stage's kind leaves the workline unled, and the thread says so with an empty name

Witness, `server/lib/server/workline.ex` `staff_opened/2`, the unfit branch:

```elixir
why when is_binary(why) ->
  staffed = restaff(thread)
  lead = Server.Channel.thread_lead(staffed.id)
  post_brief(staffed, "→ #{lead} leads, not #{wanted}: #{why} (one coworker, one workline)")
  staffed
```

`restaff/2` on a bench with no coworker of the stage's kind goes to `restaff_miss`, which returns the thread untouched. A freshly opened workline has no lead, so `lead` is nil and the line posted reads `→  leads, not <wanted>: …`. `StaffChild.staff/2` then returns `{:ok, nil}` and the tool replies with lead nil. Nobody is woken; the workline sits unled.

Before this branch the same case took the pick as asked. The removed `lead_for/2` was explicit: "a workline staffing left without a lead, takes the pick as asked", implemented by `is_nil(current) -> {:ok, wanted, :as_asked}`. That path is gone and nothing replaces it.

Concrete trigger: a bench with a reviewer and no builder; `staff_child` opens a `build` workline with `lead:` that reviewer. Wrong kind, so unfit; `restaff(thread, "builder")` hits `of_kind == []`; thread_lead stays nil. Same at `intent` (no kind) when the pick is busy, since `restaff/1` for intent picks the bench's lead and that may also be nil.

Fix (restores the old rule, one branch):

```elixir
why when is_binary(why) ->
  staffed = restaff(thread)

  case Server.Channel.thread_lead(staffed.id) do
    nil ->
      hand_to(staffed, @staff_by_stage[thread.stage] || "lead", wanted)

    lead ->
      post_brief(staffed, "→ #{lead} leads, not #{wanted}: #{why} (one coworker, one workline)")
      staffed
  end
```

Test to add, `server/test/server/mcp/server_test.exs` beside the existing "busy named lead gives way" case: seat only a reviewer on the workspace, `staff_child` a `build` workline with `lead:` that reviewer, assert the reply's `lead` is that reviewer, `Channel.thread_lead` is not nil, and no `→ … leads, not` message was posted. It fails on this head (lead nil) and passes with the fix.

## Unchanged from the earlier approvals

- `not_manager/2` refusal before the thread opens: correct, no orphan thread.
- `unfit/2` with `seat` nil (a registered agent off the bench) falls to `hand_to` as asked: matches the old doc.
- Five new tests pass and each fails without its change; `mise run check` exit 0 on this head.
