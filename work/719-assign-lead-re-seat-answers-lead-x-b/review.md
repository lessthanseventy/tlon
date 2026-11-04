# Review: 719-assign-lead-re-seat-answers-lead-x-b @ 6968995

**Verdict: request_changes.** The seat now comes up in the call and the kill-then-post race the tech lead named is closed (`Tmux.kill_window` is a synchronous shell-out and runs before the post, so the in-call `deliver` lists the leaf gone). Two things need fixing before it lands: the new refusal notice repeats every minute under the drain, and the brief's off-shift refusal is missing, so half the ticket's shape is still open.

Read: the one commit (`staffing.ex`, `switchboard.ex`, `staffing_test.exs`, `pr.md`), `Switchboard.deliver/1`, `recipients/1`, `on_shift/2`, `Arbiter.Tmux.spawn/1`, `Staffing.note_parked/1`, `Message.post_changeset/2`, `Spawn.join/3`, `Switchboard.Runner`. CHECKS: `mise run server:check` green on 6968995; no `bench_contrast` row.

## 1. Blocking: `spawn_pane` posts the refusal on every drain pass

Witness, `switchboard.ex`:

    {:error, reason} = refused ->
      if agent.id == thread.agent_id do
        Server.Channel.post(%{ ... body: "#{agent.name} could not be seated on this thread: #{inspect(reason)}" })

The handoff post stays `:pending` while nobody is seated, and `drain/0` re-runs `maybe_spawn_absent` for it each minute (the comment above it says so: "makes the drain's retry each minute safe"). Only `:already_running` and `:no_arbiter` are quiet. `:at_cap` is a normal, hours-long state (a workline waiting for a leaf), and `under_cap/3` already tells the thread about it once through `note_parked/1`, which guards itself by skipping while its own note is the thread's latest message. After this change an at-cap lead's thread gets `hronir could not be seated on this thread: :at_cap` once a minute for as long as it waits, beside the parked note. `{:tmux, why}` and `:no_workspace` persist the same way.

Fix: add `:at_cap` to the quiet list (parked is already said), and guard the notice the way `note_parked` does: skip it while the thread's latest message is a `tlon` notice with the same body. Pin it with a test: deliver the same message twice against `RefusingArbiter` and assert one notice.

## 2. Blocking: an off-shift X is still handed the thread and never seated

The brief (tertius, #28654) asked: "refuse up front what hand_off can know (X clocked out or off shift → `{:error, …}` with words". `lead_available/1` checks only `Presence.clocked_out?/1`; `pr.md` says the off-shift half is "Not done".

What happens today with X on the crew that is off: `assign_lead` sets the lead to X, the old leaf is killed and its sessions ended, and the handoff post's `@X` goes through `on_shift/2`, whose `for_shift/5` turns the off-shift lead into a stand-in. The stand-in is not the lead, so `spawn_home` sends them to the lobby. X has no pane, the thread has no leaf, and the tool answered `{"lead": X}`. That is the ticket's sentence verbatim, on the second of the two filters the brief named. The fix is the same size as the clocked-out one:

    def explain(:off_shift),
      do: "that coworker is off shift: their seat is never woken, so the thread stays with its lead"

    # an unknown handle is `Channel.assign_lead/2`'s refusal
    defp lead_available(thread_id, handle) do
      with %Agent{} = agent <- Staff.agent_by_name(handle),
           %Thread{workspace_id: ws} when is_integer(ws) <- Repo.get(Thread, thread_id) do
        cond do
          Presence.clocked_out?(agent) -> {:error, :clocked_out}
          off_shift?(ws, agent) -> {:error, :off_shift}
          true -> :ok
        end
      else
        _ -> :ok
      end
    end

    # on the bench but not on the crew on: `Switchboard.on_shift/2` would hand their mention to a stand-in
    defp off_shift?(ws, agent) do
      on = MapSet.new(Workspaces.bench(ws), & &1.agent_id)
      MapSet.member?(MapSet.new(Workspaces.bench_all(ws), & &1.agent_id), agent.id) and
        not MapSet.member?(on, agent.id)
    end

and `:ok <- lead_available(thread_id, handle)` in `hand_off/3`. Test: seat hronir on crew `night` with `day` on (the `shifts_test.exs` setup), `hand_off(thread.id, "hronir")` answers `{:error, :off_shift}`, lead unchanged, no kill-window, no messages. Mirror the clocked-out test.

## 3. Note, not blocking: the post is now delivered twice at once

`Channel.post` broadcasts on the bus and the Runner calls `deliver/1`; `hand_off` now calls it too, in the caller's process. Both reach `maybe_spawn_absent`. The Tmux arbiter serialises the window under `:global.trans` and lists tabs inside the lock, so the second sees `:already_running` and spawns nothing; `Spawn.join/3` only mints a token (`Tokens.mint`), so the cost is one unused token per hand-off. Nothing to change; saying it so nobody reads the second `Spawn.join` in a trace as a bug.

## Checked and fine

- `kind: "notice"` is cast and validated in `post_changeset/2`, and `recipients/1` and `reaches_nobody?/1` return nothing for a notice, so the refusal notice wakes nobody and cannot re-enter `spawn_pane`.
- `Orphans` waits its 3s grace only when a holder exists; a fresh X on a thread it never sat on has none, so the tool's answer does not block on a pane.
- The three tests assert the right things: the spawn's exports name X and the thread in the same call; the clocked-out refusal changes nothing (lead, messages, no kill-window); the refusal is said. They were red first per the builder's notes.
