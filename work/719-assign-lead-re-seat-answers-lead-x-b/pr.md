Closes #719: `assign_lead` answered `{"lead": X}` but X's seat never came up.

- `Staffing.hand_off/3` now seats the new lead in the same call (`Switchboard.deliver/1` on the handoff post) instead of leaving it to the bus and the drain's minute retry.
- It refuses up front when X's engine is clocked out (`{:error, :clocked_out}`, with words in `Staffing.explain/1`); nothing changes.
- `Switchboard.maybe_spawn_absent` says on the thread (a `tlon` notice) when the arbiter refuses the thread lead's seat, instead of dropping it silently. `:already_running` (booting pane) and `:no_arbiter` stay quiet.

Not done: an off-shift refusal. Off-shift X is still handed to a stand-in by `on_shift` with no word on the thread.

Checked: `menard run test --in server` on staffing, switchboard, shifts, office, channel, attention tests: green (3 new tests in `staffing_test.exs`, each red first).
