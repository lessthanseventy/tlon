Closes #171.

`Continuation.run` now skips, without counting against the 3-nudge budget, when
- the thread's lead is clocked out (`Presence.clocked_out?`), or
- a nudge is too soon: less than `continuation_gap_minutes` (new operator setting, default 10, 0 = off) since the last continuation on the thread, or since the thread opened when it has had none (the #329 case: a workline opened straight at build), or the lead posted on the thread inside that window.

Checked: new tests in `workline_continuation_test.exs` (three idles a minute apart → one nudge; idles past the gap still reach 3/3 then stuck; fresh workline waits; lead's post silences; clocked-out lead posts nothing and the budget is untouched), driven by an injected `now:`, no sleeps. `menard run check --in server` below.
