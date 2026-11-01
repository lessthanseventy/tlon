# Review: #803 restaff — a raising Trust.record degrades to neutral

**Verdict: approve.** Reviewed 68dfff5 (the one commit on `work/803-restaff-a-raising-trust-record-degra` past origin/main 7884bc5).

## What the diff does

The two `Server.Trust.record(&1.name)` candidate lookups in `restaff/2` and `suggest_lead/4` become `with_trust/1`: the lookup alone is wrapped in a `rescue` that logs a warning and returns the candidate without a `trust` key. `Server.Roster.trust_rate/1` has a `defp trust_rate(_cand), do: 0.5` fallthrough, so the keyless candidate is neutral in the tie-break, as the ticket asked. `restaff`'s outer `rescue -> restaff_miss` is untouched, and so is `restaff_miss`'s silence for non-reviewer kinds (the ticket's stated limit).

## Findings

1. **Correct, minimal.** Before: the raise inside the `Enum.map` lambda hit `restaff`'s outer `rescue`, which lands on `restaff_miss(thread, _kind, _why), do: thread` for builder/planner, so the thread came back unled with nothing posted. After: the raise is caught per candidate, `Roster.pick` runs, `hand_to` posts the leads line. Read, not run, for the red side; the green side I ran.
2. **Test runs green on the branch:** `menard run test --in server test/server/workline_test.exs:278` → `{"ok":true,"tests":1,"failed":0}`. The test seats two builders, stubs the `:trust_record` seam to raise, advances plan→build and asserts a lead in the pair and the `→ <lead> leads (build stage)` line. `workline_test.exs` is `async: false`, so the global `Application.put_env` seam is safe, and `on_exit` deletes it.
3. **Seam shape matches precedent.** `Application.get_env(:server, :trust_record, &Server.Trust.record/1)` is the same pattern as `:arbiter` / `:crew` impl overrides in this app.
4. **`escalate` has nothing to wrap on this base:** `Roster.pick(Enum.map(above, &%{coworker: &1, model: nil}), …)` passes no trust. Confirmed; the builder said so on the thread and in pr.md. #520 (which adds `trust:` there) should route through `with_trust/1` when it lands; that is #520's business, not a follow-up here.
5. **`Trust.record/2` is a single `Repo.all`,** so its failure mode is an exception (`DBConnection.ConnectionError`, `Postgrex.Error`), which `rescue` catches. No `exit` path to worry about.
6. **`Logger` is already `require`d** in the module (line 32); `Logger.warning` compiles under warnings-as-errors.
7. **CHECKS:** `mise run check` passed exit 0 on 68dfff5. Its tail carries a `tlon_eval_…` "database does not exist" line (an eval DB torn down under a straggling connection, #715's family) and `tlon/check: not posted — No commit found for SHA` (the branch was not yet pushed to GitHub when the gate ran); neither is this change's doing. No `bench_contrast` row.

No follow-ups.
