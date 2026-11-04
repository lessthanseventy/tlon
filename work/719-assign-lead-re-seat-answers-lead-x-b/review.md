# Review: 719-assign-lead-re-seat-answers-lead-x-b @ 543d383

**Verdict: approve.** Both blockers from the fabfb54 round are fixed as asked, each pinned by a test that was red first, and nothing else moved.

Read: `git diff fabfb54..543d383` (`staffing.ex`, `switchboard.ex`, `staffing_test.exs`, `pr.md`), `Staffing.note_parked/1`, `Workspaces.bench/1` and `bench_all/1` with the `on_shift/1` query (`wa.crew == "all" or wa.crew == w.shift`, shift defaults `"day"`), `Arbiter.Tmux.spawn/1` (the one source of `{:error, :at_cap}`). CHECKS: verify's `mise run check` exit 0 on the branch; I ran `menard run test --in server test/server/staffing_test.exs test/server/switchboard_test.exs` myself: 115 tests, 0 failures. No `bench_contrast` row.

## 1. Fixed: the refusal notice no longer repeats under the drain

Witness, `switchboard.ex`:

    {:error, reason} = refused when reason in [:already_running, :no_arbiter, :at_cap] -> refused
    ...
    defp note_unseated(home, body) do
      last = Repo.one(from m in Message, where: m.thread_id == ^home.id, order_by: [desc: m.id], limit: 1)
      if !(last && last.author == "tlon" && last.body == body) do

`:at_cap` is quiet (the arbiter is its only origin, and `note_parked/1` already says it), and the guard is `note_parked`'s shape, matching on the exact body. The test delivers the same handoff post three times in all (once inside `hand_off`, twice by hand) against `RefusingArbiter` and counts one notice; the at-cap test counts none. Same residual as `note_parked`: a chat message landing between two retries lets the notice say itself once more. Acceptable, and not new.

## 2. Fixed: an off-shift X is refused up front

Witness, `staffing.ex`:

    cond do
      Presence.clocked_out?(agent) -> {:error, :clocked_out}
      off_shift?(ws, agent) -> {:error, :off_shift}
      true -> :ok
    end

`off_shift?/2` is seated-on-the-bench and not in `Workspaces.bench/1`, the same set `Switchboard.on_shift/2` would hand to a stand-in, so the two can't disagree. Unknown handle and a thread with no workspace fall through to `:ok` and stay `Channel.assign_lead/2`'s refusal, as before. The test seats dahlmann on crew `night` under a `day` workspace and asserts `{:error, :off_shift}`, lead unchanged, no messages, no kill-window. `pr.md`'s "Not done" paragraph is gone and the body matches the code.

## 3. Unchanged, still fine

The double in-call delivery (note 3 last round) is left as is, as agreed: the second `deliver` sees `:already_running` under the arbiter's lock and is quiet.

## Noted, not this branch's

Verify's check tail shows `tlon/check: not posted — gh: No commit found for SHA 8afca3a…` (the gate's rebased sha is not on GitHub yet, expected before landing) and a `tlon_eval_…does not exist` line from the evals' teardown. Neither comes from these commits.
