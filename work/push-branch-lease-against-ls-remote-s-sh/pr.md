push_branch leases against what the server last pushed, not a tracking ref (closes #706, #705)

`push_branch` fetched and pruned `origin/<branch>*` and then ran a bare `--force-with-lease`, so the lease compared against a ref refreshed a moment earlier and a hand push to `work/<slug>` was overwritten silently.

Now it asks origin (`ls-remote`, a failure is an error, never "absent") and leases an explicit sha: `""` when origin has no branch (a landing deleted it), the server's own record `refs/tlon/pushed/<branch>` when it has one (a moved head is refused, saying who moved it), else the sha read, once, for a branch pushed before records. No fetch, prune or `origin/*` write, so nothing touches the shared .git. A reland uses `replace_branch/3` (leased on the sha read: its gate is the guard, and GitHub's update-branch head is what it must overwrite); `fetch_branch` is gone (#705).

Checked: `workline_publish_test.exs` (argv order and lease, plus real-git tests against a bare origin: deleted branch, hand push refused, no record, reland over an advanced head, `work/uqbar` leaves `origin/work/uqbar-fix` alone) and `menard run check --in server`: 2377 tests, 0 failed.
