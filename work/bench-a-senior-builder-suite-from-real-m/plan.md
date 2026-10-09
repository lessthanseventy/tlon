# Plan — builder-senior suite from real merged worklines (ticket #90)

**Finding:** `builder-senior` and `builder-junior` share `set: "builder"` (`Server.Bench.Roles.@roles`), so the 4 toy
fixtures (`tasks/builder/{c1,c2,f1..f4}`) are what "senior" runs today. Fixtures are a `repo/` dir copied in; graders
are `check` (hidden `check/` files copied over the workdir, then `cmd`). Nothing yet freezes a *real* repo snapshot.

**Design (assumptions, simplest thing):**
- New set `senior` → `bench/roles/tasks/senior/<id>/`; `builder-senior` => `set: "senior"`. `builder-junior` keeps `builder`.
- A task has `task.json` `"source": {"commit": "<sha>"}` instead of a `repo/` dir: the runner seeds the workdir with
  `git archive <sha>^ server` from `Profiles.tlon_root()` (the workline's parent commit — frozen, tiny on disk), then
  commits it as `fixture`. History is linear (rebase-merge), so a sha pins it forever.
- Hidden acceptance = the workline's own test files at `<sha>`, stored whole in `check/` (copied over the model's work;
  a patch would conflict if the model edited the same test file; the files are small). `cmd` = `cd server && mix test <those files>`.
- The `prompt.md` = the ticket/intent text **plus the interface the hidden tests call** (names, arities, return shapes) —
  the model cannot guess `Worktree.stranded/2`; the junior `roman` prompt does the same.
- `_build` is copied (reflink) from the live `server/_build` so a task compiles incrementally; each workdir gets its own
  test DB by path hash (`config/support/test_database_name.exs`), so runs never collide.
- `--oracle` flag: run each task with the *reference* diff applied instead of a model → proves every fixture is
  green on the real solution and red on the parent (fair + deterministic) before any model is spent.

**The pick (six; hronir to confirm/justify in thread — proposal, all merged to main 2026-10-08):**
| id | commit | why fair | why hard |
|---|---|---|---|
| s1-stranded-close | ed14041 (#196) | channel_test + server_test, no UI | 5 source files, cross-module (Worktree/Channel/MCP) |
| s2-intake-closed-slot | 272a75e (#200) | one test file, one query | Ecto correlated `not exists` |
| s3-epic-parent-law | 0044dd0 (#197) | epics_test, DB-CHECK + validation | invariants (one parent, no epic under epic) |
| s4-epic-intake | 4ab4d56 (#197) | epics_test | ordering/priority inheritance rules |
| s5-keepup-drift-note | 4e0aae8 (#201) | keep_up_test | upsert keyed notes, per-repo routing |
| s6-start-ticket-tool | 5023af6 | server_test | MCP tool wiring through endpoint+tools |
Dropped: #186/#191 (no merged commits — 186 is mid-build, 191 unmerged), UI/pixel worklines (office/home/whimsy).

## Task 1 — `Roles.load` understands `source`
Files: `server/lib/server/bench/roles.ex`, `server/test/server/bench/roles_test.exs`.
1. Test first: a tmp task dir with `task.json` `{"tier":"full","grader":{"kind":"check","cmd":"true"},"source":{"commit":"abc1234"}}`
   and no `repo/` → `Roles.load/3` returns `source: "abc1234"`, `repo: nil`; a `source` that is not a hex string of ≥7 chars raises `bad task.json`. Red.
2. In `task/2` add `source: meta["source"]["commit"]` (nil-safe) and validate `~r/^[0-9a-f]{7,40}$/` when present.
   Add `senior: "senior"` role mapping: `"builder-senior" => %{archetype: :builder, grade: "senior", set: "senior"}`; update the moduledoc line on `repo/`.
3. `~/projects/menard/bin/menard run test --in server test/server/bench/roles_test.exs` → green. Commit.

## Task 2 — Runner seeds from `source`, with `_build`
Files: `server/lib/server/bench/roles/runner.ex`, `server/test/server/bench/roles_test.exs` (or a new `runner_seed_test.exs`).
1. Test first: in a throwaway git repo with two commits (second adds `server/x.txt`), `Runner.seed_source(root, sha2, work)` leaves
   `work/server/` without `x.txt` (parent state), with a `.git` and one commit. Red.
2. Implement `seed_source/3`: `git -C root archive <sha>^ server | tar -x -C work`, then the same `git init/add/commit fixture` as `seed/2`
   (extract that shared tail). In `run_task`: `cond` on `task.source` vs `task.repo`; when source, also
   `cp -r --reflink=auto <tlon_root>/server/_build <work>/server/_build` (skip if absent). Raise `@check_timeout_s` to 900 for source tasks (cold compile).
3. Green. Commit.

## Task 3 — `--oracle`: grade the reference solution
Files: `runner.ex`, `lib/mix/tasks/server.bench_roles.ex`.
1. Test first (unit): `Runner.reference_patch(root, sha)` returns the `git diff <sha>^ <sha> -- server/lib` text (non-empty for a commit touching lib, filtered to `lib/` only so tests stay hidden). Red.
2. Implement; mix task flag `--oracle`: for each source task `git apply` that patch in the workdir instead of calling the harness, then grade. Print `✓/✗ id` per task; exit non-zero on any ✗. No results file written in oracle mode.
3. Verify: `mise run bench:roles -- --suite full --role builder-senior --oracle` prints all ✓ once Tasks 4–9 land. Commit.

## Tasks 4–9 — one fixture each (s1…s6), one commit each
For each row of the pick table, create `bench/roles/tasks/senior/<id>/`:
- `task.json`: `{"tier":"full","grader":{"kind":"check","cmd":"cd server && mix test <test files>"},"source":{"commit":"<sha>"}}`
- `prompt.md`: the ticket text (from `git show <sha>` message and `work/<slug>/plan.md` where it exists) + "interface the tests call" (read it off the hidden tests: `git show <sha> -- server/test`). Do not paste test bodies.
- `check/server/test/...`: `git show <sha>:server/test/<path>` verbatim, one file per hidden test file.
- Verify red-on-parent (hidden tests alone fail): `mix test` in a `git archive <sha>^` extract with `check/` copied → exit ≠ 0.
  Verify green-on-reference: `... --oracle` ✓ for this task.
Definition of done per task: both verifications shown in the commit message/PR notes. Tier is `full` (the canary suite stays cheap).
Drop a candidate (replace from `work/` list, e.g. `ticket-15-the-finder…`) if its tests are flaky or need the live service — say which and why.

## Task 10 — run and report
1. `mise run bench:roles -- --suite full --role builder-senior --model anthropic/claude-sonnet-5-5` then
   `--model ollama-cloud/deepseek-v4.1-flash`. (Spends plan quota; run once each — read the logs under `bench/roles/results/`, don't re-run.)
2. README regenerates itself; commit `bench/roles/results/*.json` + `README.md`; add a "senior set" paragraph to `bench/roles/README.md`'s generator text in `roles.ex` (`readme/1`) only if a fixed note is needed.
3. Post the table (model × pass/6, wall, tokens, cost) and per-task ✓/✗ to the thread.
Done = two result rows exist for `builder-senior`, `mise run check` green, `bench/roles` AGENTS/README mentions the `source` format (docs same commit).

## Risks to name, not hide
- Cold `mix` compile in a throwaway dir may exceed 15 min on flash → `_build` copy (Task 2); if still slow, cap and record as ✗ "timeout".
- Interface leakage vs. fairness: if a prompt needs >15 lines of interface, the workline is too under-specified — swap it.
- Test DB leftovers: each workdir makes `tlon_test_<hash>`; the grader should `dropdb` it after the check (add to Task 2 if `psql -l` shows buildup).
