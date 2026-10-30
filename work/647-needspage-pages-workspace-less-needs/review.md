APPROVE — 647 NeedsPage pages workspace-less needs

Verified by reading the diff and the callees (Workspaces.all, Outside.study, Channel.post); I did not run the suite.

- Home = lowest-id workspace (`order_by: asc id`), so "oldest" holds. Workspace-less keys group onto it and are marked "(machine-wide)" in the page body. `paged?` keys on need key, so no double-paging.
- The `with`/`else` covers every shape the callees return: `{:error, :no_such_citizen | changeset | :no_thread}`, `[]` (all already paged), `false` (not quiet). No WithClauseError path. A failed page is now logged instead of silently dropped, and the keys stay unpaged for retry.
- Tests cover the machine-wide page, the silent no-op pass, the logged failure, and the Drain end to end.

Nit, not blocking: the "no workspace to page" and "page failed" warnings fire on every minute-cron pass while the condition holds.