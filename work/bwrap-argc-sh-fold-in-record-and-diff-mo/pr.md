Folds ireneo's `bwrap-argv.sh` `record` and `diff` modes into `scripts/bwrap-argc.sh` — one script, one test, one task (`mise run sandbox:argv`). Closes #568.

- `bwrap-argc.sh [FILE]` is unchanged: the count and mounts grouped by prefix.
- `record [FILE]` also appends `<ts> <count> wt=<registered worktrees>` to `$BWRAP_ARGC_DIR/count.log` (default `$TMPDIR/bwrap-argc`) and snapshots the path args when they change. The snapshot reads argc's NUL-safe records, not argv's grep: only bwrap's own args before the `--` (never the command text) and never a `--setenv` value, which can carry the proxy credential.
- `diff` prints the paths added (`+`) and dropped (`-`) between the first and last snapshots.

Checked: `scripts/bwrap-argc.test.sh` went red first (`record: No such file or directory`), then green; it covers the record line, a snapshot holding mount paths only (a `/`-leading `--setenv` value and `/`-leading command args are both left out), no new snapshot when nothing changed, and a diff naming only the added path. `mise run check:names` passes. Live, in this seat's sandbox: `mise run sandbox:argv -- record` logged `793 wt=45`, and the 448-line snapshot holds no `@`.
