# Read dirs share one sandbox budget (#505, folds #582, #506)

Claude Code makes every read dir a write root and bwrap mounts ~45 args per `.git` under one.
`Projects.read_dirs/1` only capped each checkout at 100 repos, so three read dirs of 90 passed every
test and killed the seat's Bash. Now:

- `Server.SandboxBudget` is the one home for the numbers (9000 bwrap args, 45 per repo, 65 fixed
  checkouts, 7500 headroom, a 40-repo write-root reserve); `read_dir_repos/0` = 61 is what a
  project's read dirs may hold together.
- `Projects.read_dirs_split/1` spends it across the list in order: a dir is kept while the running
  count fits, skipped if not, and a later smaller one still opens. `read_dirs/1` is the kept half,
  so callers are unchanged. A path that is not a directory is neither opened nor dropped.
- `Spawn.read_dirs_export/1` posts the dropped dirs once on the thread as a notice (the operator
  chose drop over refuse).
- `nested_repos/1` counts only `-print` lines ending in `/.git` (#506): find's "Permission denied"
  text no longer counts as a repo, and the exit code is ignored, so a partial walk is a lower bound.
- The budget gate in `profiles_test.exs` now sums write-root repos and kept read-dir repos against
  the module's numbers, red against the old code (40 + 90 read-dir repos).

One correction to the spec: its 40-repo reserve assumed the gate seeded 40 under write roots, but
it seeded 82 (40 in scratch plus 2 per dev cache). The fixture now seeds exactly the reserve (one
repo per dev cache, the rest in scratch), so the test states the split. Measured on this box the
real write roots hold 2 repos and the real read dirs 46, so 61 keeps them all where 19 would have
dropped menard.

Checked: `menard run test --in server` on projects_test, profiles_test and mcp/spawn_test, each RED
first; `menard run check --in server` green.
