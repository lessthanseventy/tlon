# Review: staff_child honours a named lead on a workline (#551) — round 2

**Verdict: request_changes.** Round 1's two follow-ups are fixed (11f26f3), and well. Round 1's one **blocking** finding is not: `staff_opened/2` in `server/lib/server/workline.ex` (now lines 2350–2365) is byte-for-byte the code I quoted at 809af60. The builder's note #17017 took "the two follow-ups"; the blocking finding lived only in review.md's body. It goes back for that one thing.

Read: `git diff 809af60..11f26f3 -- . ':!work/…'` (coordination.ex, workline.ex, server_test.exs, workline_test.exs), then `restaff/1,2` (1340–1397), `hand_to/4` (1494), `restaff_miss/3` (1521–1526), `Workspaces.manager/1` (310–314). CHECKS: `mise run check` green on 11f26f3, `menard run check --in server` 2407/0, no `bench_contrast` row.

## 1. Still open (blocking): a named lead the bench cannot replace is dropped, and the workline opens unled

Witness, `workline.ex:2355–2359`:

```elixir
why when is_binary(why) ->
  staffed = restaff(thread)
  lead = Server.Channel.thread_lead(staffed.id)
  post_brief(staffed, "→ #{lead} leads, not #{wanted}: #{why} (one coworker, one workline)")
  staffed
```

Trace: `workline_changeset/1` sets no `agent_id`, so the thread is born unled. `restaff(thread)` → `restaff(thread, kind)` → `of_kind == []` → `restaff_miss(thread, kind, …)` → `do: thread` (1526), unled, silent for every kind but reviewer. Then `lead` is nil, the posted line reads `→  leads, not hronir: …`, the stage brief wakes nobody, `staff/2` answers `{:ok, nil}` and the tool replies `"lead" => nil`.

Concrete: the server_test "Named" workspace (daneri and hronir, builders only), `staff_child(lead: "hronir", workline: "spec")`. On origin/main `lead_for/2` took the pick (`is_nil(current) -> :as_asked`: "a workline staffing left without a lead takes the pick as asked"). On the branch: an orphan workline, no lead, no seat. That rule's doc was deleted with `lead_for` this round, so the branch now has neither the behaviour nor the sentence.

Fix, same as round 1, in `staff_opened/2`:

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

Red test first, in the server_test describe "staff_child with a named lead on a workline": `staff_child(lead: "hronir", workline: "spec")` → reply `lead == "hronir"`, `Channel.thread_lead(tid) == "hronir"`, exactly one leads-line (`[line] = leads_lines(tid)`), `line =~ "hronir leads"`. Add the sentence to `open/1`'s @doc too: a pick the bench cannot replace stands.

## 2. Fixed since 809af60 (verified)

- `lead_for/2` deleted; its two workline_test cases (748–774) now drive `Workline.open(lead:)` and assert the thread's lead and the posted "not yu … another workline" / "not hronir … planner" lines. One door.
- `not_manager/2` in staff_child refuses the manager before anything opens (`coordination.ex:104`, 182–190); test asserts `isError`, the name in the text, and an unchanged thread count. Reply text says what to do instead.

## 3. Still right from round 1

One pick, one `hand_to`, one leads-line, one seat on the free path; `unfit/2` holds the busy and wrong-kind rule once; `bench_all` keeps off-shift picks nameable; plain threads untouched; pr.md current.

Non-blocking findings in the follow-ups.
