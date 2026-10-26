APPROVE (#246, head c9c0586).

Read the full diff against main; did not re-run the gate (pr.md reports `menard run check`: 2184 tests, 0 failures).

Verified by reading:
- `leaf_window/2` returns tabs/nil/`{:error, why}`, with `:not_up` read as `[]`. This matches `Tmux.list_windows/2`'s contract and `leaf_tab({:error,_})` → nil. `hand_off` and `close_leaf` use `with %{index: _} <-`, so nil and error both fall through without killing anything.
- `roll_leaf` on a tmux fault ends no session and kills no window; the old code ended the sessions and then found no window to kill. `close_rolled/2` covers tab and nil.
- `clear_context` skips on a fault and still clears on `:not_up`; the trailing `:ok` is returned either way.
- `seat_for?/2` has one caller (`arbiter/tmux.ex:123`, passes tabs) and its test is updated.
- `Workspaces.remove` erases `{Server.Office, :windows, ws}`, which matches the key in `office.ex` `held_windows/1`. This is a small adjacent change, but pr.md discloses it and a test covers it.
- Tests cover the fault (warning logged, session kept, no kill-window) and `not_up` (sessions ended, nothing logged).

No blocking findings.