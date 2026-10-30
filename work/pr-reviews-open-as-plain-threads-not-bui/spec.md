# Spec — PR reviews open as plain threads (#737, dup #729)

## Problem
`Tickets.start_thread/2` always calls `Workline.promote/1`, so a ticket asking for a PR review opens a
workline at build. `owed_status` then expects commits on `work/<slug>`; the reviewer can't write, so
`Continuation.run` nags 3x (rolling the leaf at nudge 2) and `stuck/4` alarms. The nag is correct for a
build workline; the fault is the stage the thread was born at. A review's artifact is a
`review_branch` verdict on the PR head, not commits.

## Decision
A PR review is a **plain thread** (stage nil), never a workline. With stage nil `owed_status` is
`:none`: no nag, roll or stuck alarm. The nag/continuation code is untouched (no title sniffing).

## 1. Which tickets are reviews
A ticket whose `labels` include `"review"`, set by whoever files it. No title/body parsing.
`Tickets.review?/1` = `is_list(labels) and "review" in labels`.

## 2. What happens on start
`start_thread/2` keeps every guard (pause, epic/initiative, `startable`). For a review ticket it skips
`Workline.promote/1`: `open_thread` (same attrs), then `promote(ticket, thread.id)` (the tie), then
`Attention.respond` with the ask. The ask is the ticket text plus one line:
`This is a PR review, not a build: owed is a review_branch verdict (approve | request_changes) on the PR head sha you read. You write no code and own no work/<slug> branch.`
Non-review tickets are unchanged.

## 3. What the thread owes / what closes it
Owes: one `review_branch` verdict on the named head sha. Ends on `finish` (after the verdict), or
when the PR merges/closes. Auto-close-on-merge and `finish` refusal are **#695, out of scope**; this
change only stops a review being born a workline. The existing `Tickets` thread-closed -> ticket done
path applies as for any plain thread.

## Out of scope
Migration, gate, nag changes, #695, #569.

## Tests (TDD, `server/test/server/tickets_test.exs`)
1. Review-labelled ticket + `start_thread` -> thread `stage == nil`, `slug == nil`, ticket tied
   `promoted`, ask post contains the verdict line.
2. Same ticket: `Continuation` owed status for the thread is `:none` (no nudge).
3. Unlabelled ticket still opens at build (regression).

Verify: `~/projects/menard/bin/menard run test --in server test/server/tickets_test.exs`, then
`menard run check --in server`. Grade: senior.
