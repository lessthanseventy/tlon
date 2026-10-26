APPROVE — #246 (tmux fault at a leaf_tab caller), re-review of head 124c07b.

Read the diff against main; did not run the suite myself (verify runs the gate).

- `leaf_window/2` sorts tmux answers three ways: window, nil, `{:error, why}` (logged). `:not_up` reads as no windows, any other fault stays an error. All callers (`hand_off`, `close_leaf`, `roll_leaf`) fall through safely on `{:error, _}` because their `with %{index: _}` patterns don't match.
- `roll_leaf` on a fault ends no session and returns `:ok`, so the old window is never stranded. Continuation then briefs a still-live session; that is logged, and acceptable.
- `clear_context` returns `{:error, why}` before touching sessions. The clear route maps it to a refusal instead of `{:ok, cleared}`. Gateway test asserts 409 and a live session.
- `seat_for?/2` loses its default arg; the only caller (`arbiter/tmux.ex`) already passes `tabs`. Test updated.
- Tests cover fault, not-up and clear-route cases.

Nit, not blocking: the `Workspaces.remove` `:persistent_term.erase` is not about #246 (surgical-changes rule). It is small, tested and correct.