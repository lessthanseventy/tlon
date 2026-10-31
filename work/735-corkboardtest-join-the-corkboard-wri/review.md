# Review: 735 — join the corkboard writers before removing the dir

**Verdict: approve.** Branch `work/735-corkboardtest-join-the-corkboard-wri` @ 23af685d8248, one commit. `mise run check` green on the branch (CHECKS 23:43:33Z, exit 0; office 967/0, server suite in it). No `bench_contrast` row: the diff touches no persona.

## Against the brief (tertius, msg #25931)

1. **The option lives in Corkboard, default kept.** `start_link(opts)` reads `:task_supervisor`, default `Server.TaskSupervisor`, into `init`'s map; both `start_child` sites read `state.task_supervisor`. The app still starts it bare (`application.ex:61`, child_spec → `start_link([])`), so production is unchanged. The atom key sits beside the integer `ws` keys and `entry/2` only ever `Map.get`s by `ws`; nothing iterates the state.
2. **The supervisor is the test's own, unlinked, outside `start_supervised`.** `board_supervisor!/0`: `Task.Supervisor.start_link()` then `Process.unlink`, so ExUnit's teardown of `Corkboard` does not take the writers with it.
3. **on_exit does the three things in order.** `join_writers/2`: bounded wait (100 × 50 ms = 5 s) on `children(sup) == []`, `Supervisor.stop(sup)`, `File.rm_rf!(dir)`. A timeout is `flunk(@stuck)`, never swallowed. `rm_rf!` is restored in the same commit as the join — exactly what andrew ruled in.
4. **No `terminate/2` waiting on a model call.** None added.
5. **Env reset after the join**, with its why in one comment: a writer not yet at its `System.cmd` would otherwise read the real generator. That is what emma's "still running after 5s" was.
6. **The pin.** "a writer still running when the test ends is joined before the dir goes": the fake model truncates-into-existence `prompts` 25 000 times, the test returns the moment the file exists, and the half-second of writes lands under on_exit. Red with `:eexist` before the join per pr.md; I did not re-run it (the server's verify did).

The join is correct because `System.cmd` returns only when the `sh` child has exited and closed its pipe, so an empty `children/1` means no process can still create a file in `dir`. Casting `{:pinned, …}` to the already-stopped `Corkboard` afterwards is a no-op.

## Not blocking (filed as follow-ups)

- The pin's window is a count, not a deadline. The brief asked for "until a deadline, then exit". 25 000 builtin redirections is ~0.5 s on this box by estimate only: my sandbox refused the `time` run, so I could not measure it. On a fast machine the loop can finish before on_exit reaches `rm_rf!` and the pin passes without exercising the race.
- On timeout, `File.rm_rf!` runs before `flunk(@stuck)`, so the failure a reader sees may be `:eexist` rather than "writers still running". Both red, one less legible.
