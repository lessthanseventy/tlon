# Review — staff-child-honours-a-named-lead-on-a-wo (head 8a0e6d7)

**Verdict: approve.** The one finding from round 3 is fixed exactly as asked, with the test I specified. Nothing new since 70ea71b beyond that fix.

## 1. Round 3 finding fixed: an unfit pick on a bench without the stage's kind is taken as asked

Witness, `server/lib/server/workline.ex` `staff_opened/2`, the unfit branch now reads:

```elixir
case Server.Channel.thread_lead(staffed.id) do
  nil ->
    hand_to(staffed, @staff_by_stage[thread.stage] || "lead", wanted)

  lead ->
    post_brief(staffed, "→ #{lead} leads, not #{wanted}: #{why} (one coworker, one workline)")
    staffed
end
```

`restaff_miss` returns the thread untouched, so `thread_lead` is nil on a bench with no coworker of the stage's kind, and the branch falls to `hand_to` with the named pick. That restores the rule the removed `lead_for/2` promised ("left without a lead, takes the pick as asked"). The empty-name leads-line is gone with it.

Test added, `server/test/server/mcp/server_test.exs` "an unfit named lead on a bench without the stage's kind is taken as asked, not left unled": reviewer-only bench, `build` workline, `lead:` that reviewer; asserts the reply's lead, `Channel.thread_lead` and no "leads, not" line. On this head:

```
menard run test --in server test/server/mcp/server_test.exs:1344
{"ok":true,"tests":1,"failed":0}
menard run test --in server test/server/mcp/server_test.exs test/server/workline_test.exs
{"ok":true,"tests":192,"failed":0}
```

That the test was red before the fix is emma's report (#17082); I verified green on head and, by reading, that the old branch leaves `thread_lead` nil, which the assertion `== "lonnrot"` would catch.

## 2. bench_contrast

builder-junior 2/2 vs 2/2, librarian 2/2 vs 2/2: green, not findings. builder-senior "error — a side ran no tasks" is ticket #623 (the role runs zero tasks on both sides); recorded this sighting there. No REGRESSION row.

## Unchanged from the earlier approvals

- `not_manager/2` refuses an on- or off-shift manager before the thread opens: no orphan thread.
- `unfit/2` with `seat` nil (an agent not on the bench) falls to `hand_to` as asked.
- `lead_for/2` deleted; `Workline.open(lead:)` is the one door.
- `mise run check` exit 0 recorded by verify on this head.
