No free reviewer is at the builder's grade (greybeard); tzinacan (sonnet-5-5) reviewed.

# Verdict: approve

Read the diff of 3779843 (tool.ex, thread.ex, profiles.ex, AGENTS.md, server_test.exs). I did NOT run the tests (sandbox has no Postgres); verify and landing run the gate.

- `routed_to?/2` is guarded to `agent: "uqbar"`; every other identity falls to `false`. It matches only `Needs.grouped().uqbar` items whose `thread_id == thread.id`; items with `thread_id: nil` never match. It lapses with the item.
- Refusal text, tool docs and field description are consistent; the three existing tests asserting the old text were updated.
- New tests: post and notice land while routed, a thread with no need is refused, the grant lapses after settle.
- Role text says post before settling, matching the lapse.

Not blocking: `Needs.grouped/1` rebuilds all need lists and runs `prune` (a DB delete) per call. It only runs for Uqbar's cross-thread posts after the first two grants fail, so it is cheap enough.