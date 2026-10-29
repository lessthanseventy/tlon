# office tests: a TUI start waits on its own budget

Closes ticket #452 (issue #26): `office/test/refresh.test.ts` and `navigation.test.ts` went red inside the
concurrent `mise run check` gate and nowhere else.

**What changed.** The 20 office tests that boot the TUI (`bun tui/main.ts` in a tmux pane) shared one
15–25 s budget between that cold start and their steps. Alone the start paints within a second; under
the gate, every suite at once on one box, it has taken over 25 s, and the start alone blew the budget
(`screen()` empty, "never saw the toy"). `office/test/started.ts` gives a start its own budget:
`started(tmux, what, ok)` waits 120 s for the first paint and fails at once, naming it, when tmux has
closed the pane (the TUI's process exited); `TUI_TEST` (180 s) is bun's timeout for a test that boots the
TUI. Every start in the 20 files goes through it; steps keep their 25 s, and the files whose deadline
was one module-scoped constant now budget per step, so a slow start no longer eats the steps' time.
The gate's shape is unchanged: ordering office tests after server:check would add the suite's whole
runtime to every check, loaded or not.

**How I checked.** `started.test.ts` covers the three cases (paints in time; pane gone fails fast;
never paints fails after the budget with the pane). Reproduced the flake by hand: 300 busy shells on the
14 cores, then `bun test test/refresh.test.ts test/navigation.test.ts` → navigation red at its start
wait ("never saw the toy; pane: (empty)"); after the change, under 400 loops (load avg 380) the same
files plus `reload.test.ts` pass 7/7 (82 s, against 8 s unloaded). Unloaded: typecheck green, the 21
TUI-driving files 42/42 in 71 s; `mise run check` on the branch head via run_task.
