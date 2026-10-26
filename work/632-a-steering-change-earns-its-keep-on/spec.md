# #632 — a steering change earns its keep on a canary A/B before it ships

## Goal
A workline that edits a seat's steering shows two canary runs (main's, the branch's) on its thread
before review. One that doesn't runs none. Informational: a regression is a review finding, never a red verify.

## Design

### 1. What counts as steering — and what the bench can honestly measure
The bench runs each task in a fixture workdir under tmp, with `system_prompt` from
`Profiles.instantiate/2` in the checkout it runs from (`Runner.profile/2`). So:

| change | canary-able? |
|---|---|
| a persona / `@archetypes` entry in `server/lib/server/profiles.ex` (and what `instantiate` appends) | **yes** |
| a skill, an AGENTS.md a seat reads | **no** — the fixture workdir holds neither; the bench never loads them (build task 1 confirms this against `aside_argv`) |

Un-canary-able steering is not skipped silently: verify records a `bench_contrast` row with
`status: "unmeasurable"` and the file names, so the reviewer sees the change was steering and unmeasured.
No contrast is ever recorded that measures nothing.

Classifier: extend `Server.Workline.Grade` (it already classifies paths: `limits/1`) with
`steering(paths)` → `[{:profiles | :unmeasurable, path}]` (path level, cheap). It is the **gate**.
It is deliberately NOT hunk-level: personas are module attributes (`@builder_role`) referenced from
`@archetypes`, so a diff hunk rarely names its archetype. Which roles are affected is decided
**semantically** instead (next section).

### 2. Which roles
Only when the gate hits `profiles.ex`: `mix server.bench_roles --fingerprint` prints
`role => sha256(Runner.profile(role, nil).system_prompt)` for every role in `Roles.roles()`. Run in the
branch checkout and in main's; roles whose hashes differ are affected. (Catches shared edits —
`personalize`, `lead_duties`, `Soul.tone` — that move many roles.) Roles whose archetype is new on the
branch count as affected, with no main run (recorded `baseline: "absent"`).

### 3. The A/B
In `scripts/workline-verify.sh`, after the existing gate is green (and before `advance`), for each affected
role (cap below): `mise run bench:roles -- --suite canary --role R --out FILE` once in `$fresh`
(branch, rebased — the throwaway checkout) and once in a throwaway worktree of origin/main beside it
(never `$root`: the root checkout holds whatever branch the operator has out). New `--out FILE` on
`server.bench_roles` writes the run records as JSON and does **not** touch `bench/roles/results/` or the
README (a throwaway checkout's would vanish; main's would be dirtied). Same model both sides
(`--model` unset: the routed one). Canary tasks only — the full suite is never invoked from verify.

Record one CHECKS row per role, `bench_contrast`, correlation `workline:<slug>:verify`, detail:
`role, pass_a/n_a (main), pass_b/n_b (branch), tokens_a/b, turns_a/b, commit_a/b`.
`check_passed` always (it is evidence, not a gate); posted to the thread as a one-line note.

### 4. Block or inform: inform
n=2 per role and LLM variance: one drop can be a flake. A **regression** = branch passes fewer
canaries than main. It is named in the reviewer's brief as a finding to weigh. Verify stays
green. A bench that errors (harness down, quota) records `status: "error"` and does not fail verify.

### 5. Quota ceiling (per verify)
- at most **3 roles** (alphabetical; extras listed `status: "skipped: over cap"` in the row),
- canary tier only (`Roles.tiers("canary")`), so ≤ 2–3 tasks × 2 sides × 3 roles,
- per-task timeout stays the runner's (`timeout_s/1`: 300 s, builder 900, senior 1800), and the
  whole bench step has a **15 min** wall the task itself keeps (`Server.Bench.Contrast`), each side
  run as its own process group and the group killed at the wall, so nothing it spawned outlives it,
- a re-verify of an unchanged branch+main commit pair reuses the recorded row (no re-run).
Expected cost: cents per role-pair (hronir's measure); the cap, not a dollar meter, is the ceiling.

### 6. Habits
The **reviewer** proposes them, through `propose_habit`, citing the `bench_contrast` CHECKS row as
evidence — and only when a contrast is a real signal (regression or clear win), not on every row.
Verify proposes nothing.

## Out of scope
Blocking on a regression; skill / AGENTS.md canaries (needs a bench that loads them — separate ticket);
full suite; cost in dollars (tokens + turns only).

## Build tasks (each its own commit, test first)
1. `Grade.steering/1` + test (profiles.ex → `:profiles`; skill / AGENTS.md → `:unmeasurable`; others → `[]`). Also confirm in `aside_argv` that no skill/AGENTS.md reaches a bench run; if one does, move it to `:profiles`-class and add to the table.
2. `server.bench_roles --fingerprint` + test (equal on same tree; differs after editing a persona).
3. `server.bench_roles --out FILE` + test (writes records, leaves `results/` untouched).
4. Pure `Roles.contrast/2` (two record sets → pass/tokens/turns/regression?) + test.
5. `scripts/workline-verify.sh`: gate → fingerprint both → bench both → `record-verify` the row; cap + timeout. Test: a workline with no steering path runs none (the "done when" negative).
6. Reviewer brief names a regression row; reviewer persona line about `propose_habit`.

## Sequencing
Build waits on `work/verify-s-throwaway-checkout-lives-in-tmp` (edits workline-verify.sh) and on the
operator's answer on stale `work/t209` (rewrites roles.ex, runner.ex). Tasks 1–4 touch neither script and
could go first only if t209 is dead.

## Decisions I made (operator to confirm)
- skills / AGENTS.md: recorded unmeasurable, not canaried.
- roles via fingerprint, not hunk parsing (departs from hronir's lean; reason in §1).
- cap 3 roles / 15 min.
