# Review: 732-office-glance-the-calling-seat-s-own @ 50f3e66

**Verdict: approve.** Both findings from the first round (c8590b8) are fixed in 50f3e66, which is the patch from that review applied as written, plus the red test it asked for. Nothing new blocks.

## 1. `me` is now the caller's row on its own thread (fixed)

The witness:

```elixir
me: Enum.find(rows, &(&1.agent == agent and &1.thread_id == thread.id)),
```

The test now seats the same agent on a second, newer thread before the glance (`Channel.open_thread` + `Staff.start_session` on `other`). `Server.Staff.roster/0` orders `desc: s.id`, so that row sorts first and the old agent-only `Enum.find` would have returned it with `other.id`; the assertion `tid == thread.id` holds against the new code. I ran the test on the branch head:

```
menard run test --in server test/server/mcp/server_test.exs:872
{"ok":true,"tests":1,"failed":0,"failures":[]}
```

I did not re-run it against ce002af; the red is read from the `order_by`, not measured.

## 2. `roster/1` runs once per glance (fixed)

`rows = rows(ws)` computed once; `crew` is `Enum.reject` and `me` is `Enum.find` over the same list. `crew/2` and `me/2` are gone. `crew` keeps the old semantics exactly: every row of the caller's, on any thread, is dropped, as the former `r.agent != me` filter did.

## Consumers

`adapters/claude-code/mod.ts` reads the glance with `Array.isArray(got.red) && Array.isArray(got.crew)` and otherwise only `crew`, `red`, `line`, `persona`; the `Glance` type in `lib/citizen.ts` is not strict. The added `me` key is additive and breaks no reader. The empty-workspace clause carries `me: nil` so the shape is uniform.

## Checks read

- Verify's `mise run check` green on 50f3e66 (CHECKS row 15:02:00Z, server + adapters + office, 967 office tests pass). `tlon/check` not posted because the verifier's tree was dirty, not the branch's doing.
- No `bench_contrast` row owed or present: the diff touches no persona or skill.
- The first round's nit (130-column moduledoc line) is gone; the block now wraps near 100.
