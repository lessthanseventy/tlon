APPROVE — #661

Test-only change (17 lines in `server/test/server/switchboard_test.exs`, plus pr.md). No production code touched.

- The new test reassigns the lead with `Staff.assign`, ages a tlon stage notice 12 minutes, and silences both sessions. It then asserts `redeliver_unheard/0 == 0`, that the new lead (`wRobert`) is not woken after `drain`, and that `delivered_at` is unchanged.
- It pins the `unheard?(%Message{author: "tlon"})` guard (`lib/server/switchboard.ex:160`). It is the lead-change variant of the sibling test directly above it, so it adds coverage without duplicating it.
- Per the PR, the builder broke the guard and both tests went red, so the test can fail. I did not re-run that check or the suite myself; I read the diff and the guard.
- `pr.md` is in line with the change: no production code, closes #661.

No findings, no follow-ups.