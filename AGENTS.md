# workbench

**Read `docs/spec.md` before writing anything.** It is the specification this repository exists to
implement, every rule in it names the failure that paid for it, and it was reviewed adversarially twice
(`docs/spec-review.md`, `docs/v1-review.md`). If something here contradicts the spec, the spec wins; if
the spec is wrong, say so and change it in the same commit as the code that proves it.

## What to build, in order

`docs/spec.md` §9 is day one, in five steps, and step one is the database plus `wb doctor`. **Nothing
ships that cannot be repaired at 2am** — schema, migrations, `integrity_check`, JSONL export. Do not
start at step 3 because it is more interesting.

Version one is running and in daily use at `~/.config/ai-workbench`, `~/.config/ai-workspaces` and
`~/.pi/agent/extensions`. It is **evidence, not a source**: read it to see what a failure looked like,
never to copy a shape. Nothing here needs to be backwards compatible with it.

## The rules most likely to be broken by accident

- **When two things can answer the same question, delete one.** Three defects in one day were "two
  sources of truth where the untested one was in the live path".
- **Ask the arbiter whose output contains the field you care about.** A test that reads our own files
  proves only that we were consistent. `herdr config check` said `config: ok` about a stale registry
  and `herdr plugin list` printed neither the version nor the actions that had diverged.
- **A field computed at write time is not a fact at read time.** Compute age, staleness and counts in
  the query.
- **A cache that reports an empty world is a lie.** A collector that cannot collect writes nothing and
  says so — and an empty derived scope is never a licence to show everything.
- **Never invent a duration.** A log entry is a stamp, not a clock-in.
- **A measurement that returns nothing must be proven capable of returning something.** A false zero
  from a wrong key reads exactly like a real zero, and one of those got into the spec.
- **Rank and cut every surface.** Complete is not the same as useful; the count of what was set aside
  is the honest way to omit it.
- **In production, Andrew presses Enter.** Prefill the exact reviewed text in a visible pane and stop.
  Typing is only inert where `herdr pane process-info` proves a shell is in the foreground.

## Verify

There is nothing to run yet. When there is, it goes here, and a claim that something works without
having run it is the one thing this project cannot afford — the spec exists because that happened
repeatedly in version one.
