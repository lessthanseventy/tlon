# Review: 719-assign-lead-re-seat-answers-lead-x-b @ 4fb8705

**Verdict: approve.** Uqbar's two one-line asks from the gate (message 28891) are each done as asked and pinned by a test, and nothing else moved: `git diff 18729ff..4fb8705` is `staffing.ex` (+16/-9), `switchboard.ex` (+2/-2), `staffing_test.exs` (+16). My follow-up from the last round (the duplicated "⏸ parked" literal) is fixed by ask 1 and is dropped. Every earlier round's finding stays fixed (reviews at 8860f48, 18729ff).

Read: `git show 4fb8705`, `Staffing.lead_available/2`, the new `shift_check/2`, `Staffing.parked_note?/1`, `Switchboard.note_unseated/3`. CHECKS: verify's `mise run check` exit 0 on the branch (22a8110, the gate's rebased sha; office 969 pass, 0 fail). I ran `menard run test --in server test/server/staffing_test.exs test/server/switchboard_test.exs` myself: 122 tests, 0 failures. No `bench_contrast` row; the diff touches no persona file, so none was due.

## 1. Done: note_unseated reads Staffing.parked_note?

Witness, `switchboard.ex`:

    if !(last && last.author == "tlon" && String.starts_with?(last.body, said)) and
         !Server.Staffing.parked_note?(home.id) do

The inline "⏸ parked" test is gone; `Staffing.note_parked/1` and `parked_note?/1` are the one owner of the prefix. `Switchboard` already called `Server.Staffing.left_off/2`, so this adds no new dependency direction. The existing parked-note precedence test (notice posted after the parked note: no "could not be seated", `parked_note?` still true) covers it and passes.

## 2. Done: clocked-out checked before the workspace match

Witness, `staffing.ex`:

    case Staff.agent_by_name(handle) do
      %Agent{} = agent ->
        if Presence.clocked_out?(agent), do: {:error, :clocked_out}, else: shift_check(thread_id, agent)
      _ -> :ok
    end

`shift_check/2` keeps the off-shift test behind the `when is_integer(ws)` match, as the ask drew it, since a shift needs a workspace. The old `with` sent a workspace-less thread to its `else -> :ok` before either check ran, which is what the new test pins: a `scope: "machine"` thread with `workspace_id: nil`, the Manual presence engine with hronir's engine clocked out, `hand_off` answers `{:error, :clocked_out}` and the lead stays borges. Red first on the old code by construction (the guard failed, so `:ok`). An unknown handle still falls through to `:ok` and remains `Channel.assign_lead/2`'s refusal, per the comment above the function.

## Noted, not a change

- Verify's check tail ends `tlon/check: not posted — gh: No commit found for SHA 22a8110…`: the gate's rebased sha is not on GitHub before landing, expected.
- The grader's remaining suggestions (a spec.md, a Runner double-delivery test, a thread notice on a raise) were explicitly not asked for by Uqbar at the gate; the `:global.trans` lock in `Arbiter.Tmux.spawn/1` settles the double delivery and the drain retries a raised delivery. Not reopened here.

No open follow-ups.