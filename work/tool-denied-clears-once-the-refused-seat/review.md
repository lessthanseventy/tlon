REQUEST_CHANGES — reviewed by lonnrot at 5e307b0 (origin/main..HEAD: dc4f3fa needs.ex + needs_test, 090ddb8 pr.md, 6dd8b22 ulrikke's review, 5e307b0 corkboard_test).

The stage brief told me "You reviewed this before, at e45ef87". That commit is ulrikke's review (Tlon-Author: ulrikke), not mine: this is my first read, so I read the whole diff, not the delta. Filed as a ticket.

Findings:

1. BLOCKING — `refused_moved/1` clears the item on a post by any seat ever refused on the thread, not the refused seat.
   The witness:
       from(e in Event, where: e.thread_id == ^t.id and e.kind == "tool_denied", select: e.detail)
   has no time bound, so `agents` is every agent in every tool_denied event the thread ever recorded. `posted` is then the newest post by any of them. Scenario, the shape of this very thread: emma is refused twice at build (round 1); verify and back-to-build reset `last_moved` via stage_advanced; ireneo is refused twice at build (round 2); emma answers an @mention. emma's post is newer than ireneo's denials, so `denials_since(t, refused_moved(t))` is [] and ireneo's blocking phone item vanishes with no signal. The ticket says "a post on the thread by that agent"; the code says "by any agent once refused here".
   Fix (the one predicate, no new plumbing): bound both queries to after `last_moved(t, nil)`; `posted || moved` is then the max, so the DateTime juggling goes too.

       defp refused_moved(t) do
         moved = last_moved(t, nil)

         agents =
           from(e in Event,
             where: e.thread_id == ^t.id and e.kind == "tool_denied" and e.created_at > ^moved,
             select: e.detail
           )
           |> Repo.all()
           |> Enum.map(& &1["agent"])
           |> Enum.uniq()

         posted =
           Repo.one(
             from m in Message,
               where: m.thread_id == ^t.id and m.author in ^agents and m.created_at > ^moved,
               select: max(m.created_at)
           )

         posted || moved
       end

   RED first in needs_test: two denials for seat "emma", a stage_advanced event (or the workline helper's advance), two denials for "nolan", sleep past the second, a post by "emma" → `[%{kind: "tool_denied"}]` must still be listed. `deny/2` hard-codes "nolan", so it wants an agent argument. Without the fix the item clears; with it, it stays.
   The thorough form (per-agent: drop only the denials whose own agent posted after them) is better still, but it is not what I am blocking on; the bounded form matches the ticket for seats that rotate across stages.

2. Same lines, fix while there: `DateTime.from_naive!(posted, "Etc/UTC")` converts nothing. `Message.created_at` is `:utc_datetime` (message.ex:16) and `max/1` over it comes back a `DateTime` — `last_moved/2` uses `max(e.created_at)` bare for the same reason. `DateTime.from_naive!/2` on a `DateTime` is a no-op (checked: `elixir -e` returns the same ~U), so it cannot crash, but it tells the next reader the column is naive. The patch in 1 removes it.

3. The tests pin the right two directions (post after denials clears; post before, or another seat's post after, does not). The `Process.sleep(1100)` is the cost of a second-resolution column; fine.

4. corkboard_test `File.rm_rf!` → `File.rm_rf`: a cleanup that no longer raises is the right call for on_exit, and it is why the landing went red, not needs.ex. It leaves the cause (the lazy writer outliving the test and a tmp dir leaked on the race) — follow-up, not blocking.

Verified by me: the diff, the Message/Event column types, the `from_naive!` no-op. Not re-run by me: the suite; I cite verify's `mise run check` exit 0 on 5e307b0 at 01:26Z (CHECKS) and nolan's QA pass (msg 17687, the no-post path only). No bench_contrast row among the CHECKS rows shown to me.