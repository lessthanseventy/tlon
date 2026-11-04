Closes #719: `assign_lead` answered `{"lead": X}` but X's seat never came up.

- `Staffing.hand_off/3` now seats the new lead in the same call (`Switchboard.deliver/1` on the handoff post) instead of leaving it to the bus and the drain's minute retry.
- It refuses up front when X's engine is clocked out (`{:error, :clocked_out}`, with words in `Staffing.explain/1`); nothing changes.
- `Switchboard.maybe_spawn_absent` says on the thread (a `tlon` notice) when the arbiter refuses the thread lead's seat, instead of dropping it silently. `:already_running` (booting pane), `:no_arbiter` and `:at_cap` (the parked note says it) stay quiet, and the notice is skipped while it is already the thread's latest message (the drain retries each minute).
- It also refuses an off-shift X up front (`{:error, :off_shift}`): `on_shift` would hand their seat to a stand-in and the thread would have no leaf.

Checked: `menard run test --in server` on staffing, switchboard, shifts, office, channel, attention tests: green (6 new tests in `staffing_test.exs`, each red first).
