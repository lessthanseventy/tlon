# Review — bwrap-argc: record and diff modes from argv.sh (#568)

**Verdict: APPROVE**

The change folds `record` and `diff` into `scripts/bwrap-argc.sh` on the existing NUL-safe parse — one script, one test, one `sandbox:argv` mise task, exactly the shape the tech lead specified. The credential guard (never snapshot a `--setenv` value) is verified, the test went red-first then green, and the branch rebases cleanly onto main.

## What changed

- `scripts/bwrap-argc.sh` — `record [FILE]` appends `<ts> <count> wt=<n>` to `$BWRAP_ARGC_DIR/count.log` (default `$TMPDIR/bwrap-argc`) and snapshots the `/`-leading path args before the `--` (never a `--setenv` value) when they change; `diff` prints `+`/`-` paths between the first and last snapshots. `record` still prints the usual report.
- `scripts/bwrap-argc.test.sh` — covers the record line, path-only snapshot, no env value recorded, no redundant snapshot on unchanged paths, every record appending a count line, and `diff` naming the added path.
- `tasks/server.toml` — the `sandbox:argv` task; `docs/manual/tasks.md` regenerated (2676a9d, the fix for the `manual:check` drift that sent verify back once).

## Verified

- `bash scripts/bwrap-argc.test.sh` → `bwrap-argc: ok` (exit 0).
- Credential guard: a `--setenv` value that *does* start with `/` (`/secret/creds`) is excluded from the snapshot — the `opt == "--setenv" { next }` awk line holds. The test's non-`/` value is also excluded (by the `/^\//` filter).
- `diff` dropped-path direction: snapshot losing `/tmp/x1` → `-/tmp/x1`. Correct (untested by the suite, probed by hand).
- `record` prints the report as well as recording (the `if` block falls through to the report awk). Consistent with the task description's "also appends".
- Rebase safety: `git diff merge-base..origin/main` touches none of the four workline files, so the merge gate's rebase won't conflict.

## Follow-ups (non-blocking)

- **`diff` with no snapshots leaks a stderr error.** When no `argv.*` exists, the glob `"$dir"/argv.*` doesn't expand (nullglob off) and becomes a literal path, so `diff` prints `diff: '…/argv.*': No such file or directory` to stderr. `|| true` keeps exit 0 and stdout empty, so it is cosmetic — but `mise run sandbox:argv -- diff` before any `record` prints a confusing line. Guard with `shopt -s nullglob` (or `[ -e "${snaps[0]}" ]`) before diffing.