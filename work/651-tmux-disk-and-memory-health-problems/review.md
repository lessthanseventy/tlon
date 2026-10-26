APPROVE — 4409a49 (rebased onto eb73e4c; health need with stable first-seen `at`).

Re-review after the rebase. Read the diff only; did not run the suite from this seat (the server verified it).

- My earlier approval covered `health_since/1`: first-seen per problem kept in persistent_term, dropped when the problem clears, written only when the problem set changes. That code is unchanged by the rebase.
- The one conflict was in needs.ex, between upstream's `gated_at/1` and this branch's `health/0`. Both are present and independent: `gated_at` dates gates from the parked notice, `health_since` dates health items. No interaction.
- The rest of the diff since 59b602d is upstream main arriving through the rebase (staffing `leaf_window`, `clear_context` tmux-fault handling, the contrast test changes). It is not this workline's change and I did not review it as such.

No blocking findings, no follow-ups.