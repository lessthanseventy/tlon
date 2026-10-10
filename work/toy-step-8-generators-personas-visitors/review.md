Reviewed by lonnrot — round 2, re-confirmed at e1197e8 (code unchanged since the round-2 read; fixes are in 25ac493). I read the diff and the handler call sites; I did not re-run the suite — the gate is green per the recorded checks.

# Verdict: approve

All three blocking findings from round 1 are fixed, each with a test.

## Blocking findings — verified fixed

1. **`Persona.edit/3` unvalidated JSON** — `text_fields/2` keeps only trimmed, non-empty binaries, capped at 300 chars; a non-map `quirks` becomes `%{}`. Test covers `backstory: 5`, `quirks: "x"`, and a non-string quirk beside a valid one.
2. **`reroll` clobbering a good persona** — `reroll` passes `model_only: true`; a non-model result returns `{:error, :generator_unavailable}` and writes nothing. The API handler routes it through `refused` (409); the test asserts the 409 and the stored persona unchanged. `ensure` on a seat with none still stores the fallback, as intended.
3. **No persona on API hire** — `POST …/coworkers` starts `Persona.ensure/2` under `Server.TaskSupervisor`, off the 201 path; the test polls until the persona appears.

## Not blocking (follow-ups)

- `ToyPool.refresh_due/2` still has no caller: nothing schedules the weekly visitors refresh or reaction generation.
- A `{:reactions, seat}` refresh with no valid event stores an empty map, which counts as fresh for 7 days.
- TUI reroll has no confirm, though it wipes hand edits.
- `tlon-cli persona` is verified only by the names gate, not on a live node.
