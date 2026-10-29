# Review — staff-child-honours-a-named-lead-on-a-wo (round 3)

**Verdict: approve.** Branch read at 7859fe8b47959489e54ef393d579bdbb7fe405f1; the delta since my last verdict (dba109f) is that one commit.

## The finding from round 2, checked

1. **Off-shift manager named as lead slipped past `not_manager`** — fixed. The witness, `coordination.ex:185-190`:

   ```elixir
   manager? =
     ws
     |> Server.Workspaces.bench_all()
     |> Enum.any?(&(&1.name == lead and Server.Profiles.meta?(Server.Profiles.roster_entry(&1).archetype)))
   if manager?, do: {:manager_lead, lead}, else: :ok
   ```

   Verified: `bench_all/1` (`workspaces.ex:269`) is the same query as `bench/1` minus `on_shift/1`, so every seat is read regardless of `crew`/`shift`. The predicate is byte-for-byte `Workspaces.manager/1`'s (`workspaces.ex:314`), so what counts as "manager" is one definition applied to a wider bench, not a second one. `@meta_archetypes` is `[:surveyor]`, which is what the test seats. The refusal still runs ahead of `Workline.open`, so no unled thread is left behind.

2. **The test is honest.** It seats `surveyor-night` on crew `night`, asserts it is *absent* from `bench/1` before calling the tool (so the test fails if the fixture ever lands on shift and stops testing the off-shift path), then asserts `isError` and an unchanged thread count. Builder reports it went red first on the `Spawn.ensure/3` crash; consistent with round 2's traced path.

## Earlier rounds

Round 1's two follow-ups (delete `lead_for/2`; refuse a manager as named lead) landed in 11f26f3 and were approved in round 2. Nothing from any round remains open.

## Checks

`mise run check` exit 0 on the branch (09:50Z); `menard run check --in server` 2408 tests, 0 failed. No `bench_contrast` row among the five most recent CHECKS shown to me.

## Nits (not follow-ups)

The `manager?` predicate repeats `Workspaces.manager/1`'s lambda; a `Workspaces.manager?(ws, name)` would make it one line in two callers. Three lines beat a helper for a caller that doesn't exist yet — leaving it.
