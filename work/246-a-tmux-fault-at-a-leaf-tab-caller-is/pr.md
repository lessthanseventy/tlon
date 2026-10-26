A tmux fault at a `leaf_tab` caller is logged, not read as "no window" (closes #246).

- `Staffing.leaf_window/2` lists the windows and, on `{:error, why}`, logs `<what> thread N skipped: tmux <why>` as `pass/1` does. `hand_off/2`, `roll_leaf/1` and `Workline.close_leaf/1` use it; `roll_leaf` ends no session when tmux can't answer.
- `clear_context/2` lists windows first and, on a fault, logs and ends no session (was `-> []`).
- A tmux server that is not up (`{:error, :not_up}`) means no windows, not a fault: `leaf_window/2` and `clear_context/2` read it as `[]`, so `roll_leaf` and `clear_context` still end the sessions when no server is running. Verify caught this: the gateway's clear test skipped on `not_up`.
- `seat_for?/2` loses its dead `nil` default (its only caller passes tabs).
- `Workspaces.remove/1` erases the `{Server.Office, :windows, ws}` persistent_term key.
- Skipped per hronir: KeepUp's inline `require(Logger)`. `tmux.ex` untouched (#363). Rebased onto main at bcfb097 (#391).

Checked: new tests in staffing_test (roll_leaf, red before; not_up ends sessions with nothing logged, red before the `not_up` fix) and workspaces_test; `menard run check` in `server/`: 2184 tests, 0 failures.
