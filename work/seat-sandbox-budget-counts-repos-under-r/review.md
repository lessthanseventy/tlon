# review — seat-sandbox-budget-counts-repos-under-r @ 20b6e8a

**Verdict: approve**

The read_dirs half of #496, as re-scoped (tertius #10191/#10207: #306 lands as the read_dirs half; the server/tmp cleanup is #502). `Projects.read_dirs` drops any project checkout nesting more than `@max_nested_repos` (100) git repos, counted with `find <dir> -name .git -prune -print`. menard's tmp_dir repos (the second sandbox-overflow route, via TLON_READ_DIRS → additionalDirectories) no longer become seat write roots. The change is surgical (one filter clause + one helper + one test), self-contained in tlon (no sibling-repo menard commit, which is blocked by #473), and test-first: the new `projects_test` seeds 120 repos under `fat/tmp/rN/.git` and asserts only `slim` is returned — red before the filter (`[slim, fat]`), green after (`[slim]`).

`find -prune` is the right idiom — it prints each `.git` once and never descends into one, where `**/.git` would walk a big repo's objects (minutes). No shell, so the path is safe from injection. `read_dirs` is called at staffing time, not on a hot path, so the walk's cost is fine.

Verify is green past flake #501 (SwitchboardTest "a posted message wakes its addressee"), which passes alone and is unrelated to this diff — filed, not this change's fault, emma takes it after #306 lands.

Two non-blocking follow-ups filed below.

## follow-ups

## Count read-dir repos in the #299 budget test
`Projects.nested_repos/1` caps *each* checkout at 100. The threshold is calibrated so one maxed read dir fits the bwrap budget (65 fixed + 100 = 165 × 45 = 7425 ≤ 7500), but a project with several fat read dirs each under 100 could still push the *total* over 9000 — the #299 budget test (`profiles_test.exs:34`) still only counts repos under `~/` write roots and never sees read-dir repos, so it stays blind to that. The tech lead's original step 1 (#10135) was to extend #299 to count repos under the read dirs; this branch replaced that with the per-checkout guard, which is the cheap half. Extending #299 to count read-dir repos too would make the budget precise instead of heuristic.

## `nested_repos/1` miscounts on a missing or unreadable dir
`System.cmd("find", [dir, …], stderr_to_stdout: true)` merges find's error lines into stdout and ignores the exit code, so `String.split/length` counts error text as repos. For a *missing* dir the count is ~1 (≤100, dir still returned — same as preexisting behavior, no regression). For an *unreadable* dir it could falsely drop a legit checkout. Separating stderr (or checking the exit code and returning a sentinel that keeps the dir) would be cleaner.