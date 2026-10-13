# Review — souls step 3: voice from the soul (#62)

**Verdict: APPROVE.**

Diff read: `main...af92978`, 12 files. Server side: `soul.ex` (+85), `banter.ex` (+9/-3), `profiles.ex` (one line), `evals/souls.exs` (new), four test files, `server/AGENTS.md`. Office untouched, as the spec fences.

## Spec compliance

- (a) section → surface table holds. `voice/1` = Quirks/People/Wants; `tone/1` = Where they're from + Quirks. Fears/Diary reach neither; Wants/People never reach the brief. Tests assert each with marker strings.
- (b) three layers present. Caller-grep test (`soul_callers_test.exs`) allows only `soul.ex`, `banter.ex`, `profiles.ex`. Deterministic `:souls` evals: brief byte-identical minus the trailing `<soul-tone>` block; no Wants/People/Fears text. Judged mandate-wins scenario exists, `mode: :judge`, honestly commented as the only one that tests the model and not in the gate.
- (c) banter re-reads the file per `context/1` (docstring says so); brief reads at `instantiate/2` only. Matches the spec's cadence.
- `profiles.ex` is exactly one appended `<> Server.Soul.tone(name)` on the system_prompt line. Nothing else moved.
- `read/1` never raises: `check_name` rejects `../etc/passwd`, missing file → nil, headingless → `%{}`. `### sub` does not match `^##\s+`, so it lands as content and `clean/1` drops it. Duplicate headings append, not clobber.

## Verified

```
menard run test --in server test/server/soul_test.exs test/server/soul_callers_test.exs test/server/office/banter_test.exs test/server/profiles_test.exs
{"ok":true,"tests":88,"failed":0,"failures":[]}
```
Full `mise run check` passed server-side at verify (ireneo: evals 11 passed / 2 judged skipped). I did not run the judged scenario.

## Findings (non-blocking)

1. **`clean/1` strips the tone tag in one pass, so it can be reconstructed.** `String.replace("</</soul-tone>soul-tone>", ~r/<\/?soul-tone>/, "")` returns `</soul-tone>` (checked). The "cannot close the tone block early" test passes only for the naive case. Spec calls this a prompt-level fence over operator-edited text, so not blocking. Fix: replace the bare substring `soul-tone` (e.g. with `soul tone`) instead of the tag regex, which has no reconstruction path. Filed as follow-up.
2. **Note, no ticket:** `profiles_test.exs` is `async: true` and the new test mutates the global `:souls_dir` app env. Same pattern as the file's three existing `put_env` calls, and no other async module reads a soul named `atlas`, so no observed race. Worth knowing if a soul-reading async test ever appears.
3. Caller-grep is a text check: an `alias Server.Soul, as: X` or `apply/3` would evade it. Accepted by the spec as the structural layer; the judged eval is the real check. No action.
