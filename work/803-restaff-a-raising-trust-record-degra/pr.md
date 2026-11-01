A raising `Server.Trust.record/1` no longer drops a restaff handoff.

`restaff` rescued the whole function, and `restaff_miss` is silent for build/plan, so a failed trust lookup left the thread unled without a word. Trust only breaks ties, so the lookup is now wrapped on its own (`with_trust/1`): a failure logs and leaves the candidate with no `trust` key, which `Roster.pick` already reads as neutral. `suggest_lead` shares the wrapper. `restaff_miss`'s silence for non-reviewer kinds is unchanged. `escalate` passes no trust on this base (#520 not landed), so it has nothing to raise.

Closes #803. Checked: new test in `workline_test.exs` (a raising lookup via the `:trust_record` seam still posts the build leads line) was red, now green; `menard run test test/server/workline_test.exs`: 92 tests, 0 failures.
