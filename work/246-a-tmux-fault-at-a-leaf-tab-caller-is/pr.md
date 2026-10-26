A tmux fault at a `leaf_tab` caller is logged, not read as "no window" (closes #246).

- `Staffing.leaf_window/2` lists the windows and, on `{:error, why}`, logs `<what> thread N skipped: tmux <why>` as `pass/1` does. `hand_off/2`, `roll_leaf/1` and `Workline.close_leaf/1` use it; `roll_leaf` ends no session when tmux can't answer.
- `clear_context/2` lists windows first and, on a fault, logs and ends no session (was `-> []`).
- `seat_for?/2` loses its dead `nil` default (its only caller passes tabs).
- `Workspaces.remove/1` erases the `{Server.Office, :windows, ws}` persistent_term key.
- Skipped per hronir: KeepUp's inline `require(Logger)`. `tmux.ex` untouched (#363).

Checked: new tests in staffing_test (roll_leaf, red before) and workspaces_test; `menard run check --in server`.
