# #505 (folds #582) — read dirs share one sandbox budget

## Problem
Claude Code makes every read dir a write root, and bwrap mounts ~45 args per `.git` found under one; bwrap takes 9000 (#299, #455). Today `Projects.read_dirs/1` only caps each checkout at 100 nested repos (`@max_nested_repos`), and the budget test (`profiles_test.exs:56`) counts repos under the `~/` write roots only. Nothing bounds the sum: three read dirs at 90 repos give (270 + 65) × 45 ≈ 15k, pass every test, and kill the seat's Bash.

#582's other roots add nothing: `.` is under `scratch_root/1` (already seeded and counted; a seat never boots in $HOME since 9bad5e0), and `/tmp` belongs to `scripts/bwrap-argc.sh` (#568) / `server:doctor`. Read dirs are the one hole.

## Design
1. **One place for the numbers.** New `Server.SandboxBudget` (server/lib/server/sandbox_budget.ex) holds `bwrap_args: 9000`, `args_per_repo: 45`, `fixed_repos: 65`, `max_args: 7500` (headroom), and `read_dir_repos/0` = the repos the read dirs may add in total. Both `Projects` and `profiles_test.exs` read it; no literal 65/45/7500 left in either.
2. **`read_dir_repos`** = `div(max_args, args_per_repo) − fixed_repos − write_root_reserve`, where `write_root_reserve` is the 40 repos the test already seeds in a seat's scratch dir. That is 166 − 65 − 40 = **61**.
3. **`Projects.read_dirs/1` spends it across the list.** Walk the project's repos in order; keep a dir while `running + nested_repos(dir) ≤ read_dir_repos`, adding its count; a dir that does not fit is skipped (later, smaller ones may still fit). The per-dir cap of 100 goes, since the shared budget subsumes it. (`nested_repos` counts the `.git` of the dir itself too, as today.)
4. **What the seat gets when they do not fit (the one decision): drop in list order, do not refuse.** The seat opens with the dirs that fit; dropped ones are listed in a single post on its thread. Refusing to open any would stop work over a read-only convenience. `read_dirs/1` stays pure; it returns `{kept, dropped}` through a new `read_dirs_split/1` (`read_dirs/1` = kept, so callers are unchanged), and `Spawn.read_dirs_export/1` (spawn.ex:193) posts the dropped list once at launch.

## Tests (RED first)
- `profiles_test.exs`: extend the budget test: seed a project with 3 read dirs of 30 repos each (each under the old 100 cap, sum 90 > 61), run `Profiles.instantiate` + `Projects.read_dirs`, assert `(fixed_repos + Σ write-root repos + Σ nested_repos(kept read dirs)) × args_per_repo ≤ max_args`. Red on main (all three kept).
- `projects_test.exs`: dirs of 30/30/10 → kept = first and third, dropped = second (skip, not stop); a single dir over 61 → dropped; order preserved.
- `spawn` test: a dropped dir produces exactly one thread post naming it; none when all fit.

## Done
`menard run test --in server test/server/profiles_test.exs test/server/projects_test.exs` green; `menard run check --in server` green; grep shows no `65`/`45`/`7500` literals in those two files. `projects.ex` moduledoc and the comment above `@max_nested_repos` updated in the same commit.

## Open
- Value 61 assumes a seat's write roots stay ≤ 40 repos, as the test seeds; if the operator would rather give read dirs more room, raise `read_dir_repos` and shrink the reserve — one number.
- A project with one big read dir (> 61 repos) loses it silently apart from the post; acceptable unless the operator wants it to fail the launch.
