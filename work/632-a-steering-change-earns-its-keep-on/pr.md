# #632 — a steering change earns its keep on a canary A/B before it ships

Closes #632.

A workline whose diff edits a seat's steering now shows two canary runs on its thread before review:
`mix server.bench_contrast` (new) finds the roles whose system prompt moved (`mix server.bench_roles
--fingerprint`, run in a throwaway worktree of origin/main and in the branch's rebased checkout —
never the root checkout, which holds whatever branch the operator has out and is the tree the
service reads), runs the canary suite for each from both checkouts (`--out FILE`, so neither tree's
`bench/roles/results/` or README is touched), and each contrast comes back as one `bench_contrast`
CHECKS row (exit 0: pass count, tokens, turns, both commits) plus one thread note.
`scripts/workline-verify.sh` runs it after a green gate, at most 3 roles, and never turns red on it.
The task keeps its own 15-minute wall: each side runs as its own process group (`Contrast.sh/3`)
and the whole group is killed at the wall, so a bench's mix and the claude runs it spawned never
outlive verify; the script's `timeout` is only a backstop a minute past it. A branch touching no
steering runs none.
A skill or AGENTS.md edit is recorded `unmeasurable`: the bench's fixture workdir never loads them
(`Harness.aside_argv/3` passes only the prompt, read tools and model flags). The review brief and the
reviewer persona make a REGRESSION row a finding (with a flake caveat, n is small) and name
`propose_habit` for a real signal.

Pieces: `Grade.steering/1` · `Roles.fingerprint/1` · `Runner.persist/3` · `Server.Bench.Contrast`
(pure rows + the shell-out orchestrator) · `Mix.Tasks.Server.BenchContrast` · the verify block ·
the reviewer line.

## How it was checked

- Each piece test-first (red → green, its own commit): `grade_test`, `roles_test`, `roles_runner_test`,
  `contrast_test` (run/3 with a stubbed executor: nothing runs for no steering; one unmeasurable row for
  AGENTS.md; only moved roles benched, both sides; a main without `--fingerprint` is an error row; the
  cap names the skipped; every call draws on one wall and a side that hits it is an error row;
  `sh/3`: a `sleep 300 & wait` past its timeout leaves nothing alive in its process group, `pgrep -g`),
  `server_bench_contrast_test` (`paths/1` on a tmp repo), `workline_verify_script_test` (the script
  harness with a stubbed CLI and mise: no task → no run; no rows → nothing recorded; each row a
  `bench_contrast` CHECKS row and one note before the advance, mix's compile noise dropped; a red gate
  runs none; main's side is a `main-*` worktree under the verify cache at origin/main's sha, never the
  repo, and gone after), `workline_brief_test` + `profiles_test` (the reviewer rule).
- By hand (recorded as checks on the thread): `mix server.bench_roles --fingerprint --out` lists the 7
  roles; `mix server.bench_contrast` on this branch before T8 printed nothing and ran nothing.
- The full gate: `mise run check` on the committed head, run by the service (`run_task`).
- The positive end-to-end case is this workline's own verify: T8 edits `profiles.ex`, so verify will post
  the first `bench_contrast` rows — expected an `error` row for main (main's `bench_roles` has no
  `--fingerprint` until this lands) and an `unmeasurable` row for `server/AGENTS.md`.
