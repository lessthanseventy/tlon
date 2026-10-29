The claude-code adapter now registers a `pane_ref` only when `$TMUX` is a workspace socket (`tlon-workspace-<n>`); from any other tmux it registers without one, which the server already reads as "no pane". Closes #529 (follow-up to #313).

Why: `$TMUX_PANE` carries no origin, so a `%N` from the operator's own tmux was indistinguishable from a workspace pane's `%N` in `end_predating_tmux` and wake's `windowed?`. Filtering in the adapter keeps a foreign pane_ref out of the DB, so no column or server change is needed.

Checked: two new mod.test.ts cases (foreign socket → `register {}`, `tlon-workspace-1` → `register {pane_ref}`), the first red before the change; mod suite 49 pass / 0 fail via `claude plugin test`; `claude plugin validate --strict adapters` passes.
