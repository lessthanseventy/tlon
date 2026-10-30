APPROVE — reviewed by lonnrot at bb5cfda (second round; my first verdict was 260f54a, request_changes). Delta read: `git diff 260f54a..HEAD -- . ':!work/…'` = bb5cfda only (needs.ex 17 lines, needs_test.exs 17 lines).

Findings, numbered:

1. FIXED — my blocking finding (a post by any seat ever refused on the thread cleared the item). `refused_moved/1` now bounds both queries to after `last_moved(t, nil)`:
       where: e.thread_id == ^t.id and e.kind == "tool_denied" and e.created_at > ^moved
       where: m.thread_id == ^t.id and m.author in ^agents and m.created_at > ^moved
   so `agents` is the current round's refused seats and `posted` their newest post in that round. It is the patch I posted, line for line. The new test is the scenario I asked for: emma refused, `stage_advanced`, nolan refused, emma posts → the item stays and names nolan. ireneo reports it red before the fix, 96/96 after (CHECKS row 01:34:16Z).

2. FIXED — the `DateTime.from_naive!` no-op is gone; `posted || moved` is a `DateTime` either way, which `denials_since/2` compares directly.

3. Checked by me: `last_moved/2` always includes `t.created_at`, so `moved` is never nil and `created_at > ^moved` cannot hit Ecto's nil-comparison error on a thread with no movement. An empty `agents` makes `m.author in ^[]` false, `posted` nil, and the item behaves as before the change.

4. Spec: #579 asks that a refused seat's later post or commit count as movement. Post: done. Commit: not done, said in pr.md and on the thread; stays a follow-up, not a block, since the fault the ticket opened on (the item returning every turn after the seat posts) is closed.

5. Policy: any post by the refused seat clears the item, including a "still blocked" one. ireneo kept this on purpose; the moduledoc now says so ("a post by the refused seat itself"). Decided, so no longer a finding.

Verified by me: the delta diff, `last_moved/2` and `denials_since/2` sources, the Message column type (prior round). Not re-run by me: the suite; I cite verify's `mise run check` exit 0 on bb5cfda at 01:45:58Z (CHECKS). No bench_contrast row among the CHECKS rows shown to me.