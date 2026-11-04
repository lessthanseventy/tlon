# Review: 719-assign-lead-re-seat-answers-lead-x-b @ 9e15faf

**Verdict: approve.** Uqbar's four asks from the gate (message 28866) are each done as asked, each pinned by a test, and nothing beyond them moved. My earlier rounds' findings stay fixed (review at 8860f48).

Read: `git show 9e15faf` (`staffing.ex`, `switchboard.ex`, both tests), `Switchboard.deliver/1` and its `@doc`, `deliver_now/1`, `claim_reached/1`, `inert_kind?/1`, `reaches_nobody?/1`, `addressed_to_nobody_else?/1`, `spawn_pane/1`, `note_unseated/3`, `Staffing.note_parked/1` and `parked_note?/1`. CHECKS: verify's `mise run check` exit 0 on the branch (a748789, the gate's rebased sha). I ran `menard run test --in server test/server/staffing_test.exs test/server/switchboard_test.exs` myself: 121 tests, 0 failures. No `bench_contrast` row; the diff touches no persona file, so none was due.

## 1. Done: deliver_now settles only the inert kinds

Witness, `switchboard.ex`:

    if inert_kind?(message), do: claim([message.id]), else: maybe_spawn_absent(message)
    ...
    defp inert_kind?(%Message{kind: kind}), do: kind in ["notice", "suggestion", "margin", "side project"]

The live path claims only the four kinds that can never reach anyone. A plain post on a leadless thread goes back to `maybe_spawn_absent` and `{:pending, message}`, so a lead assigned a moment later hears it. `reaches_nobody?/1` keeps its closed-thread and author-only clauses for the drain alone, as the ask drew the line. Test: a leadless post is `{:pending, _}` with `delivered_at` nil, then `Staff.assign` plus `drain/0` wakes Carl and stamps it. The `deliver/1` doc still reads true for what it says: an unaddressed message stays pending and the drain picks it up. It does not mention that a notice is settled rather than left pending; a one-line omission, noted below.

## 2. Done: note_unseated dedupes on the stable prefix

Witness:

    defp note_unseated(home, said, reason) do
      ...
      if !(last && last.author == "tlon" &&
             (String.starts_with?(last.body, "⏸ parked") or String.starts_with?(last.body, said))) do
        Server.Channel.post(%{... body: "#{said}: #{reason}"})

`said` is the fixed "<name> could not be seated on this thread" and the reason rides after the colon, so a refusal whose text changes each minute is said once. The changing-refusal test now delivers `m` a second time after the notice redeliveries and still counts one notice. Same residual as `note_parked`: a chat message landing between two retries lets the notice say itself once more.

## 3. Done: never over the parked note

Same witness, the `"⏸ parked"` branch. The test posts the parked note after the post, delivers the post against a refusing arbiter, and asserts no "could not be seated" and `Staffing.parked_note?/1` still true, so the thread keeps its place in `parked/2` and its seat reservation. The literal matches `note_parked/1` and `parked_note?/1` in `staffing.ex` character for character today; it now lives in two modules, which is the one follow-up.

## 4. Done: hand_off catches an exit

Witness, `staffing.ex`:

    rescue
      e -> Logger.error("hand_off delivery on thread #{thread.id} failed: #{Exception.message(e)}")
    catch
      :exit, reason -> Logger.error("hand_off delivery on thread #{thread.id} exited: #{inspect(reason)}")

`spawn_pane/4` has no rescue or catch of its own, so `ExitingArbiter.spawn/1`'s `exit(:timeout)` reaches `hand_off` and only this `catch` keeps `{:ok, thread}`; the test asserts that and `thread_lead == "hronir"`.

## Noted, not a change

- The double in-call delivery is left as agreed: the second `deliver` sees `:already_running` under the arbiter's lock.
- `deliver_now/1` still answers `{:pending, message}` for an inert kind it has just claimed; both callers discard the value. Carried from last round.
- The drain's `claim_reached/1` still settles a leadless post through `addressed_to_nobody_else?/1` (`Enum.all?([])` is true), so the window a late-assigned lead has to hear a post is until the next drain pass, about a minute. Pre-existing on main and outside the ask's line; said so it is not mistaken for this branch's doing.
- Verify's check tail ends `tlon/check: not posted — gh: No commit found for SHA a748789…`: the gate's rebased sha is not on GitHub before landing, expected.